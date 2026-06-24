using System;
using System.Collections.Generic;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.Performance;

/// <summary>
/// A single construct that prevents Native AOT / trimming, located at a source position
/// and tagged with the kind of safety guarantee it violates. Purely descriptive: produced
/// </summary>
public sealed record AotBlocker(
    AotSafetyKind Kind,
    string File,
    int Line,
    int Column,
    int Length,
    string Construct,
    AbiBoundary EnclosingBoundary,
    string? EnclosingDeclaration)
{
    /// <summary>The diagnostic code that describes this blocker.</summary>
    public ErrorCode DiagnosticCode => Kind switch
    {
        AotSafetyKind.MetadataRequired => ErrorCode.AotReflectionUse,
        AotSafetyKind.DynamicCodeRequired => Construct.Contains("MakeGeneric", StringComparison.Ordinal)
            ? ErrorCode.AotMakeGenericType
            : ErrorCode.AotDynamicCode,
        AotSafetyKind.ExpressionTreeRequired => ErrorCode.AotExpressionTree,
        _ => ErrorCode.AotDynamicCode,
    };

    public bool IsOnPublicSurface => EnclosingBoundary == AbiBoundary.ClrPublic;
}

/// <summary>
/// Pure-analysis pass that walks a parsed <see cref="CompilationUnit"/> and records every
/// construct that blocks Native AOT or trimming: runtime reflection, dynamic code generation,
/// runtime generic instantiation (MakeGenericType/MakeGenericMethod), and expression trees.
///
/// <see cref="AotBlocker"/> facts and records the corresponding <see cref="PerformanceFacts"/>
/// into a <see cref="PerformanceFactStore"/>. See docs/design/performance-compiler-refactor.md
/// "Native AOT".
/// </summary>
public sealed class AotBlockerAnalyzer
{
    private readonly AbiClassifier _abi;
    private readonly List<AotBlocker> _blockers = new();

    public AotBlockerAnalyzer(string file, AbiClassifier abi, SemanticModel? semanticModel = null)
    {
        _abi = abi ?? new AbiClassifier(file ?? string.Empty);
    }

    /// <summary>All AOT blockers discovered during <see cref="Analyze"/>, in source order.</summary>
    public IReadOnlyList<AotBlocker> Blockers => _blockers;

    /// <summary>
    /// Walks the compilation unit, records every AOT blocker, and stores the corresponding
    /// <see cref="PerformanceFacts"/> into <paramref name="store"/> keyed by source position.
    /// Returns this analyzer so callers can chain.
    /// </summary>
    public AotBlockerAnalyzer Analyze(CompilationUnit? unit, PerformanceFactStore? store = null)
    {
        if (unit is null)
        {
            return this;
        }

        var context = new DeclarationContext(AbiBoundary.ClrInternal, null);
        foreach (var declaration in unit.Declarations)
        {
            WalkDeclaration(declaration, context);
        }

        if (store != null)
        {
            foreach (var blocker in _blockers)
            {
                store.Record(blocker.File, blocker.Line, blocker.Column, PerformanceFacts.Default with
                {
                    AotSafety = blocker.Kind,
                    Escape = EscapeKind.ReflectionBoundary,
                });
            }
        }

        return this;
    }

    private readonly record struct DeclarationContext(AbiBoundary Boundary, string? Name);

    private DeclarationContext ContextFor(string name, int line, int column, DeclarationContext fallback)
    {
        var boundary = _abi.GetBoundary(line, column) ?? fallback.Boundary;
        return new DeclarationContext(boundary, name);
    }

    /// <summary>
    /// Build the context for a type <em>member</em> (method/property/etc.), qualifying the
    /// member name with its declaring type so the attribute-emission key is unique across types
    /// and overloads with the same simple name (e.g. <c>Inspector.Describe</c> vs a top-level
    /// <c>Describe</c>). The IL emitter looks members up by this same qualified key.
    /// </summary>
    private DeclarationContext MemberContextFor(string memberName, int line, int column, DeclarationContext typeContext)
    {
        var boundary = _abi.GetBoundary(line, column) ?? typeContext.Boundary;
        var qualified = string.IsNullOrEmpty(typeContext.Name)
            ? memberName
            : $"{typeContext.Name}.{memberName}";
        return new DeclarationContext(boundary, qualified);
    }

