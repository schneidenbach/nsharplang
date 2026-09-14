namespace NSharpLang.LanguageServerDiagnostics.Tests

import System
import System.IO
import Microsoft.Extensions.Logging.Abstractions
import NSharpLang.LanguageServer.Handlers
import NSharpLang.LanguageServer.Services

// Auto-import contracts for completion: a type whose namespace the file already imports must be
// offered WITHOUT an additional import edit, so accepting the item never duplicates an import.
func LscAutoImportDocumentPath(): string {
    return Path.Combine(Path.GetTempPath(), "nsharp-auto-import-" + Guid.NewGuid().ToString("N") + ".nl")
}

func LscNewCompletionHandler(manager: DocumentManager): CompletionHandler {
    return new CompletionHandler(manager, new TypeResolver(manager), NullLogger<CompletionHandler>.Instance)
}

test "completing a generic type adds no import edit when its namespace is already imported" {
    source := LsdDecodedSource(
        """
import System.Collections.Generic

func main() {
    Lis
}
"""
    )

    manager := new DocumentManager(NullLogger<DocumentManager>.Instance)
    handler := LscNewCompletionHandler(manager)

    uri := LsdFileUri(LscAutoImportDocumentPath())
    manager.UpdateDocument(uri, source, 1)

    target := LscFindCompletionTarget(source, "Lis")
    completion := LscCompletionAt(handler, uri, target.Line, target.Character)

    item := LscSingleCompletionItem(completion, "List")
    assert LscAdditionalEditCount(item) == 0
}

test "completing Console adds no import edit when System is already imported" {
    source := LsdDecodedSource(
        """
import System

func main() {
    Cons
}
"""
    )

    manager := new DocumentManager(NullLogger<DocumentManager>.Instance)
    handler := LscNewCompletionHandler(manager)

    uri := LsdFileUri(LscAutoImportDocumentPath())
    manager.UpdateDocument(uri, source, 1)

    target := LscFindCompletionTarget(source, "Cons")
    completion := LscCompletionAt(handler, uri, target.Line, target.Character)

    item := LscSingleCompletionItem(completion, "Console")
    assert LscAdditionalEditCount(item) == 0
}
