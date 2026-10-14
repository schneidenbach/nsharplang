namespace NSharpLang.SdkProjectReferenceBoundary.Tests

import System
import System.IO

test "resolved DLL references retain input order while whitespace duplicates and both task outputs are excluded" {
    scratch := EmitTaskScratch("references")
    try {
        target := Path.Combine(scratch, "implementation.dll")
        referenceTarget := Path.Combine(scratch, "reference.dll")
        alreadyPresent := Path.Combine(scratch, "already.dll")
        firstNovel := Path.Combine(scratch, "first.dll")
        secondNovel := Path.Combine(scratch, "second.dll")

        config := EmitTaskCreateConfig()
        EmitTaskAddDllDependency(config, alreadyPresent)
        task := EmitTaskNewTask()
        EmitTaskSetObjectProperty(task, "TargetAssemblyPath", target)
        EmitTaskSetObjectProperty(task, "TargetReferenceAssemblyPath", referenceTarget)
        paths := new string[](9)
        paths[0] = "   "
        paths[1] = target.ToUpperInvariant()
        paths[2] = referenceTarget.ToUpperInvariant()
        paths[3] = firstNovel
        paths[4] = alreadyPresent
        paths[5] = firstNovel
        paths[6] = secondNovel
        paths[7] = ""
        paths[8] = secondNovel
        EmitTaskSetReferences(task, paths)

        arguments := new object?[](1)
        EmitTaskPut(arguments, 0, config)
        ignored := EmitTaskInvokePrivate(task, "AddResolvedDllReferences", 1, arguments)
        _ = ignored

        dependencies := EmitTaskConfigDependencies(config)
        assert EmitTaskCollectionCount(dependencies) == 3
        assert EmitTaskDllDependency(config, 0) == alreadyPresent
        assert EmitTaskDllDependency(config, 1) == Path.GetFullPath(firstNovel)
        assert EmitTaskDllDependency(config, 2) == Path.GetFullPath(secondNovel)
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "the writer Cecil scan keeps definitions over earlier forwarders and records nested owners while skipping malformed rows" {
    scratch := EmitTaskScratch("owner-scan")
    try {
        referencePack := EmitTaskReferencePackDirectory()
        forwarderPath := Path.Combine(scratch, "Forwarder.dll")
        definitionPath := Path.Combine(scratch, "Definition.dll")
        collectionPath := Path.Combine(scratch, "Collection.dll")
        forwarderCaseVariantPath := Path.Combine(scratch, "forwarder.dll")
        malformedPath := Path.Combine(scratch, "Malformed.dll")
        ownOutputPath := Path.Combine(scratch, "OwnOutput.dll")
        forwarderToken := EmitTaskByteArray([1, 2, 3, 4, 5, 6, 7, 8])
        definitionToken := EmitTaskByteArray([8, 7, 6, 5, 4, 3, 2, 1])
        collectionToken := EmitTaskByteArray([9, 10, 11, 12, 13, 14, 15, 16])
        EmitTaskCloneAssembly(
            Path.Combine(referencePack, "netstandard.dll"),
            forwarderPath,
            "ForwarderOwner",
            new Version(1, 0, 0, 0),
            "en-US",
            forwarderToken
        )
        EmitTaskCloneAssembly(
            Path.Combine(referencePack, "System.Runtime.dll"),
            definitionPath,
            "DefinitionOwner",
            new Version(2, 0, 0, 0),
            "fr-FR",
            definitionToken
        )
        EmitTaskCloneAssembly(
            Path.Combine(referencePack, "System.Collections.dll"),
            collectionPath,
            "CollectionOwner",
            new Version(3, 0, 0, 0),
            "de-DE",
            collectionToken
        )
        if !File.Exists(forwarderCaseVariantPath) {
            EmitTaskCloneAssembly(
                Path.Combine(referencePack, "netstandard.dll"),
                forwarderCaseVariantPath,
                "IgnoredCaseDuplicateOwner",
                new Version(9, 0, 0, 0),
                "it-IT",
                null
            )
        }
        actualDefinitionToken := EmitTaskAssemblyIdentityProperty(definitionPath, "PublicKeyToken")
        File.WriteAllText(malformedPath, "this is deliberately not an assembly")
        File.Copy(definitionPath, ownOutputPath)

        paths := new string[](9)
        paths[0] = "   "
        paths[1] = malformedPath
        paths[2] = Path.GetRelativePath(Environment.CurrentDirectory, forwarderPath)
        paths[3] = definitionPath
        paths[4] = collectionPath
        paths[5] = definitionPath
        paths[6] = Path.Combine(scratch, "missing.dll")
        paths[7] = ownOutputPath
        paths[8] = forwarderCaseVariantPath

        arguments := new object?[](4)
        EmitTaskPut(arguments, 0, EmitTaskStringList(paths))
        EmitTaskPut(arguments, 1, ownOutputPath)
        EmitTaskPut(arguments, 2, Path.Combine(scratch, "refint.dll"))
        EmitTaskPut(arguments, 3, null)
        owners := EmitTaskInvokeWriter("BuildReferenceTypeOwners", 4, arguments)
        if owners == null || arguments[3] == null {
            throw new InvalidOperationException("BuildReferenceTypeOwners returned incomplete state.")
        }
        definitionOwner := EmitTaskReferenceOwnersResolve(owners, "System.String")
        nestedOwner := EmitTaskReferenceOwnersResolve(owners, "System.Collections.Generic.List`1/Enumerator")
        exactDefinitionOwner := EmitTaskRequiredString(definitionOwner, "System.String definition owner")
        exactNestedOwner := EmitTaskRequiredString(nestedOwner, "List Enumerator nested owner")
        assert exactDefinitionOwner.StartsWith("DefinitionOwner, Version=2.0.0.0"), exactDefinitionOwner
        assert exactNestedOwner.StartsWith("CollectionOwner, Version=3.0.0.0"), exactNestedOwner
        assert EmitTaskReferenceOwnersResolve(owners, "System.Never.Exists") == null

        ownerNames := EmitTaskRequiredObject(arguments[3], "owner-name map")
        assert EmitTaskCollectionCount(ownerNames) == 3
        definitionIdentity := EmitTaskDictionaryValue(ownerNames, exactDefinitionOwner)
        if definitionIdentity == null {
            throw new InvalidOperationException("Definition owner identity was not retained.")
        }
        assert Convert.ToString(EmitTaskObjectProperty(definitionIdentity, "Culture")) == "fr-FR", Convert.ToString(EmitTaskObjectProperty(definitionIdentity, "Culture"))
        assert EmitTaskObjectByteArraysEqual(EmitTaskObjectProperty(definitionIdentity, "PublicKeyToken"), actualDefinitionToken), exactDefinitionOwner

        forwarderPaths := new string[](4)
        forwarderPaths[0] = " "
        forwarderPaths[1] = forwarderPath
        forwarderPaths[2] = definitionPath
        forwarderPaths[3] = forwarderPath
        forwarderArguments := new object?[](4)
        EmitTaskPut(forwarderArguments, 0, EmitTaskStringList(forwarderPaths))
        EmitTaskPut(forwarderArguments, 1, definitionPath)
        EmitTaskPut(forwarderArguments, 2, Path.Combine(scratch, "other-refint.dll"))
        EmitTaskPut(forwarderArguments, 3, null)
        forwarderOwners := EmitTaskInvokeWriter("BuildReferenceTypeOwners", 4, forwarderArguments)
        if forwarderOwners == null {
            throw new InvalidOperationException("Forwarder-only scan returned null.")
        }
        forwarderOwner := EmitTaskReferenceOwnersResolve(forwarderOwners, "System.String")
        exactForwarderOwner := EmitTaskRequiredString(forwarderOwner, "System.String forwarder owner")
        assert exactForwarderOwner.StartsWith("ForwarderOwner, Version=1.0.0.0"), exactForwarderOwner
    } finally {
        Directory.Delete(scratch, true)
    }
}

// A PROJECT LEAVES ONLY WITH ITS OUTPUT. The task drops a `project:` entry when MSBuild handed it that
// project's output (`ReferenceSourceTarget=ProjectReference`, `MSBuildSourceProjectFile`), and only
// for an output the configuration now holds as a `dll:` entry: one it just added, or one an equal
// `dll:` entry already held. An item that is the task's own output never replaces anything.
func EmitTaskWriteNSharpProject(root: string, name: string): string {
    directory := Path.Combine(root, name)
    Directory.CreateDirectory(directory)
    File.WriteAllText(Path.Combine(directory, "project.yml"), "name: " + name + "\ntargetFramework: net10.0\n")
    projectFile := Path.Combine(directory, name + ".csproj")
    File.WriteAllText(projectFile, "<Project Sdk=\"NSharpLang.Sdk\" />\n")
    return projectFile
}

func EmitTaskAddProjectDependency(config: object, path: string) {
    reference := EmitTaskNewInstance(EmitTaskModelAssemblyType("NSharpLang.Compiler.Reference"))
    EmitTaskSetObjectField(reference, "Project", path)
    EmitTaskCollectionAdd(EmitTaskConfigDependencies(config), reference)
}

func EmitTaskDependencyField(config: object, index: int, field: string): string {
    reference := EmitTaskCollectionItem(EmitTaskConfigDependencies(config), index)
    return Convert.ToString(EmitTaskObjectField(reference, field)) ?? ""
}

func EmitTaskProjectReferenceItem(itemSpec: string, sourceProjectFile: string): object {
    item := EmitTaskNewTaskItem(itemSpec)
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(string)
    setMetadata := EmitTaskRequiredMethod(item.GetType(), "SetMetadata", parameterTypes, "TaskItem.SetMetadata(string, string)")
    arguments := new object?[](2)
    EmitTaskPut(arguments, 0, "ReferenceSourceTarget")
    EmitTaskPut(arguments, 1, "ProjectReference")
    ignoredTarget := EmitTaskInvoke(item, setMetadata, arguments)
    _ = ignoredTarget
    EmitTaskPut(arguments, 0, "MSBuildSourceProjectFile")
    EmitTaskPut(arguments, 1, sourceProjectFile)
    ignoredSource := EmitTaskInvoke(item, setMetadata, arguments)
    _ = ignoredSource
    return item
}

test "a project entry leaves the configuration only with an output the task holds as a dll reference" {
    scratch := EmitTaskScratch("project-references")
    try {
        appProject := EmitTaskWriteNSharpProject(scratch, "App")
        keptProject := EmitTaskWriteNSharpProject(scratch, "Kept")
        presentProject := EmitTaskWriteNSharpProject(scratch, "Present")
        ownProject := EmitTaskWriteNSharpProject(scratch, "Own")
        target := Path.Combine(scratch, "App.dll")
        keptOutput := Path.Combine(scratch, "Kept.dll")
        presentOutput := Path.Combine(scratch, "Present.dll")

        config := EmitTaskCreateConfig()
        EmitTaskAddProjectDependency(config, "../Kept/project.yml")
        EmitTaskAddProjectDependency(config, "../Present/project.yml")
        EmitTaskAddProjectDependency(config, "../Own/project.yml")
        EmitTaskAddDllDependency(config, Path.GetFullPath(presentOutput))

        task := EmitTaskNewTask()
        EmitTaskSetObjectProperty(task, "TargetAssemblyPath", target)
        EmitTaskSetObjectProperty(task, "ProjectFile", Path.Combine(Path.GetDirectoryName(appProject) ?? scratch, "project.yml"))
        itemType := EmitTaskRequiredType("Microsoft.Build.Framework.ITaskItem, Microsoft.Build.Framework")
        items := Array.CreateInstance(itemType, 3)
        EmitTaskArraySet(items, 0, EmitTaskProjectReferenceItem(keptOutput, keptProject))
        EmitTaskArraySet(items, 1, EmitTaskProjectReferenceItem(presentOutput, presentProject))
        EmitTaskArraySet(items, 2, EmitTaskProjectReferenceItem(target, ownProject))
        EmitTaskSetObjectProperty(task, "References", items)

        arguments := new object?[](1)
        EmitTaskPut(arguments, 0, config)
        ignored := EmitTaskInvokePrivate(task, "AddResolvedDllReferences", 1, arguments)
        _ = ignored

        // `Kept` and `Present` left; `Own` stayed, because its item was the task's own output.
        assert EmitTaskCollectionCount(EmitTaskConfigDependencies(config)) == 3
        assert EmitTaskDependencyField(config, 0, "Project") == "../Own/project.yml"
        assert EmitTaskDependencyField(config, 1, "Dll") == Path.GetFullPath(presentOutput)
        assert EmitTaskDependencyField(config, 2, "Dll") == Path.GetFullPath(keptOutput)
    } finally {
        Directory.Delete(scratch, true)
    }
}
