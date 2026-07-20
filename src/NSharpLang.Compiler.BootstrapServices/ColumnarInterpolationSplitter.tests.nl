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
