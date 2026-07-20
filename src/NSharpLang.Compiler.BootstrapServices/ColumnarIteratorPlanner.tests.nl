namespace NSharpLang.Compiler.Columnar

import System

// Parses a func* body into a columnar node table and runs the iterator planner's decision layer on it.
// Signature facts (return canonical, parameters, type parameters, instance receiver) are supplied
// explicitly so a contract exercises exactly one decision at a time.
class ColumnarIteratorShapeProbe {
    public Shape: ColumnarIteratorShape

    constructor(
        source: string,
        returnCanonical: string,
        paramNames: string[],
        paramCanonicals: string[],
        typeParamNames: string[],
        isInstance: bool) {
        capacity := source.Length * 3 + 16
        rawKinds := new int[](capacity)
        rawStarts := new int[](capacity)
        rawValueLengths := new int[](capacity)
        tokenKinds := new int[](capacity)
        tokenStarts := new int[](capacity)
        tokenValueLengths := new int[](capacity)
        tokenCounts := new int[](2)
        tokenCount := TokenizeColumnarSourceInto(
            source, rawKinds, rawStarts, rawValueLengths,
            tokenKinds, tokenStarts, tokenValueLengths, tokenCounts)

        funcIndex := 0
        while funcIndex < tokenCount && tokenKinds[funcIndex] != 7 {
            funcIndex = funcIndex + 1
        }

        functionNameTexts := new string[](1)
        returnTypeTexts := new string[](1)
        paramNameTexts := new string[](capacity)
        paramTypeTexts := new string[](capacity)
        paramModifierKinds := new int[](capacity)
        paramDefaultKinds := new int[](capacity)
        paramDefaultTexts := new string[](capacity)
        paramTupleNameCounts := new int[](capacity)
        paramTupleNameTexts := new string[](capacity)
        returnTupleNameTexts := new string[](capacity)
        typeParamTexts := new string[](capacity)
        typeParamSpecials := new int[](capacity)
        typeParamConstraintCounts := new int[](capacity)
        typeParamConstraintTypeTexts := new string[](capacity)
        nodeKinds := new int[](capacity)
        valueStarts := new int[](capacity)
        valueLengths := new int[](capacity)
        childStart := new int[](capacity)
        childCount := new int[](capacity)
        childIndices := new int[](capacity)
        spanStarts := new int[](capacity)
        spanLengths := new int[](capacity)
        localFunctionNodeIndices := new int[](capacity)
        localFunctionTokenIndices := new int[](capacity)
        result := new int[](9)

        status := ParseColumnarProductFunctionInfoInto(
            source, tokenKinds, tokenStarts, tokenValueLengths, tokenCount, funcIndex, 0,
            functionNameTexts, returnTypeTexts, paramNameTexts, paramTypeTexts, paramModifierKinds,
            paramDefaultKinds, paramDefaultTexts, paramTupleNameCounts, paramTupleNameTexts,
            returnTupleNameTexts, typeParamTexts, typeParamSpecials, typeParamConstraintCounts,
            typeParamConstraintTypeTexts, nodeKinds, valueStarts, valueLengths, childStart, childCount,
            childIndices, spanStarts, spanLengths, localFunctionNodeIndices, localFunctionTokenIndices, result)
        if status < 0 {
            throw new InvalidOperationException("Iterator-shape probe could not parse the func* body.")
        }

        bodyRoot := result[6]
        nodes := new ColumnarNodeTable(
            nodeKinds, valueStarts, valueLengths, childStart, childCount, childIndices, spanStarts, spanLengths)
        Shape = ColumnarIteratorPlanner.AnalyzeShape(
            nodes, source, bodyRoot, "Gen", 0, returnCanonical, paramNames, paramCanonicals, typeParamNames, isInstance)
    }
}

func IteratorNoStrings(): string[] {
    return new string[](0)
}

func IteratorOne(a: string): string[] {
    values := new string[](1)
    values[0] = a
    return values
}

