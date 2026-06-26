using System;
using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

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
        _providers.Add(new PossibleNullAccessCodeFixProvider());
        _providers.Add(new AddCommentToEmptyCatchCodeFixProvider());
        _providers.Add(new RemoveUnusedImportCodeFixProvider());
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
        var hasImports = ast.Imports.Any();
        var lastImportLine = hasImports ? ast.Imports.Last().Line : 0;

        if (diagnostic.Suggestion != null &&
            CodeFixActionKernels.TryGetMissingImportEdit(
                diagnostic.Suggestion,
                hasImports,
                lastImportLine,
                out var insertLine,
                out var insertColumn,
                out var importText,
                out var title))
        {
            var edit = new TextEdit(
                insertLine,
                insertColumn,
                insertLine,
                insertColumn,
                importText);

            actions.Add(new CodeAction(
                title,
                "NL002",
                new List<TextEdit> { edit },
                CodeActionKind.QuickFix));
        }

        return actions;
    }
}

/// <summary>
/// Code fix provider for NL001: Unused Variable.
/// Marked ReviewNeeded because it removes entire lines via string matching
/// (`sourceLine.Contains("let {name}")`) which could match inside comments
/// or strings, and breaks if a line contains multiple statements.
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
        var line = diagnostic.Location.Line;

        if (CodeFixActionKernels.TryGetRemoveUnusedVariableEdit(
                diagnostic.Message,
                sourceCode,
                line,
                out var title))
        {
            var edit = new TextEdit(
                line,
                0,
                line + 1,
                0,
                "");

            actions.Add(new CodeAction(
                title,
                "NL001",
                new List<TextEdit> { edit },
                CodeActionKind.QuickFix,
                FixSafety.ReviewNeeded));
        }

        return actions;
    }
}

internal static class CodeFixActionKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    [ThreadStatic]
    private static int[]? t_editInfo;

    [ThreadStatic]
    private static string[]? t_replacementText;

    [ThreadStatic]
    private static string[]? t_titleText;

    internal static bool TryGetMissingImportEdit(
        string suggestion,
        bool hasImports,
        int lastImportLine,
        out int insertLine,
        out int insertColumn,
        out string importText,
        out string title)
    {
        insertLine = 0;
        insertColumn = 0;
        importText = string.Empty;
        title = string.Empty;

        var editInfo = t_editInfo ??= new int[2];
        var replacementText = t_replacementText ??= new string[1];
        var titleText = t_titleText ??= new string[1];
        var code = RequiredBindings.GetMissingImportEditInto(
            suggestion,
            hasImports ? 1 : 0,
            lastImportLine,
            editInfo,
            replacementText,
            titleText);
        if (code < 0)
            throw new InvalidOperationException("N# code-fix action kernel returned an invalid edit result.");

        if (code == 0)
            return false;

        insertLine = editInfo[0];
        insertColumn = editInfo[1];
        importText = replacementText[0];
        title = titleText[0];
        return true;
    }

    internal static bool TryGetRemoveUnusedVariableEdit(
        string message,
        string sourceCode,
        int line,
        out string title)
    {
        title = string.Empty;

        var replacementText = t_replacementText ??= new string[1];
        var code = RequiredBindings.GetRemoveUnusedVariableEditInto(message, sourceCode, line, replacementText);
        if (code < 0)
            throw new InvalidOperationException("N# code-fix action kernel returned an invalid edit result.");

        if (code == 0)
            return false;

        title = replacementText[0];
        return true;
    }

    internal static bool TryGetUnnecessaryNullCheckEdit(
        string sourceCode,
        int line,
        out int startColumn,
        out int endColumn,
        out string newText)
    {
        startColumn = 0;
        endColumn = 0;
        newText = string.Empty;

        var editInfo = t_editInfo ??= new int[2];
        var replacementText = t_replacementText ??= new string[1];
        var code = RequiredBindings.GetUnnecessaryNullCheckEditInto(sourceCode, line, editInfo, replacementText);
        if (code < 0)
            throw new InvalidOperationException("N# code-fix action kernel returned an invalid edit result.");

        if (code == 0)
            return false;

        startColumn = editInfo[0];
        endColumn = editInfo[1];
        newText = replacementText[0];
        return true;
    }

    internal static bool TryGetEmptyCatchCommentEdit(
        string sourceCode,
        int line,
        out int column,
        out string newText)
    {
        column = 0;
        newText = string.Empty;

        var editInfo = t_editInfo ??= new int[2];
        var replacementText = t_replacementText ??= new string[1];
        var code = RequiredBindings.GetEmptyCatchCommentEditInto(sourceCode, line, editInfo, replacementText);
        if (code < 0)
            throw new InvalidOperationException("N# code-fix action kernel returned an invalid edit result.");

        if (code == 0)
            return false;

        column = editInfo[0];
        newText = replacementText[0];
        return true;
    }

    internal static bool TryGetPossibleNullAccessEdit(
        string sourceCode,
        int line,
        int column,
        out int operatorColumn,
        out string newText)
    {
        operatorColumn = 0;
        newText = string.Empty;

        var editInfo = t_editInfo ??= new int[2];
        var replacementText = t_replacementText ??= new string[1];
        var code = RequiredBindings.GetPossibleNullAccessEditInto(sourceCode, line, column, editInfo, replacementText);
        if (code < 0)
            throw new InvalidOperationException("N# code-fix action kernel returned an invalid edit result.");

        if (code == 0)
            return false;

        operatorColumn = editInfo[0];
        newText = replacementText[0];
        return true;
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CodeFixMissingImportEditInto>(
                programType,
                "CodeFixMissingImportEditInto"),
            DogfoodKernelLoader.CreateDelegate<CodeFixRemoveUnusedVariableEditInto>(
                programType,
                "CodeFixRemoveUnusedVariableEditInto"),
            DogfoodKernelLoader.CreateDelegate<CodeFixUnnecessaryNullCheckEditInto>(
                programType,
                "CodeFixUnnecessaryNullCheckEditInto"),
            DogfoodKernelLoader.CreateDelegate<CodeFixEmptyCatchCommentEditInto>(
                programType,
                "CodeFixEmptyCatchCommentEditInto"),
            DogfoodKernelLoader.CreateDelegate<CodeFixPossibleNullAccessEditInto>(
                programType,
                "CodeFixPossibleNullAccessEditInto")));

    private delegate int CodeFixMissingImportEditInto(
        string suggestion,
        int hasImports,
        int lastImportLine,
        int[] editInfo,
        string[] importText,
        string[] titleText);

    private delegate int CodeFixRemoveUnusedVariableEditInto(
        string message,
        string source,
        int line,
        string[] titleText);

    private delegate int CodeFixUnnecessaryNullCheckEditInto(
        string source,
        int line,
        int[] editInfo,
        string[] replacementText);

    private delegate int CodeFixEmptyCatchCommentEditInto(
        string source,
        int line,
        int[] editInfo,
        string[] replacementText);

    private delegate int CodeFixPossibleNullAccessEditInto(
        string source,
        int line,
        int column,
        int[] editInfo,
        string[] replacementText);

    private sealed record Bindings(
        CodeFixMissingImportEditInto GetMissingImportEditInto,
        CodeFixRemoveUnusedVariableEditInto GetRemoveUnusedVariableEditInto,
        CodeFixUnnecessaryNullCheckEditInto GetUnnecessaryNullCheckEditInto,
        CodeFixEmptyCatchCommentEditInto GetEmptyCatchCommentEditInto,
        CodeFixPossibleNullAccessEditInto GetPossibleNullAccessEditInto);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# code-fix action kernels are unavailable.");
}

