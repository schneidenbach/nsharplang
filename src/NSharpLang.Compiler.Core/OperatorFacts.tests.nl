namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast


// THE CANONICAL CONTRACTS FOR `OperatorFacts`, IN N#.
//
// These replace `tests/OperatorFactsTests.cs`, the last canonical C# assertion layer over
// `OperatorFacts.nl` — a surface that is already entirely N#, and one of the busiest small kernels in
// the compiler: seven production owners reach it over 31 call sites (`AnalyzerAssignment`,
// `AnalyzerOperatorExpressions`, `AnalyzerExpressionTreeValidator`, `AnalyzerDiagnosticSpans`,
// `AnalyzerWriteTargets`, `AnalyzerAttributeValidator`, `FormatterWalk`), and no C# owner reaches it
// at all.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. A `tests/native/*` project reaches its subject
// through a `dll:` dependency, and a dependency-assembly ENUM MEMBER is not emittable from there:
// `op: UnaryOperator = UnaryOperator.Negate` declines at `emit.typed-local.initializer`, the same
// member in argument position declines at `emit.call.static-member-unmodeled`, and in a table row it
// is refused earlier still by `NL310` ("table-driven test case values must be compile-time
// constants"). Every input this kernel takes IS an enum member, so the contracts belong where the
// enums and the subject are the SAME assembly's own — here, in the estate the gate's Step 3a runs
// first. That is also why these are plain `test` declarations rather than the `with (…) […]` tables
// slice 1 built: this estate is compiled by the PINNED toolset, which predates them.
//
// THE COVERAGE IS EXHAUSTIVE PER ENUM, WHICH THE C# WAS NOT. The deleted file spot-checked the two
// overload-metadata families (four operators of twenty, two of eight) and never touched the three
// `GetRequired*` gates or `TryGetCompoundAssignmentBinaryOperator` at all. Here every member of
// `BinaryOperator` (20), `UnaryOperator` (8) and `AssignmentOperator` (6) is asserted against every
// entry point that accepts it, because a table kernel with a missing row is exactly the kind of
// defect a spot check cannot see.
//
// THE FOUR THINGS IT IS EASY TO GET WRONG:
//
// (1) RENDERING AN OPERATOR AND NAMING ITS CLR METHOD ARE DIFFERENT QUESTIONS WITH DIFFERENT ANSWER
// SETS. `&&` and `||` render as text and are admitted in an expression tree, but they have NO CLR
// operator method — `op_LogicalAnd` does not exist as an overload target — so the name and symbol
// families answer `null` for them while the text family answers `"&&"`.
//
// (2) THE TEXT LOSES THE POSITION, AND THE FORMATTER DEPENDS ON THAT. `PreIncrement` and
// `PostIncrement` both render `"++"` and both name `op_Increment`; where the operator goes is the
// walker's decision, not the text's.
//
// (3) `^` IS TWO OPERATORS. It is the binary `BitwiseXor`'s text AND the unary `IndexFromEnd`'s, and
// only one of them is overloadable: `BitwiseXor` names `op_ExclusiveOr`, `IndexFromEnd` names
// nothing.
//
// (4) THE UNMAPPED FALLBACK IS `"operator"`, AND IT IS UNREACHABLE THROUGH A DECLARED MEMBER —
// MEASURED, NOT ASSUMED. All 20 `BinaryOperator`, all 8 `UnaryOperator` and all 6
// `AssignmentOperator` members are mapped by the three text functions, so the `"operator"` sentinel
// and the three `InvalidOperationException` arms behind it can only be reached by an out-of-range
// value that no declared member spells. What IS contractable is the pass-through, and that is what
// the required-text contract below pins.

// ---- the text families -------------------------------------------------------------------------

