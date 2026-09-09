namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import Microsoft.Build.Framework

class SmcRequiredEmissionProbe {
    private storedValue: string

    constructor() {
        storedValue = ""
    }

    [Microsoft.Build.Framework.Required]
    Value: string {
        get {
            return storedValue
        }
        set {
            storedValue = value
        }
    }

    [Microsoft.Build.Framework.RequiredAttribute()]
    static Version: int {
        get {
            return 7
        }
    }
}

func SmcRequiredProgram(source: string): ColumnarProgramInput {
    sources := new List<string>()
    sources.Add(source)
    fileNames := new List<string>()
    fileNames.Add("/tmp/NSharpRequiredAttributeFacts.nl")
    program: ColumnarProgramInput = null
    assert ColumnarProgramInputBuilder.TryBuildMultiFile(sources, fileNames, "/tmp", out program)
    return program
}

func SmcRequiredProperty(owner: Type, name: string): PropertyInfo {
    property := owner.GetProperty(name, BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance)
    if property == null {
        throw new InvalidOperationException("Required property metadata was not found: " + name)
    }
    return property
}

func SmcAssertSingleNoArgumentRequiredAttribute(property: PropertyInfo) {
    attributes := property.GetCustomAttributesData()
    assert NullabilityProbeSequenceCount(attributes) == 1
    attribute := attributes.get_Item(0)
    assert attribute.get_AttributeType() == typeof(Microsoft.Build.Framework.RequiredAttribute)
    constructor := attribute.get_Constructor()
    assert constructor.get_DeclaringType() == typeof(Microsoft.Build.Framework.RequiredAttribute)
    assert constructor.GetParameters().Length == 0
    constructorArguments := attribute.get_ConstructorArguments()
    namedArguments := attribute.get_NamedArguments()
    assert NullabilityProbeSequenceCount(constructorArguments) == 0
    assert NullabilityProbeSequenceCount(namedArguments) == 0
}

func SmcForeignType(fullName: string, assemblyName: string): Type {
    dynamicAssembly := AssemblyBuilder.DefineDynamicAssembly(
        new AssemblyName(assemblyName),
        AssemblyBuilderAccess.Run
    )
    dynamicModule := dynamicAssembly.DefineDynamicModule(assemblyName)
    builder := dynamicModule.DefineType(fullName, TypeAttributes.Public)
    created := builder.CreateType()
    if created == null {
        throw new InvalidOperationException("The foreign identity fixture did not bake.")
    }
    return created
}

func SmcForeignTaskLoggingHelper(): Type {
    assemblyName := "NSharpTests.ForeignTaskLoggingHelper"
    dynamicAssembly := AssemblyBuilder.DefineDynamicAssembly(
        new AssemblyName(assemblyName),
        AssemblyBuilderAccess.Run
    )
    dynamicModule := dynamicAssembly.DefineDynamicModule(assemblyName)
    builder := dynamicModule.DefineType(
        "Microsoft.Build.Utilities.TaskLoggingHelper",
        TypeAttributes.Public
    )
    parameters := new Type[](3)
    parameters[0] = typeof(Microsoft.Build.Framework.MessageImportance)
    parameters[1] = typeof(string)
    parameters[2] = typeof(object[])
    method := builder.DefineMethod(
        "LogMessage",
        MethodAttributes.Public,
        ColumnarTypeOfPlanner.RequiredVoidType(),
        parameters
    )
    method.GetILGenerator().Emit(OpCodes.Ret)
    created := builder.CreateType()
    if created == null {
        throw new InvalidOperationException("The foreign TaskLoggingHelper fixture did not bake.")
    }
    return created
}

func SmcRequiredRuntimeType(valueType: Type?, description: string): Type {
    if valueType == null {
        throw new InvalidOperationException(description + " was not found.")
    }
    return valueType
}

