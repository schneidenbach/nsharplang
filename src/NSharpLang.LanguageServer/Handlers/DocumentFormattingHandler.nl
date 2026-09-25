namespace NSharpLang.LanguageServer.Handlers

import System
import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.Compiler
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// Handles textDocument/formatting requests to format N# source files
class DocumentFormattingHandler: DocumentFormattingHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<DocumentFormattingHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<DocumentFormattingHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: DocumentFormattingParams, cancellationToken: CancellationToken): Task<TextEditContainer?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null || doc.CompilationUnit == null {
            logger.LogDebug("Skipping formatting for {Uri}: document or AST unavailable", uri)
            return Task.FromResult<TextEditContainer?>(null)
        }

        config := new FormatterConfig {
            IndentSize: request.Options.TabSize,
            UseSpaces: request.Options.InsertSpaces
        }

        formattedText := ""
        try {
            formatter := new Formatter(config)
            result := formatter.FormatSafe(doc.Text, doc.CompilationUnit, doc.Comments, uri)
            for warning in result.Warnings {
                logger.LogWarning("Formatter safety warning for {Uri}: {Warning}", uri, warning)
            }

            if !result.Success {
                logger.LogWarning("Formatting aborted for {Uri}: safety checks failed", uri)
                return Task.FromResult<TextEditContainer?>(null)
            }

            formattedText = result.Text
        } catch failure: Exception {
            logger.LogError(failure, "Formatting failed for {Uri}", uri)
            return Task.FromResult<TextEditContainer?>(null)
        }

        if formattedText == doc.Text {
            logger.LogDebug("Document {Uri} is already formatted", uri)
            return Task.FromResult<TextEditContainer?>(new TextEditContainer())
        }

        lines := doc.Text.Split('\n')
        lastLine := lines.Length - 1
        lastLineLength := lines[lastLine].Length

        fullDocumentRange := new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(0, 0, lastLine, lastLineLength)

        logger.LogInformation("Formatted document {Uri}", uri)

        edit := new OmniSharp.Extensions.LanguageServer.Protocol.Models.TextEdit {
            Range: fullDocumentRange,
            NewText: formattedText
        }

        return Task.FromResult<TextEditContainer?>(new TextEditContainer(edit))
    }

    protected override func CreateRegistrationOptions(
        capability: DocumentFormattingCapability,
        clientCapabilities: ClientCapabilities
    ): DocumentFormattingRegistrationOptions {
        return new DocumentFormattingRegistrationOptions()
    }
}
