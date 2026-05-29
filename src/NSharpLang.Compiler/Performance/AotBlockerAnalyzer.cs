using System;
using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.Performance;

/// <summary>
/// A single construct that prevents Native AOT / trimming, located at a source position
/// and tagged with the kind of safety guarantee it violates. Purely descriptive: produced
/// by <see cref="AotBlockerAnalyzer"/> and consumed by diagnostics, the perf report, and
/// the AOT-attribute emitter.
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

    /// <summary>
    /// True when this blocker sits on a construct visible to external CLR consumers, so the
    /// emitted assembly should carry a <c>[Requires*]</c> annotation on the public surface.
    /// </summary>
    public bool IsOnPublicSurface => EnclosingBoundary == AbiBoundary.ClrPublic;
}

/// <summary>
/// Pure-analysis pass that walks a parsed <see cref="CompilationUnit"/> and records every
/// construct that blocks Native AOT or trimming: runtime reflection, dynamic code generation,
/// runtime generic instantiation (MakeGenericType/MakeGenericMethod), and expression trees.
///
/// Detection is shape/name-based over the AST — N# has no dedicated reflection syntax, so the
/// pass recognizes the well-known BCL entry points that force a JIT or runtime metadata. It
/// performs NO emitter changes; it only produces <see cref="AotBlocker"/> facts and records
/// the corresponding <see cref="PerformanceFacts"/> into a <see cref="PerformanceFactStore"/>.
/// See docs/design/performance-compiler-refactor.md "Native AOT".
/// </summary>
public sealed class AotBlockerAnalyzer
{
    private readonly string _file;
    private readonly AbiClassifier _abi;
    private readonly List<AotBlocker> _blockers = new();

    // Member names that, when invoked on any receiver, read runtime metadata reflectively.
    // Kept deliberately conservative: only members that are reflection-specific, so ordinary
    // APIs that merely share a verb (e.g. a domain `GetType()` is rare) are not over-reported.
    private static readonly HashSet<string> ReflectionMembers = new(StringComparer.Ordinal)
    {
        "GetType",
        "GetMethod", "GetMethods",
        "GetProperty", "GetProperties",
        "GetField", "GetFields",
        "GetMember", "GetMembers",
        "GetConstructor", "GetConstructors",
        "GetCustomAttribute", "GetCustomAttributes",
        "GetInterface", "GetInterfaces",
        "InvokeMember",
        "GetRuntimeMethod", "GetRuntimeProperty", "GetRuntimeField",
    };

    // Member names that, when invoked, generate or dispatch code at runtime (no JIT under AOT).
    private static readonly HashSet<string> DynamicCodeMembers = new(StringComparer.Ordinal)
    {
        "DynamicInvoke",
        "CreateDelegate",
    };

    // Generic-instantiation members that build types/methods at runtime.
    private static readonly HashSet<string> MakeGenericMembers = new(StringComparer.Ordinal)
    {
        "MakeGenericType",
        "MakeGenericMethod",
    };

    // Receiver types whose static members generate code or instantiate types at runtime.
    private static readonly HashSet<string> DynamicCodeReceivers = new(StringComparer.Ordinal)
    {
        "Activator",
    };

