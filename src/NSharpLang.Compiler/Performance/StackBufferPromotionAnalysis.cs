using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.Performance;

/// <summary>
/// A local array declaration that has been proven safe to store as a stack-allocated
/// <c>[InlineArray]</c> buffer instead of a heap array. The local stays semantically a
/// <c>T[]</c> to the rest of the type system; only its storage and the IL emitted for its
/// reads/writes change. See docs/design/performance-compiler-refactor.md "Stack buffers".
/// </summary>
/// <param name="Name">The N# local variable name.</param>
/// <param name="Length">The fixed, compile-time-constant element count.</param>
/// <param name="ElementTypeName">The N# element type name (e.g. <c>int</c>), resolved by the emitter.</param>
public sealed record PromotedStackBuffer(string Name, int Length, string ElementTypeName);

/// <summary>
/// Decides which non-escaping, fixed-size local array literals in a function body can be
/// promoted from a heap array to a stack-allocated <c>[InlineArray]</c> buffer.
///
/// This is a deliberately conservative, <b>fail-closed</b> analysis. A local is promoted only
/// when the analysis can <i>prove</i> the array never escapes its frame and is only ever used
/// through the small whitelist of shapes the emitter knows how to lower (index get/set,
/// <c>.Length</c>, and compiler-lowered <c>foreach</c>). Any reference the analysis does not
/// recognise — passing the local as an argument, returning it, capturing it, reassigning it,
/// taking its identity, casting it, pattern-matching it, calling a method on it other than the
/// whitelisted members, or any use the walker simply does not understand — disqualifies the
/// local. Mis-promotion would turn a safe heap array into stack memory corruption, so when in
/// doubt the analysis keeps the heap array.
/// </summary>
public static class StackBufferPromotionAnalysis
{
    /// <summary>
    /// The largest element count eligible for stack promotion. Larger literals stay on the heap
    /// to avoid blowing the stack. Mirrors the conservative thresholds used by C#'s own
    /// <c>stackalloc</c> guidance.
    /// </summary>
    public const int MaxPromotableLength = 32;

    /// <summary>
    /// N# element type names whose runtime type is a primitive, unmanaged, blittable value type.
    /// Only these are eligible for v1: a buffer of unmanaged elements has no GC references, so a
    /// stack <c>[InlineArray]</c> of them is trivially GC-safe.
    /// </summary>
    private static readonly HashSet<string> UnmanagedPrimitiveTypeNames = new()
    {
        "int", "uint", "long", "ulong", "short", "ushort",
        "byte", "sbyte", "bool", "char", "float", "double",
        "nint", "nuint",
    };

    /// <summary>
    /// Analyse <paramref name="body"/> and return the locals that can be stack-promoted.
    /// Returns an empty list when nothing qualifies (the common case) or when the method shape
    /// (async, generator, or containing nested functions/lambdas that could capture locals)
    /// makes promotion unsafe.
    /// </summary>
    public static IReadOnlyList<PromotedStackBuffer> Analyze(
        BlockStatement? body,
        IReadOnlyList<Parameter> parameters,
        bool isAsync,
        bool isGenerator)
    {
        if (body is null || isAsync || isGenerator)
        {
            return System.Array.Empty<PromotedStackBuffer>();
        }

        // Candidates: locals declared with an explicit `T[]` type, an unmanaged primitive element
        // type, and a constant-size array-literal initializer with no spreads.
        var candidates = new Dictionary<string, CandidateInfo>();
        CollectCandidates(body, candidates);
        if (candidates.Count == 0)
        {
            return System.Array.Empty<PromotedStackBuffer>();
        }

        // A name shadowed by a parameter is ambiguous; never promote it.
        foreach (var parameter in parameters)
        {
            candidates.Remove(parameter.Name);
        }

        if (candidates.Count == 0)
        {
            return System.Array.Empty<PromotedStackBuffer>();
        }

        // Walk the whole body and disqualify any candidate used outside the safe whitelist.
        var disqualified = new HashSet<string>();
        var walker = new UsageWalker(candidates.Keys.ToHashSet(), disqualified);
        walker.VisitBlock(body);

        var result = new List<PromotedStackBuffer>();
        foreach (var (name, info) in candidates)
        {
            if (!disqualified.Contains(name))
            {
                result.Add(new PromotedStackBuffer(name, info.Length, info.ElementTypeName));
            }
        }

        return result;
    }

    private readonly record struct CandidateInfo(int Length, string ElementTypeName);

