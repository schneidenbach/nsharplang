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

// Cast-hole split contracts: the splitter owns the decomposition the C# emitter previously re-derived.
// A modeled `(Type)operand` hole splits into a trimmed target-type name (no internal whitespace) and a
// trimmed non-empty operand; any other shape declines so the hole rides the equality/chain/parsed path.

test "the cast split decomposes modeled cast holes" {
    localTarget := ""
    localOperand := ""
    assert ColumnarInterpolationSplitter.TrySplitCast("(int)priority", out localTarget, out localOperand)
    assert localTarget == "int"
    assert localOperand == "priority"

    memberTarget := ""
    memberOperand := ""
    assert ColumnarInterpolationSplitter.TrySplitCast("(int)task.Priority", out memberTarget, out memberOperand)
    assert memberTarget == "int"
    assert memberOperand == "task.Priority"

    formatShapeTarget := ""
    formatShapeOperand := ""
    assert ColumnarInterpolationSplitter.TrySplitCast("(int)error.Code", out formatShapeTarget, out formatShapeOperand)
    assert formatShapeTarget == "int"
    assert formatShapeOperand == "error.Code"

    spacedTarget := ""
    spacedOperand := ""
    assert ColumnarInterpolationSplitter.TrySplitCast("( int )priority", out spacedTarget, out spacedOperand)
    assert spacedTarget == "int"
    assert spacedOperand == "priority"
}

test "the cast split declines non cast shapes" {
    noParenTarget := ""
    noParenOperand := ""
    assert !ColumnarInterpolationSplitter.TrySplitCast("int priority", out noParenTarget, out noParenOperand), "A hole without a leading paren is not a cast."

    emptyTarget := ""
    emptyOperand := ""
    assert !ColumnarInterpolationSplitter.TrySplitCast("()priority", out emptyTarget, out emptyOperand), "An empty target is not a cast."

    noOperandTarget := ""
    noOperandOperand := ""
    assert !ColumnarInterpolationSplitter.TrySplitCast("(int)", out noOperandTarget, out noOperandOperand), "A cast with no operand declines."

    spacedNameTarget := ""
    spacedNameOperand := ""
    assert !ColumnarInterpolationSplitter.TrySplitCast("(unsigned int)x", out spacedNameTarget, out spacedNameOperand), "A target with internal whitespace declines."
}

// Equality-hole split contracts: the splitter owns the decomposition. A modeled hole with exactly one
// top-level `==`/`!=` splits into trimmed non-empty sides; none, a second operator, or an empty side
// declines so the hole rides the chain/parsed-expression path unchanged.

test "the equality split decomposes modeled equality holes" {
    eqLeft := ""
    eqOp := ""
    eqRight := ""
    assert ColumnarInterpolationSplitter.TrySplitEquality("a == b", out eqLeft, out eqOp, out eqRight)
    assert eqLeft == "a"
    assert eqOp == "=="
    assert eqRight == "b"

    neLeft := ""
    neOp := ""
    neRight := ""
    assert ColumnarInterpolationSplitter.TrySplitEquality("x != y", out neLeft, out neOp, out neRight)
    assert neLeft == "x"
    assert neOp == "!="
    assert neRight == "y"

    chainLeft := ""
    chainOp := ""
    chainRight := ""
    assert ColumnarInterpolationSplitter.TrySplitEquality("left.Value == right.Value", out chainLeft, out chainOp, out chainRight)
    assert chainLeft == "left.Value"
    assert chainOp == "=="
    assert chainRight == "right.Value"
}

test "the equality split declines non equality shapes" {
    noOpLeft := ""
    noOpOp := ""
    noOpRight := ""
    assert !ColumnarInterpolationSplitter.TrySplitEquality("a + b", out noOpLeft, out noOpOp, out noOpRight), "A hole with no equality operator declines."

    doubleLeft := ""
    doubleOp := ""
    doubleRight := ""
    assert !ColumnarInterpolationSplitter.TrySplitEquality("a == b == c", out doubleLeft, out doubleOp, out doubleRight), "A second equality operator declines."

    emptySideLeft := ""
    emptySideOp := ""
    emptySideRight := ""
    assert !ColumnarInterpolationSplitter.TrySplitEquality("== b", out emptySideLeft, out emptySideOp, out emptySideRight), "An empty left side declines."
}

// Coalesce-hole split contracts: the splitter owns the decomposition the C# emitter previously re-derived
// inline (its last ad-hoc string-split decision). A modeled hole with exactly one top-level `??` splits
// into trimmed non-empty sides; none, a second operator, an empty side, or a lone `?` declines so the hole
// rides the chain/base-call/parsed-expression path unchanged.

test "the coalesce split decomposes modeled coalesce holes" {
    corpusLeft := ""
    corpusRight := ""
    assert ColumnarInterpolationSplitter.TrySplitCoalesce("email ?? missingEmail", out corpusLeft, out corpusRight)
    assert corpusLeft == "email"
    assert corpusRight == "missingEmail"

    tightLeft := ""
    tightRight := ""
    assert ColumnarInterpolationSplitter.TrySplitCoalesce("a??b", out tightLeft, out tightRight)
    assert tightLeft == "a"
    assert tightRight == "b"

    chainLeft := ""
    chainRight := ""
    assert ColumnarInterpolationSplitter.TrySplitCoalesce("user.Name ?? fallback.Name", out chainLeft, out chainRight)
    assert chainLeft == "user.Name"
    assert chainRight == "fallback.Name"
}

test "the coalesce split declines non coalesce shapes" {
    noOpLeft := ""
    noOpRight := ""
    assert !ColumnarInterpolationSplitter.TrySplitCoalesce("email", out noOpLeft, out noOpRight), "A hole with no coalesce operator declines."

    doubleLeft := ""
    doubleRight := ""
    assert !ColumnarInterpolationSplitter.TrySplitCoalesce("a ?? b ?? c", out doubleLeft, out doubleRight), "A second coalesce operator declines."

    emptyLeftLeft := ""
    emptyLeftRight := ""
    assert !ColumnarInterpolationSplitter.TrySplitCoalesce("?? b", out emptyLeftLeft, out emptyLeftRight), "An empty left side declines."

    emptyRightLeft := ""
    emptyRightRight := ""
    assert !ColumnarInterpolationSplitter.TrySplitCoalesce("a ??", out emptyRightLeft, out emptyRightRight), "An empty right side declines."

    ternaryLeft := ""
    ternaryRight := ""
    assert !ColumnarInterpolationSplitter.TrySplitCoalesce("a ? b : c", out ternaryLeft, out ternaryRight), "A single `?` is not a coalesce operator."
}
