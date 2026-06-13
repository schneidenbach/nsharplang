using System.Collections.Generic;

namespace NSharpLang.Compiler.Columnar;

/// <summary>
/// Canonical sibling-function signature row used by the columnar type inferer to resolve bare calls without
/// collapsing overloads that share a simple name.
/// </summary>
public readonly record struct ColumnarFunctionReturnSignature(
    IReadOnlyList<string> ParameterTypes,
    string ReturnType);

/// <summary>
/// COLUMNAR PIPELINE — stage 3 (docs/design/columnar-pipeline.md). Expression type inference performed
/// DIRECTLY over the columnar statement/expression tables — no C# AST. For one function body it produces, in
/// post-order (children before parents, the order inference naturally computes), the inferred canonical type
/// of every expression. Scoping mirrors stage 2: parameters as the base scope (name→declared type), `:=`
/// locals entering at their declaration point with their initializer's inferred type, nested Block/While/If
/// scopes. Call return types come from the supplied function-signature map (the stage-1 symbol model).
///
/// Covers the pure-N#-inferable surface (~92% of the corpus): literals, arithmetic with C# numeric promotion
/// (<see cref="ColumnarTypeLattice"/>), comparison/logical → bool, locals/params, N#-function call returns,
/// index on arrays/strings, cast, new/object-initializer, ternary, assignment, parenthesized. BCL-dependent
/// forms (member access types, calls whose callee is not an N# function) yield <see cref="ColumnarTypeLattice.External"/> — the
/// typed host boundary a later stage fills in. Ref/out call arguments are transparent wrappers around their
/// value expression, matching the C# AST mirror's argument traversal. The exact rules are mirrored on the C#
/// AST by the parity oracle in the tests, so the columnar inference is verified identical to walking the
/// object-graph AST.
/// </summary>
public sealed class ColumnarTypeInferer
{
    private readonly ColumnarNodeTable _nodes;
    private readonly string _source;
    private readonly Dictionary<string, string> _parameterTypes;
    private readonly Dictionary<string, List<ColumnarFunctionReturnSignature>> _functionReturnTypes;

    private readonly List<Dictionary<string, string>> _localScopes = new();
    private List<string> _types = new();

    internal ColumnarTypeInferer(
        ColumnarNodeTable nodes, string source,
        Dictionary<string, string> parameterTypes,
        Dictionary<string, List<ColumnarFunctionReturnSignature>> functionReturnTypes)
    {
        _nodes = nodes;
        _source = source;
        _parameterTypes = parameterTypes;
        _functionReturnTypes = functionReturnTypes;
    }

    /// <summary>Inferred canonical type of every expression in the body (Block, kind 25), in post-order.</summary>
    public List<string> Infer(int bodyBlockIdx)
    {
        _types = new List<string>();
        _localScopes.Clear();
        InferStatement(bodyBlockIdx);
        return _types;
    }

    private void InferStatement(int idx)
    {
        switch (_nodes.Kind(idx))
        {
            case 25: // Block
                _localScopes.Add(new Dictionary<string, string>(System.StringComparer.Ordinal));
                for (var n = 0; n < _nodes.ChildCount(idx); n++)
                    InferStatement(Child(idx, n));
                _localScopes.RemoveAt(_localScopes.Count - 1);
                break;
            case 24: // VariableDeclaration (:=): the local's type IS its initializer's inferred type.
            {
                var t = _nodes.ChildCount(idx) > 0 ? InferExpression(Child(idx, 0)) : ColumnarTypeLattice.External;
                DeclareLocal(Text(idx), t);
                break;
            }
            case 26: // While [condition, body]
                InferExpression(Child(idx, 0));
                InferStatement(Child(idx, 1));
                break;
            case 27: // If [condition, then, else?]
                InferExpression(Child(idx, 0));
                InferStatement(Child(idx, 1));
                if (_nodes.ChildCount(idx) > 2)
                    InferStatement(Child(idx, 2));
                break;
            case 20: // Return [value?]
                if (_nodes.ChildCount(idx) > 0)
                    InferExpression(Child(idx, 0));
                break;
            case 23: // ExpressionStatement [expr]
                InferExpression(Child(idx, 0));
                break;
            // 21 Break, 22 Continue: no expressions.
        }
    }

