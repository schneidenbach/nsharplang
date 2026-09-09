namespace NSharpLang.LanguageServerDiagnostics.Tests

import System.IO

test "DocumentManager syntax error produces compiler diagnostics" {
    diagnostics := LsdOpenCompilerDiagnostics("file:///test.nl", "\nfunc main(: void")
    assert diagnostics.Count > 0
}

test "DocumentManager valid code produces no compiler errors" {
    source := "\nfunc main(): void\n    print(\"Hello, World!\")"
    diagnostics := LsdOpenCompilerDiagnostics("file:///test.nl", source)
    assert !LsdContainsSeverity(diagnostics, "Error")
}

test "DocumentManager file URI relative import resolves against filesystem path" {
    tempRoot := LsdTempRoot("nsharp-lsp-import-")
    Directory.CreateDirectory(tempRoot)
    try {
        modelsDir := Path.Combine(tempRoot, "Models")
        servicesDir := Path.Combine(tempRoot, "Services")
        Directory.CreateDirectory(modelsDir)
        Directory.CreateDirectory(servicesDir)

        LsdWriteFile(tempRoot, "project.yml", "name: TempImportTest\ntargetFramework: net10.0")
        LsdWriteFile(
            tempRoot,
            "Models/Person.nl",
            LsdDecodedSource(
                """
namespace TempImportTest.Models

record Person {
    Name: string
}
"""
            )
        )
        serviceSource := LsdDecodedSource(
            """
namespace TempImportTest.Services

import "../Models/Person"

class PersonService {
    person: Person
}
"""
        )
        servicePath := Path.Combine(servicesDir, "PersonService.nl")
        File.WriteAllText(servicePath, serviceSource)
        diagnostics := LsdOpenCompilerDiagnostics(LsdFileUri(servicePath), File.ReadAllText(servicePath))
        assert !LsdContains(diagnostics, "InvalidSyntax", null)
    } finally {
        Directory.Delete(tempRoot, true)
    }
}

test "DocumentManager type import reports exact namespace diagnostic" {
    tempRoot := LsdTempRoot("nsharp-lsp-invalid-import-")
    Directory.CreateDirectory(tempRoot)
    try {
        LsdWriteFile(tempRoot, "project.yml", "name: TempInvalidImportTest\ntargetFramework: net10.0")
        source := LsdDecodedSource(
            """
import System.Console

func Main() {
}
"""
        )
        programPath := Path.Combine(tempRoot, "Program.nl")
        File.WriteAllText(programPath, source)
        diagnostics := LsdOpenCompilerDiagnostics(LsdFileUri(programPath), File.ReadAllText(programPath))
        diagnostic := LsdSingle(diagnostics, "NamespaceNotFound", "is a type, not a namespace")
        LsdAssertSpan(diagnostic, 1, 8, "System.Console".Length)
    } finally {
        Directory.Delete(tempRoot, true)
    }
}

test "DocumentManager synchronized project publishes compiler results for all open files" {
    tempRoot := LsdTempRoot("nsharp-lsp-workspace-diagnostics-")
    Directory.CreateDirectory(tempRoot)
    try {
        LsdWriteFile(tempRoot, "project.yml", "name: WorkspaceDiagnostics")
        programText := LsdDecodedSource(
            """
func Main() {
}
"""
        )
        personText := LsdDecodedSource(
            """
func Broken() -> int {
    return "oops"
}
"""
        )
        LsdWriteFile(tempRoot, "Program.nl", programText)
        LsdWriteFile(tempRoot, "Models/Person.nl", personText)

        programUri := LsdFileUri(Path.Combine(tempRoot, "Program.nl"))
        personUri := LsdFileUri(Path.Combine(tempRoot, "Models/Person.nl"))
        manager := LsdNewDocumentManager()
        LsdUpdateDocument(manager, programUri, programText)
        LsdUpdateDocument(manager, personUri, personText)

        publications := LsdDiagnosticPublications(manager, programUri)
        assert publications.Count == 2
        programPublication := LsdFindPublication(publications, programUri)
        personPublication := LsdFindPublication(publications, personUri)
        assert LsdPublicationCompilerDiagnostics(programPublication).Count == 0
        assert LsdContainsSeverity(LsdPublicationCompilerDiagnostics(personPublication), "Error")
    } finally {
        Directory.Delete(tempRoot, true)
    }
}

test "DocumentManager workspace scan publishes compiler diagnostics for error files" {
    tempRoot := LsdTempRoot("nsharp-lsp-workspace-diagnostics-")
    Directory.CreateDirectory(tempRoot)
    try {
        LsdWriteFile(tempRoot, "project.yml", "name: WorkspaceDiagnostics")
        goodText := LsdDecodedSource(
            """
func Main() {
}
"""
        )
        badText := LsdDecodedSource(
            """
func Broken() -> int {
    return "oops"
}
"""
        )
        LsdWriteFile(tempRoot, "Good.nl", goodText)
        LsdWriteFile(tempRoot, "Bad.nl", badText)

        manager := LsdNewDocumentManager()
        loadedValue := LsdInvokeStringArgument(manager, "ScanWorkspaceDirectory", tempRoot)
        loadedUris := LsdRequiredList(loadedValue, "DocumentManager workspace scan result")
        assert loadedUris.Count == 2
        goodUri := LsdFindStringContaining(loadedUris, "Good.nl")
        badUri := LsdFindStringContaining(loadedUris, "Bad.nl")

        goodPublications := LsdDiagnosticPublications(manager, goodUri)
        badPublications := LsdDiagnosticPublications(manager, badUri)
        assert goodPublications.Count >= 1
        assert badPublications.Count >= 1
        badPublication := LsdFindPublication(badPublications, badUri)
        assert LsdContainsSeverity(LsdPublicationCompilerDiagnostics(badPublication), "Error")
    } finally {
        Directory.Delete(tempRoot, true)
    }
}
