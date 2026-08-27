using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using Microsoft.Extensions.Logging;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.LanguageServer.Services;

/// <summary>
/// The REFLECTION MECHANICS behind the editor's type catalogue: load some assemblies, read types
/// out of them, cache what was read.
///
/// Every decision this service used to make is <c>EditorTypeCatalogFacts</c>'s — which assemblies
/// the editor may see, which short names it volunteers and what each denotes, which namespaces a
/// bare name is probed in and in what order, how a written type name is spelled, which CLR types
/// may be offered, how they are ranked and how many may be sent. <c>AnalyzerTypeReferenceFacts</c>
/// owns the built-in aliases. What is left below is four kinds of thing and no fifth:
/// a lazy double-checked assembly load, three <c>Reflection</c> reads, two caches, and the LINQ
/// that carries the owner's answers.
///
/// ONE ARGUMENT IS STILL SPELLED HERE, AND IT IS NAMED RATHER THAN HIDDEN:
/// <c>ignoreCase: false</c> on the full-name lookup. It is a property of the READ and not a
/// curation choice — a case-insensitive CLR full-name lookup answers a DIFFERENT type for the same
/// string, so exactness is the mechanical option rather than a policy this file gets to pick.
///
/// THE EDITOR'S TYPE UNIVERSE IS NOT THE COMPILER'S. The four seed names the owner supplies reach
/// exactly three assemblies of the running language-server process; the analyzer meanwhile builds a
/// <c>MetadataLoadContext</c> over its own 27-name table PLUS the project's own references. So
/// completion cannot offer a type from a package the user depends on and hover cannot name one.
/// Closing that gap means serving the editor from the analyzer's universe, which is the AOT
/// type-model task's scope; do not paper over it by adding a fifth seed name here.
/// </summary>
public class TypeResolver
{
    private readonly ILogger<TypeResolver> _logger;
    private readonly Dictionary<string, Type> _typeCache = new();
    private readonly List<Assembly> _loadedAssemblies = new();
    private readonly Dictionary<Assembly, Type[]> _exportedTypesCache = new();
    private HashSet<string>? _namespaceCache;
    private bool _assembliesLoaded = false;
    private readonly object _loadLock = new();

    public TypeResolver(ILogger<TypeResolver> logger)
    {
        _logger = logger;
        // CRITICAL FIX: Don't load assemblies in constructor
        // This was causing test hangs during xUnit test discovery
        // Load on first use instead
    }

    /// <summary>
    /// Ensure system assemblies are loaded (lazy initialization)
    /// </summary>
    private void EnsureAssembliesLoaded()
    {
        if (_assembliesLoaded) return;

        lock (_loadLock)
        {
            if (_assembliesLoaded) return; // Double-check after lock

            LoadSystemAssemblies();
            _assembliesLoaded = true;
        }
    }

