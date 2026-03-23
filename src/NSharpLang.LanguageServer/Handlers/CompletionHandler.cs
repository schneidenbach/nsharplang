using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles code completion (Ctrl+Space in VS Code)
/// </summary>
public class CompletionHandler : CompletionHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly TypeResolver _typeResolver;
    private readonly ILogger<CompletionHandler> _logger;

    // N# Keywords for completion
    private static readonly string[] Keywords = {
        "func", "class", "struct", "record", "interface", "enum", "union", "namespace",
        "using", "import", "if", "else", "for", "foreach", "while", "return", "break",
        "continue", "match", "switch", "case", "when", "yield", "await", "async",
        "throw", "try", "catch", "finally", "lock", "new", "this", "base", "static",
        "virtual", "override", "abstract", "sealed", "partial", "readonly", "const",
        "file", "duck", "public", "private", "internal", "protected", "required",
        "init", "let", "var", "type", "out", "ref", "params", "true", "false",
        "null", "is", "as", "typeof", "nameof", "checked", "unchecked", "and",
        "or", "not", "with", "immutable", "print", "test", "assert", "implicit", "explicit"
    };

    private static readonly string[] PrimitiveTypes = {
        "int", "long", "float", "double", "bool", "string", "void", "object",
        "byte", "short", "char", "decimal", "uint", "ulong", "ushort", "sbyte"
    };

    public CompletionHandler(DocumentManager documentManager, TypeResolver typeResolver, ILogger<CompletionHandler> logger)
    {
        _documentManager = documentManager;
        _typeResolver = typeResolver;
        _logger = logger;
    }

    public override Task<CompletionList> Handle(CompletionParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        var items = new List<CompletionItem>();

        // Check if this is member completion (triggered by '.')
        if (doc?.Text != null && IsMemberCompletion(doc.Text, request.Position.Line, request.Position.Character))
        {
            var memberItems = GetMemberCompletionItems(doc, request.Position.Line, request.Position.Character);
            if (memberItems.Any())
            {
                _logger.LogDebug("Providing {Count} member completion items for {Uri}", memberItems.Count, uri);
                return Task.FromResult(new CompletionList(memberItems));
            }
        }

        // Otherwise, provide general completion items

        // Add keywords
        items.AddRange(Keywords.Select(k => new CompletionItem
        {
            Label = k,
            Kind = CompletionItemKind.Keyword,
            Detail = "keyword",
            InsertText = k
        }));

        // Add primitive types
        items.AddRange(PrimitiveTypes.Select(t => new CompletionItem
        {
            Label = t,
            Kind = CompletionItemKind.Keyword,
            Detail = "primitive type",
            InsertText = t
        }));

        // Add symbols from the current document (using enhanced symbol info)
        if (doc?.SymbolsInfo != null)
        {
            foreach (var (name, symbolInfo) in doc.SymbolsInfo)
            {
                var item = new CompletionItem
                {
                    Label = name,
                    Kind = GetCompletionItemKindFromSymbol(symbolInfo.Kind),
                    Detail = GetSymbolDetail(symbolInfo),
                    InsertText = name,
                    Documentation = !string.IsNullOrEmpty(symbolInfo.Documentation) ? symbolInfo.Documentation : null
                };

                items.Add(item);
            }
        }

        // Add variables and parameters from semantic model
        if (doc?.SemanticModel != null)
        {
            foreach (var (name, typeInfo) in doc.SemanticModel.Variables)
            {
                if (!items.Any(i => i.Label == name))
                {
                    items.Add(new CompletionItem
                    {
                        Label = name,
                        Kind = CompletionItemKind.Variable,
                        Detail = $"variable: {typeInfo}",
                        InsertText = name
                    });
                }
            }

            foreach (var (name, typeInfo) in doc.SemanticModel.Functions)
            {
                if (!items.Any(i => i.Label == name))
                {
                    items.Add(new CompletionItem
                    {
                        Label = name,
                        Kind = CompletionItemKind.Function,
                        Detail = $"func: {typeInfo}",
                        InsertText = name
                    });
                }
            }
        }

        // Add common .NET types
        var commonTypes = new[]
        {
            ("Console", "System.Console"),
            ("List", "System.Collections.Generic.List<T>"),
            ("Dictionary", "System.Collections.Generic.Dictionary<TKey, TValue>"),
            ("Task", "System.Threading.Tasks.Task"),
            ("Exception", "System.Exception"),
            ("DateTime", "System.DateTime"),
            ("Guid", "System.Guid"),
            ("Math", "System.Math"),
            ("String", "System.String"),
            ("Linq", "System.Linq")
        };

        items.AddRange(commonTypes.Select(t => new CompletionItem
        {
            Label = t.Item1,
            Kind = CompletionItemKind.Class,
            Detail = t.Item2,
            InsertText = t.Item1
        }));

        _logger.LogDebug("Providing {Count} completion items for {Uri}", items.Count, uri);

        return Task.FromResult(new CompletionList(items));
    }

    /// <summary>
    /// Check if the completion is triggered after a dot (member access)
    /// </summary>
    private bool IsMemberCompletion(string text, int line, int character)
    {
        var lines = text.Split('\n');
        if (line >= lines.Length) return false;

        var lineText = lines[line];
        if (character == 0) return false;

        // Check if there's a dot before the cursor
        var beforeCursor = lineText.Substring(0, Math.Min(character, lineText.Length));
        return beforeCursor.TrimEnd().EndsWith(".");
    }

    /// <summary>
    /// Get member completion items for the expression before the dot
    /// </summary>
    private List<CompletionItem> GetMemberCompletionItems(Models.DocumentState doc, int line, int character)
    {
        var items = new List<CompletionItem>();

        try
        {
            var text = doc.Text;
            var lines = text.Split('\n');
            if (line >= lines.Length) return items;

            var lineText = lines[line];
            if (character == 0) return items;

            // Get the expression before the dot
            var beforeDot = lineText.Substring(0, Math.Min(character, lineText.Length)).TrimEnd();
            if (!beforeDot.EndsWith(".")) return items;

            beforeDot = beforeDot.Substring(0, beforeDot.Length - 1).TrimEnd();

            _logger.LogDebug("Resolving type for expression: {Expression}", beforeDot);

            Type? type = null;

            // Extract the identifier (rightmost token)
            var identifier = ExtractIdentifier(beforeDot);
            if (string.IsNullOrEmpty(identifier))
            {
                _logger.LogDebug("Could not extract identifier from: {Text}", beforeDot);
                return items;
            }

            // Check if this looks like a method call (ends with ")") - this indicates a chained expression
            // For now, we don't support these - would need full expression type resolution
            // The performance fix (caching GetExportedTypes) means this won't hang anymore, just returns empty
            if (identifier.EndsWith(")"))
            {
                _logger.LogDebug("Chained method call detected - not yet supported: {Identifier}", identifier);
                return items; // Return empty for now - TODO: implement full expression type resolution
            }

            // First, try to find the identifier in the semantic model (variables, parameters, etc.)
            if (doc?.SemanticModel != null)
            {
                var typeInfo = doc.SemanticModel.LookupIdentifier(identifier);
                if (typeInfo != null)
                {
                    var typeName = typeInfo.ToString();
                    _logger.LogDebug("Found identifier '{Identifier}' in semantic model with type: {TypeName}",
                        identifier, typeName);

                    // Convert TypeInfo to System.Type for reflection
                    type = _typeResolver.ResolveType(typeName);
                    if (type == null)
                    {
                        _logger.LogDebug("Could not resolve TypeInfo '{TypeName}' to System.Type", typeName);
                    }
                }
            }

            // If not found in semantic model, try to resolve as a type name (e.g., "Console", "String")
            if (type == null)
            {
                type = _typeResolver.ResolveType(identifier);
            }

            if (type != null)
            {
                _logger.LogDebug("Resolved type: {TypeName}", type.FullName);
                var members = _typeResolver.GetMembers(type);

                foreach (var member in members)
                {
                    items.Add(new CompletionItem
                    {
                        Label = member.Name,
                        Kind = member.Kind switch
                        {
                            MemberKind.Method => CompletionItemKind.Method,
                            MemberKind.Property => CompletionItemKind.Property,
                            MemberKind.Field => CompletionItemKind.Field,
                            MemberKind.Event => CompletionItemKind.Event,
                            _ => CompletionItemKind.Text
                        },
                        Detail = member.Parameters != null
                            ? $"{member.Name}({member.Parameters}): {member.Type}"
                            : $"{member.Name}: {member.Type}",
                        InsertText = member.Name,
                        Documentation = !string.IsNullOrEmpty(member.Documentation)
                            ? new MarkupContent
                            {
                                Kind = MarkupKind.Markdown,
                                Value = member.Documentation
                            }
                            : null
                    });
                }
            }
            else
            {
                _logger.LogDebug("Could not resolve type for identifier: {Identifier}", identifier);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting member completion items");
        }

        return items;
    }

    /// <summary>
    /// Extract the last identifier from a string (simplified)
    /// </summary>
    private string ExtractIdentifier(string text)
    {
        var parts = text.Split(new[] { ' ', '\t', '(', ')', '[', ']', '{', '}', ',', ';' }, StringSplitOptions.RemoveEmptyEntries);
        return parts.LastOrDefault() ?? "";
    }

    public override Task<CompletionItem> Handle(CompletionItem request, CancellationToken cancellationToken)
    {
        // We don't provide resolve capabilities, so just return the item as-is
        return Task.FromResult(request);
    }

    protected override CompletionRegistrationOptions CreateRegistrationOptions(
        CompletionCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new CompletionRegistrationOptions
        {
            // DocumentSelector will be set automatically
            ResolveProvider = false, // We provide all info upfront
            TriggerCharacters = new Container<string>(".", ":", " ")
        };
    }

    private CompletionItemKind GetCompletionItemKind(TypeInfo typeInfo)
    {
        return typeInfo switch
        {
            ClassTypeInfo => CompletionItemKind.Class,
            StructTypeInfo => CompletionItemKind.Struct,
            RecordTypeInfo => CompletionItemKind.Class,
            InterfaceTypeInfo => CompletionItemKind.Interface,
            EnumTypeInfo => CompletionItemKind.Enum,
            UnionTypeInfo => CompletionItemKind.Class,
            _ => CompletionItemKind.Variable
        };
    }

    private CompletionItemKind GetCompletionItemKindFromSymbol(LanguageServer.Models.SymbolKind kind)
    {
        return kind switch
        {
            LanguageServer.Models.SymbolKind.Class => CompletionItemKind.Class,
            LanguageServer.Models.SymbolKind.Struct => CompletionItemKind.Struct,
            LanguageServer.Models.SymbolKind.Record => CompletionItemKind.Class,
            LanguageServer.Models.SymbolKind.Interface => CompletionItemKind.Interface,
            LanguageServer.Models.SymbolKind.Enum => CompletionItemKind.Enum,
            LanguageServer.Models.SymbolKind.Union => CompletionItemKind.Class,
            LanguageServer.Models.SymbolKind.Function => CompletionItemKind.Function,
            LanguageServer.Models.SymbolKind.Method => CompletionItemKind.Method,
            LanguageServer.Models.SymbolKind.Property => CompletionItemKind.Property,
            LanguageServer.Models.SymbolKind.Field => CompletionItemKind.Field,
            LanguageServer.Models.SymbolKind.Parameter => CompletionItemKind.Variable,
            LanguageServer.Models.SymbolKind.LocalVariable => CompletionItemKind.Variable,
            LanguageServer.Models.SymbolKind.EnumMember => CompletionItemKind.EnumMember,
            LanguageServer.Models.SymbolKind.Constructor => CompletionItemKind.Constructor,
            _ => CompletionItemKind.Variable
        };
    }

    private string GetSymbolDetail(LanguageServer.Models.SymbolInfo symbol)
    {
        var parts = new List<string>();

        // Add modifiers
        var modifiers = new List<string>();
        if (symbol.Modifiers.HasFlag(Modifiers.Public)) modifiers.Add("public");
        if (symbol.Modifiers.HasFlag(Modifiers.Private)) modifiers.Add("private");
        if (symbol.Modifiers.HasFlag(Modifiers.Protected)) modifiers.Add("protected");
        if (symbol.Modifiers.HasFlag(Modifiers.Internal)) modifiers.Add("internal");
        if (symbol.Modifiers.HasFlag(Modifiers.Static)) modifiers.Add("static");
        if (symbol.Modifiers.HasFlag(Modifiers.Abstract)) modifiers.Add("abstract");
        if (symbol.Modifiers.HasFlag(Modifiers.Virtual)) modifiers.Add("virtual");
        if (symbol.Modifiers.HasFlag(Modifiers.Override)) modifiers.Add("override");
        if (symbol.Modifiers.HasFlag(Modifiers.Sealed)) modifiers.Add("sealed");
        if (symbol.Modifiers.HasFlag(Modifiers.Async)) modifiers.Add("async");

        if (modifiers.Any())
        {
            parts.Add(string.Join(" ", modifiers));
        }

        // Add kind
        parts.Add(symbol.Kind.ToString().ToLower());

        // Add name
        parts.Add(symbol.Name);

        // Add signature for functions/methods
        if (symbol.Kind == LanguageServer.Models.SymbolKind.Function ||
            symbol.Kind == LanguageServer.Models.SymbolKind.Method ||
            symbol.Kind == LanguageServer.Models.SymbolKind.Constructor)
        {
            var paramList = string.Join(", ", symbol.Parameters.Select(p => $"{p.Name}: {p.TypeName}"));
            parts.Add($"({paramList})");

            if (!string.IsNullOrEmpty(symbol.TypeName))
            {
                parts.Add($": {symbol.TypeName}");
            }
        }
        else if (!string.IsNullOrEmpty(symbol.TypeName))
        {
            parts.Add($": {symbol.TypeName}");
        }

        return string.Join(" ", parts);
    }
}
