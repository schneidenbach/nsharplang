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

test "the real Cecil scan keeps definitions over earlier forwarders and records nested owners while skipping malformed rows" {
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

        task := EmitTaskNewTask()
        EmitTaskSetObjectProperty(task, "TargetAssemblyPath", ownOutputPath)
        EmitTaskSetObjectProperty(task, "TargetReferenceAssemblyPath", Path.Combine(scratch, "refint.dll"))
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
        EmitTaskSetReferences(task, paths)

        arguments := new object?[](1)
        EmitTaskPut(arguments, 0, null)
        owners := EmitTaskInvokePrivate(task, "BuildReferenceTypeOwners", 1, arguments)
        if owners == null || arguments[0] == null {
            throw new InvalidOperationException("BuildReferenceTypeOwners returned incomplete state.")
        }
        definitionOwner := EmitTaskReferenceOwnersResolve(owners, "System.String")
        nestedOwner := EmitTaskReferenceOwnersResolve(owners, "System.Collections.Generic.List`1/Enumerator")
        exactDefinitionOwner := EmitTaskRequiredString(definitionOwner, "System.String definition owner")
        exactNestedOwner := EmitTaskRequiredString(nestedOwner, "List Enumerator nested owner")
        assert exactDefinitionOwner.StartsWith("DefinitionOwner, Version=2.0.0.0"), exactDefinitionOwner
        assert exactNestedOwner.StartsWith("CollectionOwner, Version=3.0.0.0"), exactNestedOwner
        assert EmitTaskReferenceOwnersResolve(owners, "System.Never.Exists") == null

        ownerNames := EmitTaskRequiredObject(arguments[0], "owner-name map")
        assert EmitTaskCollectionCount(ownerNames) == 3
        definitionIdentity := EmitTaskDictionaryValue(ownerNames, exactDefinitionOwner)
        if definitionIdentity == null {
            throw new InvalidOperationException("Definition owner identity was not retained.")
        }
        assert Convert.ToString(EmitTaskObjectProperty(definitionIdentity, "Culture")) == "fr-FR", Convert.ToString(EmitTaskObjectProperty(definitionIdentity, "Culture"))
        assert EmitTaskObjectByteArraysEqual(EmitTaskObjectProperty(definitionIdentity, "PublicKeyToken"), actualDefinitionToken), exactDefinitionOwner

        forwarderOnly := EmitTaskNewTask()
        EmitTaskSetObjectProperty(forwarderOnly, "TargetAssemblyPath", definitionPath)
        EmitTaskSetObjectProperty(forwarderOnly, "TargetReferenceAssemblyPath", Path.Combine(scratch, "other-refint.dll"))
        forwarderPaths := new string[](4)
        forwarderPaths[0] = " "
        forwarderPaths[1] = forwarderPath
        forwarderPaths[2] = definitionPath
        forwarderPaths[3] = forwarderPath
        EmitTaskSetReferences(forwarderOnly, forwarderPaths)
        forwarderArguments := new object?[](1)
        EmitTaskPut(forwarderArguments, 0, null)
        forwarderOwners := EmitTaskInvokePrivate(forwarderOnly, "BuildReferenceTypeOwners", 1, forwarderArguments)
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
