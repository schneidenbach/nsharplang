namespace NSharpLang.LanguageServer.Services

import System
import System.Collections.Generic
import NSharpLang.Compiler

// The editor's view of the type universe — which, since 022/4, IS the analyzer's.
//
// `EditorTypeCatalog` is the N# owner of that universe, and it holds the analyzer's assembly
// registry BY REFERENCE — so a package that loads mid-session is offerable at the next keystroke
// rather than after a restart. Its caches are keyed on that registry's identity for exactly that
// reason.
//
// What is left here is the adapter: three forwards and the shape change from the owner's
// `EditorImportableType` to the LSP's own record.
class TypeResolver {
    readonly catalog: EditorTypeCatalog

    constructor(documentManager: DocumentManager) {
        catalog = documentManager.SharedAnalyzer.CreateEditorTypeCatalog()
    }

    func ResolveType(typeName: string): Type? => catalog.ResolveType(typeName)

    func GetNamespaceSuggestions(prefix: string): List<string> => catalog.NamespaceSuggestions(prefix)

    // Get public CLR types that can be inserted with an import edit.
    func GetImportableTypes(prefix: string): List<ImportableTypeInfo> {
        results := new List<ImportableTypeInfo>()
        for importable in catalog.ImportableTypes(prefix) {
            results.Add(new ImportableTypeInfo(
                importable.Name,
                importable.FullName,
                importable.Namespace,
                importable.IsInterface,
                importable.IsEnum
            ))
        }

        return results
    }
}

// A public CLR type that can be offered as an identifier completion with an import edit.
record ImportableTypeInfo(Name: string, FullName: string, Namespace: string, IsInterface: bool, IsEnum: bool) {
}
