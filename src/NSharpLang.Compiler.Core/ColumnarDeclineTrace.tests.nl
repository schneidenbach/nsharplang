namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection


// These controls own the thread-local trace contract now that the compiler's decline state is N#.
// They keep the returned snapshot separate from its mutable per-thread accumulator and exercise the
// constructor declaration return-inside-try path where the trace must be recorded before disposal.
class ConstructorDeclineTraceThreadProbe {
    Count: int
    SiteId: string
    Message: string
    SourceFileId: int
    HasSourceFileId: bool
    Error: string

    constructor() {
        Count = 0
        SiteId = ""
        Message = ""
        SourceFileId = 0
        HasSourceFileId = false
        Error = ""
    }

    func Run() {
        try {
            ColumnarDeclineTrace.Reset()
            ColumnarDeclineTrace.SetSourceFileId(73)
            ColumnarDeclineTrace.Record("trace.worker", "worker record", 17, 3, "Worker")
            snapshot := ColumnarDeclineTrace.Snapshot()
            Count = snapshot.Count
            first := snapshot[0]
            SiteId = first.SiteId
            Message = first.Message
            SourceFileId = first.SourceFileId
            HasSourceFileId = first.HasSourceFileId
        } catch error: Exception {
            Error = error.Message
        }
    }
}

class ConstructorDeclineTraceControlsTypedLists {
    static func SetConstructors(
        input: ColumnarStructInput,
        rows: IReadOnlyList<ColumnarConstructorInput>
    ) {
        input.Constructors = rows
    }
}

func ConstructorDeclineTraceControlsRuntimeType(identity: string): Type {
    result := Type.GetType(identity)
    if result == null {
        throw new InvalidOperationException("Required trace runtime type was not found: " + identity)
    }
    return result
}

func ConstructorDeclineTraceControlsSetObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func ConstructorDeclineTraceControlsSetConstructors(input: ColumnarStructInput, rows: object) {
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(ColumnarStructInput)
    parameterTypes[1] = typeof(IReadOnlyList<ColumnarConstructorInput>)
    setter := ExecutorRequiredMethod(
        typeof(ConstructorDeclineTraceControlsTypedLists),
        "SetConstructors",
        parameterTypes
    )
    arguments := new object?[](2)
    ConstructorDeclineTraceControlsSetObject(arguments, 0, input)
    ConstructorDeclineTraceControlsSetObject(arguments, 1, rows)
    ignored := setter.Invoke(null, arguments)
    _ = ignored
}

func ConstructorDeclineTraceControlsCatchesHostileDeclarationDispose(
    program: ColumnarProgramInput,
    inputs: List<ColumnarStructInput>,
    definitions: ColumnarStructDef[],
    resolutions: ColumnarSemanticTypeResolution[],
    depths: int[]
): bool {
    try {
        ColumnarConstructorDeclarationPlanner.Declare(
            program,
            inputs,
            definitions,
            resolutions,
            depths
        )
    } catch error: InvalidOperationException {
        return error.Message == "member iterator fixture disposal failed"
    }
    return false
}

