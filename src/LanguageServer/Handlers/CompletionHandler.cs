using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NewCLILang.Compiler;
using NewCLILang.Compiler.Ast;
using LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;

namespace LanguageServer.Handlers;

/// <summary>
/// Handles code completion (Ctrl+Space in VS Code)
/// </summary>
public class CompletionHandler : CompletionHandlerBase
{
    private readonly DocumentManager _documentManager;
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

    public CompletionHandler(DocumentManager documentManager, ILogger<CompletionHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<CompletionList> Handle(CompletionParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        var items = new List<CompletionItem>();

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

                // For types with members, we could potentially add member completion here
                // but that would be better done with context-aware completion (e.g., after a dot)
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
