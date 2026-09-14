namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic


// THE CANONICAL CONTRACTS FOR `ColumnarNamedArgumentBinder` — the one owner that turns the name a
// call wrote into the slot the signature keeps it in.
//
// Each contract parses a REAL call expression through the columnar kernel, wraps the resulting
// columns in a `ColumnarNodeTable`, and asks the binder to place the arguments against a spelled
// parameter list. The two things a placement has to answer are asserted separately, because they are
// different questions: WHERE each argument belongs (the slot), and WHETHER handing the values over in
// slot order would run the written expressions out of the order they were written in.
//
// The negative cases here are not diagnostics — `AnalyzerSyntheticCallBinder` owns the sentence and
// the fix-it for an unknown name, a parameter named twice and a parameter left with nothing, and it
// reports them at the front door. What this owner answers for the same shapes is "no placement", so
// the backend declines rather than binding a call the front door rejected.
func NamedArgTable(source: string): ColumnarNodeTable {
    probe := new ColumnarNumericLiteralParseProbe(source)
    return new ColumnarNodeTable(probe.NodeKinds, probe.NodeValueStarts, probe.NodeValueLengths, probe.NodeChildStarts, probe.NodeChildCounts, probe.NodeChildren, probe.NodeSpanStarts, probe.NodeSpanLengths)
}

func NamedArgRoot(source: string): int {
    probe := new ColumnarNumericLiteralParseProbe(source)
    return probe.ParseResult[0]
}

func NamedArgNames(first: string, second: string): string[] {
    names := new string[](2)
    names[0] = first
    names[1] = second
    return names
}

func NamedArgNames3(first: string, second: string, third: string): string[] {
    names := new string[](3)
    names[0] = first
    names[1] = second
    names[2] = third
    return names
}

func NamedArgPlacement(source: string, parameterNames: string[], argumentCount: int): int[] {
    nodes := NamedArgTable(source)
    placement := new int[](0)
    if !ColumnarNamedArgumentBinder.TryPlace(nodes, source, NamedArgRoot(source), 1, argumentCount, parameterNames, parameterNames.Length, out placement) {
        return new int[](0)
    }

    return placement
}

test "the named-argument kind is 60, and a `name: value` argument parses into it with the argument as its one child" {
    assert ColumnarNamedArgumentBinder.NamedArgumentKind() == 60

    source := "Gate(flag: true)"
    nodes := NamedArgTable(source)
    root := NamedArgRoot(source)
    assert nodes.Kind(root) == ColumnarExpressionNodeKind.CallExpression()
    assert nodes.ChildCount(root) == 2

    argument := nodes.Child(root, 1)
    assert ColumnarNamedArgumentBinder.IsNamedArgument(nodes, argument)
    assert ColumnarNamedArgumentBinder.ArgumentName(nodes, source, argument) == "flag"
    assert nodes.Kind(ColumnarNamedArgumentBinder.ArgumentValueNode(nodes, argument)) == ColumnarExpressionNodeKind.BoolLiteralExpression()
}

test "a positional argument carries no name, and the value node of one is the argument itself" {
    source := "Gate(true)"
    nodes := NamedArgTable(source)
    argument := nodes.Child(NamedArgRoot(source), 1)
    assert !ColumnarNamedArgumentBinder.IsNamedArgument(nodes, argument)
    assert ColumnarNamedArgumentBinder.ArgumentName(nodes, source, argument) == null
    assert ColumnarNamedArgumentBinder.ArgumentValueNode(nodes, argument) == argument
}

test "a named `out` argument keeps the modifier wrapper underneath the name" {
    source := "TryParse(text, result: out parsed)"
    nodes := NamedArgTable(source)
    argument := nodes.Child(NamedArgRoot(source), 2)
    assert ColumnarNamedArgumentBinder.ArgumentName(nodes, source, argument) == "result"

    modifier := ColumnarNamedArgumentBinder.ArgumentValueNode(nodes, argument)
    assert nodes.Kind(modifier) == 54
    assert nodes.Text(source, modifier) == "out"
}

