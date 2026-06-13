using System.Collections.Generic;

namespace NSharpLang.Compiler.Columnar;

/// <summary>
/// How a bare identifier reference in a function body binds. Local/Parameter/Function are the lexical name
/// resolution the binder performs within a function; NotInScope is everything else (BCL/external types,
/// member targets reached through a receiver, etc.) — resolved by a later pipeline stage (type/import table).
/// </summary>
public enum ColumnarBindingKind
{
    Parameter,
    Local,
    Function,
    NotInScope,
}

/// <summary>One resolved bare-identifier occurrence: the name and what it binds to.</summary>
public readonly record struct ColumnarNameRef(string Name, ColumnarBindingKind Kind);

/// <summary>
/// COLUMNAR PIPELINE — stage 2 (docs/design/columnar-pipeline.md). Lexical name resolution performed DIRECTLY
/// over the columnar statement/expression node tables — no C# AST. For one function body it produces, in a
/// canonical pre-order, the binding classification of every bare identifier (kind 6), maintaining a scope
/// stack: parameters as the base scope, <c>:=</c> locals entering at their declaration point, and Block/While/
/// If bodies introducing nested scopes. All top-level functions are pre-declared (forward references resolve).
///
/// The exact algorithm is mirrored on the C# AST by the parity oracle in the tests, so the columnar resolution
/// is verified identical to walking the object-graph AST on the whole dogfood corpus. Design rule (slice 27):
/// names are looked up against caller-supplied sets — interning / symbol IDs live in the symbol model, not here.
///
/// Node kinds (see ParserStatements.nl / ParserExpressions.nl): STMT 20 Return,21 Break,22 Continue,
/// 23 ExpressionStatement,24 VariableDeclaration,25 Block,26 While,27 If. EXPR 0-5 literals,6 Identifier,
/// 7 Parenthesized,8 MemberAccess,9 Call,10 IndexAccess,11 Unary,12 Binary,13 Ternary,14 Assignment,15 New,
/// 16 Cast,54 RefOutArgument. A New/Cast node's child[0] is a TYPE subtree (not a name lookup); a
/// MemberAccess member name lives in the node's value span (not a child, not a lookup) — only the receiver
/// child[0] is resolved. Ref/out call arguments are transparent wrappers around the argument value.
/// </summary>
public sealed class ColumnarNameResolver
{
    private readonly ColumnarNodeTable _nodes;
    private readonly string _source;
    private readonly HashSet<string> _parameters;
    private readonly HashSet<string> _functions;

    private readonly List<HashSet<string>> _localScopes = new();
    private List<ColumnarNameRef> _refs = new();

    internal ColumnarNameResolver(
        ColumnarNodeTable nodes, string source,
        IEnumerable<string> parameterNames, IEnumerable<string> functionNames)
    {
        _nodes = nodes;
        _source = source;
        _parameters = new HashSet<string>(parameterNames, System.StringComparer.Ordinal);
        _functions = new HashSet<string>(functionNames, System.StringComparer.Ordinal);
    }

    /// <summary>Resolve every bare identifier in the function body (a Block, kind 25), in pre-order.</summary>
    public List<ColumnarNameRef> Resolve(int bodyBlockIdx)
    {
        _refs = new List<ColumnarNameRef>();
        _localScopes.Clear();
        ResolveStatement(bodyBlockIdx);
        return _refs;
    }

    private void ResolveStatement(int idx)
    {
        switch (_nodes.Kind(idx))
        {
            case 25: // Block: a new local scope; statements in source order.
                _localScopes.Add(new HashSet<string>(System.StringComparer.Ordinal));
                for (var n = 0; n < _nodes.ChildCount(idx); n++)
                    ResolveStatement(Child(idx, n));
                _localScopes.RemoveAt(_localScopes.Count - 1);
                break;
            case 24: // VariableDeclaration (:=): resolve the initializer, THEN the local enters scope.
                if (_nodes.ChildCount(idx) > 0)
                    ResolveExpression(Child(idx, 0));
                DeclareLocal(Text(idx));
                break;
            case 26: // While [condition, body]
                ResolveExpression(Child(idx, 0));
                ResolveStatement(Child(idx, 1));
                break;
            case 27: // If [condition, then, else?]
                ResolveExpression(Child(idx, 0));
                ResolveStatement(Child(idx, 1));
                if (_nodes.ChildCount(idx) > 2)
                    ResolveStatement(Child(idx, 2));
                break;
            case 20: // Return [value?]
                if (_nodes.ChildCount(idx) > 0)
                    ResolveExpression(Child(idx, 0));
                break;
            case 23: // ExpressionStatement [expr]
                ResolveExpression(Child(idx, 0));
                break;
            // 21 Break, 22 Continue: no identifiers.
        }
    }

    private void ResolveExpression(int idx)
    {
        switch (_nodes.Kind(idx))
        {
            case 6: // IdentifierExpression — the only bare-name lookup.
            {
                var name = Text(idx);
                _refs.Add(new ColumnarNameRef(name, Classify(name)));
                break;
            }
            case 7: // Parenthesized [inner]
                ResolveExpression(Child(idx, 0));
                break;
            case 8: // MemberAccess [receiver]; member name (value span) is NOT a lookup.
                ResolveExpression(Child(idx, 0));
                break;
            case 9: // Call [callee, args...]
                for (var n = 0; n < _nodes.ChildCount(idx); n++)
                    ResolveExpression(Child(idx, n));
                break;
            case 10: // IndexAccess [object, index]
                ResolveExpression(Child(idx, 0));
                ResolveExpression(Child(idx, 1));
                break;
            case 11: // Unary [operand]
                ResolveExpression(Child(idx, 0));
                break;
            case 12: // Binary [left, right]
                ResolveExpression(Child(idx, 0));
                ResolveExpression(Child(idx, 1));
                break;
            case 13: // Ternary [cond, then, else]
                ResolveExpression(Child(idx, 0));
                ResolveExpression(Child(idx, 1));
                ResolveExpression(Child(idx, 2));
                break;
            case 14: // Assignment [target, value]
                ResolveExpression(Child(idx, 0));
                ResolveExpression(Child(idx, 1));
                break;
            case 15: // New [type, args...]; child[0] is a TYPE subtree (skip), args are expressions.
                for (var n = 1; n < _nodes.ChildCount(idx); n++)
                    ResolveExpression(Child(idx, n));
                break;
            case 16: // Cast [type, operand]; child[0] is a TYPE subtree (skip), child[1] is the operand.
                ResolveExpression(Child(idx, 1));
                break;
            case 54: // RefOutArgument [value] — transparent to lexical resolution.
                ResolveExpression(Child(idx, 0));
                break;
            // 0-5 literals: no identifiers.
        }
    }

    private void DeclareLocal(string name)
    {
        if (_localScopes.Count == 0)
            _localScopes.Add(new HashSet<string>(System.StringComparer.Ordinal));
        _localScopes[_localScopes.Count - 1].Add(name);
    }

    private ColumnarBindingKind Classify(string name)
    {
        for (var i = _localScopes.Count - 1; i >= 0; i--)
        {
            if (_localScopes[i].Contains(name))
                return ColumnarBindingKind.Local;
        }

        if (_parameters.Contains(name))
            return ColumnarBindingKind.Parameter;
        if (_functions.Contains(name))
            return ColumnarBindingKind.Function;
        return ColumnarBindingKind.NotInScope;
    }

    private int Child(int idx, int n) => _nodes.Child(idx, n);

    private string Text(int idx) => _nodes.Text(_source, idx);
}
