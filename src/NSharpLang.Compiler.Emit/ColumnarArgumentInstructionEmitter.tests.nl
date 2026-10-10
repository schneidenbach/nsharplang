namespace NSharpLang.Compiler.Columnar

import System.Reflection
import System.Reflection.Emit


// THE ARGUMENT OPCODE OWNER picks the one-byte `ldarg.s`/`starg.s`/`ldarga.s` forms through index
// 255 and the two-byte long forms from 256, and the bytes it writes are read back from a baked method.
test "constructor declaration argument owner selects byte forms through 255 and long forms at 256" {
    owner := EmitFixtureTypeBuilder(
        "ConstructorDeclarationArgumentBoundary",
        "ColumnarConstructorDeclarationControls.ArgumentBoundary",
        0
    )
    parameters := EmitFixtureIntParameters(257)
    load255 := owner.DefineMethod("Load255", (MethodAttributes)22, typeof(int), parameters)
    load255Il := EmitFixtureIL(load255)
    ColumnarArgumentInstructionEmitter.EmitLoad(load255Il, 255)
    load255Il.Emit(OpCodes.Ret)
    load256 := owner.DefineMethod("Load256", (MethodAttributes)22, typeof(int), parameters)
    load256Il := EmitFixtureIL(load256)
    ColumnarArgumentInstructionEmitter.EmitLoad(load256Il, 256)
    load256Il.Emit(OpCodes.Ret)

    store255 := owner.DefineMethod("Store255", (MethodAttributes)22, ColumnarTypeOfPlanner.RequiredVoidType(), parameters)
    store255Il := EmitFixtureIL(store255)
    store255Il.Emit(OpCodes.Ldc_I4_0)
    ColumnarArgumentInstructionEmitter.EmitStore(store255Il, 255)
    store255Il.Emit(OpCodes.Ret)
    store256 := owner.DefineMethod("Store256", (MethodAttributes)22, ColumnarTypeOfPlanner.RequiredVoidType(), parameters)
    store256Il := EmitFixtureIL(store256)
    store256Il.Emit(OpCodes.Ldc_I4_0)
    ColumnarArgumentInstructionEmitter.EmitStore(store256Il, 256)
    store256Il.Emit(OpCodes.Ret)

    address255 := owner.DefineMethod("Address255", (MethodAttributes)22, ColumnarTypeOfPlanner.RequiredVoidType(), parameters)
    address255Il := EmitFixtureIL(address255)
    ColumnarArgumentInstructionEmitter.EmitLoadAddress(address255Il, 255)
    address255Il.Emit(OpCodes.Pop)
    address255Il.Emit(OpCodes.Ret)
    address256 := owner.DefineMethod("Address256", (MethodAttributes)22, ColumnarTypeOfPlanner.RequiredVoidType(), parameters)
    address256Il := EmitFixtureIL(address256)
    ColumnarArgumentInstructionEmitter.EmitLoadAddress(address256Il, 256)
    address256Il.Emit(OpCodes.Pop)
    address256Il.Emit(OpCodes.Ret)

    baked := EmitFixtureBake(owner)
    load255Bytes := EmitFixtureIlBytes(
        EmitFixtureNamedMethod(baked, "Load255")
    )
    assert load255Bytes.Length == 3
    assert load255Bytes[0] == 14
    assert load255Bytes[1] == 255
    assert load255Bytes[2] == 42
    load256Bytes := EmitFixtureIlBytes(
        EmitFixtureNamedMethod(baked, "Load256")
    )
    assert load256Bytes.Length == 5
    assert load256Bytes[0] == 254
    assert load256Bytes[1] == 9
    assert load256Bytes[2] == 0
    assert load256Bytes[3] == 1
    assert load256Bytes[4] == 42

    store255Bytes := EmitFixtureIlBytes(
        EmitFixtureNamedMethod(baked, "Store255")
    )
    assert store255Bytes.Length == 4
    assert store255Bytes[0] == 22
    assert store255Bytes[1] == 16
    assert store255Bytes[2] == 255
    assert store255Bytes[3] == 42
    store256Bytes := EmitFixtureIlBytes(
        EmitFixtureNamedMethod(baked, "Store256")
    )
    assert store256Bytes.Length == 6
    assert store256Bytes[0] == 22
    assert store256Bytes[1] == 254
    assert store256Bytes[2] == 11
    assert store256Bytes[3] == 0
    assert store256Bytes[4] == 1
    assert store256Bytes[5] == 42

    address255Bytes := EmitFixtureIlBytes(
        EmitFixtureNamedMethod(baked, "Address255")
    )
    assert address255Bytes.Length == 4
    assert address255Bytes[0] == 15
    assert address255Bytes[1] == 255
    assert address255Bytes[2] == 38
    assert address255Bytes[3] == 42
    address256Bytes := EmitFixtureIlBytes(
        EmitFixtureNamedMethod(baked, "Address256")
    )
    assert address256Bytes.Length == 6
    assert address256Bytes[0] == 254
    assert address256Bytes[1] == 10
    assert address256Bytes[2] == 0
    assert address256Bytes[3] == 1
    assert address256Bytes[4] == 38
    assert address256Bytes[5] == 42
}
