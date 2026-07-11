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
    declaringIdentity := receiver + ", System.Private.CoreLib"
    if receiver == "System.Reflection.MetadataLoadContext" {
        declaringIdentity = receiver + ", System.Reflection.MetadataLoadContext"
    }
    assert plan.DeclaringTypeName == declaringIdentity
    assert plan.MemberName == member
    assert plan.ParameterTypeNames.Length == arguments.Length
    i := 0
    while i < arguments.Length {
        assert plan.ParameterTypeNames[i] == arguments[i] + ", System.Private.CoreLib"
        i = i + 1
    }
    assert plan.ReturnTypeName == expectedReturnType + ", System.Private.CoreLib"
}

func AssertStaticCall(
    typeName: string,
    member: string,
    selectionArguments: string[],
    expectedParameters: string[],
    expectedDeclaringType: string,
    expectedReturnType: string) {
    plan := ColumnarExternalBindingPlans.GetStaticCallPlan(typeName, member, selectionArguments)
    assert plan.IsSupported
    assert plan.Kind == ColumnarExternalCallKind.Call
    assert plan.DeclaringTypeName == expectedDeclaringType + ", System.Private.CoreLib"
    assert plan.MemberName == member
    assert plan.ParameterTypeNames.Length == expectedParameters.Length
    i := 0
    while i < expectedParameters.Length {
        assert plan.ParameterTypeNames[i] == expectedParameters[i] + ", System.Private.CoreLib"
        i = i + 1
    }
    assert plan.ReturnTypeName == expectedReturnType + ", System.Private.CoreLib"
}

test "recursive code plans own every required opcode field" {
    names := new string[](60)
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
    names[32] = "Ldc_I8"
    names[33] = "Ldc_R4"
    names[34] = "Ldc_R8"
    names[35] = "Ldstr"
    names[36] = "Neg"
    names[37] = "Not"
    names[38] = "Ceq"
    names[39] = "Ldsfld"
    names[40] = "Ldtoken"
    names[41] = "Ldarga"
    names[42] = "Ldind_Ref"
    names[43] = "Conv_I8"
    names[44] = "Conv_R4"
    names[45] = "Conv_R8"
    names[46] = "Box"
    names[47] = "Ldnull"
    names[48] = "Initobj"
    names[49] = "Ldflda"
    names[50] = "Dup"
    names[51] = "Newarr"
    names[52] = "Stelem_I1"
    names[53] = "Stelem_I2"
    names[54] = "Stelem_I4"
    names[55] = "Stelem_I8"
    names[56] = "Stelem_R4"
    names[57] = "Stelem_R8"
    names[58] = "Stelem_Ref"
    names[59] = "Stelem"

    i := 0
    while i < names.Length {
        AssertSupportedOpcode(names[i])
        i = i + 1
    }

    assert !ColumnarExternalBindingPlans.GetStaticMemberPlan("OpCodes", "Unbox_Any").IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticMemberPlan("OpCodes", "Ldsflda").IsSupported
}

test "external static selections accept short and fully qualified owner names" {
    qualifiedOpcode := ColumnarExternalBindingPlans.GetStaticMemberPlan(
        "System.Reflection.Emit.OpCodes", "Ldsfld")
    assert qualifiedOpcode.IsSupported
    assert qualifiedOpcode.Kind == ColumnarExternalStaticMemberKind.Field
    assert qualifiedOpcode.DeclaringTypeName
        == "System.Reflection.Emit.OpCodes, System.Private.CoreLib"

    shortProperty := ColumnarExternalBindingPlans.GetStaticMemberPlan(
        "Environment", "NewLine")
    qualifiedProperty := ColumnarExternalBindingPlans.GetStaticMemberPlan(
        "System.Environment", "NewLine")
    assert shortProperty.IsSupported
    assert qualifiedProperty.IsSupported
    assert shortProperty.DeclaringTypeName == qualifiedProperty.DeclaringTypeName
    assert shortProperty.ValueTypeName == qualifiedProperty.ValueTypeName

}

