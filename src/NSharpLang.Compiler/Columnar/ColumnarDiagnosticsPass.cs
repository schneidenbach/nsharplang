using System.Collections.Generic;

namespace NSharpLang.Compiler.Columnar;

/// <summary>
/// COLUMNAR PIPELINE — stage 3b (docs/design/columnar-pipeline.md). Pure-structural semantic diagnostics
/// computed DIRECTLY over the columnar statement tables — no C# AST. These are the analyzer's
/// control-flow-shaped checks that need no type information: definite-return (NL305, "not all code paths
/// return a value"), unreachable-after-terminal (NL312), and — added in a later sub-slice — unused-local.
///
/// This walks the SAME node tables Stage 3 (<see cref="ColumnarTypeInferer"/>) walks, over the statement node
/// kinds the parser kernel emits: 20 Return, 21 Break, 22 Continue, 23 ExpressionStatement,
/// 24 VariableDeclaration, 25 Block, 26 While, 27 If. The kernel refuses any other statement form (throw,
/// switch, try, for, foreach, wrapper blocks …), so on every body the columnar pass accepts, those shapes
/// cannot occur — which is exactly why <see cref="StatementAlwaysReturns"/> is a faithful RESTRICTION of the
/// real <c>Analyzer.StatementAlwaysReturns</c> to the columnar subset (Return / Block / If-with-else). The
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

            // 20 Return, 21 Break, 22 Continue, 23 ExpressionStatement, 24 VariableDeclaration: no nested lists.
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
                return true;

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

    private int Child(int idx, int n) => _childIndices[_childStart[idx] + n];
}
