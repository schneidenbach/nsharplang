namespace NSharpLang.SdkProjectReferenceBoundary.Tests

import System
import System.Collections
import System.Reflection

test "the SDK emit task has one N# production owner and its exact MSBuild surface" {
    owner := EmitTaskOwnerType()
    assert owner.get_Assembly().GetName().get_Name() == "NSharpLang.Compiler.BootstrapServices"
    assert Type.GetType("NSharpLang.Build.Tasks.EmitIlAssembly, NSharpLang.Build.Tasks") == null
    legacyAssembly := EmitTaskLegacyAssembly()
    assert !Object.ReferenceEquals(owner.get_Assembly(), legacyAssembly)
    assert legacyAssembly.GetType("NSharpLang.Build.Tasks.EmitIlAssembly") == null
    assert owner.get_IsPublic()
    assert !owner.get_IsSealed()
    baseType := EmitTaskRequireType(owner.get_BaseType(), "EmitIlAssembly base")
    assert baseType.get_FullName() == "Microsoft.Build.Utilities.Task"

    constructors := owner.GetConstructors(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly)
    assert constructors.Length == 1
    assert constructors[0].GetParameters().Length == 0
    assert owner.GetConstructors(BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly).Length == 0

    properties := owner.GetProperties(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly)
    assert properties.Length == 10
    names := new string[](10)
    names[0] = "Sources"
    names[1] = "References"
    names[2] = "ProjectRoot"
    names[3] = "ProjectFile"
    names[4] = "TargetAssemblyPath"
    names[5] = "TargetReferenceAssemblyPath"
    names[6] = "AssemblyVersion"
    names[7] = "Configuration"
    names[8] = "DefineConstants"
    names[9] = "ValidateWithLegacyAnalysis"
    index := 0
    while index < names.Length {
        property := EmitTaskRequiredProperty(owner, names[index])
        assert property.get_CanRead(), names[index]
        assert property.get_CanWrite(), names[index]
        index = index + 1
    }

    itemArrayType := EmitTaskRequiredType("Microsoft.Build.Framework.ITaskItem, Microsoft.Build.Framework").MakeArrayType()
    assert EmitTaskRequiredProperty(owner, "Sources").get_PropertyType() == itemArrayType
    assert EmitTaskRequiredProperty(owner, "References").get_PropertyType() == itemArrayType
    assert EmitTaskRequiredProperty(owner, "ProjectRoot").get_PropertyType() == typeof(string)
    assert EmitTaskRequiredProperty(owner, "ProjectFile").get_PropertyType() == typeof(string)
    assert EmitTaskRequiredProperty(owner, "TargetAssemblyPath").get_PropertyType() == typeof(string)
    assert EmitTaskRequiredProperty(owner, "TargetReferenceAssemblyPath").get_PropertyType() == typeof(string)
    assert EmitTaskRequiredProperty(owner, "AssemblyVersion").get_PropertyType() == typeof(string)
    assert EmitTaskRequiredProperty(owner, "Configuration").get_PropertyType() == typeof(string)
    assert EmitTaskRequiredProperty(owner, "DefineConstants").get_PropertyType() == typeof(string)
    assert EmitTaskRequiredProperty(owner, "ValidateWithLegacyAnalysis").get_PropertyType() == typeof(bool)

    requiredType := EmitTaskRequiredType("Microsoft.Build.Framework.RequiredAttribute, Microsoft.Build.Framework")
    propertyIndex := 0
    while propertyIndex < properties.Length {
        property := properties[propertyIndex]
        requiredCount := property.GetCustomAttributes(requiredType, false).Length
        isRequired := property.get_Name() == "Sources" || property.get_Name() == "ProjectRoot" || property.get_Name() == "TargetAssemblyPath"
        if isRequired {
            assert requiredCount == 1, property.get_Name()
        } else {
            assert requiredCount == 0, property.get_Name()
        }
        propertyIndex = propertyIndex + 1
    }

    executeTypes := new Type[](0)
    execute := EmitTaskRequiredMethod(owner, "Execute", executeTypes, "EmitIlAssembly.Execute")
    assert execute.get_ReturnType() == typeof(bool)
    assert execute.get_IsVirtual()
    executeBaseOwner := EmitTaskRequireType(execute.GetBaseDefinition().get_DeclaringType(), "Execute base owner")
    assert executeBaseOwner.get_FullName() == "Microsoft.Build.Utilities.Task"
    declaredPublic := owner.GetMethods(BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.DeclaredOnly)
    publicOperationCount := 0
    publicIndex := 0
    while publicIndex < declaredPublic.Length {
        if !declaredPublic[publicIndex].get_IsSpecialName() {
            publicOperationCount = publicOperationCount + 1
        }
        publicIndex = publicIndex + 1
    }
    assert publicOperationCount == 1
    assert owner.GetFields(BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.DeclaredOnly).Length == 0

    privateFields := owner.GetFields(BindingFlags.Instance | BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.DeclaredOnly)
    fieldNames := new string[](10)
    fieldNames[0] = "sourcesValue"
    fieldNames[1] = "referencesValue"
    fieldNames[2] = "projectRootValue"
    fieldNames[3] = "projectFileValue"
    fieldNames[4] = "targetAssemblyPathValue"
    fieldNames[5] = "targetReferenceAssemblyPathValue"
    fieldNames[6] = "assemblyVersionValue"
    fieldNames[7] = "configurationValue"
    fieldNames[8] = "defineConstantsValue"
    fieldNames[9] = "validateWithLegacyAnalysisValue"
    assert privateFields.Length == fieldNames.Length
    fieldNameIndex := 0
    while fieldNameIndex < fieldNames.Length {
        matches := 0
        privateFieldIndex := 0
        while privateFieldIndex < privateFields.Length {
            if privateFields[privateFieldIndex].get_Name() == fieldNames[fieldNameIndex] {
                assert privateFields[privateFieldIndex].get_IsPrivate(), fieldNames[fieldNameIndex]
                matches = matches + 1
            }
            privateFieldIndex = privateFieldIndex + 1
        }
        assert matches == 1, fieldNames[fieldNameIndex]
        fieldNameIndex = fieldNameIndex + 1
    }

    task := EmitTaskNewTask()
    sources := EmitTaskOptionalObjectProperty(task, "Sources") as Array
    references := EmitTaskOptionalObjectProperty(task, "References") as Array
    assert sources != null
    assert references != null
    assert EmitTaskArrayLength(sources) == 0
    assert EmitTaskArrayLength(references) == 0
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "ProjectRoot")) == ""
    assert EmitTaskOptionalObjectProperty(task, "ProjectFile") == null
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "TargetAssemblyPath")) == ""
    assert EmitTaskOptionalObjectProperty(task, "TargetReferenceAssemblyPath") == null
    assert EmitTaskOptionalObjectProperty(task, "AssemblyVersion") == null
    assert EmitTaskOptionalObjectProperty(task, "Configuration") == null
    assert EmitTaskOptionalObjectProperty(task, "DefineConstants") == null
    assert Convert.ToBoolean(EmitTaskOptionalObjectProperty(task, "ValidateWithLegacyAnalysis"))
}