    private static void CollectCandidates(BlockStatement body, Dictionary<string, CandidateInfo> candidates)
    {
        foreach (var statement in EnumerateStatements(body))
        {
            if (statement is not VariableDeclarationStatement
                {
                    Type: ArrayTypeReference { ElementType: SimpleTypeReference elementType },
                    Initializer: ArrayLiteralExpression literal,
                    Name: var name,
                } declaration)
            {
                continue;
            }

            // Reject reassignable bindings handled elsewhere — Let/Const/Readonly all bind once
            // here, but we additionally require no reassignment (enforced by the usage walker).
            if (!UnmanagedPrimitiveTypeNames.Contains(elementType.Name))
            {
                continue;
            }

            if (literal.Elements.Count == 0 || literal.Elements.Count > MaxPromotableLength)
            {
                continue;
            }

            // No spreads: the buffer length must be a compile-time constant equal to the literal
            // element count.
            if (literal.Elements.Any(element => element is SpreadExpression))
            {
                continue;
            }

            // A name declared more than once in the same body is ambiguous; bail on duplicates.
            if (candidates.ContainsKey(name))
            {
                candidates.Remove(name);
                continue;
            }

            candidates[name] = new CandidateInfo(literal.Elements.Count, elementType.Name);
        }
    }

    /// <summary>
    /// Flattens every statement reachable in <paramref name="body"/>, descending into nested
    /// blocks and control-flow bodies, so candidate declarations are found wherever they appear.
    /// </summary>
    private static IEnumerable<Statement> EnumerateStatements(Statement statement)
    {
        yield return statement;

        switch (statement)
        {
            case BlockStatement block:
                foreach (var inner in block.Statements)
                {
                    foreach (var nested in EnumerateStatements(inner))
                    {
                        yield return nested;
                    }
                }
                break;
            case IfStatement ifStatement:
                foreach (var nested in EnumerateStatements(ifStatement.ThenStatement))
                {
                    yield return nested;
                }
                if (ifStatement.ElseStatement is { } elseStatement)
                {
                    foreach (var nested in EnumerateStatements(elseStatement))
                    {
                        yield return nested;
                    }
                }
                break;
            case ForStatement forStatement:
                if (forStatement.Initializer is { } init)
                {
                    foreach (var nested in EnumerateStatements(init))
                    {
                        yield return nested;
                    }
                }
                foreach (var nested in EnumerateStatements(forStatement.Body))
                {
                    yield return nested;
                }
                break;
            case ForeachStatement foreachStatement:
                foreach (var nested in EnumerateStatements(foreachStatement.Body))
                {
                    yield return nested;
                }
                break;
            case WhileStatement whileStatement:
                foreach (var nested in EnumerateStatements(whileStatement.Body))
                {
                    yield return nested;
                }
                break;
            case TryStatement tryStatement:
                foreach (var nested in EnumerateStatements(tryStatement.TryBlock))
                {
                    yield return nested;
                }
                foreach (var catchClause in tryStatement.CatchClauses)
                {
                    foreach (var nested in EnumerateStatements(catchClause.Block))
                    {
                        yield return nested;
                    }
                }
                if (tryStatement.FinallyBlock is { } finallyBlock)
                {
                    foreach (var nested in EnumerateStatements(finallyBlock))
                    {
                        yield return nested;
                    }
                }
                break;
            case UsingStatement usingStatement:
                if (usingStatement.Declaration is { } usingDeclaration)
                {
                    yield return usingDeclaration;
                }
                if (usingStatement.Body is { } usingBody)
                {
                    foreach (var nested in EnumerateStatements(usingBody))
                    {
                        yield return nested;
                    }
                }
                break;
            case LockStatement lockStatement:
                foreach (var nested in EnumerateStatements(lockStatement.Body))
                {
                    yield return nested;
                }
                break;
            case SwitchStatement switchStatement:
                foreach (var switchCase in switchStatement.Cases)
                {
                    foreach (var caseStatement in switchCase.Statements)
                    {
                        foreach (var nested in EnumerateStatements(caseStatement))
                        {
                            yield return nested;
                        }
                    }
                }
                break;
        }
    }

    /// <summary>
    /// Walks every expression and statement in the body and records, in <c>_disqualified</c>,
    /// any candidate name that appears in a context the emitter cannot safely lower as a stack
    /// buffer. The walker is intentionally exhaustive over expression shapes and treats anything
    /// unrecognised as a disqualifying use (fail-closed).
    /// </summary>
    private sealed class UsageWalker
    {
        private readonly HashSet<string> _candidates;
        private readonly HashSet<string> _disqualified;

