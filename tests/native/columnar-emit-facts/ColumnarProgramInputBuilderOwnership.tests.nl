namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections
import System.Reflection

class ColumnarInputBuilderAttempt {
    Succeeded: bool
    Program: object?

    constructor(succeeded: bool, program: object?) {
        Succeeded = succeeded
        Program = program
    }
}

// The builder's N# type is the sole parsing/materialization owner. Keep this lookup exact so these
// controls cannot silently fall back to the deleted Compiler-assembly implementation.
func ColumnarInputBuilderType(): Type {
    owner := Type.GetType(
        "NSharpLang.Compiler.Columnar.ColumnarProgramInputBuilder, NSharpLang.Compiler.Core"
    )
    if owner == null {
        throw new InvalidOperationException("Missing N# ColumnarProgramInputBuilder")
    }
    return owner
}

func ColumnarInputBuilderPrivateMethod(methodName: string, parameterCount: int): MethodInfo {
    methods := ColumnarInputBuilderType().GetMethods(BindingFlags.Static | BindingFlags.NonPublic)
    for method in methods {
        if method.get_Name() == methodName && method.GetParameters().Length == parameterCount {
            return method
        }
    }
    throw new InvalidOperationException("Missing private N# ColumnarProgramInputBuilder method " + methodName)
}

func ColumnarInputBuilderPublicMethod(methodName: string, parameterCount: int): MethodInfo {
    methods := ColumnarInputBuilderType().GetMethods(BindingFlags.Static | BindingFlags.Public)
    for method in methods {
        if method.get_Name() == methodName && method.GetParameters().Length == parameterCount {
            return method
        }
    }
    throw new InvalidOperationException("Missing public N# ColumnarProgramInputBuilder method " + methodName)
}

func ColumnarInputBuilderPut(values: object?[], index: int, value: object?) {
    values[index] = value
}

func ColumnarInputBuilderRequiredMember(target: object, name: string): object {
    field := target.GetType().GetField(name)
    if field != null {
        value := field.GetValue(target)
        if value == null {
            throw new InvalidOperationException("Columnar input member '" + name + "' was null")
        }
        return value
    }

    property := target.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Missing columnar input member '" + name + "'")
    }
    propertyValue := property.GetValue(target)
    if propertyValue == null {
        throw new InvalidOperationException("Columnar input member '" + name + "' was null")
    }
    return propertyValue
}

func ColumnarInputBuilderOptionalMember(target: object, name: string): object? {
    field := target.GetType().GetField(name)
    if field != null {
        return field.GetValue(target)
    }

    property := target.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Missing columnar input member '" + name + "'")
    }
    return property.GetValue(target)
}

func ColumnarInputBuilderList(value: object, label: string): IList {
    list := value as IList
    if list == null {
        throw new InvalidOperationException("Expected IList for " + label)
    }
    return list
}

func ColumnarInputBuilderMemberList(target: object, name: string): IList {
    return ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(target, name), name)
}

func ColumnarInputBuilderRequiredItem(values: IList, index: int): object {
    value := values[index]
    if value == null {
        throw new InvalidOperationException("Columnar input list item was null")
    }
    return value
}

func ColumnarInputBuilderRequiredTextItem(values: IList, index: int): string {
    value := values[index] as string
    if value == null {
        throw new InvalidOperationException("Columnar input list text item was null")
    }
    return value
}

func ColumnarInputBuilderText(target: object, name: string): string {
    return Convert.ToString(ColumnarInputBuilderRequiredMember(target, name)) ?? ""
}

func ColumnarInputBuilderInt(target: object, name: string): int {
    return Convert.ToInt32(ColumnarInputBuilderRequiredMember(target, name))
}

func ColumnarInputBuilderBool(target: object, name: string): bool {
    return Convert.ToBoolean(ColumnarInputBuilderRequiredMember(target, name))
}

func ColumnarInputBuilderInvokeSingle(stringSource: string): ColumnarInputBuilderAttempt {
    arguments := new object?[](2)
    ColumnarInputBuilderPut(arguments, 0, stringSource)
    ColumnarInputBuilderPut(arguments, 1, null)
    succeeded := Convert.ToBoolean(ColumnarInputBuilderPrivateMethod("TryBuild", 2).Invoke(null, arguments))
    return new ColumnarInputBuilderAttempt(succeeded, arguments[1])
}