test "all reference mutation and Cecil mechanics stay private to the N# task" {
    owner := EmitTaskOwnerType()
    privateMethods := owner.GetMethods(BindingFlags.Instance | BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.DeclaredOnly)
    expected := new string[](16)
    expected[0] = "AddResolvedDllReferences"
    expected[1] = "IsOwnOutput"
    expected[2] = "SynchronizeReferenceAssembly"
    expected[3] = "BuildReferenceTypeOwners"
    expected[4] = "RecordDefinedTypes"
    expected[5] = "GetOrAddAssemblyReference"
    expected[6] = "RemoveUnusedCoreLibAssemblyReference"
    expected[7] = "ScopeName"
    expected[8] = "VersionText"
    expected[9] = "LogCompilerDiagnostics"
    expected[10] = "LogCompilerDiagnostic"
    expected[11] = "MaterializeTypeReferences"
    expected[12] = "ScanReferenceAssembly"
    expected[13] = "RecordReferenceAssembly"
    expected[14] = "RecordModuleDefinedTypes"
    expected[15] = "RecordModuleForwarders"
    expectedIndex := 0
    while expectedIndex < expected.Length {
        matches := 0
        methodIndex := 0
        while methodIndex < privateMethods.Length {
            if privateMethods[methodIndex].get_Name() == expected[expectedIndex] {
                matches = matches + 1
            }
            methodIndex = methodIndex + 1
        }
        assert matches == 1, expected[expectedIndex]
        expectedIndex = expectedIndex + 1
    }

    privateOperationCount := 0
    methodIndex := 0
    while methodIndex < privateMethods.Length {
        if !privateMethods[methodIndex].get_IsSpecialName() {
            assert privateMethods[methodIndex].get_IsPrivate(), privateMethods[methodIndex].get_Name()
            privateOperationCount = privateOperationCount + 1
        }
        methodIndex = methodIndex + 1
    }
    assert privateOperationCount == expected.Length
}
