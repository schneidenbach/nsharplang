using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
using MediatR;
using Microsoft.Extensions.Logging;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspCodeAction = OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeAction;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;
using LspDiagnostic = OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic;
using LspCodeActionKind = OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeActionKind;
using LspTextEdit = OmniSharp.Extensions.LanguageServer.Protocol.Models.TextEdit;
using CompilerCodeAction = NSharpLang.Compiler.CodeAction;
using CompilerDiagnostic = NSharpLang.Compiler.Diagnostic;
using CompilerCodeActionKind = NSharpLang.Compiler.CodeActionKind;
using DocumentState = NSharpLang.LanguageServer.Models.DocumentState;
using DocumentUri = OmniSharp.Extensions.LanguageServer.Protocol.DocumentUri;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/codeAction requests.
///
/// WHICH DIAGNOSTIC A FIX IS FOR is N#-owned by <c>EditorCodeActionFacts</c>: the client hands
/// back the diagnostics it is showing, and finding the compiler's own diagnostic again — the
/// linter's list first, then the compiler's, matched on code AND exact position, rebuilt with the
/// contextual hint standing in for a missing suggestion — is that owner's answer. What is left
/// here is the protocol: OmniSharp's CodeAction, WorkspaceEdit and the wire names of its kinds.
/// </summary>
public class CodeActionHandler : CodeActionHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<CodeActionHandler> _logger;
    private readonly CodeFixService _codeFixService;

    public CodeActionHandler(
        DocumentManager documentManager,
        ILogger<CodeActionHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
        _codeFixService = new CodeFixService();
    }

    public override Task<CommandOrCodeActionContainer?> Handle(
        CodeActionParams request,
        CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        _logger.LogInformation("Code action requested for {Uri} at {Range}", uri, request.Range);

        if (doc?.Ast == null || doc.Source == null)
        {
            _logger.LogWarning("No AST or source available for {Uri}", uri);
            return Task.FromResult<CommandOrCodeActionContainer?>(null);
        }

        var codeActions = new List<LspCodeAction>();

        // Get diagnostics at the requested location
        var diagnosticsAtLocation = request.Context.Diagnostics
            .Where(d => d.Source == "N#")
            .ToList();

        _logger.LogInformation("Found {Count} diagnostics at location", diagnosticsAtLocation.Count);

        // Get code actions for each diagnostic
        foreach (var lspDiagnostic in diagnosticsAtLocation)
        {
            // Convert LSP diagnostic to compiler diagnostic
            var compilerDiagnostic = ConvertToCompilerDiagnostic(lspDiagnostic, doc);

            if (compilerDiagnostic != null)
            {
                var fixes = _codeFixService.GetCodeActions(
                    compilerDiagnostic,
                    doc.Ast,
                    doc.Source);

                _logger.LogInformation("Found {Count} fixes for diagnostic {Code}",
                    fixes.Count,
                    compilerDiagnostic.Code);

                foreach (var fix in fixes)
                {
                    var lspCodeAction = ConvertToLspCodeAction(fix, request.TextDocument.Uri, lspDiagnostic);
                    codeActions.Add(lspCodeAction);
                }
            }
        }

        if (codeActions.Count == 0)
        {
            _logger.LogInformation("No code actions available");
            return Task.FromResult<CommandOrCodeActionContainer?>(null);
        }

        _logger.LogInformation("Returning {Count} code actions", codeActions.Count);
        var commandOrCodeActions = codeActions.Select(ca => new CommandOrCodeAction(ca));
        return Task.FromResult<CommandOrCodeActionContainer?>(new CommandOrCodeActionContainer(commandOrCodeActions));
    }

    private static CompilerDiagnostic? ConvertToCompilerDiagnostic(
        LspDiagnostic lspDiagnostic,
        DocumentState doc)
    {
        return EditorCodeActionFacts.DiagnosticAt(
            doc.LinterDiagnostics,
            doc.Diagnostics,
            lspDiagnostic.Code?.String,
            // The wire counts from zero and the compiler counts from one.
            (int)lspDiagnostic.Range.Start.Line + 1,
            (int)lspDiagnostic.Range.Start.Character + 1);
    }

    private LspCodeAction ConvertToLspCodeAction(
        CompilerCodeAction action,
        DocumentUri uri,
        LspDiagnostic? diagnostic)
    {
        // Convert text edits
        var changes = new Dictionary<DocumentUri, IEnumerable<LspTextEdit>>();
        var textEdits = action.Edits.Select(edit => new LspTextEdit
        {
            Range = new LspRange(
                edit.StartLine - 1,  // Convert to 0-based
                edit.StartColumn,
                edit.EndLine - 1,
                edit.EndColumn),
            NewText = edit.NewText
        }).ToList();

        changes[uri] = textEdits;

        var isSuggestionOnly = action.Safety == Compiler.FixSafety.SuggestionOnly;

        var lspAction = new LspCodeAction
        {
            Title = action.Title,
            Kind = ConvertCodeActionKind(action.Kind),
            // Omit workspace edit for SuggestionOnly to prevent non-conformant clients from applying
            Edit = isSuggestionOnly ? null : new WorkspaceEdit { Changes = changes },
            // Safe fixes are preferred (shown first / auto-applicable)
            IsPreferred = action.Safety == Compiler.FixSafety.Safe,
            // SuggestionOnly fixes are disabled — the user must handle them manually
            Disabled = isSuggestionOnly
                ? new CodeActionDisabled { Reason = "Suggestion only — manual review required" }
                : null,
            // Link to the diagnostic if provided
            Diagnostics = diagnostic != null ? new Container<LspDiagnostic>(diagnostic) : null
        };

        return lspAction;
    }

    private LspCodeActionKind ConvertCodeActionKind(CompilerCodeActionKind kind)
    {
        return kind switch
        {
            CompilerCodeActionKind.QuickFix => LspCodeActionKind.QuickFix,
            CompilerCodeActionKind.Refactor => LspCodeActionKind.Refactor,
            CompilerCodeActionKind.RefactorExtract => LspCodeActionKind.RefactorExtract,
            CompilerCodeActionKind.RefactorInline => LspCodeActionKind.RefactorInline,
            CompilerCodeActionKind.RefactorRewrite => LspCodeActionKind.RefactorRewrite,
            CompilerCodeActionKind.Source => LspCodeActionKind.Source,
            CompilerCodeActionKind.SourceOrganizeImports => LspCodeActionKind.SourceOrganizeImports,
            _ => LspCodeActionKind.QuickFix
        };
    }

    // Implement required Handle method from base class
    public override Task<LspCodeAction> Handle(LspCodeAction request, CancellationToken cancellationToken)
    {
        // This method is called when resolving a code action - not currently used
        return Task.FromResult(request);
    }

    protected override CodeActionRegistrationOptions CreateRegistrationOptions(
        CodeActionCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new CodeActionRegistrationOptions
        {
            CodeActionKinds = new Container<LspCodeActionKind>(
                LspCodeActionKind.QuickFix,
                LspCodeActionKind.Refactor,
                LspCodeActionKind.RefactorExtract,
                LspCodeActionKind.RefactorInline,
                LspCodeActionKind.RefactorRewrite,
                LspCodeActionKind.Source,
                LspCodeActionKind.SourceOrganizeImports
            )
        };
    }
}
