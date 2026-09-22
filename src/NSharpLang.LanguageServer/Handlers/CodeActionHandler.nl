namespace NSharpLang.LanguageServer.Handlers

import System.Collections.Generic
import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.LanguageServer.Models
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// Handles textDocument/codeAction requests.
//
// WHICH DIAGNOSTIC A FIX IS FOR is N#-owned by `EditorCodeActionFacts`: the client hands back the
// diagnostics it is showing, and finding the compiler's own diagnostic again — the linter's list
// first, then the compiler's, matched on code AND exact position, rebuilt with the contextual hint
// standing in for a missing suggestion — is that owner's answer. What is left here is the protocol:
// OmniSharp's CodeAction, WorkspaceEdit and the wire names of its kinds.
class CodeActionHandler: CodeActionHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<CodeActionHandler>
    readonly codeFixService: CodeFixService

    constructor(documentManager: DocumentManager, logger: ILogger<CodeActionHandler>) {
        this.documentManager = documentManager
        this.logger = logger
        codeFixService = new CodeFixService()
    }

    override func Handle(request: CodeActionParams, cancellationToken: CancellationToken): Task<CommandOrCodeActionContainer?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        logger.LogInformation("Code action requested for {Uri} at {Range}", uri, request.Range)

        if doc == null || doc.Ast == null || doc.Source == null {
            logger.LogWarning("No AST or source available for {Uri}", uri)
            return Task.FromResult<CommandOrCodeActionContainer?>(null)
        }

        ast := doc.Ast
        source := doc.Source
        codeActions := new List<OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeAction>()

        // Get diagnostics at the requested location
        diagnosticsAtLocation := new List<OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic>()
        for candidate in request.Context.Diagnostics {
            if candidate.Source == "N#" {
                diagnosticsAtLocation.Add(candidate)
            }
        }

        logger.LogInformation("Found {Count} diagnostics at location", diagnosticsAtLocation.Count)

        // Get code actions for each diagnostic
        for lspDiagnostic in diagnosticsAtLocation {
            // Convert LSP diagnostic to compiler diagnostic
            compilerDiagnostic := convertToCompilerDiagnostic(lspDiagnostic, doc)

            if compilerDiagnostic != null {
                fixes := codeFixService.GetCodeActions(compilerDiagnostic, ast, source)

                logger.LogInformation("Found {Count} fixes for diagnostic {Code}", fixes.Count, compilerDiagnostic.Code)

                for fix in fixes {
                    codeActions.Add(convertToLspCodeAction(fix, request.TextDocument.Uri, lspDiagnostic))
                }
            }
        }

        if codeActions.Count == 0 {
            logger.LogInformation("No code actions available")
            return Task.FromResult<CommandOrCodeActionContainer?>(null)
        }

        logger.LogInformation("Returning {Count} code actions", codeActions.Count)
        commandOrCodeActions := new List<CommandOrCodeAction>()
        for codeAction in codeActions {
            commandOrCodeActions.Add(new CommandOrCodeAction(codeAction))
        }

        return Task.FromResult<CommandOrCodeActionContainer?>(new CommandOrCodeActionContainer(commandOrCodeActions))
    }

    static func convertToCompilerDiagnostic(
        lspDiagnostic: OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic,
        doc: DocumentState
    ): NSharpLang.Compiler.Diagnostic? {
        start := lspDiagnostic.Range.Start
        code := lspDiagnostic.Code?.String
        // The wire counts from zero and the compiler counts from one.
        line := (int)start.Line + 1
        column := (int)start.Character + 1

        return EditorCodeActionFacts.DiagnosticAt(doc.LinterDiagnostics, doc.Diagnostics, code, line, column)
    }

    func convertToLspCodeAction(
        action: NSharpLang.Compiler.CodeAction,
        uri: DocumentUri,
        diagnostic: OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic?
    ): OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeAction {
        // Convert text edits
        changes: IDictionary<DocumentUri, IEnumerable<OmniSharp.Extensions.LanguageServer.Protocol.Models.TextEdit>> = new Dictionary<DocumentUri, IEnumerable<OmniSharp.Extensions.LanguageServer.Protocol.Models.TextEdit>>()
        textEdits := new List<OmniSharp.Extensions.LanguageServer.Protocol.Models.TextEdit>()
        for edit in action.Edits {
            textEdits.Add(new OmniSharp.Extensions.LanguageServer.Protocol.Models.TextEdit {
                Range: new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                    edit.StartLine - 1,
                    // Convert to 0-based
                    edit.StartColumn,
                    edit.EndLine - 1,
                    edit.EndColumn
                ),
                NewText: edit.NewText
            })
        }

        changes[uri] = textEdits

        isSuggestionOnly := action.Safety == FixSafety.SuggestionOnly

        // Omit workspace edit for SuggestionOnly to prevent non-conformant clients from applying
        workspaceEdit: WorkspaceEdit? = null
        // SuggestionOnly fixes are disabled — the user must handle them manually
        disabled: CodeActionDisabled? = null
        if isSuggestionOnly {
            disabled = new CodeActionDisabled { Reason: "Suggestion only — manual review required" }
        } else {
            workspaceEdit = new WorkspaceEdit { Changes: changes }
        }

        // Link to the diagnostic if provided
        linkedDiagnostics: Container<OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic>? = null
        if diagnostic != null {
            linkedDiagnostics = new Container<OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic>(diagnostic)
        }

        kind := convertCodeActionKind(action.Kind)
        // Safe fixes are preferred (shown first / auto-applicable)
        isPreferred := action.Safety == FixSafety.Safe
        title := action.Title

        return new OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeAction {
            Title: title,
            Kind: kind,
            Edit: workspaceEdit,
            IsPreferred: isPreferred,
            Disabled: disabled,
            Diagnostics: linkedDiagnostics
        }
    }

    func convertCodeActionKind(kind: NSharpLang.Compiler.CodeActionKind): OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind {
        if kind == NSharpLang.Compiler.CodeActionKind.QuickFix {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind.QuickFix
        }
        if kind == NSharpLang.Compiler.CodeActionKind.Refactor {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind.Refactor
        }
        if kind == NSharpLang.Compiler.CodeActionKind.RefactorExtract {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind.RefactorExtract
        }
        if kind == NSharpLang.Compiler.CodeActionKind.RefactorInline {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind.RefactorInline
        }
        if kind == NSharpLang.Compiler.CodeActionKind.RefactorRewrite {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind.RefactorRewrite
        }
        if kind == NSharpLang.Compiler.CodeActionKind.Source {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind.Source
        }
        if kind == NSharpLang.Compiler.CodeActionKind.SourceOrganizeImports {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind.SourceOrganizeImports
        }

        return OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind.QuickFix
    }

    // Implement required Handle method from base class
    override func Handle(request: OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeAction, cancellationToken: CancellationToken): Task<OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeAction> {
        // This method is called when resolving a code action - not currently used
        return Task.FromResult(request)
    }

    protected override func CreateRegistrationOptions(
        capability: CodeActionCapability,
        clientCapabilities: ClientCapabilities
    ): CodeActionRegistrationOptions {
        return new CodeActionRegistrationOptions {
            CodeActionKinds: new Container<OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind>(
                OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind.QuickFix,
                OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind.Refactor,
                OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind.RefactorExtract,
                OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind.RefactorInline,
                OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind.RefactorRewrite,
                OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind.Source,
                OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind.SourceOrganizeImports
            )
        }
    }
}
