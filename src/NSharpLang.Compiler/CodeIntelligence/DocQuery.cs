using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Xml.Linq;

namespace NSharpLang.Compiler.CodeIntelligence;

/// <summary>
/// Result of a documentation query.
/// </summary>
public record DocResult(
    string Name,
    string FullName,
    string Kind,
    string? Summary,
    string? Namespace,
    DocMemberResult[]? Members,
    DocParameterResult[]? Parameters,
    string? ReturnType,
    string? ReturnDoc,
    string[]? BaseTypes);

public record DocMemberResult(
    string Name,
    string Kind,
    string? Type,
    string? Summary,
    string? Parameters);

public record DocParameterResult(
    string Name,
    string Type,
    string? Summary);

/// <summary>
/// Queries .NET XML documentation for types and members.
/// Standalone — no DI, no ILogger. Used by the CLI's `nlc query doc` command.
///
/// Usage:
///   var query = new DocQuery();
///   query.LoadSystemAssemblies();
///   var result = query.Lookup("Console");              // → System.Console
///   var result = query.Lookup("Console.WriteLine");    // → System.Console.WriteLine overloads
///   var result = query.Lookup("System.Console");       // → exact match
///   var result = query.Lookup("List");                 // → System.Collections.Generic.List<T>
/// </summary>
public class DocQuery
{
    private readonly Dictionary<string, XDocument> _loadedDocs = new();
    private readonly Dictionary<string, Dictionary<string, XElement>> _docIndexes = new();
    private readonly List<Assembly> _assemblies = new();
    private readonly Dictionary<string, Type> _typeCache = new();

    /// <summary>
    /// Load system assemblies for type resolution.
    /// </summary>
    public void LoadSystemAssemblies()
    {
        var coreLib = typeof(object).Assembly;
        var consoleAssembly = typeof(Console).Assembly;
        var linqAssembly = typeof(Enumerable).Assembly;
        var collectionsAssembly = typeof(List<>).Assembly;
        var ioAssembly = typeof(File).Assembly;
        var taskAssembly = typeof(System.Threading.Tasks.Task).Assembly;

        _assemblies.AddRange(new[] { coreLib, consoleAssembly, linqAssembly, collectionsAssembly, ioAssembly, taskAssembly });

        // Deduplicate
        var seen = new HashSet<string>();
        _assemblies.RemoveAll(a => !seen.Add(a.FullName ?? ""));
    }

    /// <summary>
    /// Look up documentation for a type or member by name.
    /// Supports: "Console", "System.Console", "Console.WriteLine", "List", "Dictionary"
    /// </summary>
    public DocResult? Lookup(string query)
    {
        if (string.IsNullOrWhiteSpace(query)) return null;

        // Split on dot to see if it's "Type.Member" or just "Type"
        var parts = query.Split('.');
        string typeName;
        string? memberName = null;

        if (parts.Length >= 2)
        {
            // Could be "System.Console" (namespace.type) or "Console.WriteLine" (type.member)
            // Try type.member first
            var possibleType = parts[0];
            var possibleMember = string.Join(".", parts.Skip(1));

            var type = ResolveType(possibleType);
            if (type != null)
            {
                // It's Type.Member
                typeName = possibleType;
                memberName = possibleMember;
                return LookupMember(type, memberName);
            }

            // Try as fully qualified type name
            type = ResolveType(query);
            if (type != null)
            {
                return DescribeType(type);
            }

            // Try progressively longer type names
            for (int i = parts.Length - 1; i >= 1; i--)
            {
                var tryType = string.Join(".", parts.Take(i));
                var tryMember = string.Join(".", parts.Skip(i));
                type = ResolveType(tryType);
                if (type != null)
                {
                    return LookupMember(type, tryMember);
                }
            }

            return null;
        }

        // Single name — look up type
        typeName = parts[0];
        var resolved = ResolveType(typeName);
        return resolved != null ? DescribeType(resolved) : null;
    }

    private DocResult DescribeType(Type type)
    {
        var summary = GetTypeSummary(type);
        var members = GetTypeMembers(type);
        var baseTypes = GetBaseTypes(type);

        return new DocResult(
            Name: type.Name.Split('`')[0],
            FullName: type.FullName ?? type.Name,
            Kind: GetTypeKind(type),
            Summary: summary,
            Namespace: type.Namespace,
            Members: members,
            Parameters: null,
            ReturnType: null,
            ReturnDoc: null,
            BaseTypes: baseTypes);
    }

    private DocResult? LookupMember(Type type, string memberName)
    {
        // Look for methods
        var methods = type.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance)
            .Where(m => m.Name.Equals(memberName, StringComparison.OrdinalIgnoreCase) && !m.IsSpecialName)
            .ToArray();