func ColumnarInputBuilderInvokeMulti(sources: string[], fileNames: string[], projectRoot: string): ColumnarInputBuilderAttempt {
    arguments := new object?[](4)
    ColumnarInputBuilderPut(arguments, 0, sources)
    ColumnarInputBuilderPut(arguments, 1, fileNames)
    ColumnarInputBuilderPut(arguments, 2, projectRoot)
    ColumnarInputBuilderPut(arguments, 3, null)
    succeeded := Convert.ToBoolean(ColumnarInputBuilderPublicMethod("TryBuildMultiFile", 4).Invoke(null, arguments))
    return new ColumnarInputBuilderAttempt(succeeded, arguments[3])
}

func ColumnarInputBuilderTraceMethod(methodName: string, parameterCount: int): MethodInfo {
    owner := Type.GetType(
        "NSharpLang.Compiler.Columnar.ColumnarDeclineTrace, NSharpLang.Compiler.Core"
    )
    if owner == null {
        throw new InvalidOperationException("Missing N# ColumnarDeclineTrace")
    }
    methods := owner.GetMethods(BindingFlags.Static | BindingFlags.Public)
    for method in methods {
        if method.get_Name() == methodName && method.GetParameters().Length == parameterCount {
            return method
        }
    }
    throw new InvalidOperationException("Missing N# ColumnarDeclineTrace method " + methodName)
}

func ColumnarInputBuilderTraceReset() {
    arguments := new object?[](0)
    ignored := ColumnarInputBuilderTraceMethod("Reset", 0).Invoke(null, arguments)
    _ = ignored
}

func ColumnarInputBuilderTraceSnapshot(): IList {
    arguments := new object?[](0)
    value := ColumnarInputBuilderTraceMethod("Snapshot", 0).Invoke(null, arguments)
    if value == null {
        throw new InvalidOperationException("Columnar decline trace snapshot was null")
    }
    return ColumnarInputBuilderList(value, "decline trace")
}

func ColumnarInputBuilderTraceRecord(siteId: string, message: string) {
    arguments := new object?[](5)
    ColumnarInputBuilderPut(arguments, 0, siteId)
    ColumnarInputBuilderPut(arguments, 1, message)
    ColumnarInputBuilderPut(arguments, 2, -1)
    ColumnarInputBuilderPut(arguments, 3, 0)
    ColumnarInputBuilderPut(arguments, 4, "probe")
    ignored := ColumnarInputBuilderTraceMethod("Record", 5).Invoke(null, arguments)
    _ = ignored
}

func ColumnarInputBuilderSequence(first: int, length: int): int[] {
    values := new int[](length)
    index := 0
    while index < values.Length {
        values[index] = first + index
        index = index + 1
    }
    return values
}

