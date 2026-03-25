using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
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
    private static readonly string[] PreferredNamespaces =
    {
        "System",
        "System.Collections",
        "System.Collections.Generic",
        "System.IO",
        "System.Linq",
        "System.Net",
        "System.Net.Http",
        "System.Text",
        "System.Text.Json",
        "System.Text.RegularExpressions",
        "System.Threading",
        "System.Threading.Tasks"
    };

    private readonly Dictionary<string, XDocument> _loadedDocs = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, Dictionary<string, XElement>> _docIndexes = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, XElement> _globalDocIndex = new(StringComparer.Ordinal);
    private readonly List<Assembly> _assemblies = new();
    private readonly Dictionary<string, Type> _typeCache = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, List<Type>> _typesBySimpleName = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, List<Type>> _typesByQualifiedName = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _loadedAssemblyNames = new(StringComparer.OrdinalIgnoreCase);
    private List<string>? _referencePackDirectories;
    private bool _globalDocIndexLoaded;

    /// <summary>
    /// Load system assemblies for type resolution.
    /// </summary>
    public void LoadSystemAssemblies()
    {
        AddAssembly(typeof(object).Assembly);
        AddAssembly(typeof(Console).Assembly);
        AddAssembly(typeof(Enumerable).Assembly);
        AddAssembly(typeof(List<>).Assembly);
        AddAssembly(typeof(File).Assembly);
        AddAssembly(typeof(System.Threading.Tasks.Task).Assembly);
        AddAssembly(typeof(System.Text.RegularExpressions.Regex).Assembly);
        AddAssembly(typeof(System.Net.Http.HttpClient).Assembly);
        AddAssembly(typeof(System.Text.Json.JsonSerializer).Assembly);

        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies().Where(a => !a.IsDynamic))
        {
            AddAssembly(assembly);
        }

        foreach (var assemblyName in DiscoverReferencePackAssemblyNames())
        {
            try
            {
                AddAssembly(Assembly.Load(new AssemblyName(assemblyName)));
            }
            catch
            {
                // Some ref-pack assemblies are not available at runtime. Skip them.
            }
        }
    }

    /// <summary>
    /// Look up documentation for a type or member by name.
    /// Supports: "Console", "System.Console", "Console.WriteLine", "List", "Dictionary"
    /// </summary>
    public DocResult? Lookup(string query)
    {
        if (string.IsNullOrWhiteSpace(query)) return null;

        var exactType = ResolveType(query);
        if (exactType != null)
        {
            return DescribeType(exactType);
        }

        var parts = query.Split('.');
        if (parts.Length < 2)
        {
            return null;
        }

        for (int i = parts.Length - 1; i >= 1; i--)
        {
            var typeCandidate = string.Join(".", parts.Take(i));
            var remainder = parts.Skip(i).ToArray();
            var type = ResolveType(typeCandidate);
            if (type == null) continue;

            var nestedType = ResolveNestedTypeChain(type, remainder);
            if (nestedType != null)
            {
                return DescribeType(nestedType);
            }

            if (remainder.Length > 1)
            {
                var containingType = ResolveNestedTypeChain(type, remainder.Take(remainder.Length - 1));
                if (containingType != null)
                {
                    return LookupMember(containingType, remainder[^1]);
                }
            }

            return LookupMember(type, remainder[0]);
        }

        return null;
    }

    private DocResult DescribeType(Type type)
    {
        var summary = GetTypeSummary(type);
        var members = GetTypeMembers(type);
        var baseTypes = GetBaseTypes(type);

        return new DocResult(
            Name: StripGenericArity(type.Name),
            FullName: FormatQualifiedType(type),
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
        var nestedType = type.GetNestedTypes(BindingFlags.Public)
            .FirstOrDefault(t => StripGenericArity(t.Name).Equals(memberName, StringComparison.OrdinalIgnoreCase));
        if (nestedType != null)
        {
            return DescribeType(nestedType);
        }

        var constructors = type.GetConstructors(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static)
            .Where(c =>
                memberName.Equals("#ctor", StringComparison.OrdinalIgnoreCase) ||
                memberName.Equals("ctor", StringComparison.OrdinalIgnoreCase) ||
                StripGenericArity(type.Name).Equals(memberName, StringComparison.OrdinalIgnoreCase))
            .ToArray();

        if (constructors.Length > 0)
        {
            var overloads = constructors.Select(c => new DocMemberResult(
                Name: FormatMethodSignature(c),
                Kind: "constructor",
                Type: null,
                Summary: GetMethodSummary(c),
                Parameters: FormatParameters(c)
            )).ToArray();

            return new DocResult(
                Name: StripGenericArity(type.Name),
                FullName: FormatQualifiedType(type),
                Kind: constructors.Length == 1 ? "constructor" : $"constructor ({constructors.Length} overloads)",
                Summary: GetMethodSummary(constructors[0]),
                Namespace: type.Namespace,
                Members: overloads,
                Parameters: constructors[0].GetParameters().Select(p => new DocParameterResult(
                    p.Name ?? "?", FormatType(p.ParameterType), GetParameterSummary(constructors[0], p.Name)
                )).ToArray(),
                ReturnType: null,
                ReturnDoc: null,
                BaseTypes: null);
        }

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
                FullName: $"{FormatQualifiedType(type)}.{memberName}",
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
                FullName: $"{FormatQualifiedType(type)}.{prop.Name}",
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
                FullName: $"{FormatQualifiedType(type)}.{field.Name}",
                Kind: "field",
                Summary: GetFieldSummary(field),
                Namespace: type.Namespace,
                Members: null,
                Parameters: null,
                ReturnType: FormatType(field.FieldType),
                ReturnDoc: null,
                BaseTypes: null);
        }

        var evt = type.GetEvent(memberName,
            BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance | BindingFlags.IgnoreCase);
        if (evt != null)
        {
            return new DocResult(
                Name: evt.Name,
                FullName: $"{FormatQualifiedType(type)}.{evt.Name}",
                Kind: "event",
                Summary: GetEventSummary(evt),
                Namespace: type.Namespace,
                Members: null,
                Parameters: null,
                ReturnType: evt.EventHandlerType != null ? FormatType(evt.EventHandlerType) : null,
                ReturnDoc: null,
                BaseTypes: null);
        }

        return null;
    }

    private Type? ResolveType(string name)
    {
        if (_typeCache.TryGetValue(name, out var cached))
            return cached;

        var strippedName = StripGenericArity(name);

        if (_typesByQualifiedName.TryGetValue(name, out var exactMatches) && exactMatches.Count > 0)
        {
            return CacheType(name, SelectBestType(name, exactMatches));
        }

        if (_typesByQualifiedName.TryGetValue(strippedName, out var strippedMatches) && strippedMatches.Count > 0)
        {
            return CacheType(name, SelectBestType(name, strippedMatches));
        }

        if (strippedName.Contains('.'))
        {
            var suffixMatches = _typesByQualifiedName
                .Where(kvp => kvp.Key.EndsWith($".{strippedName}", StringComparison.OrdinalIgnoreCase))
                .SelectMany(kvp => kvp.Value)
                .Distinct()
                .ToList();

            if (suffixMatches.Count > 0)
            {
                return CacheType(name, SelectBestType(name, suffixMatches));
            }
        }

        var shortName = StripGenericArity(strippedName.Split('.').Last());
        if (_typesBySimpleName.TryGetValue(shortName, out var simpleMatches) && simpleMatches.Count > 0)
        {
            return CacheType(name, SelectBestType(name, simpleMatches));
        }

        return null;
    }

    // ── XML Doc Helpers ──────────────────────────────────────────────────

    private string? GetTypeSummary(Type type) =>
        GetDocSummary(type.Assembly, $"T:{type.FullName?.Replace('+', '.')}");

    private string? GetMethodSummary(MethodBase method) =>
        GetDocSummary(method.DeclaringType?.Assembly, GetMethodDocId(method));

    private string? GetPropertySummary(PropertyInfo prop) =>
        GetDocSummary(prop.DeclaringType?.Assembly, $"P:{prop.DeclaringType?.FullName?.Replace('+', '.')}.{prop.Name}");

    private string? GetFieldSummary(FieldInfo field) =>
        GetDocSummary(field.DeclaringType?.Assembly, $"F:{field.DeclaringType?.FullName?.Replace('+', '.')}.{field.Name}");

    private string? GetEventSummary(EventInfo evt) =>
        GetDocSummary(evt.DeclaringType?.Assembly, $"E:{evt.DeclaringType?.FullName?.Replace('+', '.')}.{evt.Name}");

    private string? GetParameterSummary(MethodBase method, string? paramName)
    {
        if (paramName == null) return null;
        var element = GetDocElement(method.DeclaringType?.Assembly, GetMethodDocId(method));
        return element?.Elements("param")
            .FirstOrDefault(p => p.Attribute("name")?.Value == paramName)
            ?.Value.Trim();
    }

    private string? GetReturnsSummary(MethodInfo method)
    {
        var element = GetDocElement(method.DeclaringType?.Assembly, GetMethodDocId(method));
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

        EnsureGlobalDocIndex();
        if (_globalDocIndex.TryGetValue(docId, out var globalElement))
        {
            return globalElement;
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
            var xmlPath = GetXmlDocPath(assembly);
            if (!File.Exists(xmlPath)) return;

            var doc = XDocument.Load(xmlPath);
            _loadedDocs[assemblyName] = doc;
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

        foreach (var nestedType in type.GetNestedTypes(BindingFlags.Public))
        {
            results.Add(new DocMemberResult(
                StripGenericArity(nestedType.Name),
                "nested type",
                FormatQualifiedType(nestedType),
                GetTypeSummary(nestedType),
                null));
        }

        foreach (var ctor in type.GetConstructors(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly))
        {
            results.Add(new DocMemberResult(
                FormatMethodSignature(ctor),
                "constructor",
                null,
                GetMethodSummary(ctor),
                FormatParameters(ctor)));
        }

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

        foreach (var evt in type.GetEvents(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly))
        {
            results.Add(new DocMemberResult(evt.Name, "event",
                evt.EventHandlerType != null ? FormatType(evt.EventHandlerType) : null,
                GetEventSummary(evt), null));
        }

        return results
            .OrderBy(r => r.Kind)
            .ThenBy(r => r.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
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
        if (type.IsGenericParameter) return type.Name;
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

        return StripGenericArity(type.Name);
    }

    private static string FormatMethodSignature(MethodBase method)
    {
        var parameters = method.GetParameters();
        var paramStr = string.Join(", ", parameters.Select(p => $"{FormatType(p.ParameterType)} {p.Name}"));
        var name = method is ConstructorInfo && method.DeclaringType != null
            ? StripGenericArity(method.DeclaringType.Name)
            : method.Name;
        return $"{name}({paramStr})";
    }

    private static string FormatParameters(MethodBase method)
    {
        var parameters = method.GetParameters();
        return $"({string.Join(", ", parameters.Select(p => $"{p.Name}: {FormatType(p.ParameterType)}"))})";
    }

    private static string FormatTypeForDocId(Type type)
    {
        if (type.IsByRef)
            return $"{FormatTypeForDocId(type.GetElementType()!)}@";

        if (type.IsPointer)
            return $"{FormatTypeForDocId(type.GetElementType()!)}*";

        if (type.IsArray)
        {
            var elementType = FormatTypeForDocId(type.GetElementType()!);
            if (type.GetArrayRank() == 1) return $"{elementType}[]";

            var bounds = string.Join(",", Enumerable.Repeat("0:", type.GetArrayRank()));
            return $"{elementType}[{bounds}]";
        }

        if (type.IsGenericParameter)
        {
            var prefix = type.DeclaringMethod != null ? "``" : "`";
            return $"{prefix}{type.GenericParameterPosition}";
        }

        if (type.IsGenericType)
        {
            var genericType = type.IsGenericTypeDefinition ? type : type.GetGenericTypeDefinition();
            var typeName = genericType.FullName?.Replace('+', '.');
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

    private void AddAssembly(Assembly assembly)
    {
        var assemblyName = assembly.GetName().Name ?? assembly.FullName;
        if (string.IsNullOrWhiteSpace(assemblyName) || !_loadedAssemblyNames.Add(assemblyName))
        {
            return;
        }

        _assemblies.Add(assembly);

        foreach (var type in GetPublicTypes(assembly))
        {
            AddTypeIndex(_typesBySimpleName, StripGenericArity(type.Name), type);
            AddTypeIndex(_typesByQualifiedName, GetLookupTypeName(type), type);

            var fullName = type.FullName?.Replace('+', '.');
            if (!string.IsNullOrWhiteSpace(fullName))
            {
                AddTypeIndex(_typesByQualifiedName, fullName, type);
            }
        }
    }

    private static IEnumerable<Type> GetPublicTypes(Assembly assembly)
    {
        try
        {
            return assembly.GetTypes().Where(t => t.IsPublic || t.IsNestedPublic);
        }
        catch (ReflectionTypeLoadException ex)
        {
            return ex.Types.Where(t => t != null && (t.IsPublic || t.IsNestedPublic)).Cast<Type>();
        }
        catch
        {
            return Array.Empty<Type>();
        }
    }

    private static void AddTypeIndex(Dictionary<string, List<Type>> index, string key, Type type)
    {
        if (!index.TryGetValue(key, out var list))
        {
            list = new List<Type>();
            index[key] = list;
        }

        if (!list.Contains(type))
        {
            list.Add(type);
        }
    }

    private Type? CacheType(string name, Type? type)
    {
        if (type != null)
        {
            _typeCache[name] = type;
        }

        return type;
    }

    private static Type? ResolveNestedTypeChain(Type type, IEnumerable<string> parts)
    {
        var current = type;
        foreach (var part in parts)
        {
            var next = current.GetNestedTypes(BindingFlags.Public)
                .FirstOrDefault(t => StripGenericArity(t.Name).Equals(part, StringComparison.OrdinalIgnoreCase));

            if (next == null)
            {
                return null;
            }

            current = next;
        }

        return current;
    }

    private static Type? SelectBestType(string query, IEnumerable<Type> candidates)
    {
        return candidates
            .Distinct()
            .OrderByDescending(t => ScoreTypeMatch(query, t))
            .ThenBy(t => t.Namespace?.Length ?? int.MaxValue)
            .ThenBy(t => t.FullName, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();
    }

    private static int ScoreTypeMatch(string query, Type type)
    {
        var score = 0;
        var strippedQuery = StripGenericArity(query);
        var qualifiedName = GetLookupTypeName(type);
        var simpleName = StripGenericArity(type.Name);

        if (qualifiedName.Equals(strippedQuery, StringComparison.OrdinalIgnoreCase))
        {
            score += 1000;
        }

        if (qualifiedName.EndsWith($".{strippedQuery}", StringComparison.OrdinalIgnoreCase))
        {
            score += 400;
        }

        if (simpleName.Equals(strippedQuery.Split('.').Last(), StringComparison.OrdinalIgnoreCase))
        {
            score += 250;
        }

        var queryNamespace = GetQueryNamespace(strippedQuery);
        if (queryNamespace != null &&
            type.Namespace?.EndsWith(queryNamespace, StringComparison.OrdinalIgnoreCase) == true)
        {
            score += 300;
        }

        score += GetNamespacePriority(type.Namespace);

        if (!type.IsNested)
        {
            score += 10;
        }

        return score;
    }

    private static int GetNamespacePriority(string? ns)
    {
        if (string.IsNullOrWhiteSpace(ns)) return 0;

        for (int i = 0; i < PreferredNamespaces.Length; i++)
        {
            if (ns.Equals(PreferredNamespaces[i], StringComparison.OrdinalIgnoreCase))
            {
                return 200 - i;
            }
        }

        if (ns.Equals("System", StringComparison.OrdinalIgnoreCase) ||
            ns.StartsWith("System.", StringComparison.OrdinalIgnoreCase))
        {
            return 120;
        }

        if (ns.Equals("Microsoft", StringComparison.OrdinalIgnoreCase) ||
            ns.StartsWith("Microsoft.", StringComparison.OrdinalIgnoreCase))
        {
            return 60;
        }

        return 10;
    }

    private static string? GetQueryNamespace(string query)
    {
        var lastDot = query.LastIndexOf('.');
        return lastDot > 0 ? query[..lastDot] : null;
    }

    private static string GetLookupTypeName(Type type)
    {
        var fullName = type.FullName?.Replace('+', '.') ?? type.Name;
        return StripGenericArity(fullName);
    }

    private static string GetMethodDocId(MethodBase method)
    {
        var typePrefix = method.DeclaringType?.FullName?.Replace('+', '.');
        var memberName = method is ConstructorInfo ? "#ctor" : method.Name;
        var parameters = method.GetParameters();
        var parameterList = parameters.Length > 0
            ? $"({string.Join(",", parameters.Select(p => FormatTypeForDocId(p.ParameterType)))})"
            : "";
        return $"M:{typePrefix}.{memberName}{parameterList}";
    }

    private string GetXmlDocPath(Assembly assembly)
    {
        var assemblyLocation = assembly.Location;
        var assemblyName = assembly.GetName().Name ?? Path.GetFileNameWithoutExtension(assemblyLocation);

        if (!string.IsNullOrWhiteSpace(assemblyLocation))
        {
            var adjacentXml = Path.ChangeExtension(assemblyLocation, ".xml");
            if (File.Exists(adjacentXml)) return adjacentXml;

            var assemblyDir = Path.GetDirectoryName(assemblyLocation);
            if (!string.IsNullOrWhiteSpace(assemblyDir))
            {
                var refXml = Path.Combine(assemblyDir, "ref", $"{assemblyName}.xml");
                if (File.Exists(refXml)) return refXml;
            }
        }

        foreach (var refDir in GetReferencePackDirectories())
        {
            var candidate = Path.Combine(refDir, $"{assemblyName}.xml");
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return string.Empty;
    }

    private void EnsureGlobalDocIndex()
    {
        if (_globalDocIndexLoaded)
        {
            return;
        }

        _globalDocIndexLoaded = true;

        foreach (var refDir in GetReferencePackDirectories())
        {
            IEnumerable<string> xmlFiles;
            try
            {
                xmlFiles = Directory.EnumerateFiles(refDir, "*.xml");
            }
            catch
            {
                continue;
            }

            foreach (var xmlFile in xmlFiles)
            {
                try
                {
                    var doc = XDocument.Load(xmlFile);
                    var members = doc.Root?.Element("members")?.Elements("member");
                    if (members == null) continue;

                    foreach (var member in members)
                    {
                        var name = member.Attribute("name")?.Value;
                        if (!string.IsNullOrWhiteSpace(name) && !_globalDocIndex.ContainsKey(name))
                        {
                            _globalDocIndex[name] = member;
                        }
                    }
                }
                catch
                {
                    // Ignore malformed or unreadable XML docs and keep building the index.
                }
            }
        }
    }

    private IEnumerable<string> DiscoverReferencePackAssemblyNames()
    {
        return GetReferencePackDirectories()
            .SelectMany(dir =>
            {
                try { return Directory.EnumerateFiles(dir, "*.dll"); }
                catch { return Array.Empty<string>(); }
            })
            .Select(Path.GetFileNameWithoutExtension)
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Cast<string>();
    }

    private IEnumerable<string> GetReferencePackDirectories()
    {
        if (_referencePackDirectories != null)
        {
            return _referencePackDirectories;
        }

        var roots = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        AddDotNetRootCandidate(roots, typeof(object).Assembly.Location);
        AddDotNetRootCandidate(roots, typeof(Console).Assembly.Location);

        var dotnetRoot = Environment.GetEnvironmentVariable("DOTNET_ROOT");
        if (!string.IsNullOrWhiteSpace(dotnetRoot))
        {
            roots.Add(dotnetRoot);
        }

        var directories = new List<string>();
        foreach (var root in roots)
        {
            var packsDir = Path.Combine(root, "packs");
            if (!Directory.Exists(packsDir)) continue;

            try
            {
                foreach (var packDir in Directory.EnumerateDirectories(packsDir, "*.Ref"))
                {
                    foreach (var versionDir in Directory.EnumerateDirectories(packDir).OrderByDescending(Path.GetFileName))
                    {
                        var refRoot = Path.Combine(versionDir, "ref");
                        if (!Directory.Exists(refRoot)) continue;

                        foreach (var tfmDir in Directory.EnumerateDirectories(refRoot).OrderByDescending(Path.GetFileName))
                        {
                            directories.Add(tfmDir);
                        }
                    }
                }
            }
            catch
            {
                // Ignore broken SDK layouts and keep searching other roots.
            }
        }

        _referencePackDirectories = directories
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        return _referencePackDirectories;
    }

    private static void AddDotNetRootCandidate(HashSet<string> roots, string? assemblyLocation)
    {
        if (string.IsNullOrWhiteSpace(assemblyLocation))
        {
            return;
        }

        var dir = new DirectoryInfo(Path.GetDirectoryName(assemblyLocation)!);
        while (dir != null)
        {
            if (Directory.Exists(Path.Combine(dir.FullName, "packs")) &&
                Directory.Exists(Path.Combine(dir.FullName, "shared")))
            {
                roots.Add(dir.FullName);
                return;
            }

            dir = dir.Parent;
        }
    }

    private static string FormatQualifiedType(Type type)
    {
        if (type.IsGenericParameter) return type.Name;

        if (type.IsNested && type.DeclaringType != null)
        {
            return $"{FormatQualifiedType(type.DeclaringType)}.{FormatTypeName(type)}";
        }

        var prefix = string.IsNullOrWhiteSpace(type.Namespace) ? "" : $"{type.Namespace}.";
        return $"{prefix}{FormatTypeName(type)}";
    }

    private static string FormatTypeName(Type type)
    {
        var name = StripGenericArity(type.Name);
        if (!type.IsGenericType)
        {
            return name;
        }

        var args = type.GetGenericArguments();
        var formattedArgs = type.IsGenericTypeDefinition
            ? args.Select(a => a.Name)
            : args.Select(FormatType);

        return $"{name}<{string.Join(", ", formattedArgs)}>";
    }

    private static string StripGenericArity(string name)
    {
        if (name.IndexOf('`') < 0) return name;

        var sb = new StringBuilder(name.Length);
        for (int i = 0; i < name.Length; i++)
        {
            if (name[i] == '`')
            {
                i++;
                while (i < name.Length && char.IsDigit(name[i]))
                {
                    i++;
                }

                i--;
                continue;
            }

            sb.Append(name[i]);
        }

        return sb.ToString();
    }
}