    // Returns the inferred type AND appends it to _types after its children (post-order).
    private string InferExpression(int idx)
    {
        if (_nodes.Kind(idx) == 54) // RefOutArgument [value] — no extra AST expression in the C# oracle.
            return InferExpression(Child(idx, 0));

        string t;
        switch (_nodes.Kind(idx))
        {
            case 0: t = ColumnarTypeLattice.LiteralIntType(Text(idx)); break;
            case 1: t = ColumnarTypeLattice.LiteralFloatType(Text(idx)); break;
            case 2: t = "char"; break;
            case 3: t = "string"; break;
            case 4: t = "bool"; break;
            case 5: t = "null"; break;
            case 6: t = LookupType(Text(idx)); break;
            case 7: t = InferExpression(Child(idx, 0)); break; // Parenthesized
            case 8: // MemberAccess: receiver inferred; member type is a BCL/host boundary.
                InferExpression(Child(idx, 0));
                t = ColumnarTypeLattice.External;
                break;
            case 9: // Call [callee, args...]
            {
                var calleeIdx = Child(idx, 0);
                InferExpression(calleeIdx);
                var argTypes = new string[_nodes.ChildCount(idx) - 1];
                for (var n = 1; n < _nodes.ChildCount(idx); n++)
                    argTypes[n - 1] = InferExpression(Child(idx, n));
                t = CallReturnType(calleeIdx, argTypes);
                break;
            }
            case 10: // IndexAccess [object, index]
            {
                var objType = InferExpression(Child(idx, 0));
                InferExpression(Child(idx, 1));
                t = ColumnarTypeLattice.ElementType(objType);
                break;
            }
            case 11: // Unary [operand]
            {
                var opType = InferExpression(Child(idx, 0));
                t = ColumnarTypeLattice.Unary(Text(idx), opType);
                break;
            }
            case 12: // Binary [left, right]
            {
                var l = InferExpression(Child(idx, 0));
                var r = InferExpression(Child(idx, 1));
                t = ColumnarTypeLattice.Binary(Text(idx), l, r);
                break;
            }
            case 13: // Ternary [cond, then, else]
            {
                InferExpression(Child(idx, 0));
                var a = InferExpression(Child(idx, 1));
                var b = InferExpression(Child(idx, 2));
                t = a == b ? a : ColumnarTypeLattice.Wider(a, b);
                break;
            }
            case 14: // Assignment [target, value]
            {
                var target = InferExpression(Child(idx, 0));
                InferExpression(Child(idx, 1));
                t = target;
                break;
            }
            case 15: // New [type, args...]: result is the constructed type; args are inferred.
                for (var n = 1; n < _nodes.ChildCount(idx); n++)
                    InferExpression(Child(idx, n));
                t = CanonType(Child(idx, 0));
                break;
            case 36: // ObjectInitializer [type, name0, value0, ...]: result is the constructed type.
                t = CanonType(Child(idx, 0));
                break;
            case 42: // BareNew [type]: result is the constructed type.
                t = CanonType(Child(idx, 0));
                break;
            case 16: // Cast [type, operand]: result is the target type; operand inferred.
                InferExpression(Child(idx, 1));
                t = CanonType(Child(idx, 0));
                break;
            default: t = ColumnarTypeLattice.External; break;
        }

        _types.Add(t);
        return t;
    }

    private string LookupType(string name)
    {
        for (var i = _localScopes.Count - 1; i >= 0; i--)
        {
            if (_localScopes[i].TryGetValue(name, out var t))
                return t;
        }

        return _parameterTypes.TryGetValue(name, out var p) ? p : ColumnarTypeLattice.External;
    }

    private string CallReturnType(int calleeIdx, string[] argTypes)
    {
        if (_nodes.Kind(calleeIdx) != 6 || !_functionReturnTypes.TryGetValue(Text(calleeIdx), out var overloads))
            return ColumnarTypeLattice.External;

        if (overloads.Count == 1)
            return overloads[0].ReturnType;

        var match = -1;
        for (var i = 0; i < overloads.Count; i++)
        {
            if (!SignatureMatches(overloads[i].ParameterTypes, argTypes))
                continue;
            if (match >= 0)
                return ColumnarTypeLattice.External;
            match = i;
        }

        if (match >= 0)
            return overloads[match].ReturnType;

        return ColumnarTypeLattice.External;
    }

    private static bool SignatureMatches(IReadOnlyList<string> parameterTypes, string[] argTypes)
    {
        if (parameterTypes.Count != argTypes.Length)
            return false;

        for (var i = 0; i < parameterTypes.Count; i++)
        {
            if (parameterTypes[i] != argTypes[i])
                return false;
        }

        return true;
    }

    // Canonical type string from a columnar TYPE subtree (kinds 0 Simple,1 Generic,2 Array,3 Nullable,
    // 4 Union,5 ByRef) — matches ColumnarFunctionSymbol.CanonicalType exactly.
    private string CanonType(int idx)
    {
        switch (_nodes.Kind(idx))
        {
            case 0:
                return Text(idx);
            case 1:
            {
                var sb = new System.Text.StringBuilder();
                sb.Append(Text(idx)).Append('<');
                for (var k = 0; k < _nodes.ChildCount(idx); k++)
                {
                    if (k > 0) sb.Append(',');
                    sb.Append(CanonType(Child(idx, k)));
                }

                sb.Append('>');
                return sb.ToString();
            }
            case 2: return CanonType(Child(idx, 0)) + "[]";
            case 3: return CanonType(Child(idx, 0)) + "?";
            case 4:
            {
                var sb = new System.Text.StringBuilder();
                for (var k = 0; k < _nodes.ChildCount(idx); k++)
                {
                    if (k > 0) sb.Append('|');
                    sb.Append(CanonType(Child(idx, k)));
                }

                return sb.ToString();
            }
            case 5: return "&" + CanonType(Child(idx, 0));
            default: return ColumnarTypeLattice.External;
        }
    }

    private void DeclareLocal(string name, string type)
    {
        if (_localScopes.Count == 0)
            _localScopes.Add(new Dictionary<string, string>(System.StringComparer.Ordinal));
        _localScopes[_localScopes.Count - 1][name] = type;
    }

    private int Child(int idx, int n) => _nodes.Child(idx, n);

    private string Text(int idx) => _nodes.Text(_source, idx);
}