test "the N# input builder trims node rows through the sentinel and copies only used child indices" {
    kinds := ColumnarInputBuilderSequence(100, 6)
    valueStarts := ColumnarInputBuilderSequence(200, 6)
    valueLengths := ColumnarInputBuilderSequence(300, 6)
    childStarts := new int[](6)
    childStarts[0] = 0
    childStarts[1] = 2
    childStarts[2] = 1
    childCounts := new int[](6)
    childCounts[0] = 2
    childCounts[1] = 3
    childCounts[2] = 1
    childIndices := ColumnarInputBuilderSequence(400, 8)
    spanStarts := ColumnarInputBuilderSequence(500, 6)
    spanLengths := ColumnarInputBuilderSequence(600, 6)

    arguments := new object?[](9)
    ColumnarInputBuilderPut(arguments, 0, kinds)
    ColumnarInputBuilderPut(arguments, 1, valueStarts)
    ColumnarInputBuilderPut(arguments, 2, valueLengths)
    ColumnarInputBuilderPut(arguments, 3, childStarts)
    ColumnarInputBuilderPut(arguments, 4, childCounts)
    ColumnarInputBuilderPut(arguments, 5, childIndices)
    ColumnarInputBuilderPut(arguments, 6, spanStarts)
    ColumnarInputBuilderPut(arguments, 7, spanLengths)
    ColumnarInputBuilderPut(arguments, 8, 3)
    table := ColumnarInputBuilderPrivateMethod("BuildTrimmedNodeTable", 9).Invoke(null, arguments)
    if table == null {
        throw new InvalidOperationException("BuildTrimmedNodeTable returned null")
    }

    trimmedKinds := ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(table, "kinds"), "kinds")
    trimmedValueStarts := ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(table, "valueStarts"), "valueStarts")
    trimmedValueLengths := ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(table, "valueLengths"), "valueLengths")
    trimmedChildStarts := ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(table, "childStarts"), "childStarts")
    trimmedChildCounts := ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(table, "childCounts"), "childCounts")
    trimmedChildIndices := ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(table, "childIndices"), "childIndices")
    trimmedSpanStarts := ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(table, "spanStarts"), "spanStarts")
    trimmedSpanLengths := ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(table, "spanLengths"), "spanLengths")

    assert trimmedKinds.Count == 4
    assert trimmedValueStarts.Count == 4
    assert trimmedValueLengths.Count == 4
    assert trimmedChildStarts.Count == 4
    assert trimmedChildCounts.Count == 4
    assert trimmedSpanStarts.Count == 4
    assert trimmedSpanLengths.Count == 4
    assert trimmedChildIndices.Count == 5
    assert Convert.ToInt32(trimmedKinds[3]) == 103
    assert Convert.ToInt32(trimmedChildIndices[4]) == 404

    kinds[0] = -1
    valueStarts[0] = -1
    valueLengths[0] = -1
    childStarts[0] = -1
    childCounts[0] = -1
    childIndices[0] = -1
    spanStarts[0] = -1
    spanLengths[0] = -1
    assert Convert.ToInt32(trimmedKinds[0]) == 100
    assert Convert.ToInt32(trimmedValueStarts[0]) == 200
    assert Convert.ToInt32(trimmedValueLengths[0]) == 300
    assert Convert.ToInt32(trimmedChildStarts[0]) == 0
    assert Convert.ToInt32(trimmedChildCounts[0]) == 2
    assert Convert.ToInt32(trimmedChildIndices[0]) == 400
    assert Convert.ToInt32(trimmedSpanStarts[0]) == 500
    assert Convert.ToInt32(trimmedSpanLengths[0]) == 600
}