test "range code plans own exact runtime type identities" {
    AssertRuntimeType("Index", "System.Index")
    AssertRuntimeType("Range", "System.Range")
    AssertRuntimeType("RuntimeTypeHandle", "System.RuntimeTypeHandle")
    AssertRuntimeType("ParameterInfo", "System.Reflection.ParameterInfo")
    AssertRuntimeType("MethodBase", "System.Reflection.MethodBase")
    AssertRuntimeType("MethodAttributes", "System.Reflection.MethodAttributes")
    AssertRuntimeType("AssemblyName", "System.Reflection.AssemblyName")
    AssertRuntimeType("DynamicMethod", "System.Reflection.Emit.DynamicMethod")

    metadataLoadContext := ""
    assert ColumnarExternalBindingPlans.TryGetRuntimeTypeName(
        "MetadataLoadContext", out metadataLoadContext)
    assert metadataLoadContext
        == "System.Reflection.MetadataLoadContext, System.Reflection.MetadataLoadContext"
    pathResolver := ""
    assert ColumnarExternalBindingPlans.TryGetRuntimeTypeName(
        "PathAssemblyResolver", out pathResolver)
    assert pathResolver
        == "System.Reflection.PathAssemblyResolver, System.Reflection.MetadataLoadContext"
    assert ColumnarExternalBindingPlans.IsSupportedRuntimeTypeName(
        "System.Reflection.MetadataLoadContext")
    assert ColumnarExternalBindingPlans.IsSupportedRuntimeTypeName(
        "System.Reflection.PathAssemblyResolver")

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

test "scalar executor contracts own exact DynamicMethod reflection calls" {
    objectArray := new string[](1)
    objectArray[0] = "System.Object[]"
    AssertVirtualCall(
        "System.Reflection.ConstructorInfo",
        "Invoke",
        objectArray,
        "System.Object")

    noArguments := new string[](0)
    AssertVirtualCall(
        "System.Reflection.Emit.DynamicMethod",
        "GetILGenerator",
        noArguments,
        "System.Reflection.Emit.ILGenerator")

    invokeArguments := new string[](2)
    invokeArguments[0] = "System.Object"
    invokeArguments[1] = "System.Object[]"
    AssertVirtualCall(
        "System.Reflection.Emit.DynamicMethod",
        "Invoke",
        invokeArguments,
        "System.Object")
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
        "System.Reflection.PropertyInfo",
        "get_PropertyType",
        new string[](0),
        "System.Type")
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan(
        "PropertyInfo",
        "get_PropertyType",
        new string[](0)).IsSupported
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan(
        "System.Reflection.PropertyInfo",
        "PropertyType",
        new string[](0)).IsSupported
    oneObject := new string[](1)
    oneObject[0] = "System.Object"
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan(
        "System.Reflection.PropertyInfo",
        "get_PropertyType",
        oneObject).IsSupported
    AssertVirtualCall(
        "System.Reflection.MethodInfo",
        "MakeGenericMethod",
        oneTypeArray,
        "System.Reflection.MethodInfo")
}

test "source property metadata owns exact TypeBuilder method definition" {
    arguments := new string[](4)
    arguments[0] = "System.String"
    arguments[1] = "System.Reflection.MethodAttributes"
    arguments[2] = "System.Type"
    arguments[3] = "System.Type[]"
    AssertVirtualCall(
        "System.Reflection.Emit.TypeBuilder",
        "DefineMethod",
        arguments,
        "System.Reflection.Emit.MethodBuilder")

    wrongAttributes := new string[](4)
    wrongAttributes[0] = "System.String"
    wrongAttributes[1] = "System.Int32"
    wrongAttributes[2] = "System.Type"
    wrongAttributes[3] = "System.Type[]"
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan(
        "System.Reflection.Emit.TypeBuilder",
        "DefineMethod",
        wrongAttributes).IsSupported
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan(
        "TypeBuilder", "DefineMethod", arguments).IsSupported
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan(
        "System.Reflection.Emit.TypeBuilder",
        "defineMethod",
        arguments).IsSupported
}

