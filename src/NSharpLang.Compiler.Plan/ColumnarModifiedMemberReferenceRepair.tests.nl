namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func ModifiedMemberWriteInt32(bytes: byte[], offset: int, value: int) {
    bytes[offset] = (byte)value
    bytes[offset + 1] = (byte)(value >> 8)
    bytes[offset + 2] = (byte)(value >> 16)
    bytes[offset + 3] = (byte)(value >> 24)
}

func ModifiedMemberReadInt32(bytes: byte[], offset: int): int {
    first := (int)bytes[offset]
    second := (int)bytes[offset + 1]
    second = second << 8
    third := (int)bytes[offset + 2]
    third = third << 16
    fourth := (int)bytes[offset + 3]
    fourth = fourth << 24
    return first | second | third | fourth
}

func ModifiedMemberReplacements(oldToken: int, newToken: int): Dictionary<int, int> {
    replacements := new Dictionary<int, int>()
    replacements[oldToken] = newToken
    return replacements
}

test "ColumnarModifiedMemberReferenceRepair changes a real InlineMethod operand but never identical bytes in a constant" {
    oldToken := 0x0a000039
    newToken := 0x0a000040
    body := new byte[](12)
    body[0] = (byte)((11 << 2) | 2)
    body[1] = 0x20
    // ldc.i4
    ModifiedMemberWriteInt32(body, 2, oldToken)
    body[6] = 0x28
    // call
    ModifiedMemberWriteInt32(body, 7, oldToken)
    body[11] = 0x2a
    // ret

    assert ColumnarModifiedMemberReferenceRepair.TryPatchMethodBodiesForTests(body, ModifiedMemberReplacements(oldToken, newToken))
    assert ModifiedMemberReadInt32(body, 2) == oldToken
    assert ModifiedMemberReadInt32(body, 7) == newToken
}

test "ColumnarModifiedMemberReferenceRepair walks switches and prefixes without treating their operands as methods" {
    oldToken := 0x0a000039
    newToken := 0x0a000040
    body := new byte[](24)
    body[0] = (byte)((23 << 2) | 2)
    body[1] = 0x45
    // switch
    ModifiedMemberWriteInt32(body, 2, 1)
    ModifiedMemberWriteInt32(body, 6, oldToken)
    body[10] = 0xfe
    body[11] = 0x13
    // volatile.
    body[12] = 0xfe
    body[13] = 0x16
    // constrained. InlineType
    ModifiedMemberWriteInt32(body, 14, oldToken)
    body[18] = 0x6f
    // callvirt
    ModifiedMemberWriteInt32(body, 19, oldToken)
    body[23] = 0x2a
    // ret

    assert ColumnarModifiedMemberReferenceRepair.TryPatchMethodBodiesForTests(body, ModifiedMemberReplacements(oldToken, newToken))
    assert ModifiedMemberReadInt32(body, 6) == oldToken
    assert ModifiedMemberReadInt32(body, 14) == oldToken
    assert ModifiedMemberReadInt32(body, 19) == newToken
}

test "ColumnarModifiedMemberReferenceRepair rejects truncated switch operands and undefined opcodes" {
    truncated := new byte[](6)
    truncated[0] = (byte)((5 << 2) | 2)
    truncated[1] = 0x45
    ModifiedMemberWriteInt32(truncated, 2, 1)
    assert !ColumnarModifiedMemberReferenceRepair.TryPatchMethodBodiesForTests(truncated, new Dictionary<int, int>())

    undefined := new byte[](2)
    undefined[0] = (byte)((1 << 2) | 2)
    undefined[1] = 0x24
    assert !ColumnarModifiedMemberReferenceRepair.TryPatchMethodBodiesForTests(undefined, new Dictionary<int, int>())
}

test "ColumnarModifiedMemberReferenceRepair retains a marked method signature source when the code-plan pool grows" {
    parameterTypes := new Type[](0)
    method := typeof(string).GetMethod("ToString", parameterTypes)
    assert method != null
    plan := new ColumnarCodePlan()
    plan.PrepareV3()
    first := -1
    last := -1
    for index := 0; index < 20; index++ {
        methodIndex := plan.AddMethodWithSignature(method, typeof(string), parameterTypes, typeof(string), false, false)
        if index == 0 {
            first = methodIndex
            plan.MarkMethodForModifiedMemberReferenceRepair(methodIndex, method)
        }
        last = methodIndex
    }
    assert first == 0
    assert last == 19
    assert plan.MethodModifiedSignatureSources[first] == method
    assert plan.MethodModifiedSignatureSources[last] == null
}

test "ColumnarModifiedMemberReferenceRepair keeps unbaked VAR and MVAR identities distinct" {
    assembly := AssemblyBuilder.DefineDynamicAssembly(new AssemblyName("ModifiedMemberGenericIdentity"), AssemblyBuilderAccess.Run)
    module := assembly.DefineDynamicModule("ModifiedMemberGenericIdentity")
    owner := module.DefineType("Owner", TypeAttributes.Public)
    ownerParameters := owner.DefineGenericParameters(["T"])
    method := owner.DefineMethod("Make", MethodAttributes.Public | MethodAttributes.Static)
    methodParameters := method.DefineGenericParameters(["U", "V"])

    assert ownerParameters.Length == 1
    assert methodParameters.Length == 2
    assert ownerParameters[0].get_IsGenericTypeParameter()
    assert methodParameters[0].get_IsGenericMethodParameter()
    assert ColumnarModifiedMemberReferenceRepair.RuntimeTypeIdentity(ownerParameters[0]) != ColumnarModifiedMemberReferenceRepair.RuntimeTypeIdentity(methodParameters[0])
    assert ColumnarModifiedMemberReferenceRepair.RuntimeTypeIdentity(methodParameters[0]) != ColumnarModifiedMemberReferenceRepair.RuntimeTypeIdentity(methodParameters[1])
}