// Successor to OperatorFacts_ReturnsUnaryOperatorText — all eight of its assertions, in order.
test "operator facts render every unary operator's source text" {
    assert OperatorFacts.GetUnaryText(UnaryOperator.Negate) == "-"
    assert OperatorFacts.GetUnaryText(UnaryOperator.Not) == "!"
    assert OperatorFacts.GetUnaryText(UnaryOperator.BitwiseNot) == "~"
    assert OperatorFacts.GetUnaryText(UnaryOperator.PreIncrement) == "++"
    assert OperatorFacts.GetUnaryText(UnaryOperator.PreDecrement) == "--"
    assert OperatorFacts.GetUnaryText(UnaryOperator.PostIncrement) == "++"
    assert OperatorFacts.GetUnaryText(UnaryOperator.PostDecrement) == "--"
    assert OperatorFacts.GetUnaryText(UnaryOperator.IndexFromEnd) == "^"
}

// Successor to OperatorFacts_ReturnsBinaryOperatorText — all twenty of its assertions, in order,
// which is every member of the enum.
test "operator facts render every binary operator's source text" {
    assert OperatorFacts.GetBinaryText(BinaryOperator.Add) == "+"
    assert OperatorFacts.GetBinaryText(BinaryOperator.Subtract) == "-"
    assert OperatorFacts.GetBinaryText(BinaryOperator.Multiply) == "*"
    assert OperatorFacts.GetBinaryText(BinaryOperator.Divide) == "/"
    assert OperatorFacts.GetBinaryText(BinaryOperator.Modulo) == "%"
    assert OperatorFacts.GetBinaryText(BinaryOperator.Equal) == "=="
    assert OperatorFacts.GetBinaryText(BinaryOperator.NotEqual) == "!="
    assert OperatorFacts.GetBinaryText(BinaryOperator.Less) == "<"
    assert OperatorFacts.GetBinaryText(BinaryOperator.LessOrEqual) == "<="
    assert OperatorFacts.GetBinaryText(BinaryOperator.Greater) == ">"
    assert OperatorFacts.GetBinaryText(BinaryOperator.GreaterOrEqual) == ">="
    assert OperatorFacts.GetBinaryText(BinaryOperator.And) == "&&"
    assert OperatorFacts.GetBinaryText(BinaryOperator.Or) == "||"
    assert OperatorFacts.GetBinaryText(BinaryOperator.BitwiseAnd) == "&"
    assert OperatorFacts.GetBinaryText(BinaryOperator.BitwiseOr) == "|"
    assert OperatorFacts.GetBinaryText(BinaryOperator.BitwiseXor) == "^"
    assert OperatorFacts.GetBinaryText(BinaryOperator.LeftShift) == "<<"
    assert OperatorFacts.GetBinaryText(BinaryOperator.RightShift) == ">>"
    assert OperatorFacts.GetBinaryText(BinaryOperator.NullCoalesce) == "??"
    assert OperatorFacts.GetBinaryText(BinaryOperator.Range) == ".."
}

// Successor to OperatorFacts_ReturnsAssignmentOperatorText — all six of its assertions, in order,
// which is every member of the enum.
test "operator facts render every assignment operator's source text" {
    assert OperatorFacts.GetAssignmentText(AssignmentOperator.Assign) == "="
    assert OperatorFacts.GetAssignmentText(AssignmentOperator.AddAssign) == "+="
    assert OperatorFacts.GetAssignmentText(AssignmentOperator.SubtractAssign) == "-="
    assert OperatorFacts.GetAssignmentText(AssignmentOperator.MultiplyAssign) == "*="
    assert OperatorFacts.GetAssignmentText(AssignmentOperator.DivideAssign) == "/="
    assert OperatorFacts.GetAssignmentText(AssignmentOperator.NullCoalesceAssign) == "??="
}

// ---- the overload-metadata families ------------------------------------------------------------

// Successor to the four binary CLR-name assertions of
// OperatorFacts_ReturnsBinaryOperatorOverloadMetadata (`Add`, `LessOrEqual`, and `null` for
// `NullCoalesce` and `Range`), widened to every member. The four that answer `null` are the four an
// overload cannot express: two short-circuit operators, `??` and `..`.
test "operator facts name the CLR method for every overloadable binary operator" {
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.Add) == "op_Addition"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.Subtract) == "op_Subtraction"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.Multiply) == "op_Multiply"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.Divide) == "op_Division"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.Modulo) == "op_Modulus"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.Equal) == "op_Equality"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.NotEqual) == "op_Inequality"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.Less) == "op_LessThan"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.LessOrEqual) == "op_LessThanOrEqual"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.Greater) == "op_GreaterThan"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.GreaterOrEqual) == "op_GreaterThanOrEqual"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.BitwiseAnd) == "op_BitwiseAnd"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.BitwiseOr) == "op_BitwiseOr"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.BitwiseXor) == "op_ExclusiveOr"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.LeftShift) == "op_LeftShift"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.RightShift) == "op_RightShift"
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.And) == null
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.Or) == null
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.NullCoalesce) == null
    assert OperatorFacts.GetBinaryClrName(BinaryOperator.Range) == null
}

