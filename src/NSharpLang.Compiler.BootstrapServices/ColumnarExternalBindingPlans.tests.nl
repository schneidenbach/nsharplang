namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

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
    names := new string[](93)
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
    names[36] = "Add"
    names[37] = "Neg"
    names[38] = "Not"
    names[39] = "Ceq"
    names[40] = "Ldsfld"
    names[41] = "Ldtoken"
    names[42] = "Ldarga"
    names[43] = "Ldind_Ref"
    names[44] = "Conv_I8"
    names[45] = "Conv_R4"
    names[46] = "Conv_R8"
    names[47] = "Box"
    names[48] = "Ldnull"
    names[49] = "Initobj"
    names[50] = "Ldflda"
    names[51] = "Dup"
    names[52] = "Newarr"
    names[53] = "Stelem_I1"
    names[54] = "Stelem_I2"
    names[55] = "Stelem_I4"
    names[56] = "Stelem_I8"
    names[57] = "Stelem_R4"
    names[58] = "Stelem_R8"
    names[59] = "Stelem_Ref"
    names[60] = "Stelem"
    names[61] = "Castclass"
    names[62] = "Sub"
    names[63] = "Mul"
    names[64] = "Div"
    names[65] = "Div_Un"
    names[66] = "Rem"
    names[67] = "Rem_Un"
    names[68] = "And"
    names[69] = "Or"
    names[70] = "Xor"
    names[71] = "Shl"
    names[72] = "Shr"
    names[73] = "Shr_Un"
    names[74] = "Add_Ovf"
    names[75] = "Add_Ovf_Un"
    names[76] = "Mul_Ovf"
    names[77] = "Mul_Ovf_Un"
    names[78] = "Sub_Ovf"
    names[79] = "Sub_Ovf_Un"
    names[80] = "Cgt"
    names[81] = "Cgt_Un"
    names[82] = "Clt"
    names[83] = "Clt_Un"
    names[84] = "Ldind_I1"
    names[85] = "Ldind_U1"
    names[86] = "Ldind_I2"
    names[87] = "Ldind_U2"
    names[88] = "Ldind_I4"
    names[89] = "Ldind_U4"
    names[90] = "Ldind_I8"
    names[91] = "Ldind_R4"
    names[92] = "Ldind_R8"

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

    methodAttributes := ColumnarExternalBindingPlans.GetStaticMemberPlan(
        "MethodAttributes", "Public")
    qualifiedMethodAttributes := ColumnarExternalBindingPlans.GetStaticMemberPlan(
        "System.Reflection.MethodAttributes", "Public")
    assert methodAttributes.IsSupported
    assert qualifiedMethodAttributes.IsSupported
    assert methodAttributes.DeclaringTypeName
        == qualifiedMethodAttributes.DeclaringTypeName
    assert methodAttributes.ValueTypeName
        == qualifiedMethodAttributes.ValueTypeName

    callingConvention := ColumnarExternalBindingPlans.GetStaticMemberPlan(
        "CallingConventions", "Standard")
    qualifiedCallingConvention := ColumnarExternalBindingPlans.GetStaticMemberPlan(
        "System.Reflection.CallingConventions", "Standard")
    assert callingConvention.IsSupported
    assert qualifiedCallingConvention.IsSupported
    assert callingConvention.DeclaringTypeName
        == qualifiedCallingConvention.DeclaringTypeName
    assert callingConvention.ValueTypeName
        == qualifiedCallingConvention.ValueTypeName

    assert !ColumnarExternalBindingPlans.GetStaticMemberPlan(
        "MethodAttributes", "Private").IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticMemberPlan(
        "CallingConventions", "VarArgs").IsSupported
}