test "the N# input builder preserves multi-file family order source identities and project root" {
    firstSource := "func FirstFunction(): int { return 1 }\nenum FirstEnum { First = 1 }\nclass FirstCarrier {}\nunion FirstUnion { First }\ninterface FirstInterface {\n    func Read(): int { return 1 }\n}\ntest \"first test\" { assert true }\ntype FirstId = newtype int\n"
    secondSource := "func SecondFunction(): int {\n    func SecondLocal(): int { return 2 }\n    return SecondLocal()\n}\nenum SecondEnum { Second = 2 }\nclass SecondCarrier {\n    backing: int\n    constructor(seed: int) { backing = seed }\n    Value: int {\n        get { return backing }\n        set { backing = value }\n    }\n    func Read(): int { return backing }\n}\nunion SecondUnion { Second }\ninterface SecondInterface {\n    func Read(): int { return 2 }\n}\ntest \"second test\" { assert true }\ntype SecondId = newtype int\n"
    sources := new string[](2)
    sources[0] = firstSource
    sources[1] = secondSource
    fileNames := new string[](2)
    fileNames[0] = "First.nl"
    fileNames[1] = "Second.nl"

    attempt := ColumnarInputBuilderInvokeMulti(sources, fileNames, "/project/root")
    assert attempt.Succeeded
    program := attempt.Program
    if program == null {
        throw new InvalidOperationException("Multi-file builder returned no program")
    }
    assert ColumnarInputBuilderText(program, "ProjectRoot") == "/project/root"
    assert ColumnarInputBuilderText(program, "Source") == firstSource

    sourceFiles := ColumnarInputBuilderMemberList(program, "Sources")
    assert sourceFiles.Count == 2
    firstFile := ColumnarInputBuilderRequiredItem(sourceFiles, 0)
    secondFile := ColumnarInputBuilderRequiredItem(sourceFiles, 1)
    assert ColumnarInputBuilderText(firstFile, "FileName") == "First.nl"
    assert ColumnarInputBuilderText(firstFile, "Source") == firstSource
    assert ColumnarInputBuilderInt(firstFile, "FileId") == 0
    assert ColumnarInputBuilderText(secondFile, "FileName") == "Second.nl"
    assert ColumnarInputBuilderText(secondFile, "Source") == secondSource
    assert ColumnarInputBuilderInt(secondFile, "FileId") == 1

    functions := ColumnarInputBuilderMemberList(program, "Functions")
    assert functions.Count == 2
    firstFunction := ColumnarInputBuilderRequiredItem(functions, 0)
    secondFunction := ColumnarInputBuilderRequiredItem(functions, 1)
    assert ColumnarInputBuilderText(firstFunction, "Name") == "FirstFunction"
    assert ColumnarInputBuilderInt(firstFunction, "SourceFileId") == 0
    assert ColumnarInputBuilderText(secondFunction, "Name") == "SecondFunction"
    assert ColumnarInputBuilderInt(secondFunction, "SourceFileId") == 1
    localFunctions := ColumnarInputBuilderMemberList(secondFunction, "LocalFunctions")
    assert localFunctions.Count == 1
    localRow := ColumnarInputBuilderRequiredItem(localFunctions, 0)
    localFunction := ColumnarInputBuilderRequiredMember(localRow, "Function")
    assert ColumnarInputBuilderText(localFunction, "Name") == "SecondLocal"
    assert ColumnarInputBuilderInt(localFunction, "SourceFileId") == 1

    enums := ColumnarInputBuilderMemberList(program, "Enums")
    assert enums.Count == 2
    assert ColumnarInputBuilderText(ColumnarInputBuilderRequiredItem(enums, 0), "Name") == "FirstEnum"
    assert ColumnarInputBuilderInt(ColumnarInputBuilderRequiredItem(enums, 0), "SourceFileId") == 0
    assert ColumnarInputBuilderText(ColumnarInputBuilderRequiredItem(enums, 1), "Name") == "SecondEnum"
    assert ColumnarInputBuilderInt(ColumnarInputBuilderRequiredItem(enums, 1), "SourceFileId") == 1

    structs := ColumnarInputBuilderMemberList(program, "Structs")
    assert structs.Count == 4
    firstStruct := ColumnarInputBuilderRequiredItem(structs, 0)
    firstNewtype := ColumnarInputBuilderRequiredItem(structs, 1)
    secondStruct := ColumnarInputBuilderRequiredItem(structs, 2)
    secondNewtype := ColumnarInputBuilderRequiredItem(structs, 3)
    assert ColumnarInputBuilderText(firstStruct, "Name") == "FirstCarrier"
    assert ColumnarInputBuilderInt(firstStruct, "SourceFileId") == 0
    assert ColumnarInputBuilderText(firstNewtype, "Name") == "FirstId"
    assert ColumnarInputBuilderBool(firstNewtype, "IsNewtype")
    assert ColumnarInputBuilderInt(firstNewtype, "SourceFileId") == 0
    assert ColumnarInputBuilderText(secondStruct, "Name") == "SecondCarrier"
    assert ColumnarInputBuilderInt(secondStruct, "SourceFileId") == 1
    assert ColumnarInputBuilderText(secondNewtype, "Name") == "SecondId"
    assert ColumnarInputBuilderBool(secondNewtype, "IsNewtype")
    assert ColumnarInputBuilderInt(secondNewtype, "SourceFileId") == 1

    methods := ColumnarInputBuilderMemberList(secondStruct, "Methods")
    constructors := ColumnarInputBuilderMemberList(secondStruct, "Constructors")
    properties := ColumnarInputBuilderMemberList(secondStruct, "Properties")
    assert methods.Count == 1
    assert constructors.Count == 1
    assert properties.Count == 1
    assert ColumnarInputBuilderInt(ColumnarInputBuilderRequiredItem(methods, 0), "SourceFileId") == 1
    constructor := ColumnarInputBuilderRequiredItem(constructors, 0)
    assert ColumnarInputBuilderInt(constructor, "SourceFileId") == 1
    assert ColumnarInputBuilderInt(ColumnarInputBuilderRequiredMember(constructor, "Body"), "SourceFileId") == 1
    property := ColumnarInputBuilderRequiredItem(properties, 0)
    assert ColumnarInputBuilderInt(property, "SourceFileId") == 1
    assert ColumnarInputBuilderInt(ColumnarInputBuilderRequiredMember(property, "Getter"), "SourceFileId") == 1
    assert ColumnarInputBuilderInt(ColumnarInputBuilderRequiredMember(property, "Setter"), "SourceFileId") == 1

    unions := ColumnarInputBuilderMemberList(program, "Unions")
    assert unions.Count == 2
    assert ColumnarInputBuilderText(ColumnarInputBuilderRequiredItem(unions, 0), "Name") == "FirstUnion"
    assert ColumnarInputBuilderInt(ColumnarInputBuilderRequiredItem(unions, 0), "SourceFileId") == 0
    assert ColumnarInputBuilderText(ColumnarInputBuilderRequiredItem(unions, 1), "Name") == "SecondUnion"
    assert ColumnarInputBuilderInt(ColumnarInputBuilderRequiredItem(unions, 1), "SourceFileId") == 1

    interfaces := ColumnarInputBuilderMemberList(program, "Interfaces")
    assert interfaces.Count == 2
    firstInterface := ColumnarInputBuilderRequiredItem(interfaces, 0)
    secondInterface := ColumnarInputBuilderRequiredItem(interfaces, 1)
    assert ColumnarInputBuilderText(firstInterface, "Name") == "FirstInterface"
    assert ColumnarInputBuilderInt(firstInterface, "SourceFileId") == 0
    assert ColumnarInputBuilderText(secondInterface, "Name") == "SecondInterface"
    assert ColumnarInputBuilderInt(secondInterface, "SourceFileId") == 1
    firstInterfaceBodies := ColumnarInputBuilderMemberList(firstInterface, "MethodBodies")
    secondInterfaceBodies := ColumnarInputBuilderMemberList(secondInterface, "MethodBodies")
    assert ColumnarInputBuilderInt(ColumnarInputBuilderRequiredItem(firstInterfaceBodies, 0), "SourceFileId") == 0
    assert ColumnarInputBuilderInt(ColumnarInputBuilderRequiredItem(secondInterfaceBodies, 0), "SourceFileId") == 1

    tests := ColumnarInputBuilderMemberList(program, "Tests")
    assert tests.Count == 2
    firstTest := ColumnarInputBuilderRequiredItem(tests, 0)
    secondTest := ColumnarInputBuilderRequiredItem(tests, 1)
    assert ColumnarInputBuilderText(firstTest, "Description") == "first test"
    assert ColumnarInputBuilderInt(ColumnarInputBuilderRequiredMember(firstTest, "Body"), "SourceFileId") == 0
    assert ColumnarInputBuilderText(secondTest, "Description") == "second test"
    assert ColumnarInputBuilderInt(ColumnarInputBuilderRequiredMember(secondTest, "Body"), "SourceFileId") == 1
}

