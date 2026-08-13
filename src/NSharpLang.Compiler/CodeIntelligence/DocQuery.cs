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
///   var result = query.Lookup("List");                 // → System.Collections.Generic.List&lt;T&gt;
/// </summary>
public class DocQuery
{
    private readonly Dictionary<string, XDocument> _loadedDocs = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, Dictionary<string, XElement>> _docIndexes = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, XElement> _globalDocIndex = new(StringComparer.Ordinal);
    private readonly DocQueryTypeIndex _typeIndex = new();
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
            _typeIndex.AddAssembly(assembly);

        foreach (var assembly in ExternalAssemblyScan.Loaded())
            _typeIndex.AddAssembly(assembly);

        // Discover additional assemblies from reference packs
        foreach (var asmName in _typeIndex.DiscoverReferencePackAssemblyNames())
        {
            _typeIndex.AddAssembly(Assembly.Load(asmName));
        }
    }

    /// <summary>
    /// Look up documentation for a type or member by name.
    /// Supports: "Console", "System.Console", "Console.WriteLine", "List", "Dictionary"
    /// </summary>
    public DocResult? Lookup(string query)
    {
        if (string.IsNullOrWhiteSpace(query)) return null;

        var exactType = _typeIndex.ResolveType(query);
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
            var type = _typeIndex.ResolveType(splitPlan.TypeCandidate);
            if (type == null) continue;

            var nestedType = DocQueryTypeIndex.ResolveNestedTypeChain(type, splitPlan.RemainderParts);
            if (nestedType != null)
            {
                return DescribeType(nestedType);
            }

            if (splitPlan.HasContainingType)
            {
                var containingType = DocQueryTypeIndex.ResolveNestedTypeChain(type, splitPlan.ContainingTypeParts);
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
        var baseTypes = DocQueryReflectionFacts.GetBaseTypes(type);

        return DocQueryKernels.CreateTypeDocResult(
            DocQueryKernels.StripGenericArity(type.Name),
            DocQueryReflectionFacts.FormatQualifiedType(type),
            DocQueryReflectionFacts.GetTypeKind(type),
            summary,
            type.Namespace,
            members,
            baseTypes);
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
            var overloads = constructors.Select(c => DocQueryKernels.CreateDocMemberResult(
                DocQueryReflectionFacts.FormatMethodSignature(c),
                "constructor",
                null,
                GetMethodSummary(c),
                DocQueryReflectionFacts.FormatParameters(c)
            )).ToArray();

            return DocQueryKernels.CreateCallableDocResult(
                DocQueryKernels.StripGenericArity(type.Name),
                DocQueryReflectionFacts.FormatQualifiedType(type),
                DocQueryKernels.GetOverloadKindText("constructor", constructors.Length),
                GetMethodSummary(constructors[0]),
                type.Namespace,
                overloads,
                constructors[0].GetParameters().Select(p => DocQueryKernels.CreateDocParameterResult(
                    p.Name, DocQueryReflectionFacts.FormatType(p.ParameterType), GetParameterSummary(constructors[0], p.Name)
                )).ToArray(),
                null,
                null);
        }

        // Look for methods
        var methods = type.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance)
            .Where(m => DocQueryKernels.IsMethodMemberMatch(m.Name, memberName, m.IsSpecialName))
            .ToArray();

        if (methods.Length > 0)
        {
            // Return all overloads
            var overloads = methods.Select(m => DocQueryKernels.CreateDocMemberResult(
                DocQueryReflectionFacts.FormatMethodSignature(m),
                "method",
                DocQueryReflectionFacts.FormatType(m.ReturnType),
                GetMethodSummary(m),
                DocQueryReflectionFacts.FormatParameters(m)
            )).ToArray();

            var firstDoc = GetMethodSummary(methods[0]);

            return DocQueryKernels.CreateCallableDocResult(
                memberName,
                DocQueryKernels.FormatMemberFullName(DocQueryReflectionFacts.FormatQualifiedType(type), memberName),
                DocQueryKernels.GetOverloadKindText("method", methods.Length),
                firstDoc,
                type.Namespace,
                overloads,
                methods[0].GetParameters().Select(p => DocQueryKernels.CreateDocParameterResult(
                    p.Name, DocQueryReflectionFacts.FormatType(p.ParameterType), GetParameterSummary(methods[0], p.Name)
                )).ToArray(),
                DocQueryReflectionFacts.FormatType(methods[0].ReturnType),
                GetReturnsSummary(methods[0]));
        }

        // Look for properties
        var prop = type.GetProperty(memberName,
            BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance | BindingFlags.IgnoreCase);
        if (prop != null)
        {
            return DocQueryKernels.CreateValueDocResult(
                prop.Name,
                DocQueryKernels.FormatMemberFullName(DocQueryReflectionFacts.FormatQualifiedType(type), prop.Name),
                "property",
                GetPropertySummary(prop),
                type.Namespace,
                DocQueryReflectionFacts.FormatType(prop.PropertyType));
        }

        // Look for fields
        var field = type.GetField(memberName,
            BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance | BindingFlags.IgnoreCase);
        if (field != null)
        {
            return DocQueryKernels.CreateValueDocResult(
                field.Name,
                DocQueryKernels.FormatMemberFullName(DocQueryReflectionFacts.FormatQualifiedType(type), field.Name),
                "field",
                GetFieldSummary(field),
                type.Namespace,
                DocQueryReflectionFacts.FormatType(field.FieldType));
        }

        var evt = type.GetEvent(memberName,
            BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance | BindingFlags.IgnoreCase);
        if (evt != null)
        {
            return DocQueryKernels.CreateValueDocResult(
                evt.Name,
                DocQueryKernels.FormatMemberFullName(DocQueryReflectionFacts.FormatQualifiedType(type), evt.Name),
                "event",
                GetEventSummary(evt),
                type.Namespace,
                evt.EventHandlerType != null ? DocQueryReflectionFacts.FormatType(evt.EventHandlerType) : null);
        }

        return null;
    }

    // ── XML Doc Helpers ──────────────────────────────────────────────────

    private string? GetTypeSummary(Type type) =>
        GetDocSummary(type.Assembly, DocQueryKernels.GetReflectionTypeDocId(type));

    private string? GetMethodSummary(MethodBase method) =>
        GetDocSummary(method.DeclaringType?.Assembly, DocQueryReflectionFacts.GetMethodDocId(method));

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
        var element = GetDocElement(method.DeclaringType?.Assembly, DocQueryReflectionFacts.GetMethodDocId(method));
        return FormatDocText(element?.Elements("param")
            .FirstOrDefault(p => p.Attribute("name")?.Value == paramName)
        );
    }

    private string? GetReturnsSummary(MethodInfo method)
    {
        var element = GetDocElement(method.DeclaringType?.Assembly, DocQueryReflectionFacts.GetMethodDocId(method));
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
            var xmlPath = _typeIndex.GetXmlDocPath(assembly);
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

    private DocMemberResult[] GetTypeMembers(Type type)
    {
        var results = new List<DocMemberResult>();

        foreach (var nestedType in type.GetNestedTypes(BindingFlags.Public))
        {
            results.Add(DocQueryKernels.CreateDocMemberResult(
                DocQueryKernels.StripGenericArity(nestedType.Name),
                "nested type",
                DocQueryReflectionFacts.FormatQualifiedType(nestedType),
                GetTypeSummary(nestedType),
                null));
        }

        foreach (var ctor in type.GetConstructors(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly))
        {
            results.Add(DocQueryKernels.CreateDocMemberResult(
                DocQueryReflectionFacts.FormatMethodSignature(ctor),
                "constructor",
                null,
                GetMethodSummary(ctor),
                DocQueryReflectionFacts.FormatParameters(ctor)));
        }

        // Properties
        foreach (var prop in type.GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly))
        {
            results.Add(DocQueryKernels.CreateDocMemberResult(prop.Name, "property", DocQueryReflectionFacts.FormatType(prop.PropertyType),
                GetPropertySummary(prop), null));
        }

        // Methods (exclude special names like get_/set_)
        foreach (var method in type.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)
            .Where(m => !m.IsSpecialName))
        {
            results.Add(DocQueryKernels.CreateDocMemberResult(method.Name, "method", DocQueryReflectionFacts.FormatType(method.ReturnType),
                GetMethodSummary(method), DocQueryReflectionFacts.FormatParameters(method)));
        }

        // Fields
        foreach (var field in type.GetFields(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly))
        {
            results.Add(DocQueryKernels.CreateDocMemberResult(field.Name, "field", DocQueryReflectionFacts.FormatType(field.FieldType),
                GetFieldSummary(field), null));
        }

        foreach (var evt in type.GetEvents(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly))
        {
            results.Add(DocQueryKernels.CreateDocMemberResult(evt.Name, "event",
                evt.EventHandlerType != null ? DocQueryReflectionFacts.FormatType(evt.EventHandlerType) : null,
                GetEventSummary(evt), null));
        }

        return DocQueryKernels.OrderDocMembers(results);
    }

    private void EnsureGlobalDocIndex()
    {
        if (_globalDocIndexLoaded)
        {
            return;
        }

        _globalDocIndexLoaded = true;

        foreach (var refDir in _typeIndex.GetReferencePackDirectories())
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