test "the Required property marker is exact fully qualified and payload free from parser through declaration rows" {
    source := "namespace RequiredParserFacts\n\nclass TaskShape {\n" + "    [Microsoft.Build.Framework.Required]\n" + "    Exact: string {\n        get {\n            return \"exact\"\n        }\n    }\n\n" + "    [Microsoft.Build.Framework.RequiredAttribute()]\n" + "    ExactSuffixed: string {\n        get {\n            return \"suffixed\"\n        }\n    }\n\n" + "    [Microsoft.Build.Framework.Required()]\n" + "    static ExactStatic: int {\n        get {\n            return 7\n        }\n    }\n\n" + "    [Required]\n" + "    Unqualified: string {\n        get {\n            return \"unqualified\"\n        }\n    }\n\n" + "    [Other.Required]\n" + "    Foreign: string {\n        get {\n            return \"foreign\"\n        }\n    }\n\n" + "    [Microsoft.Build.Framework.Required(\"payload\")]\n" + "    Payload: string {\n        get {\n            return \"payload\"\n        }\n    }\n" + "}\n"

    program := SmcRequiredProgram(source)
    assert program.Structs.Count == 1
    properties := program.Structs[0].Properties
    assert properties.Count == 6
    assert properties[0].Name == "Exact"
    assert properties[0].HasMsBuildRequiredAttribute
    assert properties[1].Name == "ExactSuffixed"
    assert properties[1].HasMsBuildRequiredAttribute
    assert properties[2].Name == "ExactStatic"
    assert properties[2].IsStatic
    assert properties[2].HasMsBuildRequiredAttribute
    assert properties[3].Name == "Unqualified"
    assert !properties[3].HasMsBuildRequiredAttribute
    assert properties[4].Name == "Foreign"
    assert !properties[4].HasMsBuildRequiredAttribute
    assert properties[5].Name == "Payload"
    assert !properties[5].HasMsBuildRequiredAttribute

    rows := ColumnarDeclarationPlanner.BuildProperties(program)
    assert rows.HasMsBuildRequiredAttribute.Length == 1
    assert rows.HasMsBuildRequiredAttribute[0].Length == 6
    assert rows.HasMsBuildRequiredAttribute[0][0]
    assert rows.HasMsBuildRequiredAttribute[0][1]
    assert rows.HasMsBuildRequiredAttribute[0][2]
    assert !rows.HasMsBuildRequiredAttribute[0][3]
    assert !rows.HasMsBuildRequiredAttribute[0][4]
    assert !rows.HasMsBuildRequiredAttribute[0][5]
    assert rows.AccessorWords[0][0] == ColumnarDeclarationPlanner.InstanceAccessorAttributes()
    assert rows.AccessorWords[0][2] == ColumnarDeclarationPlanner.StaticAccessorAttributes()
}

test "Required property emission attaches the exact no argument MSBuild attribute to instance and static metadata" {
    instanceProperty := SmcRequiredProperty(typeof(SmcRequiredEmissionProbe), "Value")
    staticProperty := SmcRequiredProperty(typeof(SmcRequiredEmissionProbe), "Version")
    SmcAssertSingleNoArgumentRequiredAttribute(instanceProperty)
    SmcAssertSingleNoArgumentRequiredAttribute(staticProperty)
    instanceGetter := instanceProperty.get_GetMethod()
    if instanceGetter == null {
        throw new InvalidOperationException("The instance Required property has no getter.")
    }
    instanceSetter := instanceProperty.get_SetMethod()
    if instanceSetter == null {
        throw new InvalidOperationException("The instance Required property has no setter.")
    }
    assert !instanceGetter.get_IsStatic()
    staticGetter := staticProperty.get_GetMethod()
    if staticGetter == null {
        throw new InvalidOperationException("The static Required property has no getter.")
    }
    assert staticProperty.get_SetMethod() == null
    assert staticGetter.get_IsStatic()
}