test "a call with no name at all reports no named argument" {
    source := "Divide(10, 2)"
    assert !ColumnarNamedArgumentBinder.HasNamedArgument(NamedArgTable(source), NamedArgRoot(source), 1, 2)
}

test "one name anywhere in the list makes the call a named call" {
    leading := "Divide(numerator: 10, 2)"
    assert ColumnarNamedArgumentBinder.HasNamedArgument(NamedArgTable(leading), NamedArgRoot(leading), 1, 2)

    trailing := "Divide(10, denominator: 2)"
    assert ColumnarNamedArgumentBinder.HasNamedArgument(NamedArgTable(trailing), NamedArgRoot(trailing), 1, 2)
}

test "names written in the declared order place every argument where it already is" {
    placement := NamedArgPlacement("Divide(numerator: 10, denominator: 2)", NamedArgNames("numerator", "denominator"), 2)
    assert placement.Length == 2
    assert placement[0] == 0
    assert placement[1] == 1
}

test "names written out of the declared order place each argument at the parameter it names" {
    placement := NamedArgPlacement("Divide(denominator: 2, numerator: 10)", NamedArgNames("numerator", "denominator"), 2)
    assert placement.Length == 2
    assert placement[0] == 1
    assert placement[1] == 0
}

test "a positional argument claims the next parameter no name has taken" {
    // `Between(5, high: 9, low: 1)` — the positional `5` takes parameter zero, and the two names take
    // the two that are left, in the order the signature declares them rather than the written one.
    placement := NamedArgPlacement("Between(5, high: 9, low: 1)", NamedArgNames3("value", "low", "high"), 3)
    assert placement.Length == 3
    assert placement[0] == 0
    assert placement[1] == 2
    assert placement[2] == 1
}

test "a positional argument written AFTER a name skips the parameter the name already claimed" {
    // `Divide(numerator: 10, 2)` leaves `denominator` as the only parameter nothing has claimed.
    placement := NamedArgPlacement("Divide(numerator: 10, 2)", NamedArgNames("numerator", "denominator"), 2)
    assert placement.Length == 2
    assert placement[0] == 0
    assert placement[1] == 1
}

test "a name no parameter carries places nothing" {
    assert NamedArgPlacement("Divide(numerator: 10, denominatorr: 2)", NamedArgNames("numerator", "denominator"), 2).Length == 0
}

test "a parameter named twice places nothing" {
    assert NamedArgPlacement("Divide(numerator: 10, numerator: 2)", NamedArgNames("numerator", "denominator"), 2).Length == 0
}

test "a name that leaves an earlier parameter with nothing places nothing" {
    // `Divide(denominator: 2)` names the SECOND parameter and gives the first nothing. The defaults
    // the backend can write are the trailing ones, so a hole in front of a named argument is refused
    // rather than silently shifted.
    assert NamedArgPlacement("Divide(denominator: 2)", NamedArgNames("numerator", "denominator"), 1).Length == 0
}

test "a signature reached at fewer arguments than it declares places onto its LEADING parameters" {
    // `Indent(text: \"x\")` against `(text, width)`: the written argument claims parameter zero and the
    // trailing `width` is left to the default the declaration writes.
    nodes := NamedArgTable("Indent(text: \"x\")")
    placement := new int[](0)
    assert ColumnarNamedArgumentBinder.TryPlace(nodes, "Indent(text: \"x\")", NamedArgRoot("Indent(text: \"x\")"), 1, 1, NamedArgNames("text", "width"), 2, out placement)
    assert placement.Length == 1
    assert placement[0] == 0
}

