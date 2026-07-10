namespace NSharpLang.Compiler.Columnar

func AssertSupportedOpcode(name: string) {
    plan := ColumnarExternalBindingPlans.GetStaticMemberPlan("OpCodes", name)
    assert plan.IsSupported
    assert plan.Kind == ColumnarExternalStaticMemberKind.Field
    assert plan.DeclaringTypeName == "System.Reflection.Emit.OpCodes, System.Private.CoreLib"
    assert plan.MemberName == name
    assert plan.ValueTypeName == "System.Reflection.Emit.OpCode, System.Private.CoreLib"
}

func AssertRuntimeType(canonical: string, expected: string) {
    runtimeTypeName := ""
    assert ColumnarExternalBindingPlans.TryGetRuntimeTypeName(canonical, out runtimeTypeName)
    assert runtimeTypeName == expected + ", System.Private.CoreLib"
    assert ColumnarExternalBindingPlans.IsSupportedRuntimeTypeName(expected)
}

func AssertVirtualCall(
    receiver: string,
    member: string,
    arguments: string[],
    expectedReturnType: string) {
    plan := ColumnarExternalBindingPlans.GetInstanceCallPlan(receiver, member, arguments)
    assert plan.IsSupported
    assert plan.Kind == ColumnarExternalCallKind.CallVirtual
    assert plan.DeclaringTypeName == receiver + ", System.Private.CoreLib"
    assert plan.MemberName == member
    assert plan.ParameterTypeNames.Length == arguments.Length
    i := 0
    while i < arguments.Length {
        assert plan.ParameterTypeNames[i] == arguments[i] + ", System.Private.CoreLib"
        i = i + 1
    }
    assert plan.ReturnTypeName == expectedReturnType + ", System.Private.CoreLib"
}

test "range code plans own every required opcode field" {
    names := new string[](32)
    names[0] = "Ldc_I4_M1"
    names[1] = "Ldc_I4_0"
    names[2] = "Ldc_I4_1"
    names[3] = "Ldc_I4_2"
    names[4] = "Ldc_I4_3"
    names[5] = "Ldc_I4_4"
    names[6] = "Ldc_I4_5"
    names[7] = "Ldc_I4_6"
    names[8] = "Ldc_I4_7"
    names[9] = "Ldc_I4_8"
    names[10] = "Ldc_I4"
    names[11] = "Stloc"
    names[12] = "Ldloc"
    names[13] = "Ldloca"
    names[14] = "Ldarg"
    names[15] = "Br"
    names[16] = "Brfalse"
    names[17] = "Call"
    names[18] = "Callvirt"
    names[19] = "Newobj"
    names[20] = "Conv_I4"
    names[21] = "Ldfld"
    names[22] = "Ldlen"
    names[23] = "Ldelem_U1"
    names[24] = "Ldelem_U2"
    names[25] = "Ldelem_I4"
    names[26] = "Ldelem_U4"
    names[27] = "Ldelem_I8"
    names[28] = "Ldelem_R4"
    names[29] = "Ldelem_R8"
    names[30] = "Ldelem_Ref"
    names[31] = "Ldelem"

    i := 0
    while i < names.Length {
        AssertSupportedOpcode(names[i])
        i = i + 1
    }

    assert !ColumnarExternalBindingPlans.GetStaticMemberPlan("OpCodes", "Unbox_Any").IsSupported
}

test "range code plans own exact runtime type identities" {
    AssertRuntimeType("Index", "System.Index")
    AssertRuntimeType("Range", "System.Range")
    AssertRuntimeType("ParameterInfo", "System.Reflection.ParameterInfo")

    runtimeHelpersTypeName := ""
    assert ColumnarExternalBindingPlans.TryGetRuntimeTypeName(
        "RuntimeHelpers",
        out runtimeHelpersTypeName)
    assert runtimeHelpersTypeName
        == "System.Runtime.CompilerServices.RuntimeHelpers, System.Private.CoreLib"
    assert !ColumnarExternalBindingPlans.IsSupportedRuntimeTypeName(
        "System.Runtime.CompilerServices.RuntimeHelpers")

    arrayTypeName := ""
    assert ColumnarExternalBindingPlans.TryGetRuntimeTypeName("System.Array", out arrayTypeName)
    assert arrayTypeName == "System.Array, System.Private.CoreLib"
    assert !ColumnarExternalBindingPlans.IsSupportedRuntimeTypeName("System.Array")
}

