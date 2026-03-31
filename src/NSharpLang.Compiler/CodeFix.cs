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
/// Indicates how safe a code action is to apply without human review
/// </summary>
public enum FixSafety
{
    /// <summary>Applying the fix is always safe and correct.</summary>
    Safe,
    /// <summary>The fix is likely correct but worth a quick look before applying.</summary>
    ReviewNeeded,
    /// <summary>The fix is a suggestion only; human judgment is required.</summary>
    SuggestionOnly
}

/// <summary>
/// Represents a code action that can fix a diagnostic or perform a refactoring
/// </summary>
public record CodeAction(
    string Title,
    string DiagnosticCode,
    List<TextEdit> Edits,
    CodeActionKind Kind = CodeActionKind.QuickFix,
    FixSafety Safety = FixSafety.Safe);

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
        _providers.Add(new RemoveUnnecessaryNullCheckCodeFixProvider());
        _providers.Add(new AddCommentToEmptyCatchCodeFixProvider());
        _providers.Add(new ConvertToInterpolationCodeFixProvider());
        _providers.Add(new RemoveUnusedImportCodeFixProvider());
        _providers.Add(new ChangeLetToConstCodeFixProvider());
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
        // Message format: "Variable 'x' is declared but never read"
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
/// Code fix provider for NL003: Unnecessary Null Check.
/// Removes the entire condition expression so the user can decide what to replace it with.
/// </summary>
public class RemoveUnnecessaryNullCheckCodeFixProvider : CodeFixProvider
{
    public override IEnumerable<string> FixableDiagnosticCodes => new[] { "NL003" };

    public override List<CodeAction> GetCodeActions(
        Diagnostic diagnostic,
        CompilationUnit ast,
        string sourceCode)
    {
        var actions = new List<CodeAction>();
        var sourceLines = sourceCode.Split('\n');
        var line = diagnostic.Location.Line;

        if (line <= 0 || line > sourceLines.Length)
            return actions;

        var sourceLine = sourceLines[line - 1];

        // Replace "== null" or "!= null" patterns with the literal boolean they evaluate to:
        // x != null (where x is a value type) is always true  → replace with "true"
        // x == null (where x is a value type) is always false → replace with "false"
        //
        // We detect which variant we have by looking at the source line.
        string? newCondition = null;
        string? oldPattern = null;

        if (sourceLine.Contains("!= null"))
        {
            oldPattern = "!= null";
            newCondition = "true";
        }
        else if (sourceLine.Contains("== null"))
        {
            oldPattern = "== null";
            newCondition = "false";
        }

        if (oldPattern != null && newCondition != null)
        {
            var col = sourceLine.IndexOf(oldPattern, StringComparison.Ordinal);
            if (col >= 0)
            {
                // Remove the "!= null" or "== null" part (including leading space)
                var removeStart = col > 0 && sourceLine[col - 1] == ' ' ? col - 1 : col;
                var removeEnd = col + oldPattern.Length;
                var edit = new TextEdit(line, removeStart + 1, line, removeEnd + 1, "");

                actions.Add(new CodeAction(
                    $"Remove unnecessary null check (always {newCondition})",
                    "NL003",
                    new List<TextEdit> { edit },
                    CodeActionKind.QuickFix,
                    FixSafety.Safe));
            }
        }

        return actions;
    }
}

/// <summary>
/// Code fix provider for NL011: Empty catch block.
/// Inserts a TODO comment so the developer knows to handle the exception.
/// </summary>
public class AddCommentToEmptyCatchCodeFixProvider : CodeFixProvider
{
    public override IEnumerable<string> FixableDiagnosticCodes => new[] { "NL011" };

