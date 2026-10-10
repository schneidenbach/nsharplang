namespace NSharpLang.LanguageServerDiagnostics.Tests

import System.Collections.Generic
import System.IO
import Microsoft.Extensions.Logging.Abstractions
import NSharpLang.Compiler
import NSharpLang.LanguageServer.Services

// A REFERENCED LIBRARY REBUILT WITH A NEW MEMBER IS READ AGAIN.
//
// The language server's shared analyzer loads a project's references once per project directory into
// a metadata load context that keeps the bytes it read, and its project snapshot cache is stamped by
// sources and `project.yml` only. So a library rebuilt with a new type stayed the OLD library for
// the life of the server: a buffer calling the new member was reported "not found" until the editor
// restarted -- the defect the workspace server already guarded against (`DaemonLoadedReferenceGuard`).
// These rows rebuild a referenced library in place, the way `nlc build` writes it, with a new TYPE,
// and require both the per-document analysis and the project snapshot to see it without a restart. (A
// type, because a missing MEMBER of a referenced type is refused only at emission today, which the
// editor's analysis does not run.)
func RrLibrarySource(withWaver: bool): string {
    waver := ""
    if withWaver {
        waver = "\nclass Waver {\n    func Wave(): string {\n        return \"wave\"\n    }\n}\n"
    }
    return "namespace RefLib\n\nclass Greeter {\n    func Hello(): string {\n        return \"hello\"\n    }\n}\n" + waver
}

func RrBuildLibrary(libraryRoot: string, withWave: bool): string {
    LsdWriteFile(libraryRoot, "project.yml", "name: RefLib\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
    LsdWriteFile(libraryRoot, "Greeter.nl", RrLibrarySource(withWave))
    config := ProjectFileParser.Parse(Path.Combine(libraryRoot, "project.yml"))
    output := Path.Combine(libraryRoot, "bin", "RefLib.dll")
    result := new MultiFileCompiler(libraryRoot, config).CompileToIlAssembly("RefLib", output, false, true)
    assert result.Success, "the library did not build"
    return output
}

func RrWriteApp(appRoot: string, source: string): string {
    LsdWriteFile(appRoot, "project.yml", "name: RefApp\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n\ndependencies:\n  - dll: ../lib/bin/RefLib.dll\n")
    LsdWriteFile(appRoot, "Main.nl", source)
    return Path.Combine(appRoot, "Main.nl")
}

func RrAppSource(typeName: string, member: string): string {
    return "namespace RefApp\n\nimport RefLib\n\nfunc Greet(): string {\n    value := new " + typeName + "()\n    return value." + member + "()\n}\n"
}

func RrErrors(errors: IReadOnlyList<CompilerError>): string {
    text := ""
    for error in errors {
        if error.Severity == ErrorSeverity.Error {
            text = text + error.DiagnosticId + " " + error.Message + "\n"
        }
    }
    return text
}

func RrAllDiagnostics(manager: DocumentManager, uri: string): string {
    document := manager.GetDocument(uri)
    if document == null {
        return "no document"
    }
    diagnostics := document.Diagnostics ?? new List<CompilerError>()
    text := ""
    for diagnostic in diagnostics {
        text = text + diagnostic.Severity.ToString() + " " + diagnostic.DiagnosticId + " " + diagnostic.Message + "\n"
    }
    return text
}

func RrDocumentErrors(manager: DocumentManager, uri: string): string {
    document := manager.GetDocument(uri)
    assert document != null
    if document == null {
        return "no document"
    }
    return RrErrors(document.Diagnostics ?? new List<CompilerError>())
}

test "a referenced library rebuilt with a new type is read again by the document analysis" {
    root := LsdTempRoot("nsharp-lsp-reference-rebuild-")
    try {
        RrBuildLibrary(Path.Combine(root, "lib"), false)
        appRoot := Path.Combine(root, "app")
        uri := LsdFileUri(RrWriteApp(appRoot, RrAppSource("Greeter", "Hello")))

        manager := new DocumentManager(NullLogger<DocumentManager>.Instance)
        manager.UpdateDocument(uri, RrAppSource("Greeter", "Hello"), 1)
        assert RrDocumentErrors(manager, uri) == "", RrDocumentErrors(manager, uri)

        // The new type is not in the library yet: a real error, and the control that proves the
        // analysis reads the library at all.
        manager.UpdateDocument(uri, RrAppSource("Waver", "Wave"), 2)
        assert RrDocumentErrors(manager, uri) != "", "naming the type the library does not have yet reported nothing: " + RrAllDiagnostics(manager, uri)

        RrBuildLibrary(Path.Combine(root, "lib"), true)
        manager.UpdateDocument(uri, RrAppSource("Waver", "Wave"), 3)
        assert RrDocumentErrors(manager, uri) == "", RrDocumentErrors(manager, uri)
    } finally {
        Directory.Delete(root, true)
    }
}

test "a referenced library rebuilt with a new type is read again by the project snapshot" {
    root := LsdTempRoot("nsharp-lsp-reference-rebuild-snapshot-")
    try {
        RrBuildLibrary(Path.Combine(root, "lib"), false)
        appRoot := Path.Combine(root, "app")
        uri := LsdFileUri(RrWriteApp(appRoot, RrAppSource("Waver", "Wave")))

        manager := new DocumentManager(NullLogger<DocumentManager>.Instance)
        manager.UpdateDocument(uri, RrAppSource("Waver", "Wave"), 1)
        before := manager.GetDiagnosticsToPublish(uri)
        assert before.Count == 1, before.Count.ToString()
        assert RrErrors(before[0].CompilerDiagnostics) != "", "the snapshot reported nothing for the type the library does not have yet: " + RrAllDiagnostics(manager, uri)

        // Nothing in the app changes: only the library is rebuilt. The cached snapshot is stamped by
        // the app's sources, so only the reference guard can retire it.
        RrBuildLibrary(Path.Combine(root, "lib"), true)
        after := manager.GetDiagnosticsToPublish(uri)
        assert after.Count == 1
        assert RrErrors(after[0].CompilerDiagnostics) == "", RrErrors(after[0].CompilerDiagnostics)
    } finally {
        Directory.Delete(root, true)
    }
}