    public AotBlockerAnalyzer(string file, AbiClassifier abi)
    {
        _file = file ?? string.Empty;
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
                    var funcContext = ContextFor(func.Name, func.Line, func.Column, typeContext);
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
                    var propContext = ContextFor(prop.Name, prop.Line, prop.Column, typeContext);
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
                    WalkExpression(field.Initializer, ContextFor(field.Name, field.Line, field.Column, typeContext));
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
                InspectCall(call, context);
                WalkExpression(call.Callee, context);
                foreach (var arg in call.Arguments)
                {
                    WalkExpression(arg.Value, context);
                }
                break;

            case MemberAccessExpression member:
                WalkExpression(member.Object, context);
                break;

            case NewExpression newExpr:
                InspectNew(newExpr, context);
                foreach (var arg in newExpr.ConstructorArguments)
                {
                    WalkExpression(arg.Value, context);
                }
                if (newExpr.Initializer != null)
                {
                    foreach (var prop in newExpr.Initializer.Properties)
                    {
                        WalkExpression(prop.Value, context);
                    }
                }
                break;

            case BinaryExpression binary:
                WalkExpression(binary.Left, context);
                WalkExpression(binary.Right, context);
                break;
            case UnaryExpression unary:
                WalkExpression(unary.Operand, context);
                break;
            case AssignmentExpression assign:
                WalkExpression(assign.Target, context);
                WalkExpression(assign.Value, context);
                break;
            case TernaryExpression ternary:
                WalkExpression(ternary.Condition, context);
                WalkExpression(ternary.ThenExpression, context);
                WalkExpression(ternary.ElseExpression, context);
                break;
            case LambdaExpression lambda:
                WalkExpression(lambda.ExpressionBody, context);
                WalkStatement(lambda.BlockBody, context);
                break;
            case IndexAccessExpression index:
                WalkExpression(index.Object, context);
                WalkExpression(index.Index, context);
                break;
            case CastExpression cast:
                WalkExpression(cast.Expression, context);
                break;
            case IsExpression isExpr:
                WalkExpression(isExpr.Expression, context);
                break;
            case MatchExpression match:
                WalkExpression(match.Value, context);
                foreach (var matchCase in match.Cases)
                {
                    if (matchCase.Guard != null) WalkExpression(matchCase.Guard, context);
                    WalkExpression(matchCase.Expression, context);
                }
                break;
            case AwaitExpression await:
                WalkExpression(await.Expression, context);
                break;
            case ThrowExpression throwExpr:
                WalkExpression(throwExpr.Expression, context);
                break;
            case MustExpression must:
                WalkExpression(must.Expression, context);
                break;
            case ParenthesizedExpression paren:
                WalkExpression(paren.Inner, context);
                break;
            case WithExpression with:
                WalkExpression(with.Target, context);
                foreach (var prop in with.Properties)
                {
                    WalkExpression(prop.Value, context);
                }
                break;
            case ArrayLiteralExpression array:
                foreach (var element in array.Elements)
                {
                    WalkExpression(element, context);
                }
                break;
            case TupleExpression tuple:
                foreach (var element in tuple.Elements)
                {
                    WalkExpression(element.Value, context);
                }
                break;
            case SpreadExpression spread:
                WalkExpression(spread.Expression, context);
                break;
            case RangeExpression range:
                WalkExpression(range.Start, context);
                WalkExpression(range.End, context);
                break;
            case InterpolatedStringExpression interp:
                foreach (var part in interp.Parts.OfType<InterpolatedStringHole>())
                {
                    WalkExpression(part.Expression, context);
                }
                break;
            case CheckedExpression chk:
                WalkExpression(chk.Expression, context);
                break;
            case UncheckedExpression unchk:
                WalkExpression(unchk.Expression, context);
                break;
        }
    }

    private void InspectCall(CallExpression call, DeclarationContext context)
    {
        if (call.Callee is not MemberAccessExpression member)
        {
            return;
        }

        var name = member.MemberName;

        if (MakeGenericMembers.Contains(name))
        {
            Record(AotSafetyKind.DynamicCodeRequired, member, name, context);
            return;
        }

        if (ReflectionMembers.Contains(name))
        {
            Record(AotSafetyKind.MetadataRequired, member, name, context);
            return;
        }

        if (DynamicCodeMembers.Contains(name))
        {
            Record(AotSafetyKind.DynamicCodeRequired, member, name, context);
            return;
        }

        // Static dynamic-code entry points: Activator.CreateInstance(...).
        if (name == "CreateInstance" &&
            member.Object is IdentifierExpression receiver &&
            DynamicCodeReceivers.Contains(receiver.Name))
        {
            Record(AotSafetyKind.DynamicCodeRequired, member, $"{receiver.Name}.{name}", context);
            return;
        }

        // Expression-tree construction / compilation:
        //   Expression.Lambda(...), Expression.Call(...), expr.Compile().
        if (member.Object is IdentifierExpression exprFactory && exprFactory.Name == "Expression")
        {
            Record(AotSafetyKind.ExpressionTreeRequired, member, $"Expression.{name}", context);
            return;
        }

        if (name == "Compile")
        {
            // `.Compile()` is the LINQ-expression-tree compile entry point; AOT cannot JIT it.
            Record(AotSafetyKind.ExpressionTreeRequired, member, "Compile", context);
        }
    }

    private void InspectNew(NewExpression newExpr, DeclarationContext context)
    {
        var typeName = TypeName(newExpr.Type);
        if (typeName == null)
        {
            return;
        }

        // Constructing a LINQ expression tree directly (rare, but explicit).
        if (typeName.StartsWith("Expression", StringComparison.Ordinal))
        {
            Record(AotSafetyKind.ExpressionTreeRequired, newExpr.Line, newExpr.Column, typeName.Length, $"new {typeName}", context);
        }
    }

    private static string? TypeName(TypeReference? type) => type switch
    {
        SimpleTypeReference simple => simple.Name,
        GenericTypeReference generic => generic.Name,
        _ => null,
    };

    private void Record(AotSafetyKind kind, MemberAccessExpression member, string construct, DeclarationContext context)
    {
        // MemberAccessExpression.Column points at the access dot; the member name begins one
        // column later. Underline the member name itself for a precise caret. Use the member
        // name length (not the full reported construct, which may include a receiver prefix).
        Record(kind, member.Line, member.Column + 1, Math.Max(1, member.MemberName.Length), construct, context);
    }

    private void Record(AotSafetyKind kind, int line, int column, int length, string construct, DeclarationContext context)
    {
        _blockers.Add(new AotBlocker(
            kind,
            _file,
            line,
            column,
            Math.Max(1, length),
            construct,
            context.Boundary,
            context.Name));
    }
}
