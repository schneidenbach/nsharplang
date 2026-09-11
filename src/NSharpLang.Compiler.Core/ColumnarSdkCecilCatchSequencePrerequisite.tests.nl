namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Reflection.Emit
import Mono.Cecil

func ScsClosedMetadataEnumerable(context: MetadataLoadContext, elementType: Type): Type {
    core := context.get_CoreAssembly()
    if core == null {
        throw new InvalidOperationException("The metadata load context has no core assembly.")
    }
    definition := SmcRequiredType(core.GetType("System.Collections.Generic.IEnumerable`1"), "metadata IEnumerable<T>")
    arguments := new Type[](1)
    arguments[0] = elementType
    return definition.MakeGenericType(arguments)
}

func ScsCatchNodes(source: string): ColumnarNodeTable {
    kinds := new int[](1)
    kinds[0] = 50
    starts := new int[](1)
    lengths := new int[](1)
    lengths[0] = source.Length
    childStarts := new int[](1)
    childCounts := new int[](1)
    children := new int[](0)
    return new ColumnarNodeTable(kinds, starts, lengths, childStarts, childCounts, children)
}

func ScsRouteFailure(kind: int, trace: List<string>): string {
    try {
        trace.Add("try")
        if kind == 0 {
            throw new BadImageFormatException("bad image")
        }
        if kind == 1 {
            throw new FileNotFoundException("missing")
        }
        throw new InvalidOperationException("unrelated")
    } catch error: BadImageFormatException {
        trace.Add("bad")
        return error.Message
    } catch error: IOException {
        trace.Add("io")
        return error.Message
    }
}

func ScsCountTypes(sequence: IEnumerable<TypeDefinition>): int {
    enumerator := sequence.GetEnumerator()
    movement := enumerator as IEnumerator
    count := 0
    try {
        while movement.MoveNext() {
            current := enumerator.get_Current()
            assert current.FullName.Length > 0
            count += 1
        }
    } finally {
        disposable := enumerator as IDisposable
        if disposable != null {
            disposable.Dispose()
        }
    }
    return count
}

func ScsCountReferences(sequence: IEnumerable<AssemblyNameReference>): int {
    enumerator := sequence.GetEnumerator()
    movement := enumerator as IEnumerator
    count := 0
    try {
        while movement.MoveNext() {
            current := enumerator.get_Current()
            assert current.FullName.Length > 0
            count += 1
        }
    } finally {
        disposable := enumerator as IDisposable
        if disposable != null {
            disposable.Dispose()
        }
    }
    return count
}

test "canonical catch resolution admits exact IOException and BadImageFormatException names only" {
    exceptionType := typeof(string)
    assert ColumnarCanonicalTypeResolver.TryResolveBclExceptionType("IOException", out exceptionType)
    assert exceptionType == typeof(IOException)
    exceptionType = typeof(string)
    assert ColumnarCanonicalTypeResolver.TryResolveBclExceptionType("System.IO.IOException", out exceptionType)
    assert exceptionType == typeof(IOException)
    exceptionType = typeof(string)
    assert ColumnarCanonicalTypeResolver.TryResolveBclExceptionType("BadImageFormatException", out exceptionType)
    assert exceptionType == typeof(BadImageFormatException)
    exceptionType = typeof(string)
    assert ColumnarCanonicalTypeResolver.TryResolveBclExceptionType("System.BadImageFormatException", out exceptionType)
    assert exceptionType == typeof(BadImageFormatException)

    exceptionType = typeof(string)
    assert !ColumnarCanonicalTypeResolver.TryResolveBclExceptionType("EndOfStreamException", out exceptionType)
    assert exceptionType == null

    badImageName := "BadImageFormatException"
    nodes := ScsCatchNodes(badImageName)
    assert ColumnarCanonicalTypeResolver.TryResolveCatchType(nodes, badImageName, 0, out exceptionType)
    assert exceptionType == typeof(BadImageFormatException)
    ioName := "System.IO.IOException"
    nodes = ScsCatchNodes(ioName)
    assert ColumnarCanonicalTypeResolver.TryResolveCatchType(nodes, ioName, 0, out exceptionType)
    assert exceptionType == typeof(IOException)
}