test "iterator planner numbers zero yields with two fields and no resume states" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Zero(): IEnumerable<int> { }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.ElementCanonical == "int"
    assert probe.Shape.YieldReturnCount == 0
    assert probe.Shape.FieldCount == 2
    assert probe.Shape.InitialState == 0
    assert probe.Shape.RunningState == -1
    assert probe.Shape.DoneState == -2
}

test "iterator planner numbers a single yield as one resume state" {
    probe := new ColumnarIteratorShapeProbe(
        "func* One(): IEnumerable<int> { yield 5 }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.YieldReturnCount == 1
}

test "iterator planner numbers many yields sequentially" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Many(): IEnumerable<int> { yield 1\n yield 2\n yield 3 }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.YieldReturnCount == 3
}

test "iterator planner excludes yield break from the resume-state count" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Break(): IEnumerable<int> { yield 1\n yield break }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.YieldReturnCount == 1
}

test "iterator planner lays out state, current, parameters, then locals in hoist order" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Count(n: int): IEnumerable<int> { i: int = 0\n while i < n { yield i\n i = i + 1 } }",
        "IEnumerable<int>", IteratorOne("n"), IteratorOne("int"), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.YieldReturnCount == 1
    assert probe.Shape.FieldCount == 4
    assert probe.Shape.FieldNames[0] == "<>__state"
    assert probe.Shape.FieldRoles[0] == ColumnarIteratorPlanner.StateFieldRole()
    assert probe.Shape.FieldCanonicals[0] == "int"
    assert probe.Shape.FieldNames[1] == "<>__current"
    assert probe.Shape.FieldRoles[1] == ColumnarIteratorPlanner.CurrentFieldRole()
    assert probe.Shape.FieldNames[2] == "n"
    assert probe.Shape.FieldRoles[2] == ColumnarIteratorPlanner.CapturedParameterFieldRole()
    assert probe.Shape.FieldNames[3] == "i"
    assert probe.Shape.FieldRoles[3] == ColumnarIteratorPlanner.HoistedLocalFieldRole()
    assert probe.Shape.FieldCanonicals[3] == "int"
}

test "iterator planner infers the element type from an IEnumerable<T> return" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Strings(): IEnumerable<string> { yield break }",
        "IEnumerable<string>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.ElementCanonical == "string"
    assert probe.Shape.FieldCanonicals[1] == "string"
}

test "iterator planner exposes the eight member and override specs" {
    probe := new ColumnarIteratorShapeProbe(
        "func* One(): IEnumerable<int> { yield 5 }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert probe.Shape.MemberCount == 8
    assert probe.Shape.MemberNames[0] == ".ctor"
    assert probe.Shape.MemberNames[1] == "MoveNext"
    assert probe.Shape.MemberOverrides[1] == "System.Collections.IEnumerator.MoveNext"
    assert probe.Shape.MemberNames[2] == "get_Current"
    assert probe.Shape.MemberSignatures[2] == "():int"
    assert probe.Shape.MemberNames[6] == "GetEnumerator"
    assert probe.Shape.MemberSignatures[6] == "():IEnumerator<int>"
}

test "iterator planner declines a generic iterator element" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Repeat(): IEnumerable<T> { yield break }",
        "IEnumerable<T>", IteratorNoStrings(), IteratorNoStrings(), IteratorOne("T"), false)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.generic-unsupported"
}

test "iterator planner declines for..in inside the body" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Loop(xs: int[]): IEnumerable<int> { for x in xs { yield x } }",
        "IEnumerable<int>", IteratorOne("xs"), IteratorOne("int[]"), IteratorNoStrings(), false)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.for-in-unsupported"
}

test "iterator planner declines an instance receiver" {
    probe := new ColumnarIteratorShapeProbe(
        "func* One(): IEnumerable<int> { yield 5 }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), true)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.instance-unsupported"
}

test "iterator planner declines a nested or recursive call in the body" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Nested(): IEnumerable<int> { yield Other() }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.nested-unsupported"
}

test "iterator planner declines an otherwise-unlowered body shape" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Throwing(): IEnumerable<int> { throw new InvalidOperationException(\"x\") }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.unsupported-shape"
}
