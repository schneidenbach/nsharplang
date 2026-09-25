namespace NSharpLang.SdkProjectReferenceBoundary.Tests

import System
import System.Reflection

test "the SDK reference task has one N# production owner and its exact MSBuild surface" {
    owner := SdkTaskOwnerType("NSharpLang.Build.Tasks.LoadProjectReferences")
    assert owner.get_Assembly().GetName().get_Name() == "NSharpLang.Compiler.Driver"
    assert Type.GetType("NSharpLang.Build.Tasks.LoadProjectReferences, NSharpLang.Build.Tasks") == null
    legacyAssembly := SdkTaskLegacyAssembly()
    assert !Object.ReferenceEquals(owner.get_Assembly(), legacyAssembly)
    assert legacyAssembly.GetType("NSharpLang.Build.Tasks.LoadProjectReferences") == null
    assert owner.get_IsPublic()
    assert !owner.get_IsSealed()
    baseType := EmitTaskRequireType(owner.get_BaseType(), "LoadProjectReferences base")
    assert baseType.get_FullName() == "Microsoft.Build.Utilities.Task"

    constructors := owner.GetConstructors(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly)
    assert constructors.Length == 1
    assert constructors[0].GetParameters().Length == 0
    assert owner.GetConstructors(BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly).Length == 0

    properties := owner.GetProperties(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly)
    assert properties.Length == 5
    itemArrayType := EmitTaskRequiredType("Microsoft.Build.Framework.ITaskItem, Microsoft.Build.Framework").MakeArrayType()
    projectFile := EmitTaskRequiredProperty(owner, "ProjectFile")
    packageReferences := EmitTaskRequiredProperty(owner, "PackageReferences")
    frameworkReferences := EmitTaskRequiredProperty(owner, "FrameworkReferences")
    existingProjectReferences := EmitTaskRequiredProperty(owner, "ExistingProjectReferences")
    projectReferences := EmitTaskRequiredProperty(owner, "ProjectReferences")
    assert projectFile.get_PropertyType() == typeof(string)
    assert packageReferences.get_PropertyType() == itemArrayType
    assert frameworkReferences.get_PropertyType() == typeof(string[])
    assert existingProjectReferences.get_PropertyType() == typeof(string[])
    assert projectReferences.get_PropertyType() == typeof(string[])

    outputType := EmitTaskRequiredType("Microsoft.Build.Framework.OutputAttribute, Microsoft.Build.Framework")
    propertyIndex := 0
    while propertyIndex < properties.Length {
        property := properties[propertyIndex]
        outputCount := property.GetCustomAttributes(outputType, false).Length
        isOutput := property.get_Name() == "PackageReferences" || property.get_Name() == "FrameworkReferences" || property.get_Name() == "ProjectReferences"
        assert outputCount == (isOutput ? 1 : 0), property.get_Name()
        propertyIndex = propertyIndex + 1
    }

    executeTypes := new Type[](0)
    execute := EmitTaskRequiredMethod(owner, "Execute", executeTypes, "LoadProjectReferences.Execute")
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
    assert EmitTaskOptionalObjectProperty(task, "ProjectFile") == null
    packageValues := EmitTaskOptionalObjectProperty(task, "PackageReferences") as Array
    frameworkValues := EmitTaskOptionalObjectProperty(task, "FrameworkReferences") as Array
    existingValues := EmitTaskOptionalObjectProperty(task, "ExistingProjectReferences") as Array
    projectValues := EmitTaskOptionalObjectProperty(task, "ProjectReferences") as Array
    assert packageValues != null
    assert frameworkValues != null
    assert existingValues != null
    assert projectValues != null
    assert EmitTaskArrayLength(packageValues) == 0
    assert EmitTaskArrayLength(frameworkValues) == 0
    assert EmitTaskArrayLength(existingValues) == 0
    assert EmitTaskArrayLength(projectValues) == 0
}
