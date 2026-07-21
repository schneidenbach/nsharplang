namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic

// Splitter contracts for the multi-argument call hole family (`{String.Join(sep, values)}`): an
// identifier-chain callee with TWO OR MORE balanced comma-separated arguments splits into a hole
// for the parsed-expression hole plan; malformed argument lists stay rejected at the split so the
// literal declines before any hole-plan work.

test "the splitter accepts a two argument call hole between literal text segments" {
    parts := new List<ColumnarInterpolationPart>()
    assert ColumnarInterpolationSplitter.TrySplit("$\"  Input: [{String.Join(separator, numbers)}]\"", parts)
    assert parts.Count == 3
    assert !parts[0].IsHole
    assert parts[0].Text == "  Input: ["
    assert parts[1].IsHole
    assert parts[1].Text == "String.Join(separator, numbers)"
    assert parts[1].Format == null
    assert !parts[2].IsHole
    assert parts[2].Text == "]"
}

test "the splitter accepts nested call arguments and three argument call holes" {
    nested := new List<ColumnarInterpolationPart>()
    assert ColumnarInterpolationSplitter.TrySplit("$\"x={Math.Max(a, Math.Min(b, c))}\"", nested)
    assert nested.Count == 2
    assert nested[1].IsHole
    assert nested[1].Text == "Math.Max(a, Math.Min(b, c))"

    three := new List<ColumnarInterpolationPart>()
    assert ColumnarInterpolationSplitter.TrySplit("$\"r={Range(0, 10, 2)}\"", three)
    assert three.Count == 2
    assert three[1].IsHole
    assert three[1].Text == "Range(0, 10, 2)"
}

test "the splitter rejects malformed multi argument call holes" {
    unbalanced := new List<ColumnarInterpolationPart>()
    assert !ColumnarInterpolationSplitter.TrySplit("$\"bad={String.Join(a, b))}\"", unbalanced), "An unbalanced argument list must not split."

    stringArgument := new List<ColumnarInterpolationPart>()
    assert !ColumnarInterpolationSplitter.TrySplit("$\"bad={String.Join(a, \\\"x\\\")}\"", stringArgument), "A nested string-literal argument must not split."

    trailingComma := new List<ColumnarInterpolationPart>()
    assert !ColumnarInterpolationSplitter.TrySplit("$\"bad={String.Join(a,)}\"", trailingComma), "An empty trailing argument must not split."

    parenthesizedCallee := new List<ColumnarInterpolationPart>()
    assert !ColumnarInterpolationSplitter.TrySplit("$\"bad={(x)(a, b)}\"", parenthesizedCallee), "A non-identifier callee must not split."
}

// Integer-additive constant FOLD contracts: the splitter owns the decision the C# emitter previously
// re-derived. A modeled hole folds to its Int32 value; a run or step that would overflow Int32, or any
// non-additive shape, declines so the hole rides the parsed-expression hole path unchanged.

test "the integer additive fold evaluates modeled constant holes" {
    corpus := 0
    assert ColumnarInterpolationSplitter.TryEvaluateIntegerAdditive("1000 + 1000 - 500", out corpus)
    assert corpus == 1500

    single := 0
    assert ColumnarInterpolationSplitter.TryEvaluateIntegerAdditive("42", out single)
    assert single == 42

    negative := 0
    assert ColumnarInterpolationSplitter.TryEvaluateIntegerAdditive("5 - 10", out negative)
    assert negative == -5

    spaced := 0
    assert ColumnarInterpolationSplitter.TryEvaluateIntegerAdditive("  7 + 3  ", out spaced)
    assert spaced == 10

    maxValue := 0
    assert ColumnarInterpolationSplitter.TryEvaluateIntegerAdditive("2147483647", out maxValue)
    assert maxValue == 2147483647

    zeroBounded := 0
    assert ColumnarInterpolationSplitter.TryEvaluateIntegerAdditive("2147483646 + 1", out zeroBounded)
    assert zeroBounded == 2147483647
}

test "the integer additive fold declines overflow and non additive shapes" {
    addOverflow := 0
    assert !ColumnarInterpolationSplitter.TryEvaluateIntegerAdditive("2147483647 + 1", out addOverflow), "An add that leaves Int32 must decline."

    subOverflow := 0
    assert !ColumnarInterpolationSplitter.TryEvaluateIntegerAdditive("0 - 2147483647 - 2", out subOverflow), "A subtract that leaves Int32 must decline."

    hugeRun := 0
    assert !ColumnarInterpolationSplitter.TryEvaluateIntegerAdditive("99999999999", out hugeRun), "A digit run wider than Int32 must decline."

    identifier := 0
    assert !ColumnarInterpolationSplitter.TryEvaluateIntegerAdditive("a + b", out identifier), "A non-digit term must decline."

    badOperator := 0
    assert !ColumnarInterpolationSplitter.TryEvaluateIntegerAdditive("1 * 2", out badOperator), "A non-additive operator must decline."

    danglingOperator := 0
    assert !ColumnarInterpolationSplitter.TryEvaluateIntegerAdditive("1 +", out danglingOperator), "A trailing operator with no term must decline."

    empty := 0
    assert !ColumnarInterpolationSplitter.TryEvaluateIntegerAdditive("   ", out empty), "Whitespace with no term must decline."
}
