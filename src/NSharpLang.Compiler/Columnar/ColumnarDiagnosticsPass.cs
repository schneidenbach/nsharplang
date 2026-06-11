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
    private readonly int[] _kinds;
    private readonly int[] _valueStarts;
    private readonly int[] _valueLengths;
    private readonly int[] _childStart;
    private readonly int[] _childCount;
    private readonly int[] _childIndices;
    private readonly int[] _spanStarts;
    private readonly string _source;
    private readonly System.Func<int, (int Line, int Column)> _positionOf;

    public ColumnarDiagnosticsPass(
        int[] kinds, int[] valueStarts, int[] valueLengths,
        int[] childStart, int[] childCount, int[] childIndices, int[] spanStarts, string source,
        System.Func<int, (int Line, int Column)> positionOf)
    {
        _kinds = kinds;
        _valueStarts = valueStarts;
        _valueLengths = valueLengths;
        _childStart = childStart;
        _childCount = childCount;
        _childIndices = childIndices;
        _spanStarts = spanStarts;
        _source = source;
        _positionOf = positionOf;
    }

    /// <summary>
    /// Structural diagnostics for one function body, given its canonical return type ("void" when the
    /// declaration omits a return type, matching the stage-1 symbol model). Descriptors are emitted in a
    /// deterministic order: first unreachable-after-terminal (<c>unreachable@&lt;line&gt;:&lt;col&gt;</c>) in
    /// traversal order, then definite-return (<c>missing-return:&lt;canonicalReturnType&gt;</c>) when a non-void
    /// function does not return on all paths. Async/generator functions carry NL305 exemptions (isAsyncUnitTask /
    /// isIterator) that need BCL task-type knowledge; the adapter declines those sources to the C# analyzer
    /// before this pass runs.
    /// </summary>
    public List<string> Analyze(int bodyBlockIdx, string returnTypeCanonical)
    {
        var diagnostics = new List<string>();

        // NL312 — code after a statement that always exits is unreachable (mirrors Analyzer.AnalyzeStatements).
        CollectUnreachable(bodyBlockIdx, diagnostics);

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
        switch (_kinds[idx])
        {
            case 25: // Block — the statement list where unreachable detection happens.
            {
                var terminated = false;
                for (var n = 0; n < _childCount[idx]; n++)
                {
                    var child = Child(idx, n);
                    if (terminated)
                    {
                        var (line, column) = _positionOf(_spanStarts[child]);
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
                CollectUnreachable(Child(idx, 1), diagnostics);
                break;

            case 27: // If [condition, then, else?] — recurse into both branches.
                CollectUnreachable(Child(idx, 1), diagnostics);
                if (_childCount[idx] > 2)
                    CollectUnreachable(Child(idx, 2), diagnostics);
                break;

            case 49: // Try [tryBlock, catch1..catchN, finally?] — recurse into the try, every clause's
                // block (each clause is a kind-50 CatchClause whose block is its LAST child), and the
                // optional trailing kind-25 finally block.
                CollectUnreachable(Child(idx, 0), diagnostics);
                for (var n = 1; n < _childCount[idx]; n++)
                {
                    var clause = Child(idx, n);
                    if (_kinds[clause] == 25)
                        CollectUnreachable(clause, diagnostics);
                    else
                        CollectUnreachable(Child(clause, _childCount[clause] - 1), diagnostics);
                }

                break;

            // 20 Return, 21 Break, 22 Continue, 23 ExpressionStatement, 24 VariableDeclaration,
            // 48 Throw: no nested statement lists.
        }
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
        switch (_kinds[idx])
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
                for (var n = 1; n < _childCount[idx]; n++)
                {
                    var clause = Child(idx, n);
                    if (_kinds[clause] != 50)
                        continue; // the finally block — ignored by the analyzer's rule.
                    sawCatch = true;
                    if (!StatementAlwaysReturns(Child(clause, _childCount[clause] - 1)))
                        return false;
                }

                return sawCatch;
            }

            case 25: // Block — exits if any statement exits.
                for (var n = 0; n < _childCount[idx]; n++)
                {
                    if (StatementAlwaysReturns(Child(idx, n)))
                        return true;
                }

                return false;

            case 27: // If [condition, then, else?] — exits only with an else where both branches exit.
                return _childCount[idx] > 2
                    && StatementAlwaysReturns(Child(idx, 1))
                    && StatementAlwaysReturns(Child(idx, 2));

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
        switch (_kinds[idx])
        {
            case 3: // StringLiteral — an INTERPOLATED literal ($-prefixed token) holds identifier USES the
                // kind-6 walk cannot see (probe-confirmed FALSE NL001: a local used only in a hole reported
                // unused). Throw so the adapter's catch declines the analysis to the production linter.
                if (_valueLengths[idx] > 0 && _source[_valueStarts[idx]] == '$')
                    throw new System.InvalidOperationException("interpolated string — unused-local analysis declines");
                return;

            case 6: // Identifier expression — a use of its name, recorded in traversal order. A value-less
                // node (nameStart -1) is a TYPE-kernel tuple node masquerading as kind 6 — never a name use
                // (and Text() on it would throw; type subtrees are also skipped wholesale below).
                if (_valueStarts[idx] >= 0)
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
                for (var n = 0; n < _childCount[idx]; n++)
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
                    var (line, column) = _positionOf(_spanStarts[idx]);
                    blockStack[blockStack.Count - 1].Add((Text(idx), line, column));
                }

                for (var n = 0; n < _childCount[idx]; n++)
                    WalkUnused(Child(idx, n), usedNames, blockStack, unused);
                return;
            }

            default: // every other statement/expression: recurse so nested identifiers, blocks, and decls are seen.
                for (var n = 0; n < _childCount[idx]; n++)
                    WalkUnused(Child(idx, n), usedNames, blockStack, unused);
                return;
        }
    }

    private int Child(int idx, int n) => _childIndices[_childStart[idx] + n];

    private string Text(int idx) => _source.Substring(_valueStarts[idx], _valueLengths[idx]);
}