    private void WalkDeclaration(Declaration declaration, DeclarationContext context)
    {
        switch (declaration)
        {
            case FunctionDeclaration func:
                var funcContext = ContextFor(func.Name, func.Line, func.Column, context);
                if (func.Body != null)
                {
                    WalkStatement(func.Body, funcContext);
                }
                if (func.ExpressionBody != null)
                {
                    WalkExpression(func.ExpressionBody, funcContext);
                }
                break;

            case ClassDeclaration cls:
                WalkMembers(cls.Members, ContextFor(cls.Name, cls.Line, cls.Column, context));
                break;

            case StructDeclaration st:
                WalkMembers(st.Members, ContextFor(st.Name, st.Line, st.Column, context));
                break;

            case RecordDeclaration rec:
                WalkMembers(rec.Members, ContextFor(rec.Name, rec.Line, rec.Column, context));
                break;

            case SoaRecordDeclaration:
                break;

            case InterfaceDeclaration iface:
                WalkMembers(iface.Members, ContextFor(iface.Name, iface.Line, iface.Column, context));
                break;

            case FieldDeclaration field when field.Initializer != null:
                WalkExpression(field.Initializer, ContextFor(field.Name, field.Line, field.Column, context));
                break;
        }
    }

    private void WalkMembers(List<Declaration> members, DeclarationContext typeContext)
    {
        foreach (var member in members)
        {
            switch (member)
            {
                case FunctionDeclaration func:
                    var funcContext = MemberContextFor(func.Name, func.Line, func.Column, typeContext);
                    if (func.Body != null)
                    {
                        WalkStatement(func.Body, funcContext);
                    }
                    if (func.ExpressionBody != null)
                    {
                        WalkExpression(func.ExpressionBody, funcContext);
                    }
                    break;

                case PropertyDeclaration prop:
                    var propContext = MemberContextFor(prop.Name, prop.Line, prop.Column, typeContext);
                    if (prop.GetBody != null)
                    {
                        WalkStatement(prop.GetBody, propContext);
                    }
                    if (prop.SetBody != null)
                    {
                        WalkStatement(prop.SetBody, propContext);
                    }
                    if (prop.ExpressionBody != null)
                    {
                        WalkExpression(prop.ExpressionBody, propContext);
                    }
                    break;

                case FieldDeclaration field when field.Initializer != null:
                    WalkExpression(field.Initializer, MemberContextFor(field.Name, field.Line, field.Column, typeContext));
                    break;

                case ConstructorDeclaration ctor:
                    WalkStatement(ctor.Body, typeContext);
                    break;

                case IndexerDeclaration indexer:
                    if (indexer.GetBody != null)
                    {
                        WalkStatement(indexer.GetBody, typeContext);
                    }
                    if (indexer.SetBody != null)
                    {
                        WalkStatement(indexer.SetBody, typeContext);
                    }
                    break;

                // Nested types recurse with their own boundary.
                case ClassDeclaration:
                case StructDeclaration:
                case RecordDeclaration:
                case InterfaceDeclaration:
                    WalkDeclaration(member, typeContext);
                    break;
            }
        }
    }

