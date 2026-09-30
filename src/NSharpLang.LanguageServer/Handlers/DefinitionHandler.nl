namespace NSharpLang.LanguageServer.Handlers

import System
import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// Handles go-to-definition requests (F12 in VS Code)
class DefinitionHandler: DefinitionHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<DefinitionHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<DefinitionHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: DefinitionParams, cancellationToken: CancellationToken): Task<LocationOrLocationLinks?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null || doc.Text == null {
            return Task.FromResult<LocationOrLocationLinks?>(null)
        }

        line := request.Position.Line
        character := request.Position.Character

        try {
            // Get the word at the cursor position
            word := EditorUtilities.GetWordAtPosition(doc.Text, line, character)
            if string.IsNullOrWhiteSpace(word) {
                return Task.FromResult<LocationOrLocationLinks?>(null)
            }

            logger.LogDebug("Go to definition for: {Word}", word)

            // Tier 1: Semantic project snapshot (open buffers override disk files)
            projectDefinition := documentManager.FindProjectDefinition(uri, line, character)
            if projectDefinition != null {
                return Task.FromResult<LocationOrLocationLinks?>(createProjectLocation(uri, projectDefinition))
            }

            return Task.FromResult<LocationOrLocationLinks?>(null)
        } catch failure: Exception {
            logger.LogError(failure, "Error handling go to definition")
            return Task.FromResult<LocationOrLocationLinks?>(null)
        }
    }

    func createProjectLocation(uri: string, result: DefinitionResult): LocationOrLocationLinks {
        projectRoot := documentManager.GetProjectRootForUri(uri)
        filePath := documentManager.ResolveProjectFilePath(projectRoot, result.File)
        // COMPILER: lsflip-2. Both values are bound to locals because an object initializer whose
        // member value is itself a `new` declines at `emit.local.initializer`.
        absoluteUri := new Uri(filePath).AbsoluteUri
        range := new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
            result.Line - 1,
            result.Column - 1,
            result.Line - 1,
            result.Column - 1 + Math.Max(1, result.Length)
        )
        location := new OmniSharp.Extensions.LanguageServer.Protocol.Models.Location {
            Uri: DocumentUri.From(absoluteUri),
            Range: range
        }

        return new LocationOrLocationLinks(location)
    }

    protected override func CreateRegistrationOptions(
        capability: DefinitionCapability,
        clientCapabilities: ClientCapabilities
    ): DefinitionRegistrationOptions {
        return new DefinitionRegistrationOptions()
    }
}
