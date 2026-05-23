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
    private readonly XmlDocReader _xmlDocReader;
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

    public TypeResolver(ILogger<TypeResolver> logger, XmlDocReader xmlDocReader)
    {
        _logger = logger;
        _xmlDocReader = xmlDocReader;
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
    /// Load an assembly by name
    /// </summary>
    public void LoadAssembly(string assemblyName)
    {
        try
        {
            var assembly = Assembly.Load(assemblyName);
            if (!_loadedAssemblies.Contains(assembly))
            {
                _loadedAssemblies.Add(assembly);
                _logger.LogDebug("Loaded assembly: {AssemblyName}", assemblyName);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Could not load assembly: {AssemblyName}", assemblyName);
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
    /// Get all public types in a namespace from loaded assemblies
    /// </summary>
    public List<(string Name, string FullName, bool IsStatic, bool IsInterface, bool IsEnum)> GetTypesInNamespace(string namespaceName)
    {
        EnsureAssembliesLoaded();

        var results = new List<(string Name, string FullName, bool IsStatic, bool IsInterface, bool IsEnum)>();
        var seen = new HashSet<string>();

        foreach (var assembly in _loadedAssemblies)
        {
            try
            {
                var types = GetOrCacheExportedTypes(assembly);
                if (types == null) continue;

                foreach (var type in types)
                {
                    if (type.Namespace != namespaceName || !type.IsPublic || type.IsNested)
                        continue;
                    // Skip compiler-generated types
                    if (type.Name.StartsWith("<") || type.Name.Contains("__"))
                        continue;

                    // Clean generic type names BEFORE dedup (Action`1, Action`2 → Action)
                    var name = type.Name;
                    var backtick = name.IndexOf('`');
                    if (backtick >= 0)
                        name = name.Substring(0, backtick);

                    if (!seen.Add(name))
                        continue;

                    results.Add((name, type.FullName ?? name, type.IsAbstract && type.IsSealed, type.IsInterface, type.IsEnum));
                }
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "Error getting types from assembly {Assembly}", assembly.GetName().Name);
            }
        }

        return results;
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

    public bool IsKnownNamespace(string name)
    {
        if (WellKnownNamespaces.Contains(name))
            return true;

        return GetKnownNamespaces().Contains(name);
    }

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
    /// Get all public members of a type, filtered by access mode
    /// </summary>
    public List<MemberCompletionItem> GetMembers(Type type, MemberAccessMode mode = MemberAccessMode.All)
    {
        var items = new List<MemberCompletionItem>();

        try
        {
            // Always fetch both static and instance, then filter after
            var bindingFlags = BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static;

            // Get properties
            foreach (var prop in type.GetProperties(bindingFlags))
            {
                items.Add(new MemberCompletionItem
                {
                    Name = prop.Name,
                    Kind = MemberKind.Property,
                    Type = FormatTypeName(prop.PropertyType),
                    IsStatic = prop.GetMethod?.IsStatic ?? prop.SetMethod?.IsStatic ?? false,
                    Documentation = _xmlDocReader.GetPropertyDocumentation(prop)
                });
            }

            // Get methods (exclude property getters/setters and special methods)
            foreach (var method in type.GetMethods(bindingFlags))
            {
                if (method.IsSpecialName || method.Name.StartsWith("get_") || method.Name.StartsWith("set_"))
                {
                    continue;
                }

                var parameters = method.GetParameters();
                var paramString = string.Join(", ", parameters.Select(p =>
                    $"{p.Name}: {FormatTypeName(p.ParameterType)}"));

                items.Add(new MemberCompletionItem
                {
                    Name = method.Name,
                    Kind = MemberKind.Method,
                    Type = FormatTypeName(method.ReturnType),
                    Parameters = paramString,
                    ParameterCount = parameters.Length,
                    IsStatic = method.IsStatic,
                    Documentation = _xmlDocReader.GetMethodDocumentation(method)
                });
            }

            // Get fields
            foreach (var field in type.GetFields(bindingFlags))
            {
                items.Add(new MemberCompletionItem
                {
                    Name = field.Name,
                    Kind = MemberKind.Field,
                    Type = FormatTypeName(field.FieldType),
                    IsStatic = field.IsStatic,
                    Documentation = _xmlDocReader.GetFieldDocumentation(field)
                });
            }

            // Get events
            foreach (var evt in type.GetEvents(bindingFlags))
            {
                items.Add(new MemberCompletionItem
                {
                    Name = evt.Name,
                    Kind = MemberKind.Event,
                    Type = FormatTypeName(evt.EventHandlerType!),
                    IsStatic = evt.AddMethod?.IsStatic ?? false,
                    Documentation = null
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting members for type {Type}", type.FullName);
        }

        // Filter by access mode before collapsing overloads so static and instance members do not
        // affect each other's displayed overload count.
        if (mode == MemberAccessMode.StaticOnly)
            return CollapseOverloadsForCompletion(items.Where(i => i.IsStatic));
        if (mode == MemberAccessMode.InstanceOnly)
            return CollapseOverloadsForCompletion(items.Where(i => !i.IsStatic));

        return CollapseOverloadsForCompletion(items);
    }

    private static List<MemberCompletionItem> CollapseOverloadsForCompletion(IEnumerable<MemberCompletionItem> members)
    {
        var collapsed = new List<MemberCompletionItem>();

        foreach (var group in members.GroupBy(member => (member.Name, member.Kind, member.IsStatic)))
        {
            if (group.Key.Kind != MemberKind.Method)
            {
                collapsed.Add(group.First());
                continue;
            }

            var overloads = group.ToList();
            var representative = overloads
                .OrderBy(member => member.ParameterCount)
                .ThenBy(member => member.Parameters ?? string.Empty, StringComparer.Ordinal)
                .First();

            collapsed.Add(new MemberCompletionItem
            {
                Name = representative.Name,
                Kind = representative.Kind,
                Type = representative.Type,
                Parameters = representative.Parameters,
                ParameterCount = representative.ParameterCount,
                IsStatic = representative.IsStatic,
                Documentation = representative.Documentation,
                OverloadCount = overloads.Count
            });
        }

        return collapsed;
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

    /// <summary>
    /// Get all types from loaded assemblies (for import suggestions)
    /// </summary>
    public Dictionary<string, string> GetAllTypes()
    {
        EnsureAssembliesLoaded();

        var types = new Dictionary<string, string>();

        foreach (var assembly in _loadedAssemblies)
        {
            try
            {
                // CRITICAL FIX: Skip System.Private.CoreLib to avoid massive performance hit
                var assemblyName = assembly.GetName().Name;
                if (assemblyName == "System.Private.CoreLib")
                {
                    // Skip - too many types, causes hangs
                    continue;
                }

                // Use cached exported types
                if (!_exportedTypesCache.TryGetValue(assembly, out var exportedTypes))
                {
                    try
                    {
                        // Add a mark to prevent re-entry
                        _exportedTypesCache[assembly] = Array.Empty<Type>();

                        exportedTypes = assembly.GetExportedTypes();
                        _exportedTypesCache[assembly] = exportedTypes;
                    }
                    catch (Exception ex)
                    {
                        _logger.LogDebug(ex, "Could not get exported types for {Assembly}", assemblyName);
                        exportedTypes = Array.Empty<Type>();
                    }
                }

                foreach (var type in exportedTypes)
                {
                    if (!types.ContainsKey(type.Name) && type.IsPublic)
                    {
                        types[type.Name] = type.Namespace ?? "";
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "Error enumerating types in {Assembly}",
                    assembly.GetName().Name);
            }
        }

        return types;
    }
}

/// <summary>
/// Represents a member for completion
/// </summary>
public class MemberCompletionItem
{
    public required string Name { get; init; }
    public required MemberKind Kind { get; init; }
    public required string Type { get; init; }
    public string? Parameters { get; init; }
    public int ParameterCount { get; init; }
    public bool IsStatic { get; init; }
    public string? Documentation { get; init; }
    public int OverloadCount { get; init; } = 1;
}

/// <summary>
/// Kind of member
/// </summary>
public enum MemberKind
{
    Method,
    Property,
    Field,
    Event
}

/// <summary>
/// Controls which members to return based on static/instance access
/// </summary>
public enum MemberAccessMode
{
    All,
    StaticOnly,
    InstanceOnly
}
