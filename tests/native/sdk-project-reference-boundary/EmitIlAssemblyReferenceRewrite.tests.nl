namespace NSharpLang.SdkProjectReferenceBoundary.Tests

import System
import System.IO

test "assembly identity lookup reuses the first exact row and copies culture and token only for a new row" {
    module := EmitTaskNewCecilModule("identity-fixture")
    try {
        references := EmitTaskAssemblyReferences(module)
        firstToken := EmitTaskByteArray([1, 1, 1, 1, 1, 1, 1, 1])
        secondToken := EmitTaskByteArray([2, 2, 2, 2, 2, 2, 2, 2])
        ownerToken := EmitTaskByteArray([9, 8, 7, 6, 5, 4, 3, 2])
        first := EmitTaskNewAssemblyNameReference("Shared.Identity", new Version(4, 5, 6, 7), "en-US", firstToken)
        second := EmitTaskNewAssemblyNameReference("Shared.Identity", new Version(4, 5, 6, 7), "de-DE", secondToken)
        EmitTaskCollectionAdd(references, first)
        EmitTaskCollectionAdd(references, second)

        exactOwner := EmitTaskNewAssemblyNameDefinition("Shared.Identity", new Version(4, 5, 6, 7), "fr-FR", ownerToken)
        exactArguments := new object?[](2)
        EmitTaskPut(exactArguments, 0, module)
        EmitTaskPut(exactArguments, 1, exactOwner)
        exact := EmitTaskInvokePrivate(null, "GetOrAddAssemblyReference", 2, exactArguments)
        assert Object.ReferenceEquals(exact, first)
        assert EmitTaskCollectionCount(references) == 2
        assert Convert.ToString(EmitTaskObjectProperty(exact, "Culture")) == "en-US"
        assert EmitTaskObjectBytesEqual(EmitTaskObjectProperty(exact, "PublicKeyToken"), firstToken)

        newOwner := EmitTaskNewAssemblyNameDefinition("New.Identity", new Version(8, 1, 0, 0), "fr-FR", ownerToken)
        newArguments := new object?[](2)
        EmitTaskPut(newArguments, 0, module)
        EmitTaskPut(newArguments, 1, newOwner)
        added := EmitTaskInvokePrivate(null, "GetOrAddAssemblyReference", 2, newArguments)
        if added == null {
            throw new InvalidOperationException("GetOrAddAssemblyReference returned null for a new identity.")
        }
        assert EmitTaskCollectionCount(references) == 3
        assert Object.ReferenceEquals(EmitTaskCollectionItem(references, 2), added)
        assert Convert.ToString(EmitTaskObjectProperty(added, "Name")) == "New.Identity"
        assert Convert.ToString(EmitTaskObjectProperty(added, "Version")) == "8.1.0.0"
        assert Convert.ToString(EmitTaskObjectProperty(added, "Culture")) == "fr-FR"
        assert EmitTaskObjectBytesEqual(EmitTaskObjectProperty(added, "PublicKeyToken"), ownerToken)
    } finally {
        EmitTaskDispose(module)
    }
}

test "corelib cleanup removes every unused row in snapshot order and retains other identities" {
    module := EmitTaskNewCecilModule("corelib-cleanup")
    try {
        references := EmitTaskAssemblyReferences(module)
        token := EmitTaskByteArray([7, 7, 7, 7, 7, 7, 7, 7])
        firstCore := EmitTaskNewAssemblyNameReference("System.Private.CoreLib", new Version(10, 0, 0, 0), "", token)
        retained := EmitTaskNewAssemblyNameReference("Retained.Library", new Version(1, 0, 0, 0), "", null)
        secondCore := EmitTaskNewAssemblyNameReference("System.Private.CoreLib", new Version(9, 0, 0, 0), "", token)
        EmitTaskCollectionAdd(references, firstCore)
        EmitTaskCollectionAdd(references, retained)
        EmitTaskCollectionAdd(references, secondCore)
        arguments := new object?[](1)
        EmitTaskPut(arguments, 0, module)
        ignored := EmitTaskInvokePrivate(null, "RemoveUnusedCoreLibAssemblyReference", 1, arguments)
        _ = ignored
        assert EmitTaskCollectionCount(references) == 1
        assert Object.ReferenceEquals(EmitTaskCollectionItem(references, 0), retained)
    } finally {
        EmitTaskDispose(module)
    }
}

