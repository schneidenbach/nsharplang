namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Reflection.Metadata
import System.Reflection.Metadata.Ecma335
import System.Reflection.PortableExecutable


// 023/1b — THE ECMA-335 WRITER SURFACE IS SPELLABLE FROM N#, MEASURED BY WRITING WITH IT.
//
// Before this slice `System.Reflection.Metadata` was not in `ExternalAssemblyScan.CommonAssemblyNames`,
// so `import System.Reflection.Metadata.Ecma335` was NL704 and `BlobBuilder` was NL201 — and neither
// could be worked around by fully qualifying, because a fully-qualified STATIC RECEIVER does not bind
// at all (`System.Reflection.Metadata.Ecma335.MetadataTokens.X` answers "Variable 'System' not found").
// One scan entry opens both namespaces, because one assembly carries both.
//
// These contracts are the writer's actual vocabulary, not a sample: the class it constructs, the
// handle it declares and passes, the static factory it reaches, and the byte-level blob writing that
// replaces the SRM encoder layer. The encoder layer is refused by design — every one of its signature
// entry points has exactly two overloads, one taking `out` byref structs and one taking `Action<T>`,
// and both are off the N# surface — so the writer owns its own encoding and only needs `BlobBuilder`.
func WriterFactsNilString(): StringHandle {
    return MetadataTokens.StringHandle(0)
}

func WriterFactsIsNil(handle: StringHandle): bool {
    return handle.get_IsNil()
}

test "a metadata writer class is constructible and its members bind" {
    md := new MetadataBuilder(0, 0, 0, 0)
    name := md.GetOrAddString("hello")
    assert !WriterFactsIsNil(name)

    // The nil handle is reachable, which is what lets a writer spell an absent column.
    assert WriterFactsIsNil(WriterFactsNilString())
}

test "a handle is a local, a parameter and a return type" {
    // Handles are opaque values that only ever flow as arguments and returns — the role
    // `System.Reflection.Emit.Label` and `OpCode` already play on the admitted-type list.
    handle := MetadataTokens.MethodDefinitionHandle(1)
    assert !handle.get_IsNil()

    nil := MetadataTokens.MethodDefinitionHandle(0)
    assert nil.get_IsNil()
}

test "an EntityHandle is spelled by token, because the implicit handle conversion is not applied" {
    // Every `MetadataBuilder.Add*` that takes a parent takes `EntityHandle`, and the 28 handle structs
    // each publish `op_Implicit` to it. N# does not apply a user-defined conversion, so passing an
    // `AssemblyReferenceHandle` where an `EntityHandle` is wanted is NL402 naming the one overload.
    // The writer's spelling-around is the exact `EntityHandle(int)` overload over a computed token —
    // which is the same two-pass row reservation a from-scratch writer needs anyway, so the conversion
    // is a design constraint and not a blocker. 0x23000001 is AssemblyRef row 1.
    scope := MetadataTokens.EntityHandle(587202561)
    assert MetadataTokens.GetRowNumber(scope) == 1

    md := new MetadataBuilder(0, 0, 0, 0)
    md.AddTypeReference(scope, md.GetOrAddString("System"), md.GetOrAddString("Object"))
}

test "a blob is written byte by byte, which is what replaces the encoder layer" {
    // `void Console::WriteLine(string)` as ECMA-335 II.23.2.1 spells it: DEFAULT calling convention,
    // one parameter, void return, string parameter.
    blob := new BlobBuilder(16)
    blob.WriteByte(Convert.ToByte(0))
    blob.WriteByte(Convert.ToByte(1))
    blob.WriteByte(Convert.ToByte(1))
    blob.WriteByte(Convert.ToByte(14))
    assert blob.get_Count() == 4

    bytes := blob.ToArray()
    assert bytes.Length == 4
    assert Convert.ToInt32(bytes[3]) == 14

    // A tiny method-body header and a 4-byte token, the two shapes a body stream needs.
    body := new BlobBuilder(16)
    body.WriteByte(Convert.ToByte(46))
    body.WriteInt32(167772161)
    assert body.get_Count() == 5
}

test "the PE serialization tail binds, including the base-declared Serialize" {
    md := new MetadataBuilder(0, 0, 0, 0)
    ilStream := new BlobBuilder(16)
    root := new MetadataRootBuilder(md, "v4.0.30319", false)
    header := PEHeaderBuilder.CreateExecutableHeader()
    entry := MetadataTokens.MethodDefinitionHandle(1)

    // All eleven arguments are spelled: an omitted defaulted parameter declines, so the writer passes
    // every one, including five nulls and a `Func<>`-typed null.
    pe := new ManagedPEBuilder(header, root, ilStream, null, null, null, null, 128, entry, CorFlags.ILOnly, null)

    // `Serialize` is declared on `PEBuilder`, not on `ManagedPEBuilder`.
    peBlob := new BlobBuilder(1024)
    pe.Serialize(peBlob)
    assert peBlob.get_Count() > 0
}
