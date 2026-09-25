namespace NSharpLang.SdkProjectReferenceBoundary.Tests

import System
import System.Reflection

test "the SDK config task has one N# production owner and its exact MSBuild surface" {
    owner := SdkTaskOwnerType("NSharpLang.Build.Tasks.LoadProjectConfig")
    assert owner.get_Assembly().GetName().get_Name() == "NSharpLang.Compiler.Driver"
    assert Type.GetType("NSharpLang.Build.Tasks.LoadProjectConfig, NSharpLang.Build.Tasks") == null
    legacyAssembly := SdkTaskLegacyAssembly()
    assert !Object.ReferenceEquals(owner.get_Assembly(), legacyAssembly)
    assert legacyAssembly.GetType("NSharpLang.Build.Tasks.LoadProjectConfig") == null
    assert owner.get_IsPublic()
    assert !owner.get_IsSealed()
    baseType := EmitTaskRequireType(owner.get_BaseType(), "LoadProjectConfig base")
    assert baseType.get_FullName() == "Microsoft.Build.Utilities.Task"

    constructors := owner.GetConstructors(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly)
    assert constructors.Length == 1
    assert constructors[0].GetParameters().Length == 0
    assert owner.GetConstructors(BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly).Length == 0

    properties := owner.GetProperties(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly)
    assert properties.Length == 18
    names := new string[](18)
    names[0] = "ProjectDirectory"
    names[1] = "TargetFramework"
    names[2] = "OutputType"
    names[3] = "AssemblyName"
    names[4] = "Version"
    names[5] = "AssemblyVersion"
    names[6] = "FileVersion"
    names[7] = "Sdk"
    names[8] = "TestFramework"
    names[9] = "PackageId"
    names[10] = "PackageAuthors"
    names[11] = "PackageDescription"
    names[12] = "PackageTags"
    names[13] = "PackageLicenseExpression"
    names[14] = "PackageProjectUrl"
    names[15] = "RepositoryUrl"
    names[16] = "PackageReadmeFile"
    names[17] = "PackageReadmeSource"
    index := 0
    while index < names.Length {
        property := EmitTaskRequiredProperty(owner, names[index])
        assert property.get_CanRead(), names[index]
        assert property.get_CanWrite(), names[index]
        assert property.get_PropertyType() == typeof(string), names[index]
        index = index + 1
    }

    requiredType := EmitTaskRequiredType("Microsoft.Build.Framework.RequiredAttribute, Microsoft.Build.Framework")
    outputType := EmitTaskRequiredType("Microsoft.Build.Framework.OutputAttribute, Microsoft.Build.Framework")
    propertyIndex := 0
    while propertyIndex < properties.Length {
        property := properties[propertyIndex]
        requiredCount := property.GetCustomAttributes(requiredType, false).Length
        outputCount := property.GetCustomAttributes(outputType, false).Length
        assert requiredCount == (property.get_Name() == "ProjectDirectory" ? 1 : 0), property.get_Name()
        assert outputCount == (property.get_Name() == "ProjectDirectory" ? 0 : 1), property.get_Name()
        propertyIndex = propertyIndex + 1
    }

    executeTypes := new Type[](0)
    execute := EmitTaskRequiredMethod(owner, "Execute", executeTypes, "LoadProjectConfig.Execute")
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

    task := EmitTaskNewInstance(owner)
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "ProjectDirectory")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "TargetFramework")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "OutputType")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "AssemblyName")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "Version")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "AssemblyVersion")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "FileVersion")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "Sdk")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "TestFramework")) == "xunit"
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "PackageId")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "PackageAuthors")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "PackageDescription")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "PackageTags")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "PackageLicenseExpression")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "PackageProjectUrl")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "RepositoryUrl")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "PackageReadmeFile")) == ""
    assert Convert.ToString(EmitTaskOptionalObjectProperty(task, "PackageReadmeSource")) == ""
}
