using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Xml.Linq;
using Microsoft.Extensions.Logging;

namespace NSharpLang.LanguageServer.Services;

/// <summary>
/// Reads XML documentation files for .NET assemblies
/// </summary>
public class XmlDocReader
{
    private readonly ILogger<XmlDocReader> _logger;
    private readonly Dictionary<string, XDocument> _loadedDocs = new();
    private readonly Dictionary<string, XmlDocumentation> _docCache = new();
    private readonly Dictionary<string, Dictionary<string, XElement>> _docIndexes = new();

    public XmlDocReader(ILogger<XmlDocReader> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Get documentation for a type
    /// </summary>
    public string? GetTypeDocumentation(Type type)
    {
        var docId = $"T:{type.FullName?.Replace('+', '.')}";
        return GetDocumentation(type.Assembly, docId)?.Summary;
    }

    /// <summary>
    /// Get documentation for a method
    /// </summary>
    public string? GetMethodDocumentation(MethodInfo method)
    {
        return GetMethodDocumentationInfo(method)?.Summary;
    }

    /// <summary>
    /// Get documentation for a method, including parameter documentation
    /// </summary>
    public XmlDocumentation? GetMethodDocumentationInfo(MethodInfo method)
    {
        return GetDocumentation(method.DeclaringType?.Assembly, BuildMethodDocId(method));
    }

    /// <summary>
    /// Get documentation for a constructor, including parameter documentation
    /// </summary>
    public XmlDocumentation? GetConstructorDocumentationInfo(ConstructorInfo constructor)
    {
        return GetDocumentation(constructor.DeclaringType?.Assembly, BuildMethodDocId(constructor));
    }

    private string BuildMethodDocId(MethodBase method)
    {
        var typePrefix = method.DeclaringType?.FullName?.Replace('+', '.');
        var parameters = method.GetParameters();
        var paramString = parameters.Length > 0
            ? $"({string.Join(",", parameters.Select(p => FormatTypeForDocId(p.ParameterType)))})"
            : "";

        var methodName = method is ConstructorInfo
            ? "#ctor"
            : method.Name;

        if (method.IsGenericMethod)
        {
            methodName += $"``{method.GetGenericArguments().Length}";
        }

        return $"M:{typePrefix}.{methodName}{paramString}";
    }

    /// <summary>
    /// Get documentation for a property
    /// </summary>
    public string? GetPropertyDocumentation(PropertyInfo property)
    {
        var typePrefix = property.DeclaringType?.FullName?.Replace('+', '.');
        var docId = $"P:{typePrefix}.{property.Name}";
        return GetDocumentation(property.DeclaringType?.Assembly, docId)?.Summary;
    }

    /// <summary>
    /// Get documentation for a field
    /// </summary>
    public string? GetFieldDocumentation(FieldInfo field)
    {
        var typePrefix = field.DeclaringType?.FullName?.Replace('+', '.');
        var docId = $"F:{typePrefix}.{field.Name}";
        return GetDocumentation(field.DeclaringType?.Assembly, docId)?.Summary;
    }

    /// <summary>
    /// Get documentation by doc ID
    /// </summary>
    private XmlDocumentation? GetDocumentation(Assembly? assembly, string docId)
    {
        if (assembly == null) return null;

        var assemblyName = assembly.GetName().Name;
        if (assemblyName == null) return null;

        var cacheKey = $"{assemblyName}:{docId}";

        // Check cache first
        if (_docCache.TryGetValue(cacheKey, out var cached))
        {
            return cached;
        }

        try
        {
            // Load XML doc file if not already loaded
            var xmlDoc = GetXmlDocForAssembly(assembly);
            if (xmlDoc == null)
            {
                return null;
            }

            if (!_docIndexes.TryGetValue(assemblyName, out var index))
            {
                // Build index for fast lookup
                index = new Dictionary<string, XElement>();
                var members = xmlDoc.Root?.Element("members")?.Elements("member");
                if (members != null)
                {
                    foreach (var member in members)
                    {
                        var name = member.Attribute("name")?.Value;
                        if (name != null)
                        {
                            index[name] = member;
                        }
                    }
                }
                _docIndexes[assemblyName] = index;
            }

            // Fast O(1) lookup using index
            if (!index.TryGetValue(docId, out var memberElement))
            {
                return null;
            }

            var documentation = ExtractDocumentation(memberElement);
            if (documentation.HasContent)
            {
                _docCache[cacheKey] = documentation;
                return documentation;
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Error reading documentation for {DocId}", docId);
        }

        return null;
    }

    private static XmlDocumentation ExtractDocumentation(XElement memberElement)
    {
        var summary = NormalizeDocumentationText(memberElement.Element("summary"));
        var parameters = memberElement
            .Elements("param")
            .Select(param => new
            {
                Name = param.Attribute("name")?.Value,
                Text = NormalizeDocumentationText(param)
            })
            .Where(param => !string.IsNullOrWhiteSpace(param.Name) && !string.IsNullOrWhiteSpace(param.Text))
            .ToDictionary(param => param.Name!, param => param.Text!, StringComparer.Ordinal);

        return new XmlDocumentation(summary, parameters);
    }

    /// <summary>
    /// Get XML documentation file for an assembly
    /// </summary>
    private XDocument? GetXmlDocForAssembly(Assembly assembly)
    {
        var assemblyName = assembly.GetName().Name;
        if (assemblyName == null) return null;

        // Check if already loaded
        if (_loadedDocs.TryGetValue(assemblyName, out var doc))
        {
            return doc;
        }

        try
        {
            foreach (var candidatePath in GetXmlDocPathCandidates(assembly).Distinct(StringComparer.OrdinalIgnoreCase))
            {
                if (!File.Exists(candidatePath))
                {
                    continue;
                }

                _logger.LogDebug("Loading XML doc from: {Path}", candidatePath);
                var xmlDoc = XDocument.Load(candidatePath);
                _loadedDocs[assemblyName] = xmlDoc;
                return xmlDoc;
            }

            _logger.LogDebug("No XML doc found for assembly: {Assembly}", assemblyName);
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Error loading XML doc for assembly: {Assembly}", assemblyName);
        }

        return null;
    }

    private static IEnumerable<string> GetXmlDocPathCandidates(Assembly assembly)
    {
        var assemblyLocation = assembly.Location;
        if (string.IsNullOrEmpty(assemblyLocation))
        {
            yield break;
        }

        var assemblyDirectory = Path.GetDirectoryName(assemblyLocation);
        if (string.IsNullOrEmpty(assemblyDirectory))
        {
            yield break;
        }

        var assemblyXmlPath = Path.ChangeExtension(assemblyLocation, ".xml");
        yield return assemblyXmlPath;

        var xmlFileName = GetXmlDocFileName(assembly);
        yield return Path.Combine(assemblyDirectory, xmlFileName);
        yield return Path.Combine(assemblyDirectory, "ref", Path.GetFileName(assemblyXmlPath));
        yield return Path.Combine(assemblyDirectory, "ref", xmlFileName);

        foreach (var referencePackPath in GetReferencePackXmlDocPathCandidates(assembly, assemblyLocation, xmlFileName))
        {
            yield return referencePackPath;
        }
    }

    private static IEnumerable<string> GetReferencePackXmlDocPathCandidates(
        Assembly assembly,
        string assemblyLocation,
        string xmlFileName)
    {
        var dotnetRoot = FindDotnetRoot(Path.GetDirectoryName(assemblyLocation));
        if (dotnetRoot == null)
        {
            yield break;
        }

        var runtimePackName = GetRuntimePackName(assemblyLocation) ?? "Microsoft.NETCore.App";
        var refPackRoot = Path.Combine(dotnetRoot, "packs", $"{runtimePackName}.Ref");
        if (!Directory.Exists(refPackRoot))
        {
            yield break;
        }

        var runtimeVersion = GetRuntimePackVersion(assemblyLocation) ?? assembly.GetName().Version?.ToString();
        var targetFramework = GetTargetFrameworkMoniker(runtimeVersion);
        foreach (var versionDirectory in GetReferencePackVersionDirectories(refPackRoot, runtimeVersion))
        {
            if (targetFramework != null)
            {
                yield return Path.Combine(versionDirectory, "ref", targetFramework, xmlFileName);
            }

            var refDirectory = Path.Combine(versionDirectory, "ref");
            if (!Directory.Exists(refDirectory))
            {
                continue;
            }

            foreach (var tfmDirectory in Directory.GetDirectories(refDirectory).OrderByDescending(Path.GetFileName, StringComparer.Ordinal))
            {
                yield return Path.Combine(tfmDirectory, xmlFileName);
            }
        }
    }

    private static IEnumerable<string> GetReferencePackVersionDirectories(string refPackRoot, string? runtimeVersion)
    {
        var directories = Directory.GetDirectories(refPackRoot);
        if (runtimeVersion != null)
        {
            var exactMatch = directories.FirstOrDefault(dir =>
                string.Equals(Path.GetFileName(dir), runtimeVersion, StringComparison.OrdinalIgnoreCase));
            if (exactMatch != null)
            {
                yield return exactMatch;
            }
        }

        var runtimeMajor = TryParseMajorVersion(runtimeVersion);
        foreach (var directory in directories
            .Where(dir => runtimeVersion == null || !string.Equals(Path.GetFileName(dir), runtimeVersion, StringComparison.OrdinalIgnoreCase))
            .OrderByDescending(dir => ParseVersionOrDefault(Path.GetFileName(dir))))
        {
            if (runtimeMajor == null || TryParseMajorVersion(Path.GetFileName(directory)) == runtimeMajor)
            {
                yield return directory;
            }
        }

        foreach (var directory in directories
            .Where(dir => runtimeMajor != null && TryParseMajorVersion(Path.GetFileName(dir)) != runtimeMajor)
            .OrderByDescending(dir => ParseVersionOrDefault(Path.GetFileName(dir))))
        {
            yield return directory;
        }
    }

    private static string? FindDotnetRoot(string? startDirectory)
    {
        var envRoot = Environment.GetEnvironmentVariable("DOTNET_ROOT");
        if (!string.IsNullOrWhiteSpace(envRoot) && Directory.Exists(envRoot))
        {
            return envRoot;
        }

        var directory = !string.IsNullOrWhiteSpace(startDirectory)
            ? new DirectoryInfo(startDirectory)
            : null;

        while (directory != null)
        {
            if (Directory.Exists(Path.Combine(directory.FullName, "packs")) &&
                Directory.Exists(Path.Combine(directory.FullName, "shared")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        return null;
    }

    private static string GetXmlDocFileName(Assembly assembly)
    {
        var assemblyName = assembly.GetName().Name;
        return assemblyName == "System.Private.CoreLib"
            ? "System.Runtime.xml"
            : $"{assemblyName}.xml";
    }

    private static string? GetRuntimePackName(string assemblyLocation)
    {
        var segments = assemblyLocation.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        for (var i = 0; i < segments.Length - 2; i++)
        {
            if (segments[i] == "shared")
            {
                return segments[i + 1];
            }
        }

        return null;
    }

    private static string? GetRuntimePackVersion(string assemblyLocation)
    {
        var segments = assemblyLocation.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        for (var i = 0; i < segments.Length - 3; i++)
        {
            if (segments[i] == "shared")
            {
                return segments[i + 2];
            }
        }

        return null;
    }

    private static string? GetTargetFrameworkMoniker(string? version)
    {
        var major = TryParseMajorVersion(version);
        return major != null ? $"net{major}.0" : null;
    }

    private static int? TryParseMajorVersion(string? version)
    {
        return Version.TryParse(version, out var parsed)
            ? parsed.Major
            : null;
    }

    private static Version ParseVersionOrDefault(string? version)
    {
        return Version.TryParse(version, out var parsed)
            ? parsed
            : new Version(0, 0);
    }

    private static string? NormalizeDocumentationText(XElement? element)
    {
        var text = element?.Value;
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        return string.Join(" ", text.Split(
            new[] { ' ', '\t', '\r', '\n' },
            StringSplitOptions.RemoveEmptyEntries));
    }

    /// <summary>
    /// Format a type for doc ID (handles generics)
    /// </summary>
    private string FormatTypeForDocId(Type type)
    {
        if (type.IsByRef)
        {
            return $"{FormatTypeForDocId(type.GetElementType()!)}@";
        }

        if (type.IsPointer)
        {
            return $"{FormatTypeForDocId(type.GetElementType()!)}*";
        }

        if (type.IsArray)
        {
            var rankSuffix = type.GetArrayRank() == 1
                ? "[]"
                : $"[{new string(',', type.GetArrayRank() - 1)}]";
            return $"{FormatTypeForDocId(type.GetElementType()!)}{rankSuffix}";
        }

        if (type.IsGenericParameter)
        {
            return type.DeclaringMethod != null
                ? $"``{type.GenericParameterPosition}"
                : $"`{type.GenericParameterPosition}";
        }

        if (type.IsGenericType)
        {
            var genericType = type.IsGenericTypeDefinition ? type : type.GetGenericTypeDefinition();
            var typeName = genericType.FullName?.Split('`')[0].Replace('+', '.');
            var args = type.GetGenericArguments();
            return $"{typeName}{{{string.Join(",", args.Select(FormatTypeForDocId))}}}";
        }

        return type.FullName?.Replace('+', '.') ?? type.Name;
    }
}

public sealed record XmlDocumentation(
    string? Summary,
    IReadOnlyDictionary<string, string> Parameters)
{
    public bool HasContent => !string.IsNullOrWhiteSpace(Summary) || Parameters.Count > 0;

    public string? GetParameterDocumentation(string? parameterName)
    {
        return parameterName != null && Parameters.TryGetValue(parameterName, out var documentation)
            ? documentation
            : null;
    }
}
