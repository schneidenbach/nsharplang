namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

// A plain class whose public fields stand in for a synthesized state machine's fields, so a contract can
// execute the planner's MoveNext/get_Current plans onto DynamicMethods and run a real iterator without the
// C# emitter host.
public class ColumnarIteratorRunProbe {
    public state: int
    public current: int
    public n: int
    public i: int

    constructor() {
        state = 0
        current = 0
        n = 0
        i = 0
    }
}

// Parses a func* body into a columnar node table and runs the iterator planner's decision layer on it.
// Signature facts (return canonical, parameters, type parameters, instance receiver) are supplied
// explicitly so a contract exercises exactly one decision at a time.
class ColumnarIteratorShapeProbe {
    public Shape: ColumnarIteratorShape
    public Nodes: ColumnarNodeTable
    public BodyRoot: int
    public Source: string

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
        Nodes = nodes
        BodyRoot = bodyRoot
        Source = source
        Shape = ColumnarIteratorPlanner.AnalyzeShape(
            nodes, source, bodyRoot, "Gen", 0, returnCanonical, paramNames, paramCanonicals, typeParamNames, isInstance)
    }
}

func IteratorSetObject(values: object[], index: int, value: object) {
    values[index] = value
}

func MakeIteratorDynamicMethod(name: string, returnType: Type, parameterType: Type): DynamicMethod {
    constructorTypes := new Type[](3)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = typeof(Type)
    constructorTypes[2] = typeof(Type[])
    ctor := typeof(DynamicMethod).GetConstructor(constructorTypes)
    if ctor == null {
        throw new InvalidOperationException("Required DynamicMethod constructor was not found.")
    }
    paramTypes := new Type[](1)
    paramTypes[0] = parameterType
    args := new object[](3)
    IteratorSetObject(args, 0, name)
    IteratorSetObject(args, 1, returnType)
    IteratorSetObject(args, 2, paramTypes)
    return (DynamicMethod)ctor.Invoke(args)
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

test "iterator planner MoveNext and get_Current plans run a counting iterator sequence" {
    source := "func* Count(n: int): IEnumerable<int> { i: int = 0\n while i < n { yield i\n i = i + 1 } }"
    probe := new ColumnarIteratorShapeProbe(
        source, "IEnumerable<int>", IteratorOne("n"), IteratorOne("int"), IteratorNoStrings(), false)
    assert probe.Shape.Supported
    assert probe.Shape.FieldCount == 4

    smType := typeof(ColumnarIteratorRunProbe)
    fields := new FieldInfo[](4)
    fields[0] = smType.GetField("state")
    fields[1] = smType.GetField("current")
    fields[2] = smType.GetField("n")
    fields[3] = smType.GetField("i")
    context := new ColumnarIteratorEmitContext(
        probe.Nodes, probe.Source, probe.BodyRoot, probe.Shape, smType, typeof(int), probe.Shape.FieldNames, fields)

    moveNextPlan := ColumnarIteratorBodyPlanner.BuildMoveNextPlan(context)
    getCurrentPlan := ColumnarIteratorBodyPlanner.BuildGetCurrentPlan(context)

    moveNext := MakeIteratorDynamicMethod("MoveNext", typeof(bool), smType)
    ColumnarCodePlanExecutor.Execute(moveNextPlan, moveNext.GetILGenerator())
    getCurrent := MakeIteratorDynamicMethod("get_Current", typeof(int), smType)
    ColumnarCodePlanExecutor.Execute(getCurrentPlan, getCurrent.GetILGenerator())

    machine := new ColumnarIteratorRunProbe()
    machine.state = 0
    machine.n = 5
    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, machine)

    target: object? = null
    results := new List<int>()
    moveResult := moveNext.Invoke(target, invokeArgs)
    hasNext := Convert.ToBoolean(moveResult)
    while hasNext {
        currentResult := getCurrent.Invoke(target, invokeArgs)
        results.Add(Convert.ToInt32(currentResult))
        moveResult = moveNext.Invoke(target, invokeArgs)
        hasNext = Convert.ToBoolean(moveResult)
    }

    assert results.Count == 5
    assert results[0] == 0
    assert results[1] == 1
    assert results[2] == 2
    assert results[3] == 3
    assert results[4] == 4
}