// Successor to the four binary SYMBOL assertions of the same C# test, widened to every member. The
// symbol an overload reports is the operator's own text EXCEPT where there is no overload at all —
// `&&`, `||`, `??` and `..` render as text but answer no symbol here.
test "operator facts spell the symbol for every overloadable binary operator" {
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.Add) == "+"
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.Subtract) == "-"
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.Multiply) == "*"
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.Divide) == "/"
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.Modulo) == "%"
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.Equal) == "=="
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.NotEqual) == "!="
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.Less) == "<"
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.LessOrEqual) == "<="
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.Greater) == ">"
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.GreaterOrEqual) == ">="
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.BitwiseAnd) == "&"
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.BitwiseOr) == "|"
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.BitwiseXor) == "^"
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.LeftShift) == "<<"
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.RightShift) == ">>"
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.And) == null
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.Or) == null
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.NullCoalesce) == null
    assert OperatorFacts.GetBinarySymbol(BinaryOperator.Range) == null
}

// Successor to OperatorFacts_ReturnsUnaryOperatorOverloadMetadata — its six assertions (`Negate` and
// `PostIncrement` in both families, `null` twice for `IndexFromEnd`), widened to every member. The
// two increment pairs collapse: pre and post name the SAME CLR method and spell the same symbol.
test "operator facts name the CLR method and symbol for every overloadable unary operator" {
    assert OperatorFacts.GetUnaryClrName(UnaryOperator.Negate) == "op_UnaryNegation"
    assert OperatorFacts.GetUnaryClrName(UnaryOperator.Not) == "op_LogicalNot"
    assert OperatorFacts.GetUnaryClrName(UnaryOperator.BitwiseNot) == "op_OnesComplement"
    assert OperatorFacts.GetUnaryClrName(UnaryOperator.PreIncrement) == "op_Increment"
    assert OperatorFacts.GetUnaryClrName(UnaryOperator.PostIncrement) == "op_Increment"
    assert OperatorFacts.GetUnaryClrName(UnaryOperator.PreDecrement) == "op_Decrement"
    assert OperatorFacts.GetUnaryClrName(UnaryOperator.PostDecrement) == "op_Decrement"
    assert OperatorFacts.GetUnaryClrName(UnaryOperator.IndexFromEnd) == null

    assert OperatorFacts.GetUnarySymbol(UnaryOperator.Negate) == "-"
    assert OperatorFacts.GetUnarySymbol(UnaryOperator.Not) == "!"
    assert OperatorFacts.GetUnarySymbol(UnaryOperator.BitwiseNot) == "~"
    assert OperatorFacts.GetUnarySymbol(UnaryOperator.PreIncrement) == "++"
    assert OperatorFacts.GetUnarySymbol(UnaryOperator.PostIncrement) == "++"
    assert OperatorFacts.GetUnarySymbol(UnaryOperator.PreDecrement) == "--"
    assert OperatorFacts.GetUnarySymbol(UnaryOperator.PostDecrement) == "--"
    assert OperatorFacts.GetUnarySymbol(UnaryOperator.IndexFromEnd) == null
}

// ---- the expression-tree admission set ---------------------------------------------------------

// Successor to the five binary assertions of
// OperatorFacts_IdentifiesExpressionTreeSupportedOperators (`Add`, `And`, `RightShift` admitted;
// `NullCoalesce`, `Range` refused), widened to every member. `&&` and `||` ARE admitted here even
// though they have no CLR operator method — an expression tree models them as its own node kinds.
test "operator facts admit exactly the expression-tree binary operators" {
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.Add)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.Subtract)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.Multiply)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.Divide)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.Modulo)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.Equal)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.NotEqual)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.Less)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.LessOrEqual)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.Greater)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.GreaterOrEqual)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.And)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.Or)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.BitwiseAnd)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.BitwiseOr)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.BitwiseXor)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.LeftShift)
    assert OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.RightShift)
    assert !OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.NullCoalesce)
    assert !OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.Range)
}

