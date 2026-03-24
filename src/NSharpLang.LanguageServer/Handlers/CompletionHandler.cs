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
    /// Get member completion items for the expression before the dot.
    /// Uses AST-based expression type resolution (like HoverHandler) as the primary path,
    /// with text-based fallback for broken ASTs.
    /// </summary>
    private List<CompletionItem> GetMemberCompletionItems(Models.DocumentState doc, int line, int character)
    {
        var items = new List<CompletionItem>();

        try
        {
            // === PRIMARY PATH: AST-based resolution ===
            if (doc.CompilationUnit != null && doc.SemanticModel != null)
            {
                items = GetMemberCompletionViaAst(doc, line, character);
                if (items.Count > 0)
                {
                    _logger.LogDebug("AST-based completion returned {Count} items", items.Count);
                    return items;
                }
            }

            // === FALLBACK: text-based resolution ===
            items = GetMemberCompletionFallback(doc, line, character);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting member completion items");
        }

        return items;
    }

    /// <summary>
    /// AST-based member completion: find the MemberAccessExpression at cursor,
    /// resolve the Object expression's type, and return its members.
    /// </summary>
    private List<CompletionItem> GetMemberCompletionViaAst(Models.DocumentState doc, int line, int character)
    {
        // AstNodeFinder expects 0-based LSP coordinates as the target.
        // It internally converts 1-based node positions to 0-based for comparison.
        var expression = AstNodeFinder.FindExpressionAtPosition(
            doc.CompilationUnit!, line, character);

        if (expression is not MemberAccessExpression memberAccess)
        {
            _logger.LogDebug("No MemberAccessExpression found at ({Line}, {Col})", line, character);
            return new List<CompletionItem>();
        }

        _logger.LogDebug("Found MemberAccessExpression, resolving Object type for: {MemberName}",
            memberAccess.MemberName);

        // Try to resolve the type of the object expression (the part before the dot)
        var resolver = new ExpressionTypeResolver(doc.SemanticModel!);
        var objectType = resolver.ResolveExpressionType(memberAccess.Object);

        if (objectType != null)
        {
            var mode = IsStaticTypeAccess(memberAccess.Object, doc)
                ? MemberAccessMode.StaticOnly
                : MemberAccessMode.InstanceOnly;

            _logger.LogDebug("Resolved to System.Type: {Type}, mode: {Mode}", objectType.FullName, mode);
            return MembersToCompletionItems(_typeResolver.GetMembers(objectType, mode));
        }

        // ExpressionTypeResolver couldn't resolve — try LSP-layer fallbacks

        // Fallback 0: Namespace completion — if Object is an identifier or chained access matching a namespace
        {
            string? nsPrefix = null;
            if (memberAccess.Object is IdentifierExpression nsId)
                nsPrefix = nsId.Name;
            else
                nsPrefix = BuildNamespacePath(memberAccess);

            if (nsPrefix != null)
            {
                var nsItems = new List<CompletionItem>();

                // Add sub-namespaces (e.g., System. → Collections, Threading, Linq, ...)
                foreach (var sub in GetSubNamespaces(nsPrefix))
                {
                    nsItems.Add(new CompletionItem
                    {
                        Label = sub,
                        Kind = CompletionItemKind.Module,
                        Detail = $"namespace {nsPrefix}.{sub}",
                        InsertText = sub
                    });
                }

                // Add types directly in this namespace
                nsItems.AddRange(NamespaceTypesToCompletionItems(_typeResolver.GetTypesInNamespace(nsPrefix)));

                if (nsItems.Count > 0)
                {
                    _logger.LogDebug("Resolved '{Prefix}' as namespace with {Count} items", nsPrefix, nsItems.Count);
                    return nsItems;
                }
            }
        }

        // Fallback 1: If Object is an identifier, try resolving as a type name (Console, Math, etc.)
        if (memberAccess.Object is IdentifierExpression id)
        {
            // Try as .NET type name first (static access like Console.WriteLine)
            var resolvedType = _typeResolver.ResolveType(id.Name);
            if (resolvedType != null)
            {
                _logger.LogDebug("Resolved '{Name}' as static .NET type", id.Name);
                return MembersToCompletionItems(_typeResolver.GetMembers(resolvedType, MemberAccessMode.StaticOnly));
            }

            // Try semantic model for variable type
            var typeInfo = doc.SemanticModel!.LookupIdentifier(id.Name);
            if (typeInfo != null)
            {
                // Try to resolve TypeInfo to System.Type
                var typeName = typeInfo.ToString();
                var clrType = _typeResolver.ResolveType(typeName);
                if (clrType != null)
                {
                    _logger.LogDebug("Resolved variable '{Name}' type '{TypeName}' to CLR type", id.Name, typeName);
                    return MembersToCompletionItems(_typeResolver.GetMembers(clrType, MemberAccessMode.InstanceOnly));
                }

                // TypeInfo is a user-defined N# type — enumerate members from SymbolsInfo
                var nsharpMembers = GetNSharpTypeMembers(typeInfo, doc);
                if (nsharpMembers.Count > 0)
                {
                    _logger.LogDebug("Resolved '{Name}' as N# type with {Count} members", id.Name, nsharpMembers.Count);
                    return nsharpMembers;
                }
            }
        }

        _logger.LogDebug("Could not resolve type for member access");
        return new List<CompletionItem>();
    }

    /// <summary>
    /// Get members from a user-defined N# type (class, struct, record) via SymbolsInfo
    /// </summary>
    private List<CompletionItem> GetNSharpTypeMembers(TypeInfo typeInfo, Models.DocumentState doc)
    {
        var items = new List<CompletionItem>();
        if (doc.SymbolsInfo == null) return items;

        // Get the type name from the TypeInfo — handle all TypeInfo variants
        string? typeName = typeInfo switch
        {
            ClassTypeInfo c => c.Declaration.Name,
            StructTypeInfo s => s.Declaration.Name,
            RecordTypeInfo r => r.Declaration.Name,
            InterfaceTypeInfo i => i.Declaration.Name,
            UnionTypeInfo u => u.Declaration.Name,
            _ => typeInfo.ToString() // SimpleTypeInfo, etc. — ToString() returns the type name
        };

        if (typeName != null && doc.SymbolsInfo.TryGetValue(typeName, out var symbolInfo))
        {
            foreach (var member in symbolInfo.Members)
            {
                items.Add(new CompletionItem
                {
                    Label = member.Name,
                    Kind = GetCompletionItemKindFromSymbol(member.Kind),
                    Detail = GetSymbolDetail(member),
                    InsertText = member.Name
                });
            }
        }

        return items;
    }

    /// <summary>
    /// Determine if a member access is on a type (static) vs on a variable (instance)
    /// </summary>
    private bool IsStaticTypeAccess(Expression objectExpr, Models.DocumentState doc)
    {
        if (objectExpr is not IdentifierExpression id) return false;

        // If the identifier exists as a variable in the semantic model, it's instance access
        if (doc.SemanticModel?.LookupIdentifier(id.Name) != null) return false;

        // If the identifier resolves as a type name, it's static access
        return _typeResolver.ResolveType(id.Name) != null;
    }

    /// <summary>
    /// Convert MemberCompletionItems to LSP CompletionItems
    /// </summary>
    private static List<CompletionItem> MembersToCompletionItems(List<MemberCompletionItem> members)
    {
        return members.Select(member => new CompletionItem
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
                ? new MarkupContent { Kind = MarkupKind.Markdown, Value = member.Documentation }
                : null
        }).ToList();
    }

    /// <summary>
    /// Fallback: text-based member completion (used when AST is too broken)
    /// </summary>
    private List<CompletionItem> GetMemberCompletionFallback(Models.DocumentState doc, int line, int character)
    {
        var items = new List<CompletionItem>();
        var text = doc.Text;
        if (text == null) return items;

        var lines = text.Split('\n');
        if (line >= lines.Length) return items;

        var lineText = lines[line];
        if (character == 0) return items;

        var beforeDot = lineText.Substring(0, Math.Min(character, lineText.Length)).TrimEnd();
        if (!beforeDot.EndsWith(".")) return items;
        beforeDot = beforeDot.Substring(0, beforeDot.Length - 1).TrimEnd();

        var identifier = ExtractIdentifier(beforeDot);
        if (string.IsNullOrEmpty(identifier)) return items;

        // Try semantic model
        Type? type = null;
        if (doc.SemanticModel != null)
        {
            var typeInfo = doc.SemanticModel.LookupIdentifier(identifier);
            if (typeInfo != null)
                type = _typeResolver.ResolveType(typeInfo.ToString());
        }

        // Try as type name
        type ??= _typeResolver.ResolveType(identifier);

        if (type != null)
            return MembersToCompletionItems(_typeResolver.GetMembers(type));

        return items;
    }

    /// <summary>
    /// Build a dotted namespace path from a chain of MemberAccessExpressions
    /// e.g., System.Collections.Generic → "System.Collections.Generic"
    /// </summary>
    private static string? BuildNamespacePath(MemberAccessExpression memberAccess)
    {
        var parts = new List<string>();
        if (!string.IsNullOrEmpty(memberAccess.MemberName) && memberAccess.MemberName != "<error>")
            parts.Add(memberAccess.MemberName);

        Expression current = memberAccess.Object;
        while (current is MemberAccessExpression inner)
        {
            if (!string.IsNullOrEmpty(inner.MemberName) && inner.MemberName != "<error>")
                parts.Insert(0, inner.MemberName);
            current = inner.Object;
        }

        if (current is IdentifierExpression rootId)
        {
            parts.Insert(0, rootId.Name);
            return string.Join(".", parts);
        }

        return null;
    }

    /// <summary>
    /// Get sub-namespace names under a prefix (e.g., "System" → ["Collections", "Threading", "Linq", ...])
    /// </summary>
    private List<string> GetSubNamespaces(string prefix)
    {
        var subNamespaces = new HashSet<string>();
        var dotPrefix = prefix + ".";

        // Check all known namespace prefixes
        foreach (var ns in new[] { "System", "System.Collections", "System.Collections.Generic",
            "System.Linq", "System.Text", "System.Threading", "System.Threading.Tasks",
            "System.IO", "System.Net", "System.Net.Http" })
        {
            if (ns.StartsWith(dotPrefix) && ns.Length > dotPrefix.Length)
            {
                var remainder = ns.Substring(dotPrefix.Length);
                var nextDot = remainder.IndexOf('.');
                subNamespaces.Add(nextDot >= 0 ? remainder.Substring(0, nextDot) : remainder);
            }
        }

        return subNamespaces.ToList();
    }

    /// <summary>
    /// Convert namespace types to CompletionItems
    /// </summary>
    private static List<CompletionItem> NamespaceTypesToCompletionItems(
        List<(string Name, string FullName, bool IsStatic, bool IsInterface, bool IsEnum)> types)
    {
        return types.Select(t => new CompletionItem
        {
            Label = t.Name,
            Kind = t.IsInterface ? CompletionItemKind.Interface
                : t.IsEnum ? CompletionItemKind.Enum
                : CompletionItemKind.Class,
            Detail = t.FullName,
            InsertText = t.Name
        }).ToList();
    }

    private static string ExtractIdentifier(string text)
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
