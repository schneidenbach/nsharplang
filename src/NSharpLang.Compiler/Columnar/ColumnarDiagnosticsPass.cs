using System.Collections.Generic;

namespace NSharpLang.Compiler.Columnar;

/// <summary>
/// COLUMNAR PIPELINE — stage 3b (docs/design/columnar-pipeline.md). Pure-structural semantic diagnostics
/// computed DIRECTLY over the columnar statement tables — no C# AST. These are the analyzer's
/// control-flow-shaped checks that need no type information: definite-return (NL305, "not all code paths
/// return a value"), unreachable-after-terminal (NL312), and unused-local (NL001, via
/// <see cref="CollectUnusedLocals"/> walked in source order with the adapter's cross-function name set).
///
/// This walks the SAME node tables Stage 3 (<see cref="ColumnarTypeInferer"/>) walks, over the statement node
/// kinds the parser kernel emits: 20 Return, 21 Break, 22 Continue, 23 ExpressionStatement,
/// 24 VariableDeclaration, 25 Block, 26 While, 27 If, 28 For, 29 Foreach, 30 Deconstruction, 40 TypedLocal,
/// 41 LocalFunction, 48 Throw, 49 Try (children [tryBlock, kind-50 CatchClauses]). The kernel refuses any
/// other statement form (switch, finally, using, lock, wrapper blocks …), so on every body the columnar pass
/// accepts, those shapes cannot occur — which is exactly why <see cref="StatementAlwaysReturns"/> is a
/// faithful RESTRICTION of the real <c>Analyzer.StatementAlwaysReturns</c> to the columnar subset. EVERY
/// kernel statement addition must extend StatementAlwaysReturns + CollectUnreachable in the SAME slice. The
/// rules are mirrored on the C# AST by the parity oracle in the tests, so the columnar diagnostics are
/// verified identical to walking the object-graph AST; definitive routed parity follows at stages 4–5.
/// </summary>
public sealed class ColumnarDiagnosticsPass
{
    private readonly ColumnarNodeTable _nodes;
    private readonly string _source;
    private readonly System.Func<int, (int Line, int Column)> _positionOf;

    internal ColumnarDiagnosticsPass(
        ColumnarNodeTable nodes, string source,
        System.Func<int, (int Line, int Column)> positionOf)
    {
        _nodes = nodes;
        _source = source;
        _positionOf = positionOf;
    }

    /// <summary>
    /// Structural diagnostics for one function body, given its canonical return type ("void" when the
    /// declaration omits a return type, matching the stage-1 symbol model). Descriptors are emitted in a
    /// deterministic order: first unreachable-after-terminal (<c>unreachable@&lt;line&gt;:&lt;col&gt;</c>) in
    /// traversal order, then control-transfer-out-of-finally (<c>finally-transfer@&lt;line&gt;:&lt;col&gt;</c>,
    /// NL319) in traversal order, then definite-return (<c>missing-return:&lt;canonicalReturnType&gt;</c>) when
    /// a non-void function does not return on all paths. Async/generator functions carry NL305 exemptions
    /// (isAsyncUnitTask / isIterator) that need BCL task-type knowledge; the adapter declines those sources to
    /// the C# analyzer before this pass runs.
    /// </summary>
    public List<string> Analyze(int bodyBlockIdx, string returnTypeCanonical)
    {
        var diagnostics = new List<string>();

        // NL312 — code after a statement that always exits is unreachable (mirrors Analyzer.AnalyzeStatements).
        CollectUnreachable(bodyBlockIdx, diagnostics);

        // NL319 — a return, or a break/continue whose target loop was entered outside the finally, cannot
        // leave a finally handler (mirrors Analyzer.ReportControlTransferOutOfFinally's call sites).
        CollectFinallyTransfers(bodyBlockIdx, finallyDepth: 0, breakTargetDepth: 0, continueTargetDepth: 0, diagnostics);

        // NL305 — a non-void function must return a value on every code path. Mirrors Analyzer.cs:644.
        if (returnTypeCanonical != "void" && !StatementAlwaysReturns(bodyBlockIdx))
            diagnostics.Add("missing-return:" + returnTypeCanonical);

        return diagnostics;
    }