        if (methods.Length > 0)
        {
            // Return all overloads
            var overloads = methods.Select(m => new DocMemberResult(
                Name: FormatMethodSignature(m),
                Kind: "method",
                Type: FormatType(m.ReturnType),
                Summary: GetMethodSummary(m),
                Parameters: FormatParameters(m)
            )).ToArray();

            var firstDoc = GetMethodSummary(methods[0]);

            return new DocResult(
                Name: memberName,
                FullName: $"{type.FullName}.{memberName}",
                Kind: methods.Length == 1 ? "method" : $"method ({methods.Length} overloads)",
                Summary: firstDoc,
                Namespace: type.Namespace,
                Members: overloads,
                Parameters: methods[0].GetParameters().Select(p => new DocParameterResult(
                    p.Name ?? "?", FormatType(p.ParameterType), GetParameterSummary(methods[0], p.Name)
                )).ToArray(),
                ReturnType: FormatType(methods[0].ReturnType),
                ReturnDoc: GetReturnsSummary(methods[0]),
                BaseTypes: null);
        }

        // Look for properties
        var prop = type.GetProperty(memberName,
            BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance | BindingFlags.IgnoreCase);
        if (prop != null)
        {
            return new DocResult(
                Name: prop.Name,
                FullName: $"{type.FullName}.{prop.Name}",
                Kind: "property",
                Summary: GetPropertySummary(prop),
                Namespace: type.Namespace,
                Members: null,
                Parameters: null,
                ReturnType: FormatType(prop.PropertyType),
                ReturnDoc: null,
                BaseTypes: null);
        }

        // Look for fields
        var field = type.GetField(memberName,
            BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance | BindingFlags.IgnoreCase);
        if (field != null)
        {
            return new DocResult(
                Name: field.Name,
                FullName: $"{type.FullName}.{field.Name}",
                Kind: "field",
                Summary: GetFieldSummary(field),
                Namespace: type.Namespace,
                Members: null,
                Parameters: null,
                ReturnType: FormatType(field.FieldType),
                ReturnDoc: null,
                BaseTypes: null);
        }

