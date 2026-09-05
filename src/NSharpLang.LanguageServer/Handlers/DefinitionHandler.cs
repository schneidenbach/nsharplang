using System;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles go-to-definition requests (F12 in VS Code)
/// </summary>
public class DefinitionHandler : DefinitionHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<DefinitionHandler> _logger;

    public DefinitionHandler(DocumentManager documentManager, ILogger<DefinitionHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<LocationOrLocationLinks?> Handle(DefinitionParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<LocationOrLocationLinks?>(null);
        }

        try
        {
            // Get the word at the cursor position
            var word = EditorUtilities.GetWordAtPosition(doc.Text, request.Position.Line, request.Position.Character);
            if (string.IsNullOrWhiteSpace(word))
            {
                return Task.FromResult<LocationOrLocationLinks?>(null);
            }

            _logger.LogDebug("Go to definition for: {Word}", word);

            // Tier 1: Semantic project snapshot (open buffers override disk files)
            var projectDefinition = _documentManager.FindProjectDefinition(uri, request.Position.Line, request.Position.Character);
            if (projectDefinition != null)
            {
                return Task.FromResult<LocationOrLocationLinks?>(CreateProjectLocation(uri, projectDefinition));
            }

            return Task.FromResult<LocationOrLocationLinks?>(null);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling go to definition");
            return Task.FromResult<LocationOrLocationLinks?>(null);
        }
    }

    private LocationOrLocationLinks CreateProjectLocation(string uri, NSharpLang.Compiler.CodeIntelligence.DefinitionResult result)
    {
        var projectRoot = _documentManager.GetProjectRootForUri(uri);
        var filePath = _documentManager.ResolveProjectFilePath(projectRoot, result.File);
        var location = new Location
        {
            Uri = DocumentUri.From(new Uri(filePath).AbsoluteUri),
            Range = new LspRange(
                result.Line - 1,
                result.Column - 1,
                result.Line - 1,
                result.Column - 1 + Math.Max(1, result.Length))
        };
        return new LocationOrLocationLinks(location);
    }

    protected override DefinitionRegistrationOptions CreateRegistrationOptions(
        DefinitionCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new DefinitionRegistrationOptions();
    }

}