    private void WalkStatement(Statement? statement, DeclarationContext context)
    {
        switch (statement)
        {
            case null:
                break;
            case BlockStatement block:
                foreach (var s in block.Statements)
                {
                    WalkStatement(s, context);
                }
                break;
            case ExpressionStatement expr:
                WalkExpression(expr.Expression, context);
                break;
            case VariableDeclarationStatement varDecl when varDecl.Initializer != null:
                WalkExpression(varDecl.Initializer, context);
                break;
            case TupleDeconstructionStatement tuple:
                WalkExpression(tuple.Initializer, context);
                break;
            case ReturnStatement ret when ret.Value != null:
                WalkExpression(ret.Value, context);
                break;
            case YieldStatement yield when yield.Value != null:
                WalkExpression(yield.Value, context);
                break;
            case ThrowStatement th:
                WalkExpression(th.Expression, context);
                break;
            case PrintStatement print:
                WalkExpression(print.Value, context);
                break;
            case IfStatement ifStmt:
                WalkExpression(ifStmt.Condition, context);
                WalkStatement(ifStmt.ThenStatement, context);
                WalkStatement(ifStmt.ElseStatement, context);
                break;
            case ForStatement forStmt:
                WalkStatement(forStmt.Initializer, context);
                if (forStmt.Condition != null) WalkExpression(forStmt.Condition, context);
                if (forStmt.Iterator != null) WalkExpression(forStmt.Iterator, context);
                WalkStatement(forStmt.Body, context);
                break;
            case ForeachStatement foreachStmt:
                WalkExpression(foreachStmt.Collection, context);
                WalkStatement(foreachStmt.Body, context);
                break;
            case AwaitForEachStatement awaitForeach:
                WalkExpression(awaitForeach.Collection, context);
                WalkStatement(awaitForeach.Body, context);
                break;
            case WhileStatement whileStmt:
                WalkExpression(whileStmt.Condition, context);
                WalkStatement(whileStmt.Body, context);
                break;
            case LockStatement lockStmt:
                WalkExpression(lockStmt.LockObject, context);
                WalkStatement(lockStmt.Body, context);
                break;
            case UsingStatement usingStmt:
                WalkStatement(usingStmt.Declaration, context);
                if (usingStmt.Expression != null) WalkExpression(usingStmt.Expression, context);
                WalkStatement(usingStmt.Body, context);
                break;
            case TryStatement tryStmt:
                WalkStatement(tryStmt.TryBlock, context);
                foreach (var c in tryStmt.CatchClauses)
                {
                    WalkStatement(c.Block, context);
                }
                WalkStatement(tryStmt.FinallyBlock, context);
                break;
            case SwitchStatement switchStmt:
                WalkExpression(switchStmt.Value, context);
                foreach (var switchCase in switchStmt.Cases)
                {
                    foreach (var s in switchCase.Statements)
                    {
                        WalkStatement(s, context);
                    }
                }
                break;
            case LocalFunctionStatement local:
                // Local functions are never on the public surface; keep the enclosing
                // boundary so a blocker inside a public method still annotates that method.
                WalkStatement(local.Function.Body, context);
                if (local.Function.ExpressionBody != null)
                {
                    WalkExpression(local.Function.ExpressionBody, context);
                }
                break;
        }
    }

    private void WalkExpression(Expression? expression, DeclarationContext context)
    {
        switch (expression)
        {
            case null:
                break;

            case CallExpression call:
                WalkChildExpressions(call, context);
                break;

            case NewExpression newExpr:
                WalkChildExpressions(newExpr, context);
                break;

            case LambdaExpression lambda:
                WalkExpression(lambda.ExpressionBody, context);
                WalkStatement(lambda.BlockBody, context);
                break;

            case NameofExpression:
                // nameof operands never execute (they lower to a string literal), so a call or
                // construction referenced only inside nameof is not an AOT blocker.
                break;

            default:
                // Everything else is purely structural: a blocker anywhere in a child expression
                // belongs to this declaration. Routing through AstChildren (instead of per-node
                // child lists) keeps this fail-safe — a node or child slot missing here used to
                // hide blockers placed in that subtree.
                WalkChildExpressions(expression, context);
                break;
        }
    }

    private void WalkChildExpressions(Expression expression, DeclarationContext context)
    {
        foreach (var child in AstChildren.Of(expression))
        {
            WalkExpression(child, context);
        }
    }

}
