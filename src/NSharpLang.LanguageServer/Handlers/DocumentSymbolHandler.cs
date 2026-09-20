using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using CodeIntel = NSharpLang.Compiler.CodeIntelligence;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;
using LspSymbolKind = OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/documentSymbol requests to provide the Outline panel in VS Code.
/// Maps N# declarations (types, functions, fields, etc.) to LSP DocumentSymbol hierarchy.
///
/// WHICH declarations appear, in WHAT order, nested under what, with what detail text, and the
/// two spans — including the clamps that keep the full range containing the selection range — are
/// N#-owned by <c>EditorDocumentSymbolFacts</c>. What is left here is the protocol: OmniSharp's
/// DocumentSymbol and the wire numbers of its symbol kinds, which N# cannot name.
/// </summary>
public class DocumentSymbolHandler : DocumentSymbolHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<DocumentSymbolHandler> _logger;

    public DocumentSymbolHandler(DocumentManager documentManager, ILogger<DocumentSymbolHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<SymbolInformationOrDocumentSymbolContainer?> Handle(
        DocumentSymbolParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.CompilationUnit == null)
        {
            return Task.FromResult<SymbolInformationOrDocumentSymbolContainer?>(null);
        }

        _logger.LogDebug("Document symbol request for {Uri}", uri);

        var rows = CodeIntel.EditorDocumentSymbolFacts.SymbolRows(doc.CompilationUnit, doc.Text?.Split('\n'));

        var result = new SymbolInformationOrDocumentSymbolContainer(
            rows.Select(row => new SymbolInformationOrDocumentSymbol(ToDocumentSymbol(row))));

        return Task.FromResult<SymbolInformationOrDocumentSymbolContainer?>(result);
    }

    protected override DocumentSymbolRegistrationOptions CreateRegistrationOptions(
        DocumentSymbolCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new DocumentSymbolRegistrationOptions();
    }

    private static DocumentSymbol ToDocumentSymbol(CodeIntel.EditorDocumentSymbolRow row)
    {
        var children = new List<DocumentSymbol>();
        foreach (var child in row.Children)
        {
            children.Add(ToDocumentSymbol(child));
        }

        return new DocumentSymbol
        {
            Name = row.Name,
            Kind = ToSymbolKind(row.Kind),
            Range = new LspRange(row.StartLine, 0, row.EndLine, row.EndCharacter),
            SelectionRange = new LspRange(row.StartLine, 0, row.StartLine, row.SelectionEndCharacter),
            Detail = row.Detail,
            Children = children.Count > 0 ? new Container<DocumentSymbol>(children) : null
        };
    }

    private static LspSymbolKind ToSymbolKind(CodeIntel.EditorSymbolKind kind)
    {
        return kind switch
        {
            CodeIntel.EditorSymbolKind.Function => LspSymbolKind.Function,
            CodeIntel.EditorSymbolKind.Method => LspSymbolKind.Method,
            CodeIntel.EditorSymbolKind.Class => LspSymbolKind.Class,
            CodeIntel.EditorSymbolKind.Struct => LspSymbolKind.Struct,
            CodeIntel.EditorSymbolKind.Interface => LspSymbolKind.Interface,
            CodeIntel.EditorSymbolKind.Enum => LspSymbolKind.Enum,
            CodeIntel.EditorSymbolKind.EnumMember => LspSymbolKind.EnumMember,
            CodeIntel.EditorSymbolKind.Field => LspSymbolKind.Field,
            CodeIntel.EditorSymbolKind.Property => LspSymbolKind.Property,
            _ => LspSymbolKind.Constructor
        };
    }
}