test "range code plans own exact reflection handle calls" {
    oneTypeArray := new string[](1)
    oneTypeArray[0] = "System.Type[]"
    AssertVirtualCall(
        "System.Type",
        "GetConstructor",
        oneTypeArray,
        "System.Reflection.ConstructorInfo")

    methodArguments := new string[](2)
    methodArguments[0] = "System.String"
    methodArguments[1] = "System.Type[]"
    AssertVirtualCall(
        "System.Type",
        "GetMethod",
        methodArguments,
        "System.Reflection.MethodInfo")

    oneString := new string[](1)
    oneString[0] = "System.String"
    AssertVirtualCall(
        "System.Type",
        "GetMethod",
        oneString,
        "System.Reflection.MethodInfo")

    AssertVirtualCall(
        "System.Type",
        "GetElementType",
        new string[](0),
        "System.Type")
    AssertVirtualCall(
        "System.Type",
        "MakeArrayType",
        new string[](0),
        "System.Type")
    AssertVirtualCall(
        "System.Reflection.PropertyInfo",
        "GetGetMethod",
        new string[](0),
        "System.Reflection.MethodInfo")
    AssertVirtualCall(
        "System.Reflection.MethodInfo",
        "MakeGenericMethod",
        oneTypeArray,
        "System.Reflection.MethodInfo")
}

test "recursive code plans own exact type and local facts" {
    noArguments := new string[](0)
    AssertVirtualCall("System.Type", "get_IsSZArray", noArguments, "System.Boolean")
    AssertVirtualCall("System.Type", "get_IsValueType", noArguments, "System.Boolean")
    AssertVirtualCall("System.Type", "get_IsEnum", noArguments, "System.Boolean")
    AssertVirtualCall("System.Type", "get_IsByRef", noArguments, "System.Boolean")
    AssertVirtualCall("System.Type", "get_IsGenericParameter", noArguments, "System.Boolean")
    AssertVirtualCall("System.Type", "GetEnumUnderlyingType", noArguments, "System.Type")

    oneType := new string[](1)
    oneType[0] = "System.Type"
    AssertVirtualCall("System.Type", "IsAssignableFrom", oneType, "System.Boolean")
    AssertVirtualCall(
        "System.Reflection.Emit.LocalBuilder",
        "get_LocalType",
        noArguments,
        "System.Type")
}

test "recursive executor owns exact reflection signature facts" {
    noArguments := new string[](0)
    AssertVirtualCall(
        "System.Reflection.MethodInfo",
        "GetParameters",
        noArguments,
        "System.Reflection.ParameterInfo[]")
    AssertVirtualCall(
        "System.Reflection.MethodInfo",
        "get_ReturnType",
        noArguments,
        "System.Type")
    AssertVirtualCall(
        "System.Reflection.MethodInfo",
        "get_IsStatic",
        noArguments,
        "System.Boolean")
    AssertVirtualCall(
        "System.Reflection.MethodInfo",
        "get_IsAbstract",
        noArguments,
        "System.Boolean")
    AssertVirtualCall(
        "System.Reflection.MethodInfo",
        "get_DeclaringType",
        noArguments,
        "System.Type")
    AssertVirtualCall(
        "System.Reflection.MethodInfo",
        "get_IsGenericMethodDefinition",
        noArguments,
        "System.Boolean")

    AssertVirtualCall(
        "System.Reflection.ConstructorInfo",
        "GetParameters",
        noArguments,
        "System.Reflection.ParameterInfo[]")
    AssertVirtualCall(
        "System.Reflection.ConstructorInfo",
        "get_IsStatic",
        noArguments,
        "System.Boolean")
    AssertVirtualCall(
        "System.Reflection.ConstructorInfo",
        "get_DeclaringType",
        noArguments,
        "System.Type")
    AssertVirtualCall(
        "System.Reflection.FieldInfo",
        "get_FieldType",
        noArguments,
        "System.Type")
    AssertVirtualCall(
        "System.Reflection.FieldInfo",
        "get_IsStatic",
        noArguments,
        "System.Boolean")
    AssertVirtualCall(
        "System.Reflection.FieldInfo",
        "get_DeclaringType",
        noArguments,
        "System.Type")
    AssertVirtualCall(
        "System.Reflection.ParameterInfo",
        "get_ParameterType",
        noArguments,
        "System.Type")
}

test "range code plans own the short IL argument operand" {
    arguments := new string[](2)
    arguments[0] = "System.Reflection.Emit.OpCode"
    arguments[1] = "System.Int16"

    AssertVirtualCall(
        "System.Reflection.Emit.ILGenerator",
        "Emit",
        arguments,
        "System.Void")
}
