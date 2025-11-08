using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NewCLILang.Compiler;
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

        // Add types from the current document
        if (doc?.Symbols != null)
        {
            foreach (var (name, typeInfo) in doc.Symbols)
            {
                items.Add(new CompletionItem
                {
                    Label = name,
                    Kind = GetCompletionItemKind(typeInfo),
                    Detail = typeInfo.GetType().Name.Replace("TypeInfo", ""),
                    InsertText = name
                });
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
            DocumentSelector = DocumentSelector.ForLanguage("nsharp"),
            ResolveProvider = false, // We provide all info upfront
            TriggerCharacters = new[] { ".", ":", " " }
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
}
