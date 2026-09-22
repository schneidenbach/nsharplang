namespace NSharpLang.LanguageServer.Handlers

import System
import System.Collections.Generic
import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.LanguageServer.Models
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.JsonRpc.Server
import OmniSharp.Extensions.LanguageServer.Protocol
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// Handles rename symbol requests (F2 in VS Code).
//
// WHAT EACH REFUSAL SAYS is N#-owned by `EditorRenameGuardFacts`, which the prepare handler beside
// this one shares — the two used to hold their own copies of the same three sentences.
class RenameHandler: RenameHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<RenameHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<RenameHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: RenameParams, cancellationToken: CancellationToken): Task<WorkspaceEdit?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null {
            return Task.FromResult<WorkspaceEdit?>(null)
        }

        line := request.Position.Line
        character := request.Position.Character

        try {
            oldName := EditorUtilities.GetWordAtPosition(doc.Text, line, character)
            if string.IsNullOrWhiteSpace(oldName) {
                logger.LogDebug("No word at cursor position for rename")
                return Task.FromResult<WorkspaceEdit?>(null)
            }

            newName := request.NewName
            logger.LogInformation("Rename: '{OldName}' → '{NewName}' in {Uri}", oldName, newName, uri)

            hasSynchronizedProjectSnapshot := documentManager.HasSynchronizedProjectSnapshot(uri)
            if hasSynchronizedProjectSnapshot {
                projectReferences := documentManager.FindStrictProjectReferences(uri, line, character)
                if projectReferences == null {
                    throw renameRefused(EditorRenameGuardFacts.RenameUnresolvedMessage(oldName))
                }

                projectRoot := documentManager.GetProjectRootForUri(uri)
                changes := planChanges(projectRoot, projectReferences, newName)
                return Task.FromResult<WorkspaceEdit?>(new WorkspaceEdit { Changes: changes })
            }

            if documentManager.HasSemanticProjectContext(uri) {
                throw renameRefused(EditorRenameGuardFacts.RenameDegradedMessage(oldName))
            }

            isKnownSymbol := false
            if doc.SymbolLocations?.ContainsKey(oldName) == true {
                isKnownSymbol = true
            }

            if !isKnownSymbol {
                logger.LogDebug("Symbol '{Name}' not found in symbol locations or semantic model", oldName)
                return Task.FromResult<WorkspaceEdit?>(null)
            }

            throw renameRefused(EditorRenameGuardFacts.RenameTextOnlyMessage(oldName))
        } catch refused: RequestFailedException {
            throw refused
        } catch failure: Exception {
            logger.LogError(failure, "Error handling rename")
            return Task.FromResult<WorkspaceEdit?>(null)
        }
    }

    // The owner groups the references by file and answers the edits for each group; what is left
    // here is the `file://` key OmniSharp's change map is written with.
    func planChanges(
        projectRoot: string,
        projectReferences: List<ReferenceResult>,
        newName: string
    ): IDictionary<DocumentUri, IEnumerable<TextEdit>> {
        files := new List<string>()
        lines := new List<int>()
        columns := new List<int>()
        lengths := new List<int>()
        for reference in projectReferences {
            files.Add(reference.File)
            lines.Add(reference.Line)
            columns.Add(reference.Column)
            lengths.Add(reference.Length)
        }

        changes: IDictionary<DocumentUri, IEnumerable<TextEdit>> = new Dictionary<DocumentUri, IEnumerable<TextEdit>>()
        for group in EditorRenameEditFacts.Plan(files, lines, columns, lengths) {
            edits := new List<TextEdit>()
            for edit in group.Edits {
                edits.Add(new TextEdit {
                    Range: new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                        edit.Line,
                        edit.StartCharacter,
                        edit.Line,
                        edit.EndCharacter
                    ),
                    NewText: newName
                })
            }

            absoluteUri := new Uri(documentManager.ResolveProjectFilePath(projectRoot, group.File)).AbsoluteUri
            changes[DocumentUri.From(absoluteUri)] = edits
        }

        return changes
    }

    protected override func CreateRegistrationOptions(
        capability: RenameCapability,
        clientCapabilities: ClientCapabilities
    ): RenameRegistrationOptions {
        return new RenameRegistrationOptions {
            PrepareProvider: true
        }
    }

    static func renameRefused(message: string): RequestFailedException {
        return new RequestFailedException(
            ErrorCodes.RequestFailed,
            message,
            RequestFailedException.UnknownRequestId,
            null
        )
    }
}