    /// <summary>
    /// Unreachable-after-terminal (NL312), the columnar mirror of <c>Analyzer.AnalyzeStatements</c> (2017): in
    /// each statement list (a Block), once a statement always exits, the IMMEDIATELY following statement is
    /// reported unreachable (once), and the rest of that list is skipped. Recurses into nested blocks / if
    /// branches / while bodies exactly as <c>Analyzer.AnalyzeStatement</c> does, so unreachable code inside
    /// reachable nested blocks is still found. The reported position is the unreachable statement's start
    /// (<c>line:col</c>), via the same tokenizer line/col the parser records — matching the C# AST.
    /// </summary>
    private void CollectUnreachable(int idx, List<string> diagnostics)
    {
        switch (_nodes.Kind(idx))
        {
            case 25: // Block — the statement list where unreachable detection happens.
            {
                var terminated = false;
                for (var n = 0; n < _nodes.ChildCount(idx); n++)
                {
                    var child = Child(idx, n);
                    if (terminated)
                    {
                        var (line, column) = _positionOf(_nodes.SpanStart(child));
                        diagnostics.Add("unreachable@" + line + ":" + column);
                        break;
                    }

                    CollectUnreachable(child, diagnostics);
                    if (StatementAlwaysReturns(child))
                        terminated = true;
                }

                break;
            }

            case 26: // While [condition, body] — recurse into the body (the condition has no statements).
            case 51: // Lock [lockee, body] — recurse into the body (the lockee has no statements).
                CollectUnreachable(Child(idx, 1), diagnostics);
                break;

            case 27: // If [condition, then, else?] — recurse into both branches.
                CollectUnreachable(Child(idx, 1), diagnostics);
                if (_nodes.ChildCount(idx) > 2)
                    CollectUnreachable(Child(idx, 2), diagnostics);
                break;

            case 49: // Try [tryBlock, catch1..catchN, finally?] — recurse into the try, every clause's
                // block (each clause is a kind-50 CatchClause whose block is its LAST child), and the
                // optional trailing kind-25 finally block.
                CollectUnreachable(Child(idx, 0), diagnostics);
                for (var n = 1; n < _nodes.ChildCount(idx); n++)
                {
                    var clause = Child(idx, n);
                    if (_nodes.Kind(clause) == 25)
                        CollectUnreachable(clause, diagnostics);
                    else
                        CollectUnreachable(Child(clause, _nodes.ChildCount(clause) - 1), diagnostics);
                }

                break;

            // 20 Return, 21 Break, 22 Continue, 23 ExpressionStatement, 24 VariableDeclaration,
            // 48 Throw: no nested statement lists.
        }
    }

    /// <summary>
    /// Control-transfer-out-of-finally (NL319), the columnar mirror of the analyzer's finally-depth rule: a
    /// Return at finally depth &gt; 0, or a Break/Continue whose innermost target loop was entered at a
    /// SHALLOWER finally depth than the statement, would exit the finally handler — which ECMA-335 forbids
    /// (a finally completes only via endfinally). Loops opened INSIDE the finally record the current depth at
    /// entry, so their own break/continue stay legal — exactly the analyzer's loop-entry bookkeeping. Local
    /// functions (kind 41) need no boundary reset here: the kernel records them with zero children (their
    /// bodies live in separate node tables), and lambdas (kind 39) are expression-bodied, so no nested-body
    /// statement can appear in this walk. Reported at the transferring statement's start (line:col).
    /// </summary>
    private void CollectFinallyTransfers(int idx, int finallyDepth, int breakTargetDepth, int continueTargetDepth, List<string> diagnostics)
    {
        switch (_nodes.Kind(idx))
        {
            case 20: // Return — illegal anywhere inside a finally (depth, not immediate-parent: a return
                     // inside a try/lock nested in the finally still leaves it).
                if (finallyDepth > 0)
                    AddFinallyTransfer(idx, diagnostics);
                break;

            case 21: // Break — illegal when its target loop was entered at a shallower finally depth.
                if (finallyDepth > breakTargetDepth)
                    AddFinallyTransfer(idx, diagnostics);
                break;

            case 22: // Continue — same rule as break.
                if (finallyDepth > continueTargetDepth)
                    AddFinallyTransfer(idx, diagnostics);
                break;

            case 25: // Block — recurse the statement list.
                for (var n = 0; n < _nodes.ChildCount(idx); n++)
                    CollectFinallyTransfers(Child(idx, n), finallyDepth, breakTargetDepth, continueTargetDepth, diagnostics);
                break;

            case 26: // While [condition, body] — the body's break/continue target THIS loop.
                CollectFinallyTransfers(Child(idx, 1), finallyDepth, finallyDepth, finallyDepth, diagnostics);
                break;

            case 51: // Lock [lockee, body] — no loop entry; the body keeps the current targets
                     // (the lock's synthetic finally holds no user statements).
                CollectFinallyTransfers(Child(idx, 1), finallyDepth, breakTargetDepth, continueTargetDepth, diagnostics);
                break;

            case 27: // If [condition, then, else?] — recurse both branches.
                CollectFinallyTransfers(Child(idx, 1), finallyDepth, breakTargetDepth, continueTargetDepth, diagnostics);
                if (_nodes.ChildCount(idx) > 2)
                    CollectFinallyTransfers(Child(idx, 2), finallyDepth, breakTargetDepth, continueTargetDepth, diagnostics);
                break;

            case 28: // For [init, cond, incr, body] — only the body holds statements that can transfer.
                CollectFinallyTransfers(Child(idx, 3), finallyDepth, finallyDepth, finallyDepth, diagnostics);
                break;

            case 29: // Foreach [collection, body].
                CollectFinallyTransfers(Child(idx, 1), finallyDepth, finallyDepth, finallyDepth, diagnostics);
                break;

            case 49: // Try [tryBlock, catch1..catchN, finally?] — the trailing kind-25 child is the finally:
                // its statements walk at depth + 1; the try block and catch blocks keep the current depth.
                CollectFinallyTransfers(Child(idx, 0), finallyDepth, breakTargetDepth, continueTargetDepth, diagnostics);
                for (var n = 1; n < _nodes.ChildCount(idx); n++)
                {
                    var clause = Child(idx, n);
                    if (_nodes.Kind(clause) == 25)
                        CollectFinallyTransfers(clause, finallyDepth + 1, breakTargetDepth, continueTargetDepth, diagnostics);
                    else
                        CollectFinallyTransfers(Child(clause, _nodes.ChildCount(clause) - 1), finallyDepth, breakTargetDepth, continueTargetDepth, diagnostics);
                }

                break;

            // 23 ExpressionStatement, 24 VariableDeclaration, 30 Deconstruction, 40 TypedLocal,
            // 41 LocalFunction (zero children), 48 Throw (always legal in a finally): no nested statements.
        }
    }