        public UsageWalker(HashSet<string> candidates, HashSet<string> disqualified)
        {
            _candidates = candidates;
            _disqualified = disqualified;
        }

        private void Disqualify(string name) => _disqualified.Add(name);

        public void VisitBlock(BlockStatement block)
        {
            foreach (var statement in block.Statements)
            {
                VisitStatement(statement);
            }
        }

        private void VisitStatement(Statement? statement)
        {
            switch (statement)
            {
                case null:
                case EmptyStatement:
                case BreakStatement:
                case ContinueStatement:
                    break;
                case BlockStatement block:
                    VisitBlock(block);
                    break;
                case ExpressionStatement expression:
                    VisitExpression(expression.Expression);
                    break;
                case PrintStatement print:
                    VisitExpression(print.Value);
                    break;
                case VariableDeclarationStatement declaration:
                    // The candidate's own declaration initializer is the array literal we are
                    // promoting; visiting it is harmless because the literal contains no
                    // candidate references. Other declarations' initializers are ordinary uses.
                    VisitExpression(declaration.Initializer);
                    break;
                case TupleDeconstructionStatement tuple:
                    VisitExpression(tuple.Initializer);
                    break;
                case ReturnStatement returnStatement:
                    // Returning the array escapes it.
                    VisitExpressionAsEscape(returnStatement.Value);
                    break;
                case YieldStatement yieldStatement:
                    VisitExpressionAsEscape(yieldStatement.Value);
                    break;
                case ThrowStatement throwStatement:
                    VisitExpressionAsEscape(throwStatement.Expression);
                    break;
                case IfStatement ifStatement:
                    VisitExpression(ifStatement.Condition);
                    VisitStatement(ifStatement.ThenStatement);
                    VisitStatement(ifStatement.ElseStatement);
                    break;
                case ForStatement forStatement:
                    VisitStatement(forStatement.Initializer);
                    VisitExpression(forStatement.Condition);
                    VisitExpression(forStatement.Iterator);
                    VisitStatement(forStatement.Body);
                    break;
                case ForeachStatement foreachStatement:
                    // A candidate used as the foreach collection is a safe, whitelisted use: the
                    // emitter lowers `for x in buf` over the stack buffer directly. Any *other*
                    // expression shape in the collection position is an ordinary use.
                    VisitForeachCollection(foreachStatement.Collection);
                    VisitStatement(foreachStatement.Body);
                    break;
                case AwaitForEachStatement awaitForeach:
                    // Async iteration is not part of the lowering whitelist.
                    VisitExpressionAsEscape(awaitForeach.Collection);
                    VisitStatement(awaitForeach.Body);
                    break;
                case WhileStatement whileStatement:
                    VisitExpression(whileStatement.Condition);
                    VisitStatement(whileStatement.Body);
                    break;
                case TryStatement tryStatement:
                    VisitBlock(tryStatement.TryBlock);
                    foreach (var catchClause in tryStatement.CatchClauses)
                    {
                        VisitBlock(catchClause.Block);
                    }
                    VisitStatement(tryStatement.FinallyBlock);
                    break;
                case UsingStatement usingStatement:
                    VisitStatement(usingStatement.Declaration);
                    VisitExpressionAsEscape(usingStatement.Expression);
                    VisitStatement(usingStatement.Body);
                    break;
                case LockStatement lockStatement:
                    VisitExpressionAsEscape(lockStatement.LockObject);
                    VisitBlock(lockStatement.Body);
                    break;
                case SwitchStatement switchStatement:
                    VisitExpression(switchStatement.Value);
                    foreach (var switchCase in switchStatement.Cases)
                    {
                        foreach (var caseStatement in switchCase.Statements)
                        {
                            VisitStatement(caseStatement);
                        }
                    }
                    break;
                case AssertStatement assert:
                    VisitExpression(assert.Condition);
                    VisitExpression(assert.Message);
                    break;
                case AssertThrowsStatement assertThrows:
                    VisitBlock(assertThrows.Body);
                    break;
                case LocalFunctionStatement:
                    // A nested function can capture any enclosing local by reference. We cannot
                    // promote a buffer that a closure might observe, so fail closed: disqualify
                    // every candidate in the method. (Nested functions are rare in hot paths.)
                    DisqualifyAll();
                    break;
                default:
                    // Unknown statement shape: fail closed by disqualifying every candidate.
                    DisqualifyAll();
                    break;
            }
        }