    /// <summary>
    /// Resolve the owner's seed type names to the assemblies that declare them. The names are
    /// metadata names rather than <c>typeof</c> because that is the spelling N# can hold; several
    /// of them resolve to the same assembly, so the list is de-duplicated on the way in.
    /// </summary>
    private void LoadSystemAssemblies()
    {
        try
        {
            foreach (var seedTypeName in EditorTypeCatalogFacts.EditorUniverseSeedTypeNames())
            {
                var assembly = Type.GetType(seedTypeName, throwOnError: false)?.Assembly;
                if (assembly != null && !_loadedAssemblies.Contains(assembly))
                {
                    _loadedAssemblies.Add(assembly);
                    _logger.LogDebug("Loaded assembly: {AssemblyName}", assembly.GetName().Name);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error loading system assemblies");
        }
    }

    /// <summary>
    /// Try to resolve a type by name
    /// </summary>
    public Type? ResolveType(string typeName)
    {
        EnsureAssembliesLoaded();

        if (string.IsNullOrWhiteSpace(typeName))
        {
            return null;
        }

        typeName = EditorTypeCatalogFacts.StripNullableSuffix(typeName.Trim());

        // An array is resolved through its element, one rank per call.
        if (EditorTypeCatalogFacts.IsArrayTypeName(typeName))
        {
            var elementType = ResolveType(EditorTypeCatalogFacts.ArrayElementTypeName(typeName));
            if (elementType == null)
            {
                return null;
            }

            var arrayType = elementType.MakeArrayType();
            _typeCache[typeName] = arrayType;
            return arrayType;
        }

        typeName = EditorTypeCatalogFacts.StripGenericArgumentList(typeName);

        var aliasFullName = AnalyzerTypeReferenceFacts.BuiltInClrTypeName(typeName);
        if (aliasFullName != null)
        {
            typeName = aliasFullName;
        }
        else if (!EditorTypeCatalogFacts.IsQualifiedTypeName(typeName))
        {
            typeName = EditorTypeCatalogFacts.CommonShortTypeFullName(typeName) ?? typeName;
        }

        if (_typeCache.TryGetValue(typeName, out var cachedType))
        {
            return cachedType;
        }

        Type? resolved = null;
        try
        {
            // The owner's probe plan: the name as written, then each of its namespace prefixes.
            foreach (var candidate in EditorTypeCatalogFacts.CandidateTypeFullNames(typeName))
            {
                resolved = ResolveTypeByFullName(candidate);
                if (resolved != null)
                {
                    break;
                }
            }

            // Last resort: exported-type scan (cached per assembly).
            // This fixes missing completions like `Console.` while avoiding repeated hangs.
            if (resolved == null && !EditorTypeCatalogFacts.IsQualifiedTypeName(typeName))
            {
                resolved = ResolveTypeBySimpleName(typeName);
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Error resolving type {Type}", typeName);
        }

        if (resolved != null)
        {
            _typeCache[typeName] = resolved;
            return resolved;
        }

        return null;
    }

    private Type? ResolveTypeByFullName(string fullName)
    {
        foreach (var assembly in _loadedAssemblies)
        {
            try
            {
                var type = assembly.GetType(fullName, throwOnError: false, ignoreCase: false);
                if (type != null)
                    return type;
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "Error searching assembly {Assembly} for type {Type}",
                    assembly.GetName().Name, fullName);
            }
        }

        return null;
    }

    private Type? ResolveTypeBySimpleName(string simpleName)
    {
        foreach (var assembly in _loadedAssemblies)
        {
            try
            {
                if (!_exportedTypesCache.TryGetValue(assembly, out var exportedTypes))
                {
                    exportedTypes = assembly.GetExportedTypes();
                    _exportedTypesCache[assembly] = exportedTypes;
                }

                var match = exportedTypes.FirstOrDefault(t => t.Name == simpleName);
                if (match != null)
                    return match;
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "Error scanning exported types in assembly {Assembly}",
                    assembly.GetName().Name);
            }
        }

        return null;
    }

    /// <summary>
    /// Get public CLR types that can be inserted with an import edit.
    /// Empty-prefix requests return a curated set so general completion stays useful
    /// without flooding the editor with framework types.
    /// </summary>
    public List<ImportableTypeInfo> GetImportableTypes(string prefix)
    {
        EnsureAssembliesLoaded();

        prefix = prefix.Trim();
        var results = new Dictionary<string, ImportableTypeInfo>(StringComparer.Ordinal);

        void AddType(Type? type, bool forceInclude = false)
        {
            if (type == null || !EditorTypeCatalogFacts.IsOfferableCompletionType(
                    type.Name, type.Namespace, type.FullName, type.IsPublic, type.IsNested))
            {
                return;
            }

            var name = EditorTypeCatalogFacts.CompletionTypeDisplayName(type.Name);
            if (!forceInclude && !EditorTypeCatalogFacts.MatchesCompletionPrefix(name, prefix))
            {
                return;
            }

            results.TryAdd(type.FullName!, new ImportableTypeInfo(
                name,
                type.FullName!,
                type.Namespace!,
                type.IsInterface,
                type.IsEnum));
        }

        foreach (var fullName in EditorTypeCatalogFacts.CommonShortTypeFullNames())
        {
            AddType(ResolveTypeByFullName(fullName), forceInclude: true);
        }

        if (prefix.Length > 0)
        {
            foreach (var assembly in _loadedAssemblies)
            {
                var types = GetOrCacheExportedTypes(assembly);
                if (types == null)
                {
                    continue;
                }

                foreach (var type in types)
                {
                    AddType(type);
                }
            }
        }

        return results.Values
            .OrderBy(type => type, Comparer<ImportableTypeInfo>.Create(
                (left, right) => EditorTypeCatalogFacts.CompareImportableTypes(
                    left.Name, left.Namespace, right.Name, right.Namespace)))
            .Take(EditorTypeCatalogFacts.MaxImportableTypeResults())
            .ToList();
    }

    public List<string> GetNamespaceSuggestions(string prefix)
    {
        var namespaces = GetKnownNamespaces();
        var results = new HashSet<string>(StringComparer.Ordinal);
        var parentNamespace = EditorTypeCatalogFacts.NamespacePrefixParent(prefix);
        var segmentPrefix = EditorTypeCatalogFacts.NamespacePrefixSegment(prefix);

        foreach (var ns in namespaces)
        {
            var nextSegment = EditorTypeCatalogFacts.NextNamespaceSegment(ns, parentNamespace);
            if (nextSegment.Length == 0)
            {
                continue;
            }

            if (EditorTypeCatalogFacts.MatchesNamespaceSegmentPrefix(nextSegment, segmentPrefix))
            {
                results.Add(nextSegment);
            }
        }

        return results
            .OrderBy(segment => segment, Comparer<string>.Create(EditorTypeCatalogFacts.CompareNamespaceSegments))
            .ToList();
    }

    /// <summary>
    /// The owner's seed list unioned with every namespace of every assembly the editor can see.
    /// The seed is what answers the first keystroke after <c>import</c>, before any scan has run.
    /// </summary>
    private HashSet<string> GetKnownNamespaces()
    {
        if (_namespaceCache != null)
        {
            return _namespaceCache;
        }

        EnsureAssembliesLoaded();

        var namespaces = new HashSet<string>(
            EditorTypeCatalogFacts.WellKnownNamespaceSeeds(), StringComparer.Ordinal);

        foreach (var assembly in _loadedAssemblies)
        {
            var types = GetOrCacheExportedTypes(assembly);
            if (types == null)
            {
                continue;
            }

            foreach (var ns in types.Select(t => t.Namespace).Where(ns => !string.IsNullOrWhiteSpace(ns)))
            {
                namespaces.Add(ns!);
            }
        }

        _namespaceCache = namespaces;
        return namespaces;
    }

    /// <summary>
    /// Get exported types from an assembly, caching the result to avoid repeated reflection scans.
    /// </summary>
    private Type[]? GetOrCacheExportedTypes(Assembly assembly)
    {
        if (_exportedTypesCache.TryGetValue(assembly, out var cached))
            return cached;

        try
        {
            var types = assembly.GetExportedTypes();
            _exportedTypesCache[assembly] = types;
            return types;
        }
        catch
        {
            return null;
        }
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