    private void AddFinallyTransfer(int idx, List<string> diagnostics)
    {
        var (line, column) = _positionOf(_nodes.SpanStart(idx));
        diagnostics.Add("finally-transfer@" + line + ":" + column);
    }

    /// <summary>
    /// Whether control reaching this statement always exits the function (return). The columnar subset of
    /// <c>Analyzer.StatementAlwaysReturns</c>: a Return always exits; a Block exits if any contained statement
    /// exits (later statements are then unreachable); an If exits only when it has an else AND both branches
    /// exit. Every other columnar statement kind (Break, Continue, ExpressionStatement, VariableDeclaration,
    /// While) is non-exiting. Throw/switch/try/wrapper-block forms cannot appear (the kernel refuses them).
    /// </summary>
    private bool StatementAlwaysReturns(int idx)
    {
        switch (_nodes.Kind(idx))
        {
            case 20: // Return (with or without a value) — on kernel-accepted input there are no error placeholders.
            case 48: // Throw — always exits, exactly like the analyzer's StatementAlwaysReturns throw arm.
                return true;

            case 49: // Try [tryBlock, catch1..catchN, finally?] — the analyzer's rule VERBATIM: exits iff
            {        // the try exits AND there is at least ONE catch AND every catch clause's block exits.
                     // The FINALLY (a trailing kind-25 child) is IGNORED — probe-pinned: a zero-catch
                     // `try {return} finally {}` never satisfies always-returns (NL305 demands a trailing
                     // return).
                if (!StatementAlwaysReturns(Child(idx, 0)))
                    return false;
                var sawCatch = false;
                for (var n = 1; n < _nodes.ChildCount(idx); n++)
                {
                    var clause = Child(idx, n);
                    if (_nodes.Kind(clause) != 50)
                        continue; // the finally block — ignored by the analyzer's rule.
                    sawCatch = true;
                    if (!StatementAlwaysReturns(Child(clause, _nodes.ChildCount(clause) - 1)))
                        return false;
                }

                return sawCatch;
            }

            case 25: // Block — exits if any statement exits.
                for (var n = 0; n < _nodes.ChildCount(idx); n++)
                {
                    if (StatementAlwaysReturns(Child(idx, n)))
                        return true;
                }

                return false;

            case 27: // If [condition, then, else?] — exits only with an else where both branches exit.
                return _nodes.ChildCount(idx) > 2
                    && StatementAlwaysReturns(Child(idx, 1))
                    && StatementAlwaysReturns(Child(idx, 2));

            case 51: // Lock [lockee, body] — exits iff the body exits (probe-pinned: `lock s { return 1 }`
                     // with no trailing return satisfies the analyzer).
                return StatementAlwaysReturns(Child(idx, 1));

            default: // 21 Break, 22 Continue, 23 ExpressionStatement, 24 VariableDeclaration, 26 While.
                return false;
        }
    }