test "corelib cleanup retains a real corelib row while a real TypeRef still uses it" {
    assembly := EmitTaskReadAssembly(typeof(SdkBoundaryRun).get_Assembly().get_Location())
    try {
        module := EmitTaskObjectProperty(assembly, "MainModule")
        stringReference := EmitTaskFindTypeReference(assembly, "System.String")
        if stringReference == null {
            throw new InvalidOperationException("The emitted fixture contained no System.String TypeRef.")
        }
        assert EmitTaskTypeReferenceScopeName(stringReference) == "System.Private.CoreLib"
        coreLibrary := EmitTaskFindAssemblyReference(module, "System.Private.CoreLib")
        if coreLibrary == null {
            throw new InvalidOperationException("The emitted fixture contained no System.Private.CoreLib AssemblyRef.")
        }

        arguments := new object?[](1)
        EmitTaskPut(arguments, 0, module)
        ignored := EmitTaskInvokePrivate(null, "RemoveUnusedCoreLibAssemblyReference", 1, arguments)
        _ = ignored

        assert Object.ReferenceEquals(EmitTaskFindAssemblyReference(module, "System.Private.CoreLib"), coreLibrary)
    } finally {
        EmitTaskDispose(assembly)
    }
}

test "an empty owner scan copies implementation bytes and observes missing target before an invalid reference path" {
    scratch := EmitTaskScratch("empty-owner-copy")
    try {
        sourceAssembly := typeof(SdkBoundaryRun).get_Assembly().get_Location()
        implementation := Path.Combine(scratch, "Implementation.dll")
        referenceOutput := Path.Combine(Path.Combine(scratch, "refint"), "Implementation.dll")
        File.Copy(sourceAssembly, implementation)
        originalBytes := File.ReadAllBytes(implementation)

        task := EmitTaskNewTask()
        EmitTaskSetObjectProperty(task, "TargetAssemblyPath", implementation)
        EmitTaskSetObjectProperty(task, "TargetReferenceAssemblyPath", referenceOutput)
        EmitTaskSetReferences(task, new string[](0))
        arguments := new object?[](0)
        ignored := EmitTaskInvokePrivate(task, "SynchronizeReferenceAssembly", 0, arguments)
        _ = ignored
        assert File.Exists(referenceOutput)
        assert EmitTaskBytesEqual(originalBytes, File.ReadAllBytes(referenceOutput))

        missingTask := EmitTaskNewTask()
        EmitTaskSetObjectProperty(missingTask, "TargetAssemblyPath", Path.Combine(scratch, "missing.dll"))
        EmitTaskSetObjectProperty(missingTask, "TargetReferenceAssemblyPath", "\u0000invalid")
        ignored = EmitTaskInvokePrivate(missingTask, "SynchronizeReferenceAssembly", 0, arguments)
        _ = ignored

        ioTask := EmitTaskNewTask()
        EmitTaskSetObjectProperty(ioTask, "TargetAssemblyPath", implementation)
        EmitTaskSetObjectProperty(ioTask, "TargetReferenceAssemblyPath", scratch)
        captured := EmitTaskCapturePrivateFailure(ioTask, "SynchronizeReferenceAssembly", 0, arguments)
        assert captured != null
        assert captured is UnauthorizedAccessException
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "reference synchronization rewrites a real corelib TypeRef to the defining reference identity" {
    scratch := EmitTaskScratch("scope-rewrite")
    try {
        referencePack := EmitTaskReferencePackDirectory()
        ownerPath := Path.Combine(scratch, "ReferenceOwner.dll")
        ownerToken := EmitTaskByteArray([4, 3, 2, 1, 4, 3, 2, 1])
        EmitTaskCloneAssembly(
            Path.Combine(referencePack, "System.Runtime.dll"),
            ownerPath,
            "ReferenceOwner",
            new Version(6, 5, 4, 3),
            "fr-FR",
            ownerToken
        )
        actualOwnerToken := EmitTaskAssemblyIdentityProperty(ownerPath, "PublicKeyToken")
        implementation := Path.Combine(scratch, "Implementation.dll")
        referenceOutput := Path.Combine(Path.Combine(scratch, "refint"), "Implementation.dll")
        File.Copy(typeof(SdkBoundaryRun).get_Assembly().get_Location(), implementation)

        task := EmitTaskNewTask()
        EmitTaskSetObjectProperty(task, "TargetAssemblyPath", implementation)
        EmitTaskSetObjectProperty(task, "TargetReferenceAssemblyPath", referenceOutput)
        ownerPaths := new string[](1)
        ownerPaths[0] = ownerPath
        EmitTaskSetReferences(task, ownerPaths)
        arguments := new object?[](0)
        ignored := EmitTaskInvokePrivate(task, "SynchronizeReferenceAssembly", 0, arguments)
        _ = ignored
        assert File.Exists(referenceOutput)
        assert !EmitTaskBytesEqual(File.ReadAllBytes(implementation), File.ReadAllBytes(referenceOutput))

        EmitTaskAssertRewriteOutput(referenceOutput, actualOwnerToken)
    } finally {
        Directory.Delete(scratch, true)
    }
}