test "the single-source builder preserves a null Tests value when the source declares no tests" {
    attempt := ColumnarInputBuilderInvokeSingle("func NoTests(): int { return 1 }\n")
    assert attempt.Succeeded
    program := attempt.Program
    if program == null {
        throw new InvalidOperationException("Single-source builder returned no program")
    }
    assert ColumnarInputBuilderOptionalMember(program, "Tests") == null
}

test "constructor-chain expressions materialize ordinary nodes while preserving the input constructor ABI" {
    inputType := ColumnarIlEmitterBootstrapType("ColumnarConstructorInput")
    inputConstructors := inputType.GetConstructors(
        BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly
    )
    assert inputConstructors.Length == 1
    assert inputConstructors[0].GetParameters().Length == 8, "ColumnarConstructorInput must retain its established eight-parameter CLR constructor"

    source := "class Inputs {}\nclass Cache {}\nclass Owner {\n    constructor(root: string): this(Build(root, null), root, new Cache(),) {}\n    constructor(inputs: Inputs, root: string, cache: Cache) {}\n    static func Build(root: string, value: object?): Inputs { return new Inputs() }\n}\n"
    attempt := ColumnarInputBuilderInvokeSingle(source)
    assert attempt.Succeeded
    program := attempt.Program
    if program == null {
        throw new InvalidOperationException("The constructor-chain input program was null")
    }

    structs := ColumnarInputBuilderMemberList(program, "Structs")
    owner: object? = null
    structIndex := 0
    while structIndex < structs.Count {
        candidate := ColumnarInputBuilderRequiredItem(structs, structIndex)
        if ColumnarInputBuilderText(candidate, "Name") == "Owner" {
            owner = candidate
        }
        structIndex = structIndex + 1
    }
    if owner == null {
        throw new InvalidOperationException("The constructor-chain owner input was missing")
    }

    ownerInput: object = owner
    constructors := ColumnarInputBuilderMemberList(ownerInput, "Constructors")
    assert constructors.Count == 2
    chained := ColumnarInputBuilderRequiredItem(constructors, 0)
    assert ColumnarInputBuilderInt(chained, "ChainInitKind") == 1
    kinds := ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(chained, "ChainArgKinds"), "ChainArgKinds")
    texts := ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(chained, "ChainArgTexts"), "ChainArgTexts")
    nodes := ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(chained, "ChainArgNodes"), "ChainArgNodes")
    roots := ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(chained, "ChainArgRoots"), "ChainArgRoots")
    assert kinds.Count == 3
    assert texts.Count == 3
    assert nodes.Count == 3
    assert roots.Count == 3
    assert Convert.ToInt32(kinds[0]) == 0
    assert ColumnarInputBuilderRequiredTextItem(texts, 0) == "Build(root, null)"
    assert Convert.ToInt32(kinds[1]) == 0
    assert ColumnarInputBuilderRequiredTextItem(texts, 1) == "root"
    assert Convert.ToInt32(kinds[2]) == 41
    assert ColumnarInputBuilderRequiredTextItem(texts, 2) == "Cache", "the established no-argument new chain text remains the type name"

    firstNodes := ColumnarInputBuilderRequiredItem(nodes, 0)
    secondNodes := ColumnarInputBuilderRequiredItem(nodes, 1)
    thirdNodes := ColumnarInputBuilderRequiredItem(nodes, 2)
    firstKinds := ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(firstNodes, "Kinds"), "first argument kinds")
    secondKinds := ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(secondNodes, "Kinds"), "second argument kinds")
    thirdKinds := ColumnarInputBuilderList(ColumnarInputBuilderRequiredMember(thirdNodes, "Kinds"), "third argument kinds")
    assert Convert.ToInt32(firstKinds[Convert.ToInt32(roots[0])]) == 9
    assert Convert.ToInt32(secondKinds[Convert.ToInt32(roots[1])]) == 6
    assert Convert.ToInt32(thirdKinds[Convert.ToInt32(roots[2])]) == 15
}