test "the placement moves every column of an argument row together, and reports whether it moved anything" {
    source := "Divide(denominator: 2, numerator: 10)"
    nodes := NamedArgTable(source)
    root := NamedArgRoot(source)

    argumentTypes := new Type[](2)
    argumentTypes[0] = typeof(string)
    argumentTypes[1] = typeof(int)
    facts := ColumnarDirectCallArgumentFacts.Empty(2)
    facts.ArgumentNodes[0] = ColumnarNamedArgumentBinder.ArgumentValueNode(nodes, nodes.Child(root, 1))
    facts.ArgumentNodes[1] = ColumnarNamedArgumentBinder.ArgumentValueNode(nodes, nodes.Child(root, 2))
    facts.IsNullLiteral[0] = true

    denominatorNode := facts.ArgumentNodes[0]
    numeratorNode := facts.ArgumentNodes[1]

    placement := NamedArgPlacement(source, NamedArgNames("numerator", "denominator"), 2)
    assert ColumnarNamedArgumentBinder.ApplyPlacement(argumentTypes, facts, placement)

    // The row written FIRST belongs to `denominator`, which is slot one.
    assert argumentTypes[1] == typeof(string)
    assert argumentTypes[0] == typeof(int)
    assert facts.ArgumentNodes[1] == denominatorNode
    assert facts.ArgumentNodes[0] == numeratorNode
    assert facts.IsNullLiteral[1]
    assert !facts.IsNullLiteral[0]

    // The written order is kept, because handing the values over in slot order would otherwise run
    // the two written expressions the wrong way round.
    assert facts.RequiresReorder
    assert facts.WrittenOrderSlots[0] == 1
    assert facts.WrittenOrderSlots[1] == 0
}

test "a placement that leaves every argument where it was written needs no reorder" {
    source := "Divide(numerator: 10, denominator: 2)"
    nodes := NamedArgTable(source)
    root := NamedArgRoot(source)

    argumentTypes := new Type[](2)
    argumentTypes[0] = typeof(int)
    argumentTypes[1] = typeof(int)
    facts := ColumnarDirectCallArgumentFacts.Empty(2)
    facts.ArgumentNodes[0] = ColumnarNamedArgumentBinder.ArgumentValueNode(nodes, nodes.Child(root, 1))
    facts.ArgumentNodes[1] = ColumnarNamedArgumentBinder.ArgumentValueNode(nodes, nodes.Child(root, 2))

    assert ColumnarNamedArgumentBinder.ApplyPlacement(argumentTypes, facts, NamedArgPlacement(source, NamedArgNames("numerator", "denominator"), 2))
    assert !facts.RequiresReorder
    assert facts.WrittenOrderSlots[0] == 0
    assert facts.WrittenOrderSlots[1] == 1
}

test "candidates that spell their parameters the same way are gathered once" {
    candidates := new List<string[]>()
    ColumnarNamedArgumentBinder.AddCandidate(candidates, NamedArgNames("numerator", "denominator"), 2)
    ColumnarNamedArgumentBinder.AddCandidate(candidates, NamedArgNames("numerator", "denominator"), 2)
    assert candidates.Count == 1

    ColumnarNamedArgumentBinder.AddCandidate(candidates, NamedArgNames("left", "right"), 2)
    assert candidates.Count == 2

    // A signature with FEWER parameters than the call wrote arguments cannot be one of them.
    ColumnarNamedArgumentBinder.AddCandidate(candidates, NamedArgNames("only", "two"), 3)
    assert candidates.Count == 2
}

test "two same-arity candidates that both admit the names but place them differently place nothing" {
    source := "Pick(second: 2, first: 1)"
    candidates := new List<string[]>()
    ColumnarNamedArgumentBinder.AddCandidate(candidates, NamedArgNames("first", "second"), 2)
    ColumnarNamedArgumentBinder.AddCandidate(candidates, NamedArgNames("second", "first"), 2)

    placement := new int[](0)
    assert !ColumnarNamedArgumentBinder.TryAgreedPlacement(NamedArgTable(source), source, NamedArgRoot(source), 1, 2, candidates, out placement)
}

