using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
using NSharpLang.LanguageServer.Models;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.JsonRpc.Server;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles rename symbol requests (F2 in VS Code)
/// </summary>
public class RenameHandler : RenameHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<RenameHandler> _logger;

    public RenameHandler(DocumentManager documentManager, ILogger<RenameHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<WorkspaceEdit?> Handle(RenameParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<WorkspaceEdit?>(null);
        }

        try
        {
            var oldName = EditorUtilities.GetWordAtPosition(doc.Text, request.Position.Line, request.Position.Character);
            if (string.IsNullOrWhiteSpace(oldName))
            {
                _logger.LogDebug("No word at cursor position for rename");
                return Task.FromResult<WorkspaceEdit?>(null);
            }

            var newName = request.NewName;
            _logger.LogInformation("Rename: '{OldName}' → '{NewName}' in {Uri}", oldName, newName, uri);

            var hasSynchronizedProjectSnapshot = _documentManager.HasSynchronizedProjectSnapshot(uri);
            if (hasSynchronizedProjectSnapshot)
            {
                var projectReferences = _documentManager.FindStrictProjectReferences(uri, request.Position.Line, request.Position.Character);
                if (projectReferences == null)
                {
                    throw RenameRefused(
                        $"Rename for '{oldName}' is unavailable because semantic resolution could not safely identify the selected symbol. " +
                        "No edits were applied; refusing fallback rename to avoid editing unrelated symbols.");
                }

                var projectRoot = _documentManager.GetProjectRootForUri(uri);
                var changes = projectReferences
                    .GroupBy(reference => reference.File)
                    .ToDictionary(
                        group => DocumentUri.From(new Uri(_documentManager.ResolveProjectFilePath(projectRoot, group.Key)).AbsoluteUri),
                        group => (IEnumerable<TextEdit>)group
                            .OrderByDescending(reference => reference.Line)
                            .ThenByDescending(reference => reference.Column)
                            .Select(reference => new TextEdit
                            {
                                Range = new LspRange(
                                    reference.Line - 1,
                                    reference.Column - 1,
                                    reference.Line - 1,
                                    reference.Column - 1 + reference.Length),
                                NewText = newName
                            })
                            .ToList());

                return Task.FromResult<WorkspaceEdit?>(new WorkspaceEdit { Changes = changes });
            }

            if (_documentManager.HasSemanticProjectContext(uri))
            {
                throw RenameRefused(
                    $"Rename for '{oldName}' is unavailable because semantic project analysis is degraded. " +
                    "Save or fix the project files and retry; refusing text-only rename to avoid editing unrelated symbols.");
            }

            // Verify the symbol exists in our symbol locations or semantic model before
            // falling back to same-document text edits for synthetic/non-project files.
            var isKnownSymbol = false;
            if (doc.SymbolLocations?.ContainsKey(oldName) == true)
                isKnownSymbol = true;
            else if (doc.SemanticModel?.LookupIdentifier(oldName) != null)
                isKnownSymbol = true;

            if (!isKnownSymbol)
            {
                _logger.LogDebug("Symbol '{Name}' not found in symbol locations or semantic model", oldName);
                return Task.FromResult<WorkspaceEdit?>(null);
            }

            // Find strict semantic references in the standalone document. Text-only
            // document-wide rename is intentionally refused because it can edit
            // unrelated symbols that happen to share the same spelling.
            var references = _documentManager.FindStrictDocumentReferences(uri, request.Position.Line, request.Position.Character);

            if (references == null || references.Count == 0)
            {
                throw RenameRefused(
                    $"Rename for '{oldName}' is unavailable because semantic resolution could not safely identify the selected symbol. " +
                    "No edits were applied; refusing text-only rename to avoid editing unrelated symbols.");
            }

            var declarationCount = _documentManager.CountDocumentDeclarations(uri, oldName);
            if (declarationCount == 0)
            {
                throw RenameRefused(
                    $"Rename for '{oldName}' is unavailable because semantic resolution found no declaration for this symbol in the current document. " +
                    "No edits were applied; open the containing project and retry for cross-file symbols.");
            }

            if (declarationCount > 1)
            {
                throw RenameRefused(
                    $"Rename for '{oldName}' is unsafe without project semantics because this document declares {declarationCount} symbols with that name. " +
                    "No edits were applied; open the containing project or remove the ambiguity and retry.");
            }

            _logger.LogInformation("Found {Count} references to '{Name}'", references.Count, oldName);

            // Build text edits for each strict semantic reference
            var edits = references.Select(r => new TextEdit
            {
                Range = new LspRange(r.Line - 1, r.Column - 1, r.Line - 1, r.Column - 1 + r.Length),
                NewText = newName
            }).ToList();

            var workspaceEdit = new WorkspaceEdit
            {
                Changes = new Dictionary<DocumentUri, IEnumerable<TextEdit>>
                {
                    [DocumentUri.From(uri)] = edits
                }
            };

            return Task.FromResult<WorkspaceEdit?>(workspaceEdit);
        }
        catch (RequestFailedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling rename");
            return Task.FromResult<WorkspaceEdit?>(null);
        }
    }

    protected override RenameRegistrationOptions CreateRegistrationOptions(
        RenameCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new RenameRegistrationOptions
        {
            PrepareProvider = true
        };
    }

    private static RequestFailedException RenameRefused(string message)
    {
        return new RequestFailedException(
            ErrorCodes.RequestFailed,
            message,
            RequestFailedException.UnknownRequestId,
            inner: null!);
    }
}
