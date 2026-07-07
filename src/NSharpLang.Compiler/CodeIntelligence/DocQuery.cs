using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Xml.Linq;

namespace NSharpLang.Compiler.CodeIntelligence;

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
        var seedAssemblies = new Assembly[]
        {
            typeof(object).Assembly,
            typeof(Console).Assembly,
            typeof(System.Linq.Enumerable).Assembly,
            typeof(System.Collections.Generic.List<>).Assembly,
            typeof(System.IO.File).Assembly,
            typeof(System.Threading.Tasks.Task).Assembly,
            typeof(System.Text.RegularExpressions.Regex).Assembly,
            typeof(System.Net.Http.HttpClient).Assembly,
            typeof(System.Text.Json.JsonSerializer).Assembly,
        };

        foreach (var assembly in seedAssemblies)
            AddAssembly(assembly);

        foreach (var assembly in ExternalAssemblyScan.Loaded())
            AddAssembly(assembly);

        // Discover additional assemblies from reference packs
        foreach (var asmName in DiscoverReferencePackAssemblyNames())
        {
            AddAssembly(Assembly.Load(asmName));
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

        var splitPlans = DocQueryKernels.GetLookupSplitPlans(query);
        if (splitPlans.Length == 0)
        {
            return null;
        }

        foreach (var splitPlan in splitPlans)
        {
            var type = ResolveType(splitPlan.TypeCandidate);
            if (type == null) continue;

            var nestedType = ResolveNestedTypeChain(type, splitPlan.RemainderParts);
            if (nestedType != null)
            {
                return DescribeType(nestedType);
            }

            if (splitPlan.HasContainingType)
            {
                var containingType = ResolveNestedTypeChain(type, splitPlan.ContainingTypeParts);
                if (containingType != null)
                {
                    return LookupMember(containingType, splitPlan.LastRemainder);
                }
            }

            return LookupMember(type, splitPlan.FirstRemainder);
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
            .FirstOrDefault(t => DocQueryKernels.IsDocMemberNameMatch(t.Name, memberName));
        if (nestedType != null)
        {
            return DescribeType(nestedType);
        }

        var constructors = type.GetConstructors(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static)
            .Where(c => DocQueryKernels.IsConstructorMemberMatch(memberName, type.Name))
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
                Kind: DocQueryKernels.GetOverloadKindText("constructor", constructors.Length),
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
            .Where(m => DocQueryKernels.IsMethodMemberMatch(m.Name, memberName, m.IsSpecialName))
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
                FullName: DocQueryKernels.FormatMemberFullName(FormatQualifiedType(type), memberName),
                Kind: DocQueryKernels.GetOverloadKindText("method", methods.Length),
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
                FullName: DocQueryKernels.FormatMemberFullName(FormatQualifiedType(type), prop.Name),
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
                FullName: DocQueryKernels.FormatMemberFullName(FormatQualifiedType(type), field.Name),
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
                FullName: DocQueryKernels.FormatMemberFullName(FormatQualifiedType(type), evt.Name),
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

        if (DocQueryKernels.ShouldSearchQualifiedSuffix(strippedName))
        {
            var suffixMatches = DeduplicateTypeCandidates(_typesByQualifiedName
                .Where(kvp => DocQueryKernels.IsQualifiedTypeSuffixMatch(kvp.Key, strippedName))
                .SelectMany(kvp => kvp.Value)
                .ToArray());

            if (suffixMatches.Length > 0)
            {
                return CacheType(name, SelectBestType(name, suffixMatches));
            }
        }

        var shortName = DocQueryKernels.GetResolveTypeShortName(strippedName);
        if (_typesBySimpleName.TryGetValue(shortName, out var simpleMatches) && simpleMatches.Count > 0)
        {
            return CacheType(name, SelectBestType(name, simpleMatches));
        }

        return null;
    }

    // ── XML Doc Helpers ──────────────────────────────────────────────────

    private string? GetTypeSummary(Type type) =>
        GetDocSummary(type.Assembly, DocQueryKernels.GetReflectionTypeDocId(type));

    private string? GetMethodSummary(MethodBase method) =>
        GetDocSummary(method.DeclaringType?.Assembly, GetMethodDocId(method));

    private string? GetPropertySummary(PropertyInfo prop) =>
        GetDocSummary(prop.DeclaringType?.Assembly,
            DocQueryKernels.GetDocMemberDocId("P:", prop.DeclaringType?.FullName, prop.Name));

    private string? GetFieldSummary(FieldInfo field) =>
        GetDocSummary(field.DeclaringType?.Assembly,
            DocQueryKernels.GetDocMemberDocId("F:", field.DeclaringType?.FullName, field.Name));

    private string? GetEventSummary(EventInfo evt) =>
        GetDocSummary(evt.DeclaringType?.Assembly,
            DocQueryKernels.GetDocMemberDocId("E:", evt.DeclaringType?.FullName, evt.Name));

    private string? GetParameterSummary(MethodBase method, string? paramName)
    {
        if (paramName == null) return null;
        var element = GetDocElement(method.DeclaringType?.Assembly, GetMethodDocId(method));
        return FormatDocText(element?.Elements("param")
            .FirstOrDefault(p => p.Attribute("name")?.Value == paramName)
        );
    }

    private string? GetReturnsSummary(MethodInfo method)
    {
        var element = GetDocElement(method.DeclaringType?.Assembly, GetMethodDocId(method));
        return FormatDocText(element?.Element("returns"));
    }

    private string? GetDocSummary(Assembly? assembly, string docId)
    {
        var element = GetDocElement(assembly, docId);
        return FormatDocText(element?.Element("summary"));
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

        return DocQueryKernels.OrderDocMembers(results);
    }

    private string[] GetBaseTypes(Type type)
    {
        var baseTypeDisplayName = type.BaseType != null ? FormatType(type.BaseType) : null;
        var interfaceDisplayNames = type.GetInterfaces().Select(FormatType).ToArray();
        return DocQueryKernels.FormatBaseTypeList(
            type.BaseType?.FullName,
            baseTypeDisplayName,
            interfaceDisplayNames);
    }

    private static string FormatType(Type type)
    {
        if (type.IsGenericParameter) return type.Name;
        var builtinName = DocQueryKernels.FormatBuiltinTypeName(type.FullName);
        if (builtinName != null) return builtinName;

        if (type.IsGenericType)
        {
            var formattedArgs = type.GetGenericArguments().Select(FormatType).ToArray();
            return DocQueryKernels.FormatGenericTypeName(type.Name, formattedArgs);
        }

        if (type.IsArray)
            return DocQueryKernels.FormatArrayTypeName(FormatType(type.GetElementType()!));

        return StripGenericArity(type.Name);
    }

    private static string FormatMethodSignature(MethodBase method)
    {
        var parameters = method.GetParameters();
        var parameterNames = parameters.Select(p => p.Name ?? "").ToArray();
        var parameterTypeNames = parameters.Select(p => FormatType(p.ParameterType)).ToArray();
        var name = DocQueryKernels.GetMethodSignatureName(
            method.Name,
            method.DeclaringType?.Name,
            method is ConstructorInfo);
        return DocQueryKernels.FormatMethodSignature(name, parameterNames, parameterTypeNames);
    }

    private static string FormatParameters(MethodBase method)
    {
        var parameters = method.GetParameters();
        var parameterNames = parameters.Select(p => p.Name ?? "").ToArray();
        var parameterTypeNames = parameters.Select(p => FormatType(p.ParameterType)).ToArray();
        return DocQueryKernels.FormatParameterList(parameterNames, parameterTypeNames);
    }

    private static string FormatTypeForDocId(Type type)
    {
        if (type.IsByRef)
            return DocQueryKernels.FormatByRefTypeDocId(FormatTypeForDocId(type.GetElementType()!));

        if (type.IsPointer)
            return DocQueryKernels.FormatPointerTypeDocId(FormatTypeForDocId(type.GetElementType()!));

        if (type.IsArray)
        {
            var elementType = FormatTypeForDocId(type.GetElementType()!);
            return DocQueryKernels.FormatArrayTypeDocId(elementType, type.GetArrayRank());
        }

        if (type.IsGenericParameter)
        {
            return DocQueryKernels.FormatGenericParameterDocId(
                type.DeclaringMethod != null,
                type.GenericParameterPosition);
        }

        if (type.IsGenericType)
        {
            var genericType = type.IsGenericTypeDefinition ? type : type.GetGenericTypeDefinition();
            var parameterTypeDocIds = type.GetGenericArguments().Select(FormatTypeForDocId).ToArray();
            return DocQueryKernels.FormatGenericTypeDocId(genericType.FullName, parameterTypeDocIds);
        }

        return DocQueryKernels.FormatNamedTypeDocId(type.FullName, type.Name);
    }

    private static string GetTypeKind(Type type)
    {
        return DocQueryKernels.GetReflectionTypeKind(
            type.IsEnum,
            type.IsInterface,
            type.IsValueType,
            type.IsAbstract,
            type.IsSealed);
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

            var fullName = DocQueryKernels.GetQualifiedTypeIndexName(type.FullName);
            if (fullName != null)
            {
                AddTypeIndex(_typesByQualifiedName, fullName, type);
            }
        }
    }

    private static IEnumerable<Type> GetPublicTypes(Assembly assembly)
    {
            return assembly.GetTypes().Where(t => DocQueryKernels.ShouldIncludePublicType(t.IsPublic, t.IsNestedPublic));
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
                .FirstOrDefault(t => DocQueryKernels.IsDocMemberNameMatch(t.Name, part));

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
        var candidateList = candidates as IReadOnlyList<Type> ?? candidates.ToArray();
        var distinctCandidates = DeduplicateTypeCandidates(candidateList);
        return DocQueryKernels.SelectBestDocType(query, distinctCandidates);
    }

    private static Type[] DeduplicateTypeCandidates(IReadOnlyList<Type> candidates)
    {
        return DocQueryKernels.DeduplicateStableTypes(candidates);
    }

    private static string GetLookupTypeName(Type type)
        => DocQueryKernels.GetReflectionLookupTypeName(type);

    private static string GetMethodDocId(MethodBase method)
    {
        var parameters = method.GetParameters();
        var parameterTypeDocIds = parameters.Select(p => FormatTypeForDocId(p.ParameterType)).ToArray();
        var memberName = DocQueryKernels.GetMethodDocMemberName(method.Name, method is ConstructorInfo);
        return DocQueryKernels.GetMethodDocId(method.DeclaringType?.FullName, memberName, parameterTypeDocIds);
    }

    private string GetXmlDocPath(Assembly assembly)
    {
        return DocQueryKernels.GetXmlDocPath(
            assembly.Location,
            assembly.GetName().Name,
            GetReferencePackDirectories().ToArray());
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
            {
                xmlFiles = Directory.EnumerateFiles(refDir, "*.xml");
            }

            foreach (var xmlFile in xmlFiles)
            {
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
            }
        }
    }

    private IEnumerable<string> DiscoverReferencePackAssemblyNames()
    {
        return DocQueryKernels.DiscoverReferencePackAssemblyNames(GetReferencePackDirectories().ToArray());
    }

    private static string[] DeduplicateReferencePackAssemblyNames(IReadOnlyList<string> names)
    {
        return DocQueryKernels.DeduplicateStableStringsOrdinalIgnoreCase(names);
    }

    private IEnumerable<string> GetReferencePackDirectories()
    {
        if (_referencePackDirectories != null)
        {
            return _referencePackDirectories;
        }

        _referencePackDirectories = DocQueryKernels.GetReferencePackDirectories(
            _assemblies.Select(assembly => assembly.Location).ToArray(),
            Environment.GetEnvironmentVariable("DOTNET_ROOT")).ToList();

        return _referencePackDirectories;
    }

    private static string FormatQualifiedType(Type type)
    {
        if (type.IsGenericParameter) return type.Name;

        if (type.IsNested && type.DeclaringType != null)
        {
            return DocQueryKernels.FormatNestedQualifiedTypeName(
                FormatQualifiedType(type.DeclaringType),
                FormatTypeName(type));
        }

        return DocQueryKernels.FormatQualifiedTypeName(type.Namespace, FormatTypeName(type));
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

        return DocQueryKernels.FormatGenericTypeName(name, formattedArgs.ToArray());
    }

    private static string StripGenericArity(string name)
        => DocQueryKernels.StripGenericArity(name);

    private static string? FormatDocText(XElement? element)
    {
        if (element == null) return null;

        var raw = string.Concat(element.Nodes().Select(FormatDocNode));
        return DocQueryKernels.FormatDocTextRaw(raw);
    }

    private static string FormatDocNode(XNode node)
    {
        return node switch
        {
            XText text => text.Value,
            XElement element => DocQueryKernels.FormatDocElementNodeText(
                element.Name.LocalName,
                element.Value,
                string.Concat(element.Nodes().Select(FormatDocNode)),
                element.Attribute("name")?.Value,
                element.Attribute("langword")?.Value,
                element.Attribute("href")?.Value,
                element.Attribute("cref")?.Value),
            _ => ""
        };
    }
}