func ConstructorDeclineTraceControlsRunThread(probe: ConstructorDeclineTraceThreadProbe) {
    noParameters := new Type[](0)
    threadType := ConstructorDeclineTraceControlsRuntimeType(
        "System.Threading.Thread, System.Private.CoreLib"
    )
    threadStartType := ConstructorDeclineTraceControlsRuntimeType(
        "System.Threading.ThreadStart, System.Private.CoreLib"
    )
    createParameters := new Type[](3)
    createParameters[0] = typeof(Type)
    createParameters[1] = typeof(object)
    createParameters[2] = typeof(string)
    createDelegate := ExecutorRequiredMethod(typeof(Delegate), "CreateDelegate", createParameters)
    delegateArguments := new object?[](3)
    ConstructorDeclineTraceControlsSetObject(delegateArguments, 0, threadStartType)
    ConstructorDeclineTraceControlsSetObject(delegateArguments, 1, probe)
    ConstructorDeclineTraceControlsSetObject(delegateArguments, 2, "Run")
    callback := createDelegate.Invoke(null, delegateArguments)
    if callback == null {
        throw new InvalidOperationException("Trace thread callback was not created")
    }

    constructorParameters := new Type[](1)
    constructorParameters[0] = threadStartType
    constructor := ExecutorRequiredConstructor(threadType, constructorParameters)
    threadArguments := new object?[](1)
    ConstructorDeclineTraceControlsSetObject(threadArguments, 0, callback)
    thread := constructor.Invoke(threadArguments)
    if thread == null {
        throw new InvalidOperationException("Trace thread was not constructed")
    }

    start := ExecutorRequiredMethod(threadType, "Start", noParameters)
    join := ExecutorRequiredMethod(threadType, "Join", noParameters)
    invokeArguments := new object?[](0)
    startResult := start.Invoke(thread, invokeArguments)
    _ = startResult
    joinResult := join.Invoke(thread, invokeArguments)
    _ = joinResult
}

test "columnar decline trace resets with the BCL empty snapshot and copies recorded rows" {
    ColumnarDeclineTrace.Reset()
    try {
        firstEmpty := ColumnarDeclineTrace.Snapshot()
        secondEmpty := ColumnarDeclineTrace.Snapshot()
        expectedEmpty := System.Array.Empty<ColumnarDeclineReason>()
        firstEmptyObject := firstEmpty as object
        secondEmptyObject := secondEmpty as object
        expectedEmptyObject := expectedEmpty as object
        assert Object.ReferenceEquals(firstEmptyObject, secondEmptyObject)
        assert Object.ReferenceEquals(firstEmptyObject, expectedEmptyObject)
        assert firstEmpty.Count == 0

        ColumnarDeclineTrace.Record("trace.first", "first record", 11, 2, "First")
        firstSnapshot := ColumnarDeclineTrace.Snapshot()
        ColumnarDeclineTrace.Record("trace.second", "second record", 19, 4, "Second")
        secondSnapshot := ColumnarDeclineTrace.Snapshot()
        firstSnapshotObject := firstSnapshot as object
        secondSnapshotObject := secondSnapshot as object
        firstRecordObject := firstSnapshot[0] as object
        secondRecordObject := secondSnapshot[0] as object
        assert !Object.ReferenceEquals(firstSnapshotObject, secondSnapshotObject)
        assert Object.ReferenceEquals(firstRecordObject, secondRecordObject)
        assert firstSnapshot.Count == 1
        assert firstSnapshot[0].SiteId == "trace.first"
        assert firstSnapshot[0].Message == "first record"
        assert firstSnapshot[0].SpanStart == 11
        assert firstSnapshot[0].SpanLength == 2
        assert firstSnapshot[0].MemberName == "First"
        assert !firstSnapshot[0].HasSourceFileId
        assert secondSnapshot.Count == 2
        assert secondSnapshot[0].SiteId == "trace.first"
        assert secondSnapshot[1].SiteId == "trace.second"

        ColumnarDeclineTrace.SetSourceFileId(29)
        ColumnarDeclineTrace.Reset()
        ColumnarDeclineTrace.Record("trace.after-reset", "reset source id", 23, 1, "Reset")
        afterSourceReset := ColumnarDeclineTrace.Snapshot()
        assert afterSourceReset.Count == 1
        assert !afterSourceReset[0].HasSourceFileId
        assert afterSourceReset[0].SourceFileId == 0

        ColumnarDeclineTrace.Reset()
        ColumnarDeclineTrace.SetSourceFileId(29)
        ColumnarDeclineTrace.Record("trace.source", "source record", 31, 5, "Source")
        ColumnarDeclineTrace.ClearSourceFileId()
        ColumnarDeclineTrace.Record("trace.cleared", "cleared record", 37, 7, "Cleared")
        sourceSnapshot := ColumnarDeclineTrace.Snapshot()
        assert sourceSnapshot.Count == 2
        assert sourceSnapshot[0].HasSourceFileId
        assert sourceSnapshot[0].SourceFileId == 29
        assert !sourceSnapshot[1].HasSourceFileId
        assert sourceSnapshot[1].SourceFileId == 0

        ColumnarDeclineTrace.Reset()
        afterReset := ColumnarDeclineTrace.Snapshot()
        afterResetObject := afterReset as object
        assert Object.ReferenceEquals(afterResetObject, expectedEmptyObject)
    } finally {
        ColumnarDeclineTrace.Reset()
    }
}