test "a candidate that cannot admit the names is skipped rather than blocking the one that can" {
    source := "Pick(second: 2, first: 1)"
    candidates := new List<string[]>()
    ColumnarNamedArgumentBinder.AddCandidate(candidates, NamedArgNames("left", "right"), 2)
    ColumnarNamedArgumentBinder.AddCandidate(candidates, NamedArgNames("first", "second"), 2)

    placement := new int[](0)
    assert ColumnarNamedArgumentBinder.TryAgreedPlacement(NamedArgTable(source), source, NamedArgRoot(source), 1, 2, candidates, out placement)
    assert placement[0] == 1
    assert placement[1] == 0
}

test "an agreed IN-POSITION placement flattens the wrappers out of the node table" {
    source := "Divide(numerator: 10, denominator: 2)"
    nodes := NamedArgTable(source)
    root := NamedArgRoot(source)
    assert ColumnarNamedArgumentBinder.HasNamedArgument(nodes, root, 1, 2)

    candidates := new List<string[]>()
    ColumnarNamedArgumentBinder.AddCandidate(candidates, NamedArgNames("numerator", "denominator"), 2)
    placement := new int[](0)
    assert ColumnarNamedArgumentBinder.TryAgreedPlacement(nodes, source, root, 1, 2, candidates, out placement)

    // The wrappers carried nothing once the names were checked against a real signature, so the call
    // is now the positional one the names describe — which is what lets a residual owner emit it.
    assert !ColumnarNamedArgumentBinder.HasNamedArgument(nodes, root, 1, 2)
    assert nodes.Kind(nodes.Child(root, 1)) == ColumnarExpressionNodeKind.IntLiteralExpression()
    assert nodes.Kind(nodes.Child(root, 2)) == ColumnarExpressionNodeKind.IntLiteralExpression()
}

test "an agreed placement that MOVES an argument leaves the wrappers in the node table" {
    source := "Divide(denominator: 2, numerator: 10)"
    nodes := NamedArgTable(source)
    root := NamedArgRoot(source)

    candidates := new List<string[]>()
    ColumnarNamedArgumentBinder.AddCandidate(candidates, NamedArgNames("numerator", "denominator"), 2)
    placement := new int[](0)
    assert ColumnarNamedArgumentBinder.TryAgreedPlacement(nodes, source, root, 1, 2, candidates, out placement)

    // Only the planner can emit a move, because only it evaluates the written order into
    // temporaries first — so the wrappers stay, and any other owner still declines.
    assert ColumnarNamedArgumentBinder.HasNamedArgument(nodes, root, 1, 2)
}

test "a type still being emitted answers no reflection question, so it contributes no candidate" {
    assert !ColumnarNamedArgumentBinder.IsReflectable(null)
    assert ColumnarNamedArgumentBinder.IsReflectable(typeof(string))

    candidates := new List<string[]>()
    ColumnarNamedArgumentBinder.CollectReflectedParameterNames(null, "Replace", 2, false, candidates)
    assert candidates.Count == 0
}

test "the reflected parameter names of an external member are its declaration's, in order" {
    // `string.Replace` declares TWO two-parameter overloads, `(string, string)` and `(char, char)`,
    // and they spell their parameters differently -- which is exactly why a name prunes an overload
    // set: only one of these two admits `oldValue`/`newValue`.
    candidates := new List<string[]>()
    ColumnarNamedArgumentBinder.CollectReflectedParameterNames(typeof(string), "Replace", 2, false, candidates)
    assert candidates.Count == 2

    stringOverload := false
    charOverload := false
    for names in candidates {
        assert names.Length == 2
        if names[0] == "oldValue" && names[1] == "newValue" {
            stringOverload = true
        }

        if names[0] == "oldChar" && names[1] == "newChar" {
            charOverload = true
        }
    }

    assert stringOverload
    assert charOverload
}

test "an extension method's callable names start one parameter in, past the receiver" {
    method := typeof(string).GetMethod("Replace", [typeof(string), typeof(string)])
    assert method != null

    declared := ColumnarNamedArgumentBinder.ReflectedParameterNames(method)
    assert declared.Length == 2
    assert declared[0] == "oldValue"

    shifted := ColumnarNamedArgumentBinder.ReflectedExtensionParameterNames(method)
    assert shifted.Length == 1
    assert shifted[0] == "newValue"
}
