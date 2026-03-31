using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
using NSharpLang.LanguageServer.Models;
using Microsoft.Extensions.Logging;
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

            // Verify the symbol exists in our symbol locations or semantic model
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

            var projectReferences = _documentManager.FindProjectReferences(uri, request.Position.Line, request.Position.Character);
            if (projectReferences != null)
            {
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

            if (_documentManager.HasSynchronizedProjectSnapshot(uri))
            {
                return Task.FromResult<WorkspaceEdit?>(null);
            }

            // Find all references to this symbol in the document
            var references = _documentManager.FindAllReferences(uri, oldName);
            if (references.Count == 0)
            {
                _logger.LogDebug("No references found for '{Name}'", oldName);
                return Task.FromResult<WorkspaceEdit?>(null);
            }

            _logger.LogInformation("Found {Count} references to '{Name}'", references.Count, oldName);

            // Build text edits for each reference
            var edits = references.Select(r => new TextEdit
            {
                Range = new LspRange(r.Line, r.Column, r.Line, r.Column + r.Length),
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

}
