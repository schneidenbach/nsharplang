namespace NSharpLang.Compiler.Columnar

import System
import System.Diagnostics
import System.IO


// THE CANONICAL CONTRACTS FOR `ColumnarRuntimeTypeFacts`, IN N#.
//
// These replace `tests/ColumnarRuntimeTypeFactsTests.cs`, the shortest file in the C# estate (20
// lines, one `[Theory]`, four `[InlineData]` rows) and the last canonical C# assertion layer over
// this kernel. The subject is already entirely N# (`ColumnarRuntimeTypeFacts.nl`); its production
// referrers are `ColumnarRuntimeInstanceMemberResolver.nl` and the C# `ColumnarIlEmitter`, which
// consults it before it will lower an instance call onto an external runtime object.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. The block recorded against this file in slice 3
// was "4 `Type`-constant rows, refused by NL310, needing finding 99.1's `Type.GetType` seeding" —
// and the first half of that is a statement about a `with (…) […]` TABLE in a `tests/native`
// project, where `NL310` requires each row value to be a compile-time constant and a `System.Type`
// is not one. Here the four facts are ASSERT EXPRESSIONS and `typeof` is ordinary: 116 estate
// `.tests.nl` files already spell it, and the subject's OWN body is written with `typeof(Process)`,
// `typeof(ProcessStartInfo)` and `typeof(StreamReader)`.
//
// THE SECOND HALF OF THAT BLOCK WAS REAL, AND IT IS WHY THIS FILE HAS A `NamedType` HELPER.
// `typeof(FileStream)` DECLINES at emit — it is not on the columnar `typeof` surface — which is
// exactly why the subject itself reaches `FileStream` and `DirectoryInfo` through
// `Type.GetType("System.IO.FileStream")` rather than through `typeof`. Finding 99.1's seeding is
// therefore not optional decoration here: it is the only way to name half of this kernel's own
// admitted set, and `NamedType` makes the seeding explicit and non-null.
//
// THE THREE THINGS THAT ARE EASY TO GET WRONG:
//
// (1) THE TWO FAMILIES ARE DISJOINT, AND THE EMITTER DEPENDS ON THAT. A direct-call interop type
// (`Stream`, `FileStream`, `DirectoryInfo`) is NOT a process interop type, and a process interop
// type (`Process`, `ProcessStartInfo`, `StreamReader`) is NOT a direct-call one. The deleted C#
// asked only one of the two questions and never crossed them, so nothing anywhere stated that a
// type admitted by one gate is refused by the other.
//
// (2) `StreamReader` IS NOT A `Stream`, AND THE SPLIT IS DELIBERATE. `StreamReader` is on the
// PROCESS side because it is what `Process.StandardOutput` hands back; `Stream` is on the
// direct-call side. Reading the two rules as one "IO types" rule gets both wrong.
//
// (3) TWO OF THE DIRECT-CALL ROWS ARE RESOLVED BY NAME AT RUNTIME AND GUARDED AGAINST NULL, so if
// either name ever stopped resolving the gate would silently answer `false` for a type it is
// supposed to admit — and no negative assertion anywhere would notice. These contracts state the
// POSITIVE for both, which is the only shape that does.

// `typeof` cannot name every runtime type the columnar surface knows, so the types this kernel
// resolves BY NAME are named the same way here, with the null the subject guards against turned
// into a loud failure rather than a quiet `false`.
func NamedRuntimeType(name: string): Type {
    found := Type.GetType(name)
    if found == null {
        throw new InvalidOperationException("The runtime interop type was not resolvable: " + name)
    }

    return found
}

// Successor to IsSupportedProcessInteropType_ClassifiesProcessInteropTypes — all four of its rows.
test "columnar runtime type facts admit the three process interop types" {
    assert ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType(typeof(Process))
    assert ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType(typeof(ProcessStartInfo))
    assert ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType(typeof(StreamReader))
    assert !ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType(typeof(string))
}

// The gate is a closed set, not a namespace test: the `System.Diagnostics` and `System.IO`
// neighbours the emitter never modeled are refused, and so is a plain object.
test "the process interop gate is a closed set of exactly three types" {
    assert !ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType(NamedRuntimeType("System.Diagnostics.Stopwatch"))
    assert !ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType(NamedRuntimeType("System.IO.StreamWriter"))
    assert !ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType(typeof(int))
    assert !ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType(typeof(object))
}

// The deleted C# knew only the process gate. This gate is not unasserted, though — measured, not
// assumed: `ColumnarDirectCallAdversarial.tests.nl:459` and `:538` already reach it for
// `FileStream` and `DirectoryInfo` as a PRECONDITION of the direct-call cases they are really
// about. What is new here is the gate stated as a gate: its `Stream` row, its closed set, and the
// disjointness crossing below.
test "columnar runtime type facts admit the three direct-call interop types" {
    assert ColumnarRuntimeTypeFacts.IsSupportedDirectCallInteropType(typeof(Stream))
    assert ColumnarRuntimeTypeFacts.IsSupportedDirectCallInteropType(NamedRuntimeType("System.IO.FileStream"))
    assert ColumnarRuntimeTypeFacts.IsSupportedDirectCallInteropType(NamedRuntimeType("System.IO.DirectoryInfo"))
}

// The two name-resolved rows, stated as the lookups the subject actually performs. If either ever
// answered null the gate above would go quietly false, so the resolution itself is the claim.
test "the name-resolved direct-call rows resolve to the types they name" {
    fileStreamType := NamedRuntimeType("System.IO.FileStream")
    assert fileStreamType.Name == "FileStream"
    assert ColumnarRuntimeTypeFacts.IsSupportedDirectCallInteropType(fileStreamType)

    directoryInfoType := NamedRuntimeType("System.IO.DirectoryInfo")
    assert directoryInfoType.Name == "DirectoryInfo"
    assert ColumnarRuntimeTypeFacts.IsSupportedDirectCallInteropType(directoryInfoType)
}

test "the direct-call gate is a closed set of exactly three types" {
    assert !ColumnarRuntimeTypeFacts.IsSupportedDirectCallInteropType(NamedRuntimeType("System.IO.MemoryStream"))
    assert !ColumnarRuntimeTypeFacts.IsSupportedDirectCallInteropType(NamedRuntimeType("System.IO.FileInfo"))
    assert !ColumnarRuntimeTypeFacts.IsSupportedDirectCallInteropType(typeof(string))
    assert !ColumnarRuntimeTypeFacts.IsSupportedDirectCallInteropType(typeof(object))
}

// The crossing the deleted C# could not make, because it only knew one of the two gates.
test "the direct-call and process interop gates admit disjoint type sets" {
    assert !ColumnarRuntimeTypeFacts.IsSupportedDirectCallInteropType(typeof(Process))
    assert !ColumnarRuntimeTypeFacts.IsSupportedDirectCallInteropType(typeof(ProcessStartInfo))
    assert !ColumnarRuntimeTypeFacts.IsSupportedDirectCallInteropType(typeof(StreamReader))

    assert !ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType(typeof(Stream))
    assert !ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType(NamedRuntimeType("System.IO.FileStream"))
    assert !ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType(NamedRuntimeType("System.IO.DirectoryInfo"))
}
