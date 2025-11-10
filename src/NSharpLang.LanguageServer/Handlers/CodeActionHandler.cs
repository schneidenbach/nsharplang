using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
using MediatR;
using Microsoft.Extensions.Logging;
using NSharpLang.Compiler;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspCodeAction = OmniSharp.Extensions.LanguageServer.Protocol.Models.CodeAction;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;
using CompilerCodeAction = NewCLILang.Compiler.CodeAction;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/codeAction requests for quick fixes and refactorings
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

        // Get refactorings not tied to diagnostics
        var line = (int)request.Range.Start.Line + 1; // Convert to 1-based
        var column = (int)request.Range.Start.Character + 1;
        var refactorings = _codeFixService.GetCodeActionsForDocument(doc.Ast, doc.Source, line, column);

        foreach (var refactoring in refactorings)
        {
            var lspCodeAction = ConvertToLspCodeAction(refactoring, request.TextDocument.Uri, null);
            codeActions.Add(lspCodeAction);
        }

        if (codeActions.Count == 0)
        {
            _logger.LogInformation("No code actions available");
            return Task.FromResult<CommandOrCodeActionContainer?>(null);
        }

        _logger.LogInformation("Returning {Count} code actions", codeActions.Count);
        return Task.FromResult<CommandOrCodeActionContainer?>(new CommandOrCodeActionContainer(codeActions));
    }

    private Diagnostic? ConvertToCompilerDiagnostic(
        OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic lspDiagnostic,
        DocumentState doc)
    {
        // Find matching diagnostic from the linter
        if (doc.LinterDiagnostics == null)
            return null;

        var line = (int)lspDiagnostic.Range.Start.Line + 1; // Convert to 1-based
        var column = (int)lspDiagnostic.Range.Start.Character + 1;

        // Find diagnostic at this location with matching code
        var code = lspDiagnostic.Code?.String;
        if (code == null)
            return null;

        return doc.LinterDiagnostics.FirstOrDefault(d =>
            d.Code == code &&
            d.Location.Line == line &&
            d.Location.Column == column);
    }

    private LspCodeAction ConvertToLspCodeAction(
        CompilerCodeAction action,
        DocumentUri uri,
        OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic? diagnostic)
    {
        // Convert text edits
        var changes = new Dictionary<DocumentUri, IEnumerable<TextEdit>>();
        var textEdits = action.Edits.Select(edit => new TextEdit
        {
            Range = new LspRange(
                edit.StartLine - 1,  // Convert to 0-based
                edit.StartColumn,
                edit.EndLine - 1,
                edit.EndColumn),
            NewText = edit.NewText
        }).ToList();

        changes[uri] = textEdits;

        var lspAction = new LspCodeAction
        {
            Title = action.Title,
            Kind = ConvertCodeActionKind(action.Kind),
            Edit = new WorkspaceEdit
            {
                Changes = changes
            }
        };

        // Link to the diagnostic if provided
        if (diagnostic != null)
        {
            lspAction.Diagnostics = new Container<OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic>(diagnostic);
        }

        return lspAction;
    }

    private CodeActionKind ConvertCodeActionKind(NewCLILang.Compiler.CodeActionKind kind)
    {
        return kind switch
        {
            NewCLILang.Compiler.CodeActionKind.QuickFix => CodeActionKind.QuickFix,
            NewCLILang.Compiler.CodeActionKind.Refactor => CodeActionKind.Refactor,
            NewCLILang.Compiler.CodeActionKind.RefactorExtract => CodeActionKind.RefactorExtract,
            NewCLILang.Compiler.CodeActionKind.RefactorInline => CodeActionKind.RefactorInline,
            NewCLILang.Compiler.CodeActionKind.RefactorRewrite => CodeActionKind.RefactorRewrite,
            NewCLILang.Compiler.CodeActionKind.Source => CodeActionKind.Source,
            NewCLILang.Compiler.CodeActionKind.SourceOrganizeImports => CodeActionKind.SourceOrganizeImports,
            _ => CodeActionKind.QuickFix
        };
    }

    protected override CodeActionRegistrationOptions CreateRegistrationOptions(
        CodeActionCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new CodeActionRegistrationOptions
        {
            DocumentSelector = DocumentSelector.ForLanguage("nsharp"),
            CodeActionKinds = new Container<CodeActionKind>(
                CodeActionKind.QuickFix,
                CodeActionKind.Refactor,
                CodeActionKind.RefactorExtract,
                CodeActionKind.RefactorInline,
                CodeActionKind.RefactorRewrite,
                CodeActionKind.Source,
                CodeActionKind.SourceOrganizeImports
            )
        };
    }
}