test "columnar decline trace isolates the worker thread accumulator and source id" {
    ColumnarDeclineTrace.Reset()
    try {
        ColumnarDeclineTrace.SetSourceFileId(41)
        ColumnarDeclineTrace.Record("trace.main", "main record", 1, 1, "Main")
        probe := new ConstructorDeclineTraceThreadProbe()
        ConstructorDeclineTraceControlsRunThread(probe)

        mainSnapshot := ColumnarDeclineTrace.Snapshot()
        assert mainSnapshot.Count == 1
        assert mainSnapshot[0].SiteId == "trace.main"
        assert mainSnapshot[0].HasSourceFileId
        assert mainSnapshot[0].SourceFileId == 41
        assert probe.Error == ""
        assert probe.Count == 1
        assert probe.SiteId == "trace.worker"
        assert probe.Message == "worker record"
        assert probe.HasSourceFileId
        assert probe.SourceFileId == 73
    } finally {
        ColumnarDeclineTrace.Reset()
    }
}

test "constructor declaration records its decline before a hostile constructor iterator throws on disposal" {
    definition := ConstructorDeclarationControlsDefinition("ConstructorDeclineTraceDispose", 0)
    brokenBody := ConstructorDeclarationControlsEmptyBody(
        "Broken",
        new string[](0),
        new string[](0)
    )
    brokenConstructor := ConstructorDeclarationControlsConstructor(
        brokenBody,
        2,
        ConstructorDeclarationControlsEmptyInts(),
        ConstructorDeclarationControlsEmptyTexts(),
        false
    )
    input := ConstructorDeclarationControlsInput(
        definition.DeclaredTypeName,
        new List<ColumnarConstructorInput>()
    )
    inputs := new List<ColumnarStructInput>()
    inputs.Add(input)
    definitions := new ColumnarStructDef[](1)
    definitions[0] = definition
    depths := new int[](1)
    program := ConstructorDeclarationControlsProgram("", inputs)
    resolutions := ConstructorDeclarationControlsResolutions(program, definitions)

    rows := new object[](1)
    ConstructorDeclineTraceControlsSetObject(rows, 0, brokenConstructor)
    state := new MemberIteratorControlsRowsState(rows, true)
    state.CountAllowed = true
    hostileRows := MemberIteratorControlsWrapReadOnlyList(
        "ConstructorDeclineTraceHostileConstructors",
        typeof(ColumnarConstructorInput),
        state
    )
    ConstructorDeclineTraceControlsSetConstructors(input, hostileRows)

    ColumnarDeclineTrace.Reset()
    try {
        disposalCaught := ConstructorDeclineTraceControlsCatchesHostileDeclarationDispose(
            program,
            inputs,
            definitions,
            resolutions,
            depths
        )
        assert disposalCaught
        snapshot := ColumnarDeclineTrace.Snapshot()
        assert snapshot.Count == 1
        assert snapshot[0].SiteId == "emit.ctor.base-chain-without-base"
        assert snapshot[0].Message == "constructor base initializer requires a modeled base class"
        assert snapshot[0].MemberName == definition.Builder.get_Name() + ".constructor"
        assert snapshot[0].SpanStart == -1
        assert snapshot[0].SpanLength == 0
        assert !snapshot[0].HasSourceFileId
        assert state.MoveCount == 1
        assert state.CurrentCount == 1
        assert state.DisposeCount == 1
    } finally {
        ColumnarDeclineTrace.Reset()
    }
}