test "recursive code plans own exact type and local facts" {
    noArguments := new string[](0)
    AssertVirtualCall("System.Type", "GetType", noArguments, "System.Type")
    AssertVirtualCall(
        "System.Type",
        "GetMethods",
        noArguments,
        "System.Reflection.MethodInfo[]")
    AssertVirtualCall(
        "System.Type",
        "GetConstructors",
        noArguments,
        "System.Reflection.ConstructorInfo[]")
    AssertVirtualCall("System.Type", "get_BaseType", noArguments, "System.Type")
    AssertVirtualCall("System.Type", "get_IsSZArray", noArguments, "System.Boolean")
    AssertVirtualCall("System.Type", "get_IsValueType", noArguments, "System.Boolean")
    AssertVirtualCall("System.Type", "get_IsEnum", noArguments, "System.Boolean")
    AssertVirtualCall("System.Type", "get_IsByRef", noArguments, "System.Boolean")
    AssertVirtualCall("System.Type", "get_IsGenericParameter", noArguments, "System.Boolean")
    AssertVirtualCall("System.Type", "GetEnumUnderlyingType", noArguments, "System.Type")
    AssertVirtualCall("System.Type", "GetGenericTypeDefinition", noArguments, "System.Type")
    AssertVirtualCall("System.Type", "GetGenericArguments", noArguments, "System.Type[]")
    AssertVirtualCall("System.Type", "get_IsGenericTypeDefinition", noArguments, "System.Boolean")
    AssertVirtualCall("System.Type", "get_IsGenericType", noArguments, "System.Boolean")
    AssertVirtualCall("System.Type", "get_HasElementType", noArguments, "System.Boolean")
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan(
        "System.Type", "HasElementType", noArguments).IsSupported
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan(
        "Type", "get_HasElementType", noArguments).IsSupported
    AssertVirtualCall("System.Type", "get_IsAbstract", noArguments, "System.Boolean")
    AssertVirtualCall("System.Type", "get_IsInterface", noArguments, "System.Boolean")
    AssertVirtualCall("System.Type", "get_IsByRefLike", noArguments, "System.Boolean")
    AssertVirtualCall("System.Type", "get_GenericParameterPosition", noArguments, "System.Int32")
    AssertVirtualCall(
        "System.Type",
        "get_DeclaringMethod",
        noArguments,
        "System.Reflection.MethodBase")

    oneType := new string[](1)
    oneType[0] = "System.Type"
    AssertVirtualCall("System.Type", "IsAssignableFrom", oneType, "System.Boolean")
    oneTypeArray := new string[](1)
    oneTypeArray[0] = "System.Type[]"
    AssertVirtualCall("System.Type", "MakeGenericType", oneTypeArray, "System.Type")
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
        "GetGenericArguments",
        noArguments,
        "System.Type[]")
    AssertVirtualCall(
        "System.Reflection.MethodInfo",
        "GetGenericMethodDefinition",
        noArguments,
        "System.Reflection.MethodInfo")
    AssertVirtualCall(
        "System.Reflection.MethodInfo",
        "get_ReturnType",
        noArguments,
        "System.Type")
    AssertVirtualCall(
        "System.Reflection.MethodInfo",
        "get_Name",
        noArguments,
        "System.String")
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
        "get_IsPublic",
        noArguments,
        "System.Boolean")
    AssertVirtualCall(
        "System.Reflection.MethodInfo",
        "get_DeclaringType",
        noArguments,
        "System.Type")
    AssertVirtualCall(
        "System.Reflection.MethodInfo",
        "get_IsGenericMethod",
        noArguments,
        "System.Boolean")
    AssertVirtualCall(
        "System.Reflection.MethodInfo",
        "get_IsGenericMethodDefinition",
        noArguments,
        "System.Boolean")
    AssertVirtualCall(
        "System.Reflection.MethodInfo",
        "get_CallingConvention",
        noArguments,
        "System.Reflection.CallingConventions")

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
        "System.Reflection.ConstructorInfo",
        "get_CallingConvention",
        noArguments,
        "System.Reflection.CallingConventions")
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
        "get_IsLiteral",
        noArguments,
        "System.Boolean")
    AssertVirtualCall(
        "System.Reflection.FieldInfo",
        "get_IsPublic",
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
    AssertVirtualCall(
        "System.Reflection.ParameterInfo",
        "get_IsOptional",
        noArguments,
        "System.Boolean")
    parameterAttributeArguments := new string[](2)
    parameterAttributeArguments[0] = "System.Type"
    parameterAttributeArguments[1] = "System.Boolean"
    AssertVirtualCall(
        "System.Reflection.ParameterInfo",
        "IsDefined",
        parameterAttributeArguments,
        "System.Boolean")
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

test "runtime call plans own exact constructed generic return identities" {
    plan := ColumnarExternalBindingPlans.GetInstanceCallPlan(
        "System.IO.StreamReader",
        "ReadToEndAsync",
        new string[](0))
    runtimeType := Type.GetType(
        "System.Threading.Tasks.Task`1[System.String], System.Private.CoreLib")

    assert runtimeType != null
    assert plan.IsSupported
    assert plan.Kind == ColumnarExternalCallKind.CallVirtual
    assert plan.ReturnTypeName == runtimeType.get_AssemblyQualifiedName()
}

test "static call plans own exact CLR overloads" {
    stringArgument := new string[](1)
    stringArgument[0] = "System.String"
    AssertStaticCall(
        "Assembly",
        "LoadFrom",
        stringArgument,
        stringArgument,
        "System.Reflection.Assembly",
        "System.Reflection.Assembly")
    AssertStaticCall(
        "Assembly",
        "Load",
        stringArgument,
        stringArgument,
        "System.Reflection.Assembly",
        "System.Reflection.Assembly")
    AssertStaticCall("Type", "GetType", stringArgument, stringArgument, "System.Type", "System.Type")

    assemblyNameArguments := new string[](2)
    assemblyNameArguments[0] = "System.Reflection.AssemblyName"
    assemblyNameArguments[1] = "System.Reflection.AssemblyName"
    AssertStaticCall(
        "AssemblyName",
        "GetAssemblyName",
        stringArgument,
        stringArgument,
        "System.Reflection.AssemblyName",
        "System.Reflection.AssemblyName")
    AssertStaticCall(
        "AssemblyName",
        "ReferenceMatchesDefinition",
        assemblyNameArguments,
        assemblyNameArguments,
        "System.Reflection.AssemblyName",
        "System.Boolean")
    AssertStaticCall("Int32", "Parse", stringArgument, stringArgument, "System.Int32", "System.Int32")
    AssertStaticCall("int", "Parse", stringArgument, stringArgument, "System.Int32", "System.Int32")

    intTryParseArguments := new string[](2)
    intTryParseArguments[0] = "System.String"
    intTryParseArguments[1] = "System.Int32&"
    AssertStaticCall(
        "Int32",
        "TryParse",
        intTryParseArguments,
        intTryParseArguments,
        "System.Int32",
        "System.Boolean")
    AssertStaticCall(
        "int",
        "TryParse",
        intTryParseArguments,
        intTryParseArguments,
        "System.Int32",
        "System.Boolean")

    doubleParseSelection := new string[](2)
    doubleParseSelection[0] = "System.String"
    doubleParseSelection[1] = "System.Globalization.CultureInfo"
    doubleParseParameters := new string[](2)
    doubleParseParameters[0] = "System.String"
    doubleParseParameters[1] = "System.IFormatProvider"
    AssertStaticCall(
        "Double",
        "Parse",
        doubleParseSelection,
        doubleParseParameters,
        "System.Double",
        "System.Double")

    doubleTryParseSelection := new string[](3)
    doubleTryParseSelection[0] = "System.String"
    doubleTryParseSelection[1] = "System.Globalization.CultureInfo"
    doubleTryParseSelection[2] = "System.Double&"
    doubleTryParseParameters := new string[](3)
    doubleTryParseParameters[0] = "System.String"
    doubleTryParseParameters[1] = "System.IFormatProvider"
    doubleTryParseParameters[2] = "System.Double&"
    AssertStaticCall(
        "Double",
        "TryParse",
        doubleTryParseSelection,
        doubleTryParseParameters,
        "System.Double",
        "System.Boolean")
}

test "static call plans own exact TypeBuilder member rebinding overloads" {
    fieldArguments := new string[](2)
    fieldArguments[0] = "System.Type"
    fieldArguments[1] = "System.Reflection.FieldInfo"
    AssertStaticCall(
        "TypeBuilder",
        "GetField",
        fieldArguments,
        fieldArguments,
        "System.Reflection.Emit.TypeBuilder",
        "System.Reflection.FieldInfo")
    AssertStaticCall(
        "System.Reflection.Emit.TypeBuilder",
        "GetField",
        fieldArguments,
        fieldArguments,
        "System.Reflection.Emit.TypeBuilder",
        "System.Reflection.FieldInfo")

    methodArguments := new string[](2)
    methodArguments[0] = "System.Type"
    methodArguments[1] = "System.Reflection.MethodInfo"
    AssertStaticCall(
        "TypeBuilder",
        "GetMethod",
        methodArguments,
        methodArguments,
        "System.Reflection.Emit.TypeBuilder",
        "System.Reflection.MethodInfo")
    AssertStaticCall(
        "System.Reflection.Emit.TypeBuilder",
        "GetMethod",
        methodArguments,
        methodArguments,
        "System.Reflection.Emit.TypeBuilder",
        "System.Reflection.MethodInfo")

    constructorArguments := new string[](2)
    constructorArguments[0] = "System.Type"
    constructorArguments[1] = "System.Reflection.ConstructorInfo"
    AssertStaticCall(
        "TypeBuilder",
        "GetConstructor",
        constructorArguments,
        constructorArguments,
        "System.Reflection.Emit.TypeBuilder",
        "System.Reflection.ConstructorInfo")
    AssertStaticCall(
        "System.Reflection.Emit.TypeBuilder",
        "GetConstructor",
        constructorArguments,
        constructorArguments,
        "System.Reflection.Emit.TypeBuilder",
        "System.Reflection.ConstructorInfo")
}

test "external binding scopes own exact assembly type discovery calls" {
    stringArgument := new string[](1)
    stringArgument[0] = "System.String"
    AssertVirtualCall(
        "System.Reflection.Assembly",
        "GetName",
        new string[](0),
        "System.Reflection.AssemblyName")
    AssertVirtualCall(
        "System.Reflection.Assembly",
        "GetType",
        stringArgument,
        "System.Type")
    AssertVirtualCall(
        "System.Reflection.Assembly",
        "GetExportedTypes",
        new string[](0),
        "System.Type[]")
    AssertVirtualCall(
        "System.Type",
        "get_AssemblyQualifiedName",
        new string[](0),
        "System.String")
    AssertVirtualCall(
        "System.Type",
        "get_Assembly",
        new string[](0),
        "System.Reflection.Assembly")
    AssertVirtualCall(
        "System.Reflection.Assembly",
        "get_Location",
        new string[](0),
        "System.String")
    AssertVirtualCall(
        "System.Reflection.AssemblyName",
        "get_FullName",
        new string[](0),
        "System.String")

    AssertVirtualCall(
        "System.Reflection.MetadataLoadContext",
        "LoadFromAssemblyPath",
        stringArgument,
        "System.Reflection.Assembly")
    AssertVirtualCall(
        "System.Reflection.MetadataLoadContext",
        "LoadFromAssemblyName",
        stringArgument,
        "System.Reflection.Assembly")
    AssertVirtualCall(
        "System.Reflection.MetadataLoadContext",
        "Dispose",
        new string[](0),
        "System.Void")
}

test "static call plans decline aliases signatures and arity outside the contract" {
    stringArgument := new string[](1)
    stringArgument[0] = "System.String"
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "System.Type", "GetType", stringArgument).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "Type", "getType", stringArgument).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "Type", "GetType", new string[](0)).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "AssemblyName", "GetAssemblyName", new string[](0)).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "Assembly", "Load", new string[](0)).IsSupported
    wrongAssemblyNames := new string[](2)
    wrongAssemblyNames[0] = "System.Reflection.AssemblyName"
    wrongAssemblyNames[1] = "System.Type"
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "AssemblyName",
        "ReferenceMatchesDefinition",
        wrongAssemblyNames).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan("System.Int32", "Parse", stringArgument).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan("double", "Parse", stringArgument).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan("System.Double", "Parse", stringArgument).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan("Int32", "parse", stringArgument).IsSupported

    wrongIntTryParseArguments := new string[](2)
    wrongIntTryParseArguments[0] = "System.String"
    wrongIntTryParseArguments[1] = "System.Int32"
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "Int32",
        "TryParse",
        wrongIntTryParseArguments).IsSupported

    wrongDoubleParseArguments := new string[](2)
    wrongDoubleParseArguments[0] = "System.String"
    wrongDoubleParseArguments[1] = "System.IFormatProvider"
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "Double",
        "Parse",
        wrongDoubleParseArguments).IsSupported

    wrongDoubleTryParseArguments := new string[](3)
    wrongDoubleTryParseArguments[0] = "System.String"
    wrongDoubleTryParseArguments[1] = "System.Globalization.CultureInfo"
    wrongDoubleTryParseArguments[2] = "System.Single&"
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "Double",
        "TryParse",
        wrongDoubleTryParseArguments).IsSupported
}

test "TypeBuilder member rebinding plans decline every near miss" {
    fieldArguments := new string[](2)
    fieldArguments[0] = "System.Type"
    fieldArguments[1] = "System.Reflection.FieldInfo"
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "typebuilder", "GetField", fieldArguments).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "TypeBuilder", "getField", fieldArguments).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "TypeBuilder", "GetField", new string[](1)).IsSupported

    builderFieldArguments := new string[](2)
    builderFieldArguments[0] = "System.Type"
    builderFieldArguments[1] = "System.Reflection.Emit.FieldBuilder"
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "TypeBuilder", "GetField", builderFieldArguments).IsSupported

    swappedFieldArguments := new string[](2)
    swappedFieldArguments[0] = "System.Reflection.FieldInfo"
    swappedFieldArguments[1] = "System.Type"
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "TypeBuilder", "GetField", swappedFieldArguments).IsSupported

    wrongMethodArguments := new string[](2)
    wrongMethodArguments[0] = "System.Type"
    wrongMethodArguments[1] = "System.Reflection.MethodBase"
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "TypeBuilder", "GetMethod", wrongMethodArguments).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "TypeBuilder", "GetConstructor", wrongMethodArguments).IsSupported
}