test "external instance call selection rejects same named foreign receivers while static and byref contracts remain exact" {
    messageTypes := new string[](3)
    messageTypes[0] = "Microsoft.Build.Framework.MessageImportance"
    messageTypes[1] = "System.String"
    messageTypes[2] = "System.Object[]"
    instancePlan := ColumnarExternalBindingPlans.GetInstanceCallPlan(
        "Microsoft.Build.Utilities.TaskLoggingHelper",
        "LogMessage",
        messageTypes
    )
    assert instancePlan.IsSupported

    exactSelection := ColumnarRuntimeDirectCallSelection.Empty()
    assert ColumnarRuntimeDirectCallResolver.TrySelect(
        instancePlan,
        typeof(Microsoft.Build.Utilities.TaskLoggingHelper),
        false,
        out exactSelection
    )
    assert exactSelection.Method != null
    assert exactSelection.Method.get_DeclaringType() == typeof(Microsoft.Build.Utilities.TaskLoggingHelper)
    assert !exactSelection.Method.get_IsStatic()

    foreignLogger := SmcForeignTaskLoggingHelper()
    foreignSignature := new Type[](3)
    foreignSignature[0] = typeof(Microsoft.Build.Framework.MessageImportance)
    foreignSignature[1] = typeof(string)
    foreignSignature[2] = typeof(object[])
    foreignMethod := foreignLogger.GetMethod("LogMessage", foreignSignature)
    if foreignMethod == null {
        throw new InvalidOperationException("The foreign TaskLoggingHelper fixture lost its exact LogMessage signature.")
    }
    assert !foreignMethod.get_IsStatic()
    rejectedSelection := ColumnarRuntimeDirectCallSelection.Empty()
    assert !ColumnarRuntimeDirectCallResolver.TrySelect(instancePlan, foreignLogger, false, out rejectedSelection)
    assert rejectedSelection.Method == null

    staticTypeArguments := new string[](1)
    staticTypeArguments[0] = "System.Object"
    staticPlan := ColumnarExternalBindingPlans.GetExplicitGenericStaticCallPlan(
        "System.Array",
        "Empty",
        staticTypeArguments,
        new string[](0)
    )
    staticSelection := ColumnarRuntimeDirectCallSelection.Empty()
    assert ColumnarRuntimeDirectCallResolver.TrySelect(staticPlan, typeof(Array), true, out staticSelection)
    assert staticSelection.Method != null
    assert staticSelection.Method.get_IsStatic()
    assert staticSelection.ReturnType == typeof(object[])

    byRefNames := new string[](2)
    byRefNames[0] = "System.Reflection.Metadata.BlobBuilder&"
    byRefNames[1] = "System.Reflection.Metadata.BlobBuilder&"
    byRefPlan := ColumnarExternalBindingPlans.GetInstanceCallPlan(
        "System.Reflection.Emit.PersistedAssemblyBuilder",
        "GenerateMetadata",
        byRefNames
    )
    assert byRefPlan.IsSupported
    persistedType := SmcRequiredRuntimeType(
        Type.GetType("System.Reflection.Emit.PersistedAssemblyBuilder, System.Reflection.Emit"),
        "System.Reflection.Emit.PersistedAssemblyBuilder"
    )
    blobType := SmcRequiredRuntimeType(
        Type.GetType("System.Reflection.Metadata.BlobBuilder, System.Reflection.Metadata"),
        "System.Reflection.Metadata.BlobBuilder"
    )
    assert ExternalAssemblyScan.HasExactTypeIdentity(persistedType, byRefPlan.DeclaringTypeName)
    foreignPersisted := SmcForeignType(
        "System.Reflection.Emit.PersistedAssemblyBuilder",
        "NSharpTests.ForeignPersistedAssemblyBuilder"
    )
    assert !ExternalAssemblyScan.HasExactTypeIdentity(foreignPersisted, byRefPlan.DeclaringTypeName)
    byRefType := blobType.MakeByRefType()
    byRefSignature := new Type[](2)
    byRefSignature[0] = byRefType
    byRefSignature[1] = byRefType
    byRefMethod := persistedType.GetMethod("GenerateMetadata", byRefSignature)
    if byRefMethod == null {
        throw new InvalidOperationException("PersistedAssemblyBuilder.GenerateMetadata(BlobBuilder&, BlobBuilder&) was not found.")
    }
    assert !byRefMethod.get_IsStatic()
    byRefParameters := byRefMethod.GetParameters()
    assert byRefParameters.Length == 2
    assert byRefParameters[0].get_IsOut()
    assert byRefParameters[1].get_IsOut()
}