/// <summary>
/// Code fix provider for NL003: Unnecessary Null Check.
/// Replaces value-type null comparisons with the literal boolean they evaluate to.
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
        var line = diagnostic.Location.Line;

        if (CodeFixActionKernels.TryGetUnnecessaryNullCheckEdit(
                sourceCode,
                line,
                out var conditionStart,
                out var conditionEnd,
                out var newCondition))
        {
            var edit = new TextEdit(line, conditionStart, line, conditionEnd, newCondition);

            actions.Add(new CodeAction(
                $"Remove unnecessary null check (always {newCondition})",
                "NL003",
                new List<TextEdit> { edit },
                CodeActionKind.QuickFix,
                FixSafety.Safe));
        }

        return actions;
    }
}

/// <summary>
/// Code actions for NL905: possible null access.
/// The null-conditional edit changes result nullability, so it requires review.
/// Guard/fallback/assertion options are suggestion-only because they need intent.
/// </summary>
public class PossibleNullAccessCodeFixProvider : CodeFixProvider
{
    public override IEnumerable<string> FixableDiagnosticCodes => new[] { "NL905" };

    public override List<CodeAction> GetCodeActions(
        Diagnostic diagnostic,
        CompilationUnit ast,
        string sourceCode)
    {
        var actions = new List<CodeAction>();
        var line = diagnostic.Location.Line;

        if (CodeFixActionKernels.TryGetPossibleNullAccessEdit(
                sourceCode,
                line,
                diagnostic.Location.Column,
                out var operatorIndex,
                out var replacementText))
        {
            if (replacementText == "?.")
            {
                actions.Add(new CodeAction(
                    "Use null-conditional access (review result nullability)",
                    "NL905",
                    new List<TextEdit> { new(line, operatorIndex, line, operatorIndex + 1, replacementText) },
                    CodeActionKind.QuickFix,
                    FixSafety.ReviewNeeded));
            }
            else if (replacementText == "?[")
            {
                actions.Add(new CodeAction(
                    "Use null-conditional index access (review result nullability)",
                    "NL905",
                    new List<TextEdit> { new(line, operatorIndex, line, operatorIndex + 1, replacementText) },
                    CodeActionKind.QuickFix,
                    FixSafety.ReviewNeeded));
            }
        }

        actions.Add(new CodeAction(
            "Add a guard before using the maybe-null value",
            "NL905",
            new List<TextEdit>(),
            CodeActionKind.QuickFix,
            FixSafety.SuggestionOnly));

        actions.Add(new CodeAction(
            "Add a fallback with ?? after a safe access",
            "NL905",
            new List<TextEdit>(),
            CodeActionKind.QuickFix,
            FixSafety.SuggestionOnly));

        actions.Add(new CodeAction(
            "Assert non-null only after proving the value is present",
            "NL905",
            new List<TextEdit>(),
            CodeActionKind.QuickFix,
            FixSafety.SuggestionOnly));

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
        var line = diagnostic.Location.Line;

        if (!CodeFixActionKernels.TryGetEmptyCatchCommentEdit(sourceCode, line, out var column, out var newText))
            return actions;

        var edit = new TextEdit(
            line,
            column,
            line,
            column,
            newText);

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
/// Code fix provider for NL010: Unused Import.
/// Deletes the entire import line. Marked ReviewNeeded because the underlying
/// NL010 analysis has known false positives (hardcoded type maps, missing
/// extension method tracking, etc.).
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
            FixSafety.ReviewNeeded));

        return actions;
    }
}