        /// <summary>
        /// Visits a foreach collection expression. A bare candidate identifier here is a safe,
        /// whitelisted use. Anything else is treated as an ordinary (escaping-capable) expression.
        /// </summary>
        private void VisitForeachCollection(Expression collection)
        {
            if (collection is IdentifierExpression)
            {
                // Safe: emitter lowers foreach over the stack buffer. No further visiting needed.
                return;
            }

            VisitExpression(collection);
        }

        /// <summary>
        /// Visits an expression where a candidate appearing as a bare identifier or simple index
        /// access is treated as escaping (e.g. argument, return value, RHS of assignment).
        /// </summary>
        private void VisitExpressionAsEscape(Expression? expression)
        {
            if (expression is IdentifierExpression identifier && _candidates.Contains(identifier.Name))
            {
                Disqualify(identifier.Name);
                return;
            }

            VisitExpression(expression);
        }

        private void VisitExpression(Expression? expression)
        {
            switch (expression)
            {
                case null:
                case IntLiteralExpression:
                case FloatLiteralExpression:
                case CharLiteralExpression:
                case StringLiteralExpression:
                case BoolLiteralExpression:
                case NullLiteralExpression:
                case ThisExpression:
                case BaseExpression:
                case DefaultExpression:
                case TypeOfExpression:
                case SizeOfExpression:
                    break;

                case IdentifierExpression identifier:
                    // A bare candidate reference (loaded as a value) escapes — the whole point of
                    // promotion is that the array object is never materialised. The whitelisted
                    // uses (index, .Length, foreach) intercept the identifier *before* reaching
                    // this case, so any identifier we see here is a disqualifying use.
                    if (_candidates.Contains(identifier.Name))
                    {
                        Disqualify(identifier.Name);
                    }
                    break;

                case IndexAccessExpression indexAccess:
                    VisitIndexAccess(indexAccess);
                    break;

                case MemberAccessExpression memberAccess:
                    VisitMemberAccess(memberAccess);
                    break;

                case AssignmentExpression assignment:
                    VisitAssignment(assignment);
                    break;

                case BinaryExpression binary:
                    VisitExpression(binary.Left);
                    VisitExpression(binary.Right);
                    break;

                case UnaryExpression unary:
                    VisitExpression(unary.Operand);
                    break;

                case TernaryExpression ternary:
                    VisitExpression(ternary.Condition);
                    VisitExpressionAsEscape(ternary.ThenExpression);
                    VisitExpressionAsEscape(ternary.ElseExpression);
                    break;

                case RangeExpression range:
                    VisitExpression(range.Start);
                    VisitExpression(range.End);
                    break;

                case CallExpression call:
                    VisitCall(call);
                    break;

                case InterpolatedStringExpression interpolated:
                    foreach (var part in interpolated.Parts)
                    {
                        if (part is InterpolatedStringHole hole)
                        {
                            VisitExpressionAsEscape(hole.Expression);
                        }
                    }
                    break;

                case CastExpression cast:
                    // Casting the array (e.g. to object/IEnumerable) escapes it.
                    VisitExpressionAsEscape(cast.Expression);
                    break;

                case IsExpression isExpression:
                    VisitExpressionAsEscape(isExpression.Expression);
                    break;

                case ParenthesizedExpression parenthesized:
                    VisitExpression(parenthesized.Inner);
                    break;

                case CheckedExpression @checked:
                    VisitExpression(@checked.Expression);
                    break;

                case UncheckedExpression @unchecked:
                    VisitExpression(@unchecked.Expression);
                    break;

                case MustExpression must:
                    VisitExpressionAsEscape(must.Expression);
                    break;

                case AwaitExpression await:
                    VisitExpressionAsEscape(await.Expression);
                    break;

                case ThrowExpression throwExpression:
                    VisitExpressionAsEscape(throwExpression.Expression);
                    break;

                case NameofExpression nameofExpression:
                    VisitExpressionAsEscape(nameofExpression.Target);
                    break;

                case SpreadExpression spread:
                    VisitExpressionAsEscape(spread.Expression);
                    break;

                case ArrayLiteralExpression arrayLiteral:
                    foreach (var element in arrayLiteral.Elements)
                    {
                        VisitExpressionAsEscape(element);
                    }
                    break;

                case TupleExpression tuple:
                    foreach (var element in tuple.Elements)
                    {
                        VisitExpressionAsEscape(element.Value);
                    }
                    break;

                case MatchExpression match:
                    VisitExpressionAsEscape(match.Value);
                    foreach (var matchCase in match.Cases)
                    {
                        VisitExpressionAsEscape(matchCase.Guard);
                        VisitExpressionAsEscape(matchCase.Expression);
                    }
                    break;

                case LambdaExpression:
                    // A lambda can capture any enclosing local by reference. Fail closed:
                    // disqualify every candidate in the method.
                    DisqualifyAll();
                    break;

                case NewExpression newExpression:
                    foreach (var argument in newExpression.ConstructorArguments)
                    {
                        VisitExpressionAsEscape(argument.Value);
                    }
                    VisitExpression(newExpression.Initializer);
                    break;

                case ObjectInitializerExpression objectInitializer:
                    foreach (var initializer in objectInitializer.Properties)
                    {
                        VisitExpressionAsEscape(initializer.IndexExpression);
                        VisitExpressionAsEscape(initializer.Value);
                    }
                    break;

                case WithExpression withExpression:
                    VisitExpressionAsEscape(withExpression.Target);
                    foreach (var initializer in withExpression.Properties)
                    {
                        VisitExpressionAsEscape(initializer.IndexExpression);
                        VisitExpressionAsEscape(initializer.Value);
                    }
                    break;

                default:
                    // Unknown expression shape: fail closed. We cannot prove non-escape, so
                    // disqualify every candidate in the method.
                    DisqualifyAll();
                    break;
            }
        }

