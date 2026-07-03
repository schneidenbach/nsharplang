using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using Microsoft.Extensions.Logging;

namespace NSharpLang.LanguageServer.Services;

/// <summary>
/// Resolves types from loaded assemblies and provides member information
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

    private static readonly Dictionary<string, string> AliasToFullName = new(StringComparer.Ordinal)
    {
        ["bool"] = "System.Boolean",
        ["byte"] = "System.Byte",
        ["sbyte"] = "System.SByte",
        ["short"] = "System.Int16",
        ["ushort"] = "System.UInt16",
        ["int"] = "System.Int32",
        ["uint"] = "System.UInt32",
        ["long"] = "System.Int64",
        ["ulong"] = "System.UInt64",
        ["char"] = "System.Char",
        ["float"] = "System.Single",
        ["double"] = "System.Double",
        ["decimal"] = "System.Decimal",
        ["string"] = "System.String",
        ["object"] = "System.Object",
        ["void"] = "System.Void",
    };

    private static readonly Dictionary<string, string> CommonShortTypeToFullName = new(StringComparer.Ordinal)
    {
        ["Console"] = "System.Console",
        ["String"] = "System.String",
        ["Math"] = "System.Math",
        ["DateTime"] = "System.DateTime",
        ["Guid"] = "System.Guid",
        ["Exception"] = "System.Exception",
        ["List"] = "System.Collections.Generic.List`1",
        ["Dictionary"] = "System.Collections.Generic.Dictionary`2",
        ["HashSet"] = "System.Collections.Generic.HashSet`1",
        ["IEnumerable"] = "System.Collections.Generic.IEnumerable`1",
        ["Task"] = "System.Threading.Tasks.Task",
        ["CancellationToken"] = "System.Threading.CancellationToken",
    };

    private static readonly string[] CommonNamespacePrefixes =
    [
        "System",
        "System.Collections",
        "System.Collections.Generic",
        "System.Linq",
        "System.Text",
        "System.Threading",
        "System.Threading.Tasks",
    ];

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
    /// Load common system assemblies
    /// </summary>
    private void LoadSystemAssemblies()
    {
        try
        {
            // Load core assemblies
            var coreAssemblies = new[]
            {
                typeof(object).Assembly,                          // System.Private.CoreLib
                typeof(Console).Assembly,                         // System.Console
                typeof(System.Linq.Enumerable).Assembly,          // System.Linq
                typeof(System.Collections.Generic.List<>).Assembly, // System.Collections
            };

            foreach (var assembly in coreAssemblies)
            {
                if (!_loadedAssemblies.Contains(assembly))
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

        typeName = typeName.Trim();

        // Handle nullable types (e.g., "string?" -> "string")
        if (typeName.EndsWith("?"))
        {
            typeName = typeName.Substring(0, typeName.Length - 1).TrimEnd();
        }

        // Handle array types (e.g., "int[]" -> resolve int, then make array type)
        if (typeName.EndsWith("[]"))
        {
            var elementTypeName = typeName.Substring(0, typeName.Length - 2).TrimEnd();
            var elementType = ResolveType(elementTypeName);
            if (elementType != null)
            {
                var arrayType = elementType.MakeArrayType();
                _typeCache[typeName] = arrayType;
                return arrayType;
            }
            return null;
        }

        // Strip generic arguments for now (e.g., Task<string> -> Task)
        // IntelliSense uses reflection against the open type; generic argument resolution is handled elsewhere.
        var genericStart = typeName.IndexOf('<');
        if (genericStart >= 0)
        {
            typeName = typeName.Substring(0, genericStart).TrimEnd();
        }

        if (AliasToFullName.TryGetValue(typeName, out var aliasFullName))
        {
            typeName = aliasFullName;
        }
        else if (!typeName.Contains('.') && CommonShortTypeToFullName.TryGetValue(typeName, out var commonFullName))
        {
            typeName = commonFullName;
        }

        if (_typeCache.TryGetValue(typeName, out var cachedType))
        {
            return cachedType;
        }

        // Try to find type in loaded assemblies
        Type? resolved = null;
        try
        {
            // Exact match (fast path)
            resolved = ResolveTypeByFullName(typeName);

            // If input is a short name, try a few common namespaces (still cheap).
            if (resolved == null && !typeName.Contains('.'))
            {
                foreach (var ns in CommonNamespacePrefixes)
                {
                    resolved = ResolveTypeByFullName($"{ns}.{typeName}");
                    if (resolved != null)
                        break;
                }
            }

            // Last resort: exported-type scan (cached per assembly).
            // This fixes missing completions like `Console.` while avoiding repeated hangs.
            if (resolved == null && !typeName.Contains('.'))
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

    /// <summary>
    /// Get the namespace that should be imported for a resolved type.
    /// Returns null for primitive aliases or unresolved type names.
    /// </summary>
    public string? GetImportNamespace(string typeName)
    {
        var type = ResolveType(typeName);
        return type != null ? GetImportNamespace(type) : null;
    }

    /// <summary>
    /// Get the namespace that should be imported for a resolved CLR type.
    /// </summary>
    public string? GetImportNamespace(Type type)
    {
        if (type.IsArray)
        {
            type = type.GetElementType() ?? type;
        }

        if (type.IsGenericType)
        {
            type = type.GetGenericTypeDefinition();
        }

        return type.Namespace;
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
    public List<ImportableTypeInfo> GetImportableTypes(string prefix, int maxResults = 200)
    {
        EnsureAssembliesLoaded();

        prefix = prefix.Trim();
        var results = new Dictionary<string, ImportableTypeInfo>(StringComparer.Ordinal);

        void AddType(Type? type, bool forceInclude = false)
        {
            if (type == null || !type.IsPublic || type.IsNested)
            {
                return;
            }

            if (string.IsNullOrWhiteSpace(type.Namespace) || string.IsNullOrWhiteSpace(type.FullName))
            {
                return;
            }

            if (type.Name.StartsWith("<", StringComparison.Ordinal) || type.Name.Contains("__", StringComparison.Ordinal))
            {
                return;
            }

            var name = GetCompletionTypeName(type);
            if (!forceInclude && prefix.Length > 0 && !name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            results.TryAdd(type.FullName, new ImportableTypeInfo(
                name,
                type.FullName,
                type.Namespace,
                type.IsAbstract && type.IsSealed,
                type.IsInterface,
                type.IsEnum));
        }

        foreach (var fullName in CommonShortTypeToFullName.Values)
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
            .OrderBy(type => GetNamespacePriority(type.Namespace))
            .ThenBy(type => type.Name, StringComparer.Ordinal)
            .ThenBy(type => type.Namespace, StringComparer.Ordinal)
            .Take(maxResults)
            .ToList();
    }

    public List<string> GetNamespaceSuggestions(string prefix)
    {
        var namespaces = GetKnownNamespaces();
        var results = new HashSet<string>(StringComparer.Ordinal);
        var normalizedPrefix = prefix.Trim();
        var wantsChildren = normalizedPrefix.EndsWith(".", StringComparison.Ordinal);
        var basePrefix = wantsChildren ? normalizedPrefix[..^1] : normalizedPrefix;

        string parentNamespace;
        string segmentPrefix;

        if (string.IsNullOrEmpty(basePrefix))
        {
            parentNamespace = string.Empty;
            segmentPrefix = string.Empty;
        }
        else if (wantsChildren)
        {
            parentNamespace = basePrefix;
            segmentPrefix = string.Empty;
        }
        else
        {
            var lastDot = basePrefix.LastIndexOf('.');
            parentNamespace = lastDot >= 0 ? basePrefix[..lastDot] : string.Empty;
            segmentPrefix = lastDot >= 0 ? basePrefix[(lastDot + 1)..] : basePrefix;
        }

        foreach (var ns in namespaces)
        {
            if (!TryGetNextNamespaceSegment(ns, parentNamespace, out var nextSegment))
            {
                continue;
            }

            if (nextSegment.StartsWith(segmentPrefix, StringComparison.Ordinal))
            {
                results.Add(nextSegment);
            }
        }

        return results.OrderBy(x => x, StringComparer.Ordinal).ToList();
    }

    /// <summary>
    /// Check if a name matches a known namespace
    /// </summary>
    // Common .NET namespaces — checked first to avoid expensive assembly scans
    private static readonly HashSet<string> WellKnownNamespaces = new(StringComparer.Ordinal)
    {
        "System", "System.Collections", "System.Collections.Generic", "System.Collections.Concurrent",
        "System.Linq", "System.Text", "System.Text.RegularExpressions",
        "System.Threading", "System.Threading.Tasks",
        "System.IO", "System.Net", "System.Net.Http",
        "System.Reflection", "System.Runtime", "System.Diagnostics",
        "System.Globalization", "System.ComponentModel",
        "Microsoft.Extensions.DependencyInjection",
        "Microsoft.Extensions.Logging",
        "Microsoft.AspNetCore.Mvc",
    };

    private HashSet<string> GetKnownNamespaces()
    {
        if (_namespaceCache != null)
        {
            return _namespaceCache;
        }

        EnsureAssembliesLoaded();

        var namespaces = new HashSet<string>(WellKnownNamespaces, StringComparer.Ordinal);

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

    private static bool TryGetNextNamespaceSegment(string candidateNamespace, string parentNamespace, out string nextSegment)
    {
        nextSegment = string.Empty;

        if (string.IsNullOrEmpty(parentNamespace))
        {
            var firstDot = candidateNamespace.IndexOf('.');
            nextSegment = firstDot >= 0 ? candidateNamespace[..firstDot] : candidateNamespace;
            return nextSegment.Length > 0;
        }

        var prefix = parentNamespace + ".";
        if (!candidateNamespace.StartsWith(prefix, StringComparison.Ordinal))
        {
            return false;
        }

        var remainder = candidateNamespace[prefix.Length..];
        if (remainder.Length == 0)
        {
            return false;
        }

        var nextDot = remainder.IndexOf('.');
        nextSegment = nextDot >= 0 ? remainder[..nextDot] : remainder;
        return nextSegment.Length > 0;
    }

    private static string GetCompletionTypeName(Type type)
    {
        var name = type.Name;
        var backtick = name.IndexOf('`');
        return backtick >= 0 ? name[..backtick] : name;
    }

    private static int GetNamespacePriority(string namespaceName)
    {
        return namespaceName switch
        {
            "System" => 0,
            "System.Collections.Generic" => 1,
            "System.Threading.Tasks" => 2,
            "System.Linq" => 3,
            _ when namespaceName.StartsWith("System.", StringComparison.Ordinal) => 10,
            _ => 20
        };
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

    /// <summary>
    /// Format a type name for display
    /// </summary>
    private string FormatTypeName(Type type)
    {
        if (type.IsGenericType)
        {
            var genericType = type.GetGenericTypeDefinition();
            var genericArgs = type.GetGenericArguments();
            var typeName = genericType.Name;

            // Remove `1, `2, etc. from generic type names
            var backtickIndex = typeName.IndexOf('`');
            if (backtickIndex > 0)
            {
                typeName = typeName.Substring(0, backtickIndex);
            }

            var argNames = string.Join(", ", genericArgs.Select(FormatTypeName));
            return $"{typeName}<{argNames}>";
        }

        // Use simple names for common types
        return type.Name switch
        {
            "Int32" => "int",
            "Int64" => "long",
            "Single" => "float",
            "Double" => "double",
            "Boolean" => "bool",
            "String" => "string",
            "Void" => "void",
            "Object" => "object",
            _ => type.Name
        };
    }

}

/// <summary>
/// A public CLR type that can be offered as an identifier completion with an import edit.
/// </summary>
public sealed record ImportableTypeInfo(
    string Name,
    string FullName,
    string Namespace,
    bool IsStatic,
    bool IsInterface,
    bool IsEnum);