        return null;
    }

    private Type? ResolveType(string name)
    {
        if (_typeCache.TryGetValue(name, out var cached))
            return cached;

        // Collect all candidates, prefer System.* namespace
        Type? bestMatch = null;

        foreach (var assembly in _assemblies)
        {
            Type[] types;
            try { types = assembly.GetExportedTypes(); }
            catch { continue; }

            foreach (var type in types)
            {
                var shortName = type.Name.Split('`')[0];

                // Exact full name match — always wins
                if (type.FullName?.Equals(name, StringComparison.OrdinalIgnoreCase) ?? false)
                {
                    _typeCache[name] = type;
                    return type;
                }

                // Short name match
                if (shortName.Equals(name, StringComparison.OrdinalIgnoreCase))
                {
                    // Prefer System.* types over internal/private types
                    if (bestMatch == null ||
                        (type.Namespace?.StartsWith("System") == true && bestMatch.Namespace?.StartsWith("System") != true))
                    {
                        bestMatch = type;
                    }
                }
            }
        }

        if (bestMatch != null)
        {
            _typeCache[name] = bestMatch;
        }

        return bestMatch;
    }

    // ── XML Doc Helpers ──────────────────────────────────────────────────

    private string? GetTypeSummary(Type type) =>
        GetDocSummary(type.Assembly, $"T:{type.FullName?.Replace('+', '.')}");

    private string? GetMethodSummary(MethodInfo method)
    {
        var typePrefix = method.DeclaringType?.FullName?.Replace('+', '.');
        var parameters = method.GetParameters();
        var paramString = parameters.Length > 0
            ? $"({string.Join(",", parameters.Select(p => FormatTypeForDocId(p.ParameterType)))})"
            : "";
        return GetDocSummary(method.DeclaringType?.Assembly, $"M:{typePrefix}.{method.Name}{paramString}");
    }

    private string? GetPropertySummary(PropertyInfo prop) =>
        GetDocSummary(prop.DeclaringType?.Assembly, $"P:{prop.DeclaringType?.FullName?.Replace('+', '.')}.{prop.Name}");

    private string? GetFieldSummary(FieldInfo field) =>
        GetDocSummary(field.DeclaringType?.Assembly, $"F:{field.DeclaringType?.FullName?.Replace('+', '.')}.{field.Name}");

    private string? GetParameterSummary(MethodInfo method, string? paramName)
    {
        if (paramName == null) return null;
        var element = GetDocElement(method.DeclaringType?.Assembly,
            $"M:{method.DeclaringType?.FullName?.Replace('+', '.')}.{method.Name}");
        return element?.Elements("param")
            .FirstOrDefault(p => p.Attribute("name")?.Value == paramName)
            ?.Value.Trim();
    }

    private string? GetReturnsSummary(MethodInfo method)
    {
        var element = GetDocElement(method.DeclaringType?.Assembly,
            $"M:{method.DeclaringType?.FullName?.Replace('+', '.')}.{method.Name}");
        return element?.Element("returns")?.Value.Trim();
    }

    private string? GetDocSummary(Assembly? assembly, string docId)
    {
        var element = GetDocElement(assembly, docId);
        return element?.Element("summary")?.Value.Trim();
    }

    private XElement? GetDocElement(Assembly? assembly, string docId)
    {
        if (assembly == null) return null;

        var assemblyName = assembly.GetName().Name;
        if (assemblyName == null) return null;

        // Load XML doc if needed
        if (!_docIndexes.ContainsKey(assemblyName))
        {
            LoadXmlDoc(assembly);
        }

        if (_docIndexes.TryGetValue(assemblyName, out var index) &&
            index.TryGetValue(docId, out var element))
        {
            return element;
        }

        return null;
    }

    private void LoadXmlDoc(Assembly assembly)
    {
        var assemblyName = assembly.GetName().Name;
        if (assemblyName == null || _docIndexes.ContainsKey(assemblyName)) return;

        var index = new Dictionary<string, XElement>();
        _docIndexes[assemblyName] = index;

        try
        {
            var assemblyLocation = assembly.Location;
            if (string.IsNullOrEmpty(assemblyLocation)) return;

            var xmlPath = Path.ChangeExtension(assemblyLocation, ".xml");
            if (!File.Exists(xmlPath))
            {
                // Try ref/ subdirectory
                xmlPath = Path.Combine(Path.GetDirectoryName(assemblyLocation)!, "ref",
                    Path.GetFileName(Path.ChangeExtension(assemblyLocation, ".xml")));
            }

            if (!File.Exists(xmlPath)) return;

            var doc = XDocument.Load(xmlPath);
            var members = doc.Root?.Element("members")?.Elements("member");
            if (members == null) return;

            foreach (var member in members)
            {
                var name = member.Attribute("name")?.Value;
                if (name != null) index[name] = member;
            }
        }
        catch { /* graceful degradation — no docs is fine */ }
    }

    // ── Type Formatting ──────────────────────────────────────────────────

    private DocMemberResult[] GetTypeMembers(Type type)
    {
        var results = new List<DocMemberResult>();

        // Properties
        foreach (var prop in type.GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly))
        {
            results.Add(new DocMemberResult(prop.Name, "property", FormatType(prop.PropertyType),
                GetPropertySummary(prop), null));
        }

        // Methods (exclude special names like get_/set_)
        foreach (var method in type.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)
            .Where(m => !m.IsSpecialName))
        {
            results.Add(new DocMemberResult(method.Name, "method", FormatType(method.ReturnType),
                GetMethodSummary(method), FormatParameters(method)));
        }

        // Fields
        foreach (var field in type.GetFields(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly))
        {
            results.Add(new DocMemberResult(field.Name, "field", FormatType(field.FieldType),
                GetFieldSummary(field), null));
        }

        return results.ToArray();
    }

    private string[] GetBaseTypes(Type type)
    {
        var result = new List<string>();
        if (type.BaseType != null && type.BaseType != typeof(object) && type.BaseType != typeof(ValueType))
            result.Add(FormatType(type.BaseType));
        foreach (var iface in type.GetInterfaces())
            result.Add(FormatType(iface));
        return result.ToArray();
    }

    private static string FormatType(Type type)
    {
        if (type == typeof(void)) return "void";
        if (type == typeof(int)) return "int";
        if (type == typeof(long)) return "long";
        if (type == typeof(float)) return "float";
        if (type == typeof(double)) return "double";
        if (type == typeof(bool)) return "bool";
        if (type == typeof(string)) return "string";
        if (type == typeof(char)) return "char";
        if (type == typeof(byte)) return "byte";
        if (type == typeof(object)) return "object";

        if (type.IsGenericType)
        {
            var name = type.Name.Split('`')[0];
            var args = type.GetGenericArguments();
            return $"{name}<{string.Join(", ", args.Select(FormatType))}>";
        }

        if (type.IsArray)
            return $"{FormatType(type.GetElementType()!)}[]";

        return type.Name;
    }

    private static string FormatMethodSignature(MethodInfo method)
    {
        var parameters = method.GetParameters();
        var paramStr = string.Join(", ", parameters.Select(p => $"{FormatType(p.ParameterType)} {p.Name}"));
        return $"{method.Name}({paramStr})";
    }

    private static string FormatParameters(MethodInfo method)
    {
        var parameters = method.GetParameters();
        return $"({string.Join(", ", parameters.Select(p => $"{p.Name}: {FormatType(p.ParameterType)}"))})";
    }

    private static string FormatTypeForDocId(Type type)
    {
        if (type.IsGenericType)
        {
            var typeName = type.FullName?.Split('`')[0];
            var args = type.GetGenericArguments();
            return $"{typeName}{{{string.Join(",", args.Select(FormatTypeForDocId))}}}";
        }
        return type.FullName?.Replace('+', '.') ?? type.Name;
    }

    private static string GetTypeKind(Type type)
    {
        if (type.IsEnum) return "enum";
        if (type.IsInterface) return "interface";
        if (type.IsValueType) return "struct";
        if (type.IsAbstract && type.IsSealed) return "static class";
        if (type.IsAbstract) return "abstract class";
        return "class";
    }
}
