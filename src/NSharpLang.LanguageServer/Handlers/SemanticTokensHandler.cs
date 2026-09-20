using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Models;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using CodeIntel = NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/semanticTokens/full requests.
///
/// WHICH tokens are painted and WHAT each one is are N#-owned by
/// <c>EditorSemanticTokenFacts</c>: the order of the identifier rules, the re-lexing of an
/// interpolated literal's holes, the walk that finds the Go-style error capture, and the three
/// reasons a classified token is still not emitted. What is left here is the protocol — the
/// LEGEND, whose order is a promise this server made to the client at startup, and the symbol
/// tables the editor keeps in its own C# shapes.
/// </summary>
public class SemanticTokensHandler : SemanticTokensHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<SemanticTokensHandler> _logger;

    // Token types in legend order — index matters!
    internal static readonly string[] TokenTypes =
    {
        "namespace",      // 0
        "type",           // 1
        "class",          // 2
        "struct",         // 3
        "enum",           // 4
        "interface",      // 5
        "typeParameter",  // 6
        "parameter",      // 7
        "variable",       // 8
        "property",       // 9
        "function",       // 10
        "method",         // 11
        "keyword",        // 12
        "comment",        // 13
        "string",         // 14
        "number",         // 15
        "operator",       // 16
        "enumMember",     // 17
    };

    // Token modifiers in legend order — index matters!
    internal static readonly string[] TokenModifiers =
    {
        "declaration",    // 0
        "definition",     // 1
        "readonly",       // 2
        "static",         // 3
        "async",          // 4
        "catchResult",    // 5
    };

    internal const int CatchResultModifierMask = 1 << 5;

    public SemanticTokensHandler(DocumentManager documentManager, ILogger<SemanticTokensHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    protected override SemanticTokensRegistrationOptions CreateRegistrationOptions(
        SemanticTokensCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new SemanticTokensRegistrationOptions
        {
            Full = new SemanticTokensCapabilityRequestFull { Delta = false },
            Legend = new SemanticTokensLegend
            {
                TokenTypes = new Container<SemanticTokenType>(
                    TokenTypes.Select(t => new SemanticTokenType(t))),
                TokenModifiers = new Container<SemanticTokenModifier>(
                    TokenModifiers.Select(m => new SemanticTokenModifier(m))),
            },
        };
    }

    protected override Task<SemanticTokensDocument> GetSemanticTokensDocument(
        ITextDocumentIdentifierParams @params, CancellationToken cancellationToken)
    {
        return Task.FromResult(new SemanticTokensDocument(CreateRegistrationOptions(
            new SemanticTokensCapability(), new ClientCapabilities())));
    }

    protected override Task Tokenize(SemanticTokensBuilder builder, ITextDocumentIdentifierParams identifier, CancellationToken cancellationToken)
    {
        var uri = identifier.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Tokens == null || doc.Text == null)
        {
            return Task.CompletedTask;
        }

        _logger.LogDebug("Semantic tokens request for {Uri} with {TokenCount} tokens", uri, doc.Tokens.Count);

        foreach (var row in CodeIntel.EditorSemanticTokenFacts.TokenRows(
            doc.Tokens,
            doc.CompilationUnit,
            doc.SemanticModel,
            BuildTypeNameSet(doc),
            BuildTypeKindMap(doc),
            BuildFunctionNameSet(doc),
            BuildPropertyNameSet(doc),
            BuildEnumMemberNameSet(doc)))
        {
            if (cancellationToken.IsCancellationRequested) break;

            builder.Push(
                row.Line, row.Character, row.Length,
                LegendIndex(row.Kind),
                row.IsCatchResult ? CatchResultModifierMask : 0);
        }

        return Task.CompletedTask;
    }

    /// <summary>
    /// The owner's kind word placed in this server's legend. The legend's order is the protocol
    /// contract; the word is what the owner decided.
    /// </summary>
    private static int LegendIndex(string kind)
    {
        for (var index = 0; index < TokenTypes.Length; index++)
        {
            if (TokenTypes[index] == kind)
            {
                return index;
            }
        }

        return 1; // "type"
    }

    internal static HashSet<string> BuildTypeNameSet(DocumentState doc)
    {
        var names = new HashSet<string>();

        if (doc.Symbols != null)
        {
            foreach (var name in doc.Symbols.Keys)
            {
                names.Add(name);
            }
        }

        if (doc.SymbolsInfo != null)
        {
            foreach (var (name, info) in doc.SymbolsInfo)
            {
                if (info.Kind is Models.SymbolKind.Class or Models.SymbolKind.Struct
                    or Models.SymbolKind.Record or Models.SymbolKind.Interface
                    or Models.SymbolKind.Enum or Models.SymbolKind.Union)
                {
                    names.Add(name);
                }
            }
        }

        return names;
    }

    /// <summary>
    /// Every symbol's declared kind, named by the C# enum member. Which of those the outline paints
    /// as a class and which as an enum is the owner's decision, not this map's.
    /// </summary>
    internal static Dictionary<string, string> BuildTypeKindMap(DocumentState doc)
    {
        var kinds = new Dictionary<string, string>();

        if (doc.SymbolsInfo != null)
        {
            foreach (var (name, info) in doc.SymbolsInfo)
            {
                kinds[name] = info.Kind.ToString();
            }
        }

        return kinds;
    }

    internal static HashSet<string> BuildFunctionNameSet(DocumentState doc)
    {
        var names = new HashSet<string>();

        if (doc.SymbolsInfo != null)
        {
            foreach (var (name, info) in doc.SymbolsInfo)
            {
                if (info.Kind is Models.SymbolKind.Function or Models.SymbolKind.Method)
                {
                    names.Add(name);
                }
            }
        }

        if (doc.SemanticModel != null)
        {
            foreach (var name in doc.SemanticModel.Functions.Keys)
            {
                names.Add(name);
            }
        }

        return names;
    }

    internal static HashSet<string> BuildPropertyNameSet(DocumentState doc)
    {
        var names = new HashSet<string>();

        if (doc.SymbolsInfo != null)
        {
            foreach (var (_, info) in doc.SymbolsInfo)
            {
                foreach (var member in info.Members)
                {
                    if (member.Kind is Models.SymbolKind.Property)
                    {
                        names.Add(member.Name);
                    }
                }
            }
        }

        return names;
    }

    internal static HashSet<string> BuildEnumMemberNameSet(DocumentState doc)
    {
        var names = new HashSet<string>();

        if (doc.SymbolsInfo != null)
        {
            foreach (var (_, info) in doc.SymbolsInfo)
            {
                foreach (var member in info.Members)
                {
                    if (member.Kind is Models.SymbolKind.EnumMember)
                    {
                        names.Add(member.Name);
                    }
                }
            }
        }

        return names;
    }
}
