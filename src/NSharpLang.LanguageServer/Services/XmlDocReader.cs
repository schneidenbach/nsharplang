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
    private readonly Dictionary<string, string> _docCache = new();
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
        return GetDocumentation(type.Assembly, docId);
    }

    /// <summary>
    /// Get documentation for a method
    /// </summary>
    public string? GetMethodDocumentation(MethodInfo method)
    {
        var typePrefix = method.DeclaringType?.FullName?.Replace('+', '.');
        var parameters = method.GetParameters();
        var paramString = parameters.Length > 0
            ? $"({string.Join(",", parameters.Select(p => FormatTypeForDocId(p.ParameterType)))})"
            : "";

        var docId = $"M:{typePrefix}.{method.Name}{paramString}";
        return GetDocumentation(method.DeclaringType?.Assembly, docId);
    }

    /// <summary>
    /// Get documentation for a property
    /// </summary>
    public string? GetPropertyDocumentation(PropertyInfo property)
    {
        var typePrefix = property.DeclaringType?.FullName?.Replace('+', '.');
        var docId = $"P:{typePrefix}.{property.Name}";
        return GetDocumentation(property.DeclaringType?.Assembly, docId);
    }

    /// <summary>
    /// Get documentation for a field
    /// </summary>
    public string? GetFieldDocumentation(FieldInfo field)
    {
        var typePrefix = field.DeclaringType?.FullName?.Replace('+', '.');
        var docId = $"F:{typePrefix}.{field.Name}";
        return GetDocumentation(field.DeclaringType?.Assembly, docId);
    }

    /// <summary>
    /// Get documentation by doc ID
    /// </summary>
    private string? GetDocumentation(Assembly? assembly, string docId)
    {
        if (assembly == null) return null;

        // Check cache first
        if (_docCache.TryGetValue(docId, out var cached))
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

            // Get or build index for this assembly
            var assemblyName = assembly.GetName().Name;
            if (assemblyName == null) return null;

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

            // Extract summary
            var summary = memberElement.Element("summary")?.Value.Trim();
            if (!string.IsNullOrWhiteSpace(summary))
            {
                // Cache and return
                _docCache[docId] = summary;
                return summary;
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Error reading documentation for {DocId}", docId);
        }

        return null;
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
            // Try to find XML file in same directory as assembly
            var assemblyLocation = assembly.Location;
            if (string.IsNullOrEmpty(assemblyLocation))
            {
                return null;
            }

            var xmlPath = Path.ChangeExtension(assemblyLocation, ".xml");
            if (File.Exists(xmlPath))
            {
                _logger.LogDebug("Loading XML doc from: {Path}", xmlPath);
                var xmlDoc = XDocument.Load(xmlPath);
                _loadedDocs[assemblyName] = xmlDoc;
                return xmlDoc;
            }

            // Try ref/ subdirectory
            var refPath = Path.Combine(Path.GetDirectoryName(assemblyLocation)!, "ref", Path.GetFileName(xmlPath));
            if (File.Exists(refPath))
            {
                _logger.LogDebug("Loading XML doc from: {Path}", refPath);
                var xmlDoc = XDocument.Load(refPath);
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

    /// <summary>
    /// Format a type for doc ID (handles generics)
    /// </summary>
    private string FormatTypeForDocId(Type type)
    {
        if (type.IsGenericType)
        {
            var typeName = type.FullName?.Split('`')[0];
            var args = type.GetGenericArguments();
            return $"{typeName}{{{string.Join(",", args.Select(FormatTypeForDocId))}}}";
        }

        return type.FullName?.Replace('+', '.') ?? type.Name;
    }
}
