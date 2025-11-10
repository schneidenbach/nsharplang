using System;
using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

/// <summary>
/// Represents a text edit to be applied to a document
/// </summary>
public record TextEdit(
    int StartLine,
    int StartColumn,
    int EndLine,
    int EndColumn,
    string NewText);

/// <summary>
/// Represents a code action that can fix a diagnostic or perform a refactoring
/// </summary>
public record CodeAction(
    string Title,
    string DiagnosticCode,
    List<TextEdit> Edits,
    CodeActionKind Kind = CodeActionKind.QuickFix);

/// <summary>
/// Kind of code action (quick fix, refactoring, etc.)
/// </summary>
public enum CodeActionKind
{
    QuickFix,
    Refactor,
    RefactorExtract,
    RefactorInline,
    RefactorRewrite,
    Source,
    SourceOrganizeImports
}

/// <summary>
/// Base class for code fix providers
/// </summary>
public abstract class CodeFixProvider
{
    /// <summary>
    /// The diagnostic codes this provider can fix
    /// </summary>
    public abstract IEnumerable<string> FixableDiagnosticCodes { get; }

    /// <summary>
    /// Get code actions for a diagnostic
    /// </summary>
    public abstract List<CodeAction> GetCodeActions(
        Diagnostic diagnostic,
        CompilationUnit ast,
        string sourceCode);
}

/// <summary>
/// Main code fix service that coordinates all fix providers
/// </summary>
public class CodeFixService
{
    private readonly List<CodeFixProvider> _providers = new();

    public CodeFixService()
    {
        // Register all built-in providers
        _providers.Add(new AddMissingImportCodeFixProvider());
        _providers.Add(new RemoveUnusedVariableCodeFixProvider());
        _providers.Add(new AddNullCheckCodeFixProvider());
    }

    /// <summary>
    /// Get all available code actions for a diagnostic
    /// </summary>
    public List<CodeAction> GetCodeActions(
        Diagnostic diagnostic,
        CompilationUnit ast,
        string sourceCode)
    {
        var actions = new List<CodeAction>();

        foreach (var provider in _providers)
        {
            if (provider.FixableDiagnosticCodes.Contains(diagnostic.Code))
            {
                var providerActions = provider.GetCodeActions(diagnostic, ast, sourceCode);
                actions.AddRange(providerActions);
            }
        }

        return actions;
    }

    /// <summary>
    /// Get all available code actions for a document (not tied to a specific diagnostic)
    /// </summary>
    public List<CodeAction> GetCodeActionsForDocument(
        CompilationUnit ast,
        string sourceCode,
        int line,
        int column)
    {
        // For now, we'll focus on diagnostic-based fixes
        // Future: Add refactorings that don't require a diagnostic
        return new List<CodeAction>();
    }
}

/// <summary>
/// Code fix provider for NL002: Missing Import
/// </summary>
public class AddMissingImportCodeFixProvider : CodeFixProvider
{
    public override IEnumerable<string> FixableDiagnosticCodes => new[] { "NL002" };

    public override List<CodeAction> GetCodeActions(
        Diagnostic diagnostic,
        CompilationUnit ast,
        string sourceCode)
    {
        var actions = new List<CodeAction>();

        // Extract the namespace from the suggestion
        // Suggestion format: "Add 'import System.Collections.Generic'"
        if (diagnostic.Suggestion?.StartsWith("Add 'import ") == true)
        {
            var startIndex = "Add 'import ".Length;
            var endIndex = diagnostic.Suggestion.IndexOf('\'', startIndex);
            if (endIndex > startIndex)
            {
                var namespaceToImport = diagnostic.Suggestion[startIndex..endIndex];

                // Find the right place to insert the import
                var (insertLine, insertColumn) = FindImportInsertionPoint(ast, sourceCode);

                // Create the text edit
                var importText = $"import {namespaceToImport}\n";
                var edit = new TextEdit(
                    insertLine,
                    insertColumn,
                    insertLine,
                    insertColumn,
                    importText);

                actions.Add(new CodeAction(
                    $"Add import {namespaceToImport}",
                    "NL002",
                    new List<TextEdit> { edit },
                    CodeActionKind.QuickFix));
            }
        }

        return actions;
    }

    private (int Line, int Column) FindImportInsertionPoint(CompilationUnit ast, string sourceCode)
    {
        // Insert after the last import, or at the beginning if no imports
        if (ast.Imports.Any())
        {
            var lastImport = ast.Imports.Last();
            // Insert on the next line after the last import
            return (lastImport.Line + 1, 0);
        }
        else
        {
            // Insert at the beginning of the file
            return (1, 0);
        }
    }
}

/// <summary>
/// Code fix provider for NL001: Unused Variable
/// </summary>
public class RemoveUnusedVariableCodeFixProvider : CodeFixProvider
{
    public override IEnumerable<string> FixableDiagnosticCodes => new[] { "NL001" };

    public override List<CodeAction> GetCodeActions(
        Diagnostic diagnostic,
        CompilationUnit ast,
        string sourceCode)
    {
        var actions = new List<CodeAction>();

        // Extract variable name from diagnostic message
        // Message format: "Unused variable 'x'"
        var message = diagnostic.Message;
        var startIndex = message.IndexOf('\'');
        var endIndex = message.LastIndexOf('\'');

        if (startIndex >= 0 && endIndex > startIndex)
        {
            var variableName = message[(startIndex + 1)..endIndex];

            // Find the variable declaration in the AST
            var sourceLines = sourceCode.Split('\n');
            var line = diagnostic.Location.Line;

            if (line > 0 && line <= sourceLines.Length)
            {
                var sourceLine = sourceLines[line - 1];

                // Check if this is the entire statement or part of it
                // For simplicity, we'll remove the entire line if it contains the declaration
                if (sourceLine.Contains($"let {variableName}") ||
                    sourceLine.Contains($"var {variableName}") ||
                    sourceLine.Contains($"const {variableName}"))
                {
                    // Remove the entire line
                    var edit = new TextEdit(
                        line,
                        0,
                        line + 1,
                        0,
                        "");

                    actions.Add(new CodeAction(
                        $"Remove unused variable '{variableName}'",
                        "NL001",
                        new List<TextEdit> { edit },
                        CodeActionKind.QuickFix));
                }
            }
        }

        return actions;
    }
}

/// <summary>
/// Code fix provider for NL003: Unnecessary Null Check
/// </summary>
public class AddNullCheckCodeFixProvider : CodeFixProvider
{
    public override IEnumerable<string> FixableDiagnosticCodes => new[] { "NL003" };

    public override List<CodeAction> GetCodeActions(
        Diagnostic diagnostic,
        CompilationUnit ast,
        string sourceCode)
    {
        var actions = new List<CodeAction>();

        // For NL003 (unnecessary null check), the fix is to remove the check
        var sourceLines = sourceCode.Split('\n');
        var line = diagnostic.Location.Line;

        if (line > 0 && line <= sourceLines.Length)
        {
            var sourceLine = sourceLines[line - 1];

            // This is a diagnostic about unnecessary null checks
            // The fix would be to remove or simplify the condition
            // For now, we'll provide a suggestion to remove it
            // This is complex because we need to understand the context

            actions.Add(new CodeAction(
                "Remove unnecessary null check",
                "NL003",
                new List<TextEdit>(),  // Empty edits for now - would need AST analysis
                CodeActionKind.QuickFix));
        }

        return actions;
    }
}