test "emitted catch clauses preserve BadImageFormat then IOException routing and propagate unrelated failures" {
    trace := new List<string>()
    assert ScsRouteFailure(0, trace) == "bad image"
    assert trace.Count == 2
    assert trace[0] == "try"
    assert trace[1] == "bad"

    trace.Clear()
    assert ScsRouteFailure(1, trace) == "missing"
    assert trace.Count == 2
    assert trace[0] == "try"
    assert trace[1] == "io"

    trace.Clear()
    propagated := false
    try {
        ScsRouteFailure(2, trace)
    } catch error: InvalidOperationException {
        assert error.Message == "unrelated"
        propagated = true
    }
    assert propagated
    assert trace.Count == 1
    assert trace[0] == "try"
}

test "Cecil sequence admission requires exact closed IEnumerable and element identities across load contexts" {
    typeElements := new Type[](4)
    typeElements[0] = typeof(TypeDefinition)
    typeElements[1] = typeof(ExportedType)
    typeElements[2] = typeof(AssemblyNameReference)
    typeElements[3] = typeof(Mono.Cecil.TypeReference)
    index := 0
    while index < typeElements.Length {
        assert ColumnarTypeOfPlanner.IsSupportedCecilSequenceType(SmcClosedEnumerable(typeElements[index]))
        index += 1
    }

    assert !ColumnarTypeOfPlanner.IsSupportedCecilSequenceType(typeof(IEnumerable<int>).GetGenericTypeDefinition())
    assert !ColumnarTypeOfPlanner.IsSupportedCecilSequenceType(SmcClosedEnumerable(typeof(string)))
    sourceElement := TypeOfCreateBuilder("Mono.Cecil.TypeDefinition", "NSharpTests.ForeignCecilElement", 0)
    assert !ColumnarTypeOfPlanner.IsSupportedCecilSequenceType(SmcClosedEnumerable(sourceElement))
    assert !ColumnarTypeOfPlanner.IsSupportedCecilSequenceType(SmcClosedEnumerable(SmcBake(sourceElement)))
    assert !ColumnarTypeOfPlanner.IsSupportedCecilSequenceType(TypeOfCreateBuilder("System.Collections.Generic.IEnumerable`1", "NSharpTests.ForeignEnumerable", 1))
    assert !ColumnarTypeOfPlanner.IsSupportedCecilSequenceType(SmcEnumBuilder("System.Collections.Generic.IEnumerable`1"))

    context := SmcMetadataContext()
    try {
        cecilPath := typeof(ReaderParameters).get_Assembly().get_Location()
        metadataTypeDefinition := SmcMetadataType(context, cecilPath, "Mono.Cecil.TypeDefinition")
        metadataExportedType := SmcMetadataType(context, cecilPath, "Mono.Cecil.ExportedType")
        metadataAssemblyReference := SmcMetadataType(context, cecilPath, "Mono.Cecil.AssemblyNameReference")
        metadataTypeReference := SmcMetadataType(context, cecilPath, "Mono.Cecil.TypeReference")
        assert ColumnarTypeOfPlanner.IsSupportedCecilSequenceType(ScsClosedMetadataEnumerable(context, metadataTypeDefinition))
        assert ColumnarTypeOfPlanner.IsSupportedCecilSequenceType(ScsClosedMetadataEnumerable(context, metadataExportedType))
        assert ColumnarTypeOfPlanner.IsSupportedCecilSequenceType(ScsClosedMetadataEnumerable(context, metadataAssemblyReference))
        assert ColumnarTypeOfPlanner.IsSupportedCecilSequenceType(ScsClosedMetadataEnumerable(context, metadataTypeReference))
    } finally {
        context.Dispose()
    }
}

test "emitted Cecil generic sequence loops use the real properties and preserve one enumerator through finally" {
    assembly := AssemblyDefinition.ReadAssembly(typeof(ColumnarRuntimeInstanceMemberResolver).get_Assembly().get_Location())
    try {
        module := assembly.MainModule
        types := module.Types
        typeSequence: IEnumerable<TypeDefinition> = types
        typeCount := ScsCountTypes(typeSequence)
        assert typeCount == types.Count
        assert typeCount > 0

        references := module.AssemblyReferences
        referenceSequence: IEnumerable<AssemblyNameReference> = references
        referenceCount := ScsCountReferences(referenceSequence)
        assert referenceCount == references.Count
        assert referenceCount > 0
    } finally {
        assembly.Dispose()
    }
}