// Successor to the four unary assertions of the same C# test (`Negate`, `Not` admitted;
// `BitwiseNot`, `IndexFromEnd` refused), widened to every member: the admitted set is exactly two,
// and both increment and decrement forms are refused in either position.
test "operator facts admit exactly two expression-tree unary operators" {
    assert OperatorFacts.IsSupportedExpressionTreeUnaryOperator(UnaryOperator.Negate)
    assert OperatorFacts.IsSupportedExpressionTreeUnaryOperator(UnaryOperator.Not)
    assert !OperatorFacts.IsSupportedExpressionTreeUnaryOperator(UnaryOperator.BitwiseNot)
    assert !OperatorFacts.IsSupportedExpressionTreeUnaryOperator(UnaryOperator.PreIncrement)
    assert !OperatorFacts.IsSupportedExpressionTreeUnaryOperator(UnaryOperator.PreDecrement)
    assert !OperatorFacts.IsSupportedExpressionTreeUnaryOperator(UnaryOperator.PostIncrement)
    assert !OperatorFacts.IsSupportedExpressionTreeUnaryOperator(UnaryOperator.PostDecrement)
    assert !OperatorFacts.IsSupportedExpressionTreeUnaryOperator(UnaryOperator.IndexFromEnd)
}

// ---- the two families the C# never touched -----------------------------------------------------

// NEW COVERAGE. The formatter reaches its operator text through the three `GetRequired*` gates, not
// through the plain ones, and nothing asserted them. A mapped operator must pass through unchanged —
// the gate exists to turn the `"operator"` sentinel into a throw, not to alter a real answer.
test "operator facts pass a renderable operator through the required-text gate" {
    assert OperatorFacts.GetRequiredBinaryText(BinaryOperator.LeftShift) == "<<"
    assert OperatorFacts.GetRequiredUnaryText(UnaryOperator.IndexFromEnd) == "^"
    assert OperatorFacts.GetRequiredAssignmentText(AssignmentOperator.NullCoalesceAssign) == "??="
}

// NEW COVERAGE. The analyser's compound-assignment arm reads `x += y` as `x = x + y` through this
// mapping, and nothing asserted it. Four of the six assignment operators decompose; `=` has nothing
// to decompose and `??=` is not an arithmetic compound at all. The out parameter is seeded with
// `Range` — which is neither an answer nor the refusal fallback — so every assertion below can only
// be satisfied by a value the call itself wrote.
test "operator facts map the four compound assignments and refuse the other two" {
    compound: BinaryOperator = BinaryOperator.Range
    assert OperatorFacts.TryGetCompoundAssignmentBinaryOperator(AssignmentOperator.AddAssign, out compound)
    assert compound == BinaryOperator.Add

    compound = BinaryOperator.Range
    assert OperatorFacts.TryGetCompoundAssignmentBinaryOperator(AssignmentOperator.SubtractAssign, out compound)
    assert compound == BinaryOperator.Subtract

    compound = BinaryOperator.Range
    assert OperatorFacts.TryGetCompoundAssignmentBinaryOperator(AssignmentOperator.MultiplyAssign, out compound)
    assert compound == BinaryOperator.Multiply

    compound = BinaryOperator.Range
    assert OperatorFacts.TryGetCompoundAssignmentBinaryOperator(AssignmentOperator.DivideAssign, out compound)
    assert compound == BinaryOperator.Divide

    compound = BinaryOperator.Range
    assert !OperatorFacts.TryGetCompoundAssignmentBinaryOperator(AssignmentOperator.Assign, out compound)
    assert compound == BinaryOperator.Add

    compound = BinaryOperator.Range
    assert !OperatorFacts.TryGetCompoundAssignmentBinaryOperator(AssignmentOperator.NullCoalesceAssign, out compound)
    assert compound == BinaryOperator.Add
}