test "range code plans own exact runtime type identities" {
    AssertRuntimeType("Index", "System.Index")
    AssertRuntimeType("Range", "System.Range")
    AssertRuntimeType("RuntimeTypeHandle", "System.RuntimeTypeHandle")
    AssertRuntimeType("ParameterInfo", "System.Reflection.ParameterInfo")
    AssertRuntimeType("MethodBase", "System.Reflection.MethodBase")
    AssertRuntimeType("MethodAttributes", "System.Reflection.MethodAttributes")
    AssertRuntimeType("CallingConventions", "System.Reflection.CallingConventions")
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

test "source constructor metadata owns exact TypeBuilder constructor definition" {
    arguments := new string[](3)
    arguments[0] = "System.Reflection.MethodAttributes"
    arguments[1] = "System.Reflection.CallingConventions"
    arguments[2] = "System.Type[]"
    AssertVirtualCall(
        "System.Reflection.Emit.TypeBuilder",
        "DefineConstructor",
        arguments,
        "System.Reflection.Emit.ConstructorBuilder")

    wrongConvention := new string[](3)
    wrongConvention[0] = "System.Reflection.MethodAttributes"
    wrongConvention[1] = "System.Int32"
    wrongConvention[2] = "System.Type[]"
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan(
        "System.Reflection.Emit.TypeBuilder",
        "DefineConstructor",
        wrongConvention).IsSupported
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan(
        "TypeBuilder", "DefineConstructor", arguments).IsSupported
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

test "static call plans own String.Join over string sequences with the enumerable overload" {
    listArguments := new string[](2)
    listArguments[0] = "System.String"
    listArguments[1] = typeof(List<string>).FullName
    enumerableIdentity := typeof(IEnumerable<string>).get_AssemblyQualifiedName()

    listPlan := ColumnarExternalBindingPlans.GetStaticCallPlan(
        "String", "Join", listArguments)
    assert listPlan.IsSupported
    assert listPlan.Kind == ColumnarExternalCallKind.Call
    assert listPlan.DeclaringTypeName == "System.String, System.Private.CoreLib"
    assert listPlan.MemberName == "Join"
    assert listPlan.ParameterTypeNames.Length == 2
    assert listPlan.ParameterTypeNames[0] == "System.String, System.Private.CoreLib"
    assert listPlan.ParameterTypeNames[1] == enumerableIdentity
    assert listPlan.ReturnTypeName == "System.String, System.Private.CoreLib"

    // The fully qualified owner spelling resolves the same overload.
    qualifiedArguments := new string[](2)
    qualifiedArguments[0] = "System.String"
    qualifiedArguments[1] = typeof(List<string>).FullName
    qualifiedPlan := ColumnarExternalBindingPlans.GetStaticCallPlan(
        "System.String", "Join", qualifiedArguments)
    assert qualifiedPlan.IsSupported
    assert qualifiedPlan.ParameterTypeNames[1] == enumerableIdentity

    // The lowercase `string` keyword is not a resolvable runtime static owner, so it is declined
    // and stays with the legacy string owner (a supported plan over it would become a terminal
    // ownership claim the owner resolver cannot satisfy).
    lowerArguments := new string[](2)
    lowerArguments[0] = "System.String"
    lowerArguments[1] = typeof(List<string>).FullName
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "string", "Join", lowerArguments).IsSupported

    // A direct IEnumerable<string> value flows to the identical overload.
    enumerableArguments := new string[](2)
    enumerableArguments[0] = "System.String"
    enumerableArguments[1] = typeof(IEnumerable<string>).FullName
    enumerablePlan := ColumnarExternalBindingPlans.GetStaticCallPlan(
        "String", "Join", enumerableArguments)
    assert enumerablePlan.IsSupported
    assert enumerablePlan.ParameterTypeNames[1] == enumerableIdentity

    // The resolved enumerable identity binds the exact CLR overload.
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(IEnumerable<string>)
    joinMethod := typeof(string).GetMethod("Join", parameterTypes)
    assert joinMethod != null
    assert joinMethod.get_ReturnType() == typeof(string)
}

test "String.Join plans close the generic overload for int sequences with pinned type arguments" {
    enumerableIntIdentity := typeof(IEnumerable<int>).get_AssemblyQualifiedName()

    // int[], List<int>, and IEnumerable<int> all bind the generic String.Join<T> closed at
    // T=Int32: int[] is not covariant to object[], so no non-generic overload can own them.
    intArrayArguments := new string[](2)
    intArrayArguments[0] = "System.String"
    intArrayArguments[1] = "System.Int32[]"
    arrayPlan := ColumnarExternalBindingPlans.GetStaticCallPlan(
        "String", "Join", intArrayArguments)
    assert arrayPlan.IsSupported, "String.Join over an int[] must plan the pinned generic closure."
    assert arrayPlan.Kind == ColumnarExternalCallKind.Call
    assert arrayPlan.TypeArgumentNames.Length == 1
    assert arrayPlan.TypeArgumentNames[0] == "System.Int32, System.Private.CoreLib"
    assert arrayPlan.ParameterTypeNames.Length == 2
    assert arrayPlan.ParameterTypeNames[0] == "System.String, System.Private.CoreLib"
    assert arrayPlan.ParameterTypeNames[1] == enumerableIntIdentity
    assert arrayPlan.ReturnTypeName == "System.String, System.Private.CoreLib"

    intListArguments := new string[](2)
    intListArguments[0] = "System.String"
    intListArguments[1] = typeof(List<int>).FullName
    listPlan := ColumnarExternalBindingPlans.GetStaticCallPlan(
        "String", "Join", intListArguments)
    assert listPlan.IsSupported, "String.Join over a List<int> must plan the pinned generic closure."
    assert listPlan.TypeArgumentNames.Length == 1
    assert listPlan.ParameterTypeNames[1] == enumerableIntIdentity

    intEnumerableArguments := new string[](2)
    intEnumerableArguments[0] = "System.String"
    intEnumerableArguments[1] = typeof(IEnumerable<int>).FullName
    enumerablePlan := ColumnarExternalBindingPlans.GetStaticCallPlan(
        "String", "Join", intEnumerableArguments)
    assert enumerablePlan.IsSupported, "String.Join over an IEnumerable<int> must plan the pinned generic closure."
    assert enumerablePlan.TypeArgumentNames.Length == 1
    assert enumerablePlan.ParameterTypeNames[1] == enumerableIntIdentity

    // The non-generic string rows stay exactly as before: no pinned type arguments.
    stringListArguments := new string[](2)
    stringListArguments[0] = "System.String"
    stringListArguments[1] = typeof(List<string>).FullName
    assert ColumnarExternalBindingPlans.GetStaticCallPlan(
        "String", "Join", stringListArguments).TypeArgumentNames.Length == 0
}

test "String.Join plans close the generic overload for supported primitive element sequences" {
    // Ownership transferred from the deleted C# generic emitter arm: every supported primitive value
    // element (not just Int32) closes String.Join<T> at the front door across array, List<T>,
    // IReadOnlyList<T>, and IEnumerable<T> forms.
    longArrayArguments := new string[](2)
    longArrayArguments[0] = "System.String"
    longArrayArguments[1] = "System.Int64[]"
    longPlan := ColumnarExternalBindingPlans.GetStaticCallPlan(
        "String", "Join", longArrayArguments)
    assert longPlan.IsSupported, "String.Join over a long[] must plan the generic closure."
    assert longPlan.Kind == ColumnarExternalCallKind.Call
    assert longPlan.TypeArgumentNames.Length == 1
    assert longPlan.TypeArgumentNames[0] == "System.Int64, System.Private.CoreLib"
    assert longPlan.ParameterTypeNames[0] == "System.String, System.Private.CoreLib"
    assert longPlan.ParameterTypeNames[1] == typeof(IEnumerable<long>).get_AssemblyQualifiedName()
    assert longPlan.ReturnTypeName == "System.String, System.Private.CoreLib"

    // A List<double> now binds String.Join<Double> (previously legacy-owned by the deleted C# arm).
    doubleListArguments := new string[](2)
    doubleListArguments[0] = "System.String"
    doubleListArguments[1] = typeof(List<double>).FullName
    doublePlan := ColumnarExternalBindingPlans.GetStaticCallPlan(
        "String", "Join", doubleListArguments)
    assert doublePlan.IsSupported, "String.Join over a List<double> must plan the generic closure."
    assert doublePlan.TypeArgumentNames[0] == "System.Double, System.Private.CoreLib"
    assert doublePlan.ParameterTypeNames[1] == typeof(IEnumerable<double>).get_AssemblyQualifiedName()

    // A read-only list of byte binds String.Join<Byte>.
    byteReadOnlyArguments := new string[](2)
    byteReadOnlyArguments[0] = "System.String"
    byteReadOnlyArguments[1] = typeof(IReadOnlyList<byte>).FullName
    bytePlan := ColumnarExternalBindingPlans.GetStaticCallPlan(
        "String", "Join", byteReadOnlyArguments)
    assert bytePlan.IsSupported, "String.Join over an IReadOnlyList<byte> must plan the generic closure."
    assert bytePlan.TypeArgumentNames[0] == "System.Byte, System.Private.CoreLib"
    assert bytePlan.ParameterTypeNames[1] == typeof(IEnumerable<byte>).get_AssemblyQualifiedName()

    // An IEnumerable<char> binds String.Join<Char>.
    charEnumerableArguments := new string[](2)
    charEnumerableArguments[0] = "System.String"
    charEnumerableArguments[1] = typeof(IEnumerable<char>).FullName
    charPlan := ColumnarExternalBindingPlans.GetStaticCallPlan(
        "String", "Join", charEnumerableArguments)
    assert charPlan.IsSupported, "String.Join over an IEnumerable<char> must plan the generic closure."
    assert charPlan.TypeArgumentNames[0] == "System.Char, System.Private.CoreLib"
    assert charPlan.ParameterTypeNames[1] == typeof(IEnumerable<char>).get_AssemblyQualifiedName()
}

test "String.Join plans decline outside the modeled sequence contracts" {
    // A string[] argument binds the params overload, not the enumerable one, so it is declined
    // and stays with its existing owner.
    stringArrayArguments := new string[](2)
    stringArrayArguments[0] = "System.String"
    stringArrayArguments[1] = "System.String[]"
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "String", "Join", stringArrayArguments).IsSupported

    // A List<decimal> is a value sequence, but decimal is outside the supported primitive Join
    // element set, so it is declined (only the modeled primitive elements close the generic).
    decimalListArguments := new string[](2)
    decimalListArguments[0] = "System.String"
    decimalListArguments[1] = typeof(List<decimal>).FullName
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "String", "Join", decimalListArguments).IsSupported

    // A non-string separator, wrong arity, and mis-spelled member all decline.
    charSeparatorArguments := new string[](2)
    charSeparatorArguments[0] = "System.Char"
    charSeparatorArguments[1] = typeof(List<string>).FullName
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "String", "Join", charSeparatorArguments).IsSupported

    oneArgument := new string[](1)
    oneArgument[0] = "System.String"
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "String", "Join", oneArgument).IsSupported

    listArguments := new string[](2)
    listArguments[0] = "System.String"
    listArguments[1] = typeof(List<string>).FullName
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "String", "join", listArguments).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan(
        "StringBuilder", "Join", listArguments).IsSupported
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