    /// <summary>
    /// Stage 3b-iii (unused-local, NL001) over one function body, walked in SOURCE ORDER. This faithfully
    /// reproduces the Linter's time-/scope-ordered behaviour: every identifier expression (kind 6) adds its
    /// name to <paramref name="usedNames"/> as it is encountered (the analog of the file-level
    /// <c>_usedVariables</c> the Linter's <c>MarkVariableUsed</c> populates — which the caller seeds with each
    /// function's parameters and does NOT clear between functions). Each <c>:=</c> local (kind 24) is recorded
    /// in the innermost enclosing Block's scope; when a Block (kind 25) finishes, its locals are checked against
    /// <paramref name="usedNames"/> AS OF THAT MOMENT — so a use appearing after the block closes (a later
    /// sibling block, or a later function) does NOT suppress it, while an earlier use (a prior function, an
    /// earlier statement, or a parameter) does. Discards (<c>_</c> / <c>_</c>-prefixed) are exempt. Reported at
    /// the declaration's line:col. Interpolated strings can't hide a use: the kernel refuses them, so such
    /// sources decline upstream.
    /// </summary>
    public void CollectUnusedLocals(int bodyRoot, System.Collections.Generic.HashSet<string> usedNames, List<string> unused)
        => WalkUnused(bodyRoot, usedNames, new List<List<(string Name, int Line, int Column)>>(), unused);

    private void WalkUnused(
        int idx, System.Collections.Generic.HashSet<string> usedNames,
        List<List<(string Name, int Line, int Column)>> blockStack, List<string> unused)
    {
        switch (_nodes.Kind(idx))
        {
            case 3: // StringLiteral — an INTERPOLATED literal ($-prefixed token) holds identifier USES
                // inside its holes that the kind-6 walk cannot see (a local used only in a hole would be
                // a FALSE NL001). The shared splitter extracts hole ROOT identifiers under the SAME
                // grammar the emitter models, so uses and emitted IL agree by construction; a literal
                // beyond that grammar keeps the throw — the adapter's catch declines the analysis to the
                // production linter, matching the emitter's decline of the identical program.
                if (_nodes.ValueLength(idx) > 0 && _source[_nodes.ValueStart(idx)] == '$')
                {
                    var interpolationParts = new List<ColumnarInterpolationSplitter.Part>();
                    if (!ColumnarInterpolationSplitter.TrySplit(
                            _source.Substring(_nodes.ValueStart(idx), _nodes.ValueLength(idx)), interpolationParts))
                        throw new System.InvalidOperationException("interpolated string — unused-local analysis declines");
                    ColumnarInterpolationSplitter.CollectHoleRoots(interpolationParts, usedNames);
                }
                return;

            case 6: // Identifier expression — a use of its name, recorded in traversal order. A value-less
                // node (nameStart -1) is a TYPE-kernel tuple node masquerading as kind 6 — never a name use
                // (and Text() on it would throw; type subtrees are also skipped wholesale below).
                if (_nodes.ValueStart(idx) >= 0)
                    usedNames.Add(Text(idx));
                return;

            case 38: // GenericCallee / BareNew — children are TYPE-kernel subtrees ONLY (their node kinds
            case 42: // collide with expression kinds); the callee name lives in the value span. Skip them,
                     // mirroring the emitter's capture-scan discipline.
                return;

            case 25: // Block — its own scope: collect its direct `:=` locals, then check them at block exit.
            {
                var scope = new List<(string Name, int Line, int Column)>();
                blockStack.Add(scope);
                for (var n = 0; n < _nodes.ChildCount(idx); n++)
                    WalkUnused(Child(idx, n), usedNames, blockStack, unused);

                foreach (var (name, line, column) in scope)
                {
                    if (name != "_"
                        && !name.StartsWith("_", System.StringComparison.Ordinal)
                        && !usedNames.Contains(name))
                    {
                        unused.Add("unused-local:" + name + "@" + line + ":" + column);
                    }
                }

                blockStack.RemoveAt(blockStack.Count - 1);
                return;
            }

            case 24: // VariableDeclaration (`:=`): declared in the innermost block; then its initializer's uses.
            {
                if (blockStack.Count > 0)
                {
                    var (line, column) = _positionOf(_nodes.SpanStart(idx));
                    blockStack[blockStack.Count - 1].Add((Text(idx), line, column));
                }

                for (var n = 0; n < _nodes.ChildCount(idx); n++)
                    WalkUnused(Child(idx, n), usedNames, blockStack, unused);
                return;
            }

            default: // every other statement/expression: recurse so nested identifiers, blocks, and decls are seen.
                for (var n = 0; n < _nodes.ChildCount(idx); n++)
                    WalkUnused(Child(idx, n), usedNames, blockStack, unused);
                return;
        }
    }

    private int Child(int idx, int n) => _nodes.Child(idx, n);

    private string Text(int idx) => _nodes.Text(_source, idx);
}