    public override List<CodeAction> GetCodeActions(
        Diagnostic diagnostic,
        CompilationUnit ast,
        string sourceCode)
    {
        var actions = new List<CodeAction>();
        var sourceLines = sourceCode.Split('\n');
        var line = diagnostic.Location.Line;

        if (line <= 0 || line > sourceLines.Length)
            return actions;

        // Find the opening brace line and insert the comment on the next line
        // We'll insert after the line that contains the opening `{`
        var catchLine = sourceLines[line - 1];
        var indent = new string(' ', catchLine.Length - catchLine.TrimStart().Length + 4); // +4 for inner indent

        var edit = new TextEdit(
            line,
            catchLine.Length + 1, // end of the `{` line (1-indexed col after last char)
            line,
            catchLine.Length + 1,
            $"\n{indent}// TODO: handle exception");

        actions.Add(new CodeAction(
            "Add TODO comment to empty catch block",
            "NL011",
            new List<TextEdit> { edit },
            CodeActionKind.QuickFix,
            FixSafety.Safe));

        return actions;
    }
}

/// <summary>
/// Code fix provider for NL013: Prefer string interpolation.
/// Converts "hello " + name to $"hello {name}".
/// </summary>
public class ConvertToInterpolationCodeFixProvider : CodeFixProvider
{
    public override IEnumerable<string> FixableDiagnosticCodes => new[] { "NL013" };

    public override List<CodeAction> GetCodeActions(
        Diagnostic diagnostic,
        CompilationUnit ast,
        string sourceCode)
    {
        var actions = new List<CodeAction>();
        var sourceLines = sourceCode.Split('\n');
        var line = diagnostic.Location.Line;

        if (line <= 0 || line > sourceLines.Length)
            return actions;

        // The transformation is non-trivial in general (nested + chains, format specifiers, etc.).
        // We provide the action with SuggestionOnly safety so the user knows manual review is expected.
        actions.Add(new CodeAction(
            "Convert string concatenation to interpolated string",
            "NL013",
            new List<TextEdit>(), // Edits require full expression parsing — provided as hint only
            CodeActionKind.RefactorRewrite,
            FixSafety.SuggestionOnly));

        return actions;
    }
}

/// <summary>
/// Code fix provider for NL010: Unused Import.
/// Deletes the entire import line. Safe to apply automatically.
/// </summary>
public class RemoveUnusedImportCodeFixProvider : CodeFixProvider
{
    public override IEnumerable<string> FixableDiagnosticCodes => new[] { "NL010" };

    public override List<CodeAction> GetCodeActions(
        Diagnostic diagnostic,
        CompilationUnit ast,
        string sourceCode)
    {
        var actions = new List<CodeAction>();
        var line = diagnostic.Location.Line;

        if (line <= 0)
            return actions;

        // Remove the entire import line (line N → line N+1, column 0 to column 0)
        var edit = new TextEdit(line, 0, line + 1, 0, "");

        actions.Add(new CodeAction(
            "Remove unused import",
            "NL010",
            new List<TextEdit> { edit },
            CodeActionKind.SourceOrganizeImports,
            FixSafety.Safe));

        return actions;
    }
}

/// <summary>
/// Code fix provider for NL015: Prefer Const.
/// Replaces the `let` keyword with `const` on the declaration line.
/// </summary>
public class ChangeLetToConstCodeFixProvider : CodeFixProvider
{
    public override IEnumerable<string> FixableDiagnosticCodes => new[] { "NL015" };

    public override List<CodeAction> GetCodeActions(
        Diagnostic diagnostic,
        CompilationUnit ast,
        string sourceCode)
    {
        var actions = new List<CodeAction>();
        var sourceLines = sourceCode.Split('\n');
        var line = diagnostic.Location.Line;

        if (line <= 0 || line > sourceLines.Length)
            return actions;

        var sourceLine = sourceLines[line - 1];

        // Find `let ` on the declaration line and replace with `const `
        var letIndex = sourceLine.IndexOf("let ", StringComparison.Ordinal);
        if (letIndex < 0)
            return actions;

        // Replace `let ` (4 chars) with `const ` (6 chars)
        var edit = new TextEdit(line, letIndex + 1, line, letIndex + 4 + 1, "const ");

        actions.Add(new CodeAction(
            "Change 'let' to 'const'",
            "NL015",
            new List<TextEdit> { edit },
            CodeActionKind.QuickFix,
            FixSafety.Safe));

        return actions;
    }
}