test "a later-file parse failure keeps null output deepest-first trace rows and clears its source id" {
    sources := new string[](2)
    sources[0] = "func Accepted(): int { return 1 }\n"
    sources[1] = "func Refused(): int[] {\n    return new int[] { 1, 2, 3 }\n}\n"
    fileNames := new string[](2)
    fileNames[0] = "Accepted.nl"
    fileNames[1] = "Refused.nl"

    ColumnarInputBuilderTraceReset()
    try {
        attempt := ColumnarInputBuilderInvokeMulti(sources, fileNames, "/project/root")
        assert !attempt.Succeeded
        assert attempt.Program == null

        ColumnarInputBuilderTraceRecord("parse.cleanup-probe", "cleanup probe")
        snapshot := ColumnarInputBuilderTraceSnapshot()
        assert snapshot.Count == 4
        deepest := ColumnarInputBuilderRequiredItem(snapshot, 0)
        declaration := ColumnarInputBuilderRequiredItem(snapshot, 1)
        materialization := ColumnarInputBuilderRequiredItem(snapshot, 2)
        probe := ColumnarInputBuilderRequiredItem(snapshot, 3)
        assert ColumnarInputBuilderText(deepest, "SiteId") == "parse.function"
        assert ColumnarInputBuilderText(deepest, "Message") == "function body or signature could not be parsed into columnar input"
        assert ColumnarInputBuilderBool(deepest, "HasSourceFileId")
        assert ColumnarInputBuilderInt(deepest, "SourceFileId") == 1
        assert ColumnarInputBuilderText(declaration, "Message") == "function declaration could not be parsed into columnar input"
        assert ColumnarInputBuilderBool(declaration, "HasSourceFileId")
        assert ColumnarInputBuilderInt(declaration, "SourceFileId") == 1
        assert ColumnarInputBuilderText(materialization, "Message") == "function declaration materialization failed"
        assert ColumnarInputBuilderBool(materialization, "HasSourceFileId")
        assert ColumnarInputBuilderInt(materialization, "SourceFileId") == 1
        assert ColumnarInputBuilderText(probe, "SiteId") == "parse.cleanup-probe"
        assert !ColumnarInputBuilderBool(probe, "HasSourceFileId")
        assert ColumnarInputBuilderInt(probe, "SourceFileId") == 0
    } finally {
        ColumnarInputBuilderTraceReset()
    }
}
