namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections
import System.Reflection

// This source reaches the real product assembly boundary, rather than the new selection helper:
// only TryEmitColumnarAssembly owns its initialized `out byte[] assembly` slot.  A missing
// executable entry point returns false before metadata/save and leaves that slot as the BCL's
// Array.Empty<byte>() singleton.
func EntryPointRealizationPut(values: object?[], index: int, value: object?) {
    values[index] = value
}

// Keep the oracle boxed.  The contract is reference identity with the BCL singleton, and it
// does not need an object-to-byte-array cast merely to prove that identity.
func EntryPointRealizationBclEmptyByteArray(): object {
    emptyDefinition := typeof(Array).GetMethod("Empty")
    if emptyDefinition == null || !emptyDefinition.get_IsGenericMethodDefinition() {
        throw new InvalidOperationException("System.Array.Empty<T>() was not found.")
    }

    typeArguments := new Type[](1)
    typeArguments[0] = typeof(byte)
    closedEmpty := emptyDefinition.MakeGenericMethod(typeArguments)
    noArguments := new object?[](0)
    value := closedEmpty.Invoke(null, noArguments)
    if value == null {
        throw new InvalidOperationException("System.Array.Empty<byte>() returned null.")
    }
    return value
}

func EntryPointRealizationEmptyEntryPointTrace(): IList {
    snapshot := ColumnarTraceTestMethod("Snapshot")
    noArguments := new object?[](0)
    records := snapshot.Invoke(null, noArguments) as IList
    if records == null {
        throw new InvalidOperationException("The entry-point fixture did not return a decline snapshot.")
    }
    return records
}

// This requires parser success first, so false is the entry-point boundary rather than a malformed
// source failure. The selected direct N# controls cover the retained selected-method slot; this
// production witness covers the separate assembly byte slot only.
test "an executable without main preserves the real empty assembly output" {
    parse := ColumnarInputBuilderPrivateMethod("TryBuild", 2)
    parseArguments := new object?[](2)
    EntryPointRealizationPut(
        parseArguments,
        0,
        "func EntryPointRealizationNoMain(): int {\n    return 7\n}\n"
    )
    EntryPointRealizationPut(parseArguments, 1, null)
    assert Convert.ToBoolean(parse.Invoke(null, parseArguments))

    program := parseArguments[1]
    if program == null {
        throw new InvalidOperationException("The entry-point fixture parser returned no program.")
    }

    reset := ColumnarTraceTestMethod("Reset")
    noArguments := new object?[](0)
    _ = reset.Invoke(null, noArguments)

    emit := ColumnarIlEmitterPublicMethod("TryEmitColumnarAssembly", 7)
    emitArguments := new object?[](7)
    EntryPointRealizationPut(emitArguments, 0, "EntryPointRealizationNoMain")
    EntryPointRealizationPut(emitArguments, 1, "Program")
    EntryPointRealizationPut(emitArguments, 2, program)
    EntryPointRealizationPut(emitArguments, 3, true)
    EntryPointRealizationPut(emitArguments, 4, null)
    EntryPointRealizationPut(emitArguments, 5, null)
    EntryPointRealizationPut(emitArguments, 6, null)

    assert !Convert.ToBoolean(emit.Invoke(null, emitArguments))
    assert EntryPointRealizationEmptyEntryPointTrace().Count == 0

    image := emitArguments[4]
    if image == null {
        throw new InvalidOperationException("The executable entry-point refusal did not write its assembly slot.")
    }
    assert Object.ReferenceEquals(image, EntryPointRealizationBclEmptyByteArray())
}
