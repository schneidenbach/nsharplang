namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// A NARROWED VALUE-NULLABLE MEMBER PATH IS READ AS ITS ELEMENT, AT EMIT.
//
// `if h.Slot == null { return 0 }; return h.Slot + 1` checked clean — the analyzer files a null fact
// for the path and collapses the read to `int` — and then declined at
// `emit.return.type-mismatch`, because the emitter's narrowing knew only bare names and the read
// still arrived as `Nullable<int>`. These rows build the program for real, assert the emitter takes
// it without that decline, and run it: once with a value, and once through each invalidation with
// a NULL, where a stale unwrap would throw instead of answering the null the program reads.
func NarrowedPathSource(): string {
    holder := "class Holder {\n    Slot: int?\n}\n\n"
    bareRead := "func PathEqBare(h: Holder): int {\n    if h.Slot == null {\n        return 0\n    }\n\n    return h.Slot + 1\n}\n\n"
    prefixRewrite := "func PathAfterPrefixRewrite(h: Holder, other: Holder): int? {\n    current := h\n    if current.Slot == null {\n        return -1\n    }\n\n    current = other\n    return current.Slot\n}\n\n"
    overwrite := "func PathAfterOverwrite(h: Holder): int? {\n    if h.Slot == null {\n        return -1\n    }\n\n    h.Slot = null\n    return h.Slot\n}\n"
    return holder + bareRead + prefixRewrite + overwrite
}

func NarrowedPathAssembly(): Assembly {
    program := EmitFixtureProgram(["Probe"], [NarrowedPathSource()], "NarrowedPathProbe")
    ColumnarDeclineTrace.Reset()
    bytes: byte[] = null
    emitted := ColumnarIlEmitter.TryEmitColumnarAssembly("NarrowedPath" + Guid.NewGuid().ToString("N"), "Program", program, false, out bytes, null, null)
    for reason in ColumnarDeclineTrace.Snapshot() {
        assert reason.SiteId != "emit.return.type-mismatch"
    }
    assert emitted
    return Assembly.Load(bytes)
}

func NarrowedPathHolder(assembly: Assembly, slot: int?): object {
    holderType := assembly.GetType("Probe.Holder")
    assert holderType != null
    holder := Activator.CreateInstance(holderType)
    assert holder != null
    field := holderType.GetField("Slot")
    if field != null {
        field.SetValue(holder, slot)
    } else {
        property := holderType.GetProperty("Slot")
        assert property != null
        property.SetValue(holder, slot)
    }
    return holder
}

func NarrowedPathCall(assembly: Assembly, name: string, arguments: object?[]): object? {
    owner := assembly.GetType("Probe.Program")
    assert owner != null
    method := owner.GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
    assert method != null
    return method.Invoke(null, arguments)
}

// The answer a row needs a value from: a null answer is a fixture failure, not a value.
func NarrowedPathAnswer(assembly: Assembly, name: string, arguments: object?[]): string {
    answer := NarrowedPathCall(assembly, name, arguments)
    if answer == null {
        throw new InvalidOperationException(name + " answered null.")
    }
    return answer.ToString() ?? ""
}

test "a bare read of a narrowed int? member path emits as its element and runs" {
    assembly := NarrowedPathAssembly()

    present: object?[] = [NarrowedPathHolder(assembly, 5)]
    assert NarrowedPathAnswer(assembly, "PathEqBare", present) == "6"

    absent: object?[] = [NarrowedPathHolder(assembly, null)]
    assert NarrowedPathAnswer(assembly, "PathEqBare", absent) == "0"
}

test "a write to the path or to a prefix ends the emitted narrowing" {
    assembly := NarrowedPathAssembly()

    rewritten: object?[] = [NarrowedPathHolder(assembly, 1), NarrowedPathHolder(assembly, null)]
    assert NarrowedPathCall(assembly, "PathAfterPrefixRewrite", rewritten) == null

    overwritten: object?[] = [NarrowedPathHolder(assembly, 1)]
    assert NarrowedPathCall(assembly, "PathAfterOverwrite", overwritten) == null
}
