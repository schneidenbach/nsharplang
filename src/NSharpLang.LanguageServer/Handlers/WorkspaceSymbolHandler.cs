using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using OmniSharp.Extensions.LanguageServer.Protocol.Workspace;
using CodeIntel = NSharpLang.Compiler.CodeIntelligence;
using LspSymbolKind = OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles workspace/symbol requests (Ctrl+T — Go to Symbol in Workspace).
///
/// WHICH names a file offers, in WHAT order and WHERE each one sits are N#-owned by
/// <c>EditorWorkspaceSymbolFacts</c>: the subsequence match, the one-level member expansion, the
/// rule that a member is only reached through a matching type, and the coordinate arithmetic —
/// including the shipped off-by-one the owner's contract now pins. What is left here is the
/// protocol: OmniSharp's WorkspaceSymbol and the wire numbers of its symbol kinds.
/// </summary>
public class WorkspaceSymbolHandler : WorkspaceSymbolsHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<WorkspaceSymbolHandler> _logger;

    public WorkspaceSymbolHandler(DocumentManager documentManager, ILogger<WorkspaceSymbolHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<WorkspaceSymbol>?> Handle(WorkspaceSymbolParams request, CancellationToken cancellationToken)
    {
        var query = request.Query ?? string.Empty;
        _logger.LogDebug("Workspace symbol request: '{Query}'", query);

        var symbols = new List<WorkspaceSymbol>();

        foreach (var doc in _documentManager.GetAllDocuments())
        {
            if (cancellationToken.IsCancellationRequested) break;

            foreach (var row in CodeIntel.EditorWorkspaceSymbolFacts.SymbolRows(doc.CompilationUnit, doc.Text, query))
            {
                symbols.Add(new WorkspaceSymbol
                {
                    Name = row.Name,
                    Kind = ConvertSymbolKind(row.Kind),
                    Location = new Location
                    {
                        Uri = DocumentUri.From(doc.Uri),
                        Range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                            row.Line, row.StartCharacter, row.Line, row.EndCharacter)
                    },
                    ContainerName = row.ContainerName
                });
            }
        }

        _logger.LogDebug("Returning {Count} workspace symbols", symbols.Count);
        return Task.FromResult<Container<WorkspaceSymbol>?>(new Container<WorkspaceSymbol>(symbols));
    }

    protected override WorkspaceSymbolRegistrationOptions CreateRegistrationOptions(
        WorkspaceSymbolCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new WorkspaceSymbolRegistrationOptions();
    }

    /// <summary>
    /// The owner's subsequence match, under the name nine years of callers and the
    /// internals-visibility fixture know it by.
    /// </summary>
    internal static bool MatchesQuery(string name, string query)
        => CodeIntel.EditorWorkspaceSymbolFacts.MatchesQuery(name, query);

    private static LspSymbolKind ConvertSymbolKind(CodeIntel.EditorSymbolTableKind kind)
    {
        return kind switch
        {
            CodeIntel.EditorSymbolTableKind.Class => LspSymbolKind.Class,
            CodeIntel.EditorSymbolTableKind.Struct => LspSymbolKind.Struct,
            CodeIntel.EditorSymbolTableKind.Record => LspSymbolKind.Class,
            CodeIntel.EditorSymbolTableKind.Interface => LspSymbolKind.Interface,
            CodeIntel.EditorSymbolTableKind.Enum => LspSymbolKind.Enum,
            CodeIntel.EditorSymbolTableKind.Union => LspSymbolKind.Enum,
            CodeIntel.EditorSymbolTableKind.Function => LspSymbolKind.Function,
            CodeIntel.EditorSymbolTableKind.Method => LspSymbolKind.Method,
            CodeIntel.EditorSymbolTableKind.Property => LspSymbolKind.Property,
            CodeIntel.EditorSymbolTableKind.Field => LspSymbolKind.Field,
            CodeIntel.EditorSymbolTableKind.Parameter => LspSymbolKind.Variable,
            CodeIntel.EditorSymbolTableKind.LocalVariable => LspSymbolKind.Variable,
            CodeIntel.EditorSymbolTableKind.EnumMember => LspSymbolKind.EnumMember,
            CodeIntel.EditorSymbolTableKind.Constructor => LspSymbolKind.Constructor,
            _ => LspSymbolKind.Variable
        };
    }
}
