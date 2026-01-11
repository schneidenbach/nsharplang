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
    /// Get all public members of a type
    /// </summary>
    public List<MemberCompletionItem> GetMembers(Type type, bool includeStatic = true)
    {
        var items = new List<MemberCompletionItem>();

        try
        {
            var bindingFlags = BindingFlags.Public | BindingFlags.Instance;
            if (includeStatic)
            {
                bindingFlags |= BindingFlags.Static;
            }

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

        return items;
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
    public bool IsStatic { get; init; }
    public string? Documentation { get; init; }
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
