using System;
using System.Collections.Generic;
using NSharpLang.Compiler;

namespace NSharpLang.LanguageServer.Services;

/// <summary>
/// The editor's view of the type universe — which, since 022/4, IS the analyzer's.
///
/// This service used to build a universe of its own: four <c>Type.GetType</c> seed names resolving to
/// THREE assemblies of the running language-server process, behind a lazy double-checked load, with
/// its own type cache, exported-type cache and namespace cache. The analyzer sitting beside it held a
/// <c>MetadataLoadContext</c> over 27 common assemblies PLUS every reference the project declares, so
/// completion could not offer, and hover could not name, a type from a package the user depends on.
///
/// <c>EditorTypeCatalog</c> is the N# owner of that universe now, and it holds the analyzer's
/// assembly registry BY REFERENCE — so a package that loads mid-session is offerable at the next
/// keystroke rather than after a restart. Its caches are keyed on that registry's identity for
/// exactly that reason.
///
/// What is left here is the adapter: three forwards and the shape change from the owner's
/// <c>EditorImportableType</c> to the LSP's own record.
/// </summary>
public class TypeResolver
{
    private readonly EditorTypeCatalog _catalog;

    public TypeResolver(DocumentManager documentManager)
    {
        _catalog = documentManager.SharedAnalyzer.CreateEditorTypeCatalog();
    }

    public Type? ResolveType(string typeName) => _catalog.ResolveType(typeName);

    public List<string> GetNamespaceSuggestions(string prefix) => _catalog.NamespaceSuggestions(prefix);

    /// <summary>
    /// Get public CLR types that can be inserted with an import edit.
    /// </summary>
    public List<ImportableTypeInfo> GetImportableTypes(string prefix)
    {
        var results = new List<ImportableTypeInfo>();
        foreach (var type in _catalog.ImportableTypes(prefix))
        {
            results.Add(new ImportableTypeInfo(
                type.Name, type.FullName, type.Namespace, type.IsInterface, type.IsEnum));
        }

        return results;
    }
}

/// <summary>
/// A public CLR type that can be offered as an identifier completion with an import edit.
/// </summary>
public sealed record ImportableTypeInfo(
    string Name,
    string FullName,
    string Namespace,
    bool IsInterface,
    bool IsEnum);