        private void VisitIndexAccess(IndexAccessExpression indexAccess)
        {
            // `buf[i]` is the canonical safe use: the candidate is the index *object*. The index
            // expression itself is an ordinary use (and could itself reference a candidate, which
            // would be an escape). A null-conditional index (`buf?[i]`) is not lowered specially,
            // so it disqualifies.
            if (indexAccess.Object is IdentifierExpression identifier && _candidates.Contains(identifier.Name))
            {
                if (indexAccess.IsNullConditional)
                {
                    Disqualify(identifier.Name);
                }

                // Safe object position — do not visit it as an escape. Still visit the index.
                VisitExpressionAsEscape(indexAccess.Index);
                return;
            }

            VisitExpressionAsEscape(indexAccess.Object);
            VisitExpressionAsEscape(indexAccess.Index);
        }

        private void VisitMemberAccess(MemberAccessExpression memberAccess)
        {
            // `buf.Length` is the only whitelisted member. Any other member access on the
            // candidate (e.g. `.Clone()`, `.GetType()`, `.AsSpan()`) disqualifies it.
            if (memberAccess.Object is IdentifierExpression identifier && _candidates.Contains(identifier.Name))
            {
                if (memberAccess.MemberName != "Length" || memberAccess.IsNullConditional)
                {
                    Disqualify(identifier.Name);
                }

                // Safe member — do not treat the object as an escape.
                return;
            }

            VisitExpressionAsEscape(memberAccess.Object);
        }

        private void VisitAssignment(AssignmentExpression assignment)
        {
            // `buf[i] = value` is safe in the target position. `buf = value` (reassignment) or
            // `buf.X = value` disqualifies. The RHS is an ordinary (escaping-capable) use.
            switch (assignment.Target)
            {
                case IndexAccessExpression { Object: IdentifierExpression targetIdentifier } indexTarget
                    when _candidates.Contains(targetIdentifier.Name):
                    if (indexTarget.IsNullConditional || assignment.Operator == AssignmentOperator.NullCoalesceAssign)
                    {
                        // Null-coalescing assignment is not lowered for stack buffers.
                        Disqualify(targetIdentifier.Name);
                    }
                    VisitExpressionAsEscape(indexTarget.Index);
                    break;

                case IdentifierExpression identifierTarget when _candidates.Contains(identifierTarget.Name):
                    // Reassigning the whole buffer is not supported (would need to re-promote).
                    Disqualify(identifierTarget.Name);
                    break;

                default:
                    VisitExpression(assignment.Target);
                    break;
            }

            VisitExpressionAsEscape(assignment.Value);
        }

        private void VisitCall(CallExpression call)
        {
            // The callee may be a member access whose receiver is a candidate (e.g. `buf.Foo()`),
            // which is not whitelisted and must disqualify.
            VisitExpression(call.Callee);

            foreach (var argument in call.Arguments)
            {
                // Passing the candidate to any call escapes it (the callee body is opaque here).
                VisitExpressionAsEscape(argument.Value);
            }
        }

        /// <summary>
        /// Disqualifies every candidate in the method. Used for capture contexts (lambdas, local
        /// functions) and unknown expression/statement shapes where we cannot prove non-escape.
        /// Maximally conservative and trivially fail-closed.
        /// </summary>
        private void DisqualifyAll()
        {
            foreach (var name in _candidates)
            {
                Disqualify(name);
            }
        }
    }
}
