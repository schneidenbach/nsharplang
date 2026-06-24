using System;
using System.Collections.Generic;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.CodeIntelligence;

/// <summary>
/// Applies TextEdits to source files. Handles the tricky parts:
/// - Multiple edits per file (applied bottom-to-top so line numbers stay valid)
/// - Overlapping edit detection
/// - Insert-at-line-start (column 0)
///
/// TextEdit coordinates are 1-based lines and 0-based, end-exclusive columns.
/// Whole-line deletion ranges may end at the next line, column 0; for the final
/// document line that means one line past EOF at column 0.
/// </summary>
public static class FixApplicator
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    /// <summary>
    /// Apply a list of TextEdits to source text.
    /// Edits are applied in reverse order (bottom-to-top) so that line numbers
    /// from earlier edits remain valid.
    /// </summary>
    public static string ApplyEdits(string source, List<TextEdit> edits)
    {
        if (edits.Count == 0) return source;

        var sortedEdits = ValidateAndSortEdits(source, edits);
        var inputs = MaterializeEditInputs(sortedEdits);
        var output = new string[1];
        var code = RequiredBindings.ApplyOrderedTextEdits(
            source,
            inputs.StartLines,
            inputs.StartColumns,
            inputs.EndLines,
            inputs.EndColumns,
            inputs.NewTexts,
            inputs.Count,
            output);

        if (code != 0)
            throw new InvalidOperationException("N# fix applicator kernel rejected the edit application.");

        return output[0];
    }

    /// <summary>
    /// Validate a set of edits, detect overlaps, and return them in the only safe application order:
    /// bottom-to-top and right-to-left. This is intentionally public so callers such as nlc fix can
    /// preflight a whole fix plan before writing any files.
    /// </summary>
    public static List<TextEdit> ValidateAndSortEdits(IReadOnlyCollection<TextEdit> edits)
    {
        // Sort edits bottom-to-top, right-to-left so applying them doesn't shift earlier positions.
        // Same-position zero-width inserts are applied in reverse input order so the final text
        // preserves the caller's input order.
        var sortedEdits = FixApplicatorTextEditOrderer.OrderTextEdits(edits);
        ValidateSortedEdits(null, sortedEdits);
        return sortedEdits;
    }

    /// <summary>
    /// Source-aware validation for automated writes. Rejects coordinates outside the document instead
    /// of silently clamping them, while preserving the single intentional EOF insertion shape.
    /// </summary>
    public static List<TextEdit> ValidateAndSortEdits(string source, IReadOnlyCollection<TextEdit> edits)
    {
        var sortedEdits = ValidateAndSortEdits(edits);
        ValidateSortedEdits(source, sortedEdits);
        return sortedEdits;
    }

    private static void ValidateSortedEdits(string? source, List<TextEdit> sortedEdits)
    {
        var inputs = MaterializeEditInputs(sortedEdits);
        var errorInfo = new int[2];
        var code = RequiredBindings.ValidateOrderedTextEdits(
            source ?? string.Empty,
            source == null ? 0 : 1,
            inputs.StartLines,
            inputs.StartColumns,
            inputs.EndLines,
            inputs.EndColumns,
            inputs.NewTexts,
            inputs.Count,
            errorInfo);

        if (code == 0)
            return;

        throw CreateValidationException(code, errorInfo, sortedEdits);
    }

    private static InvalidOperationException CreateValidationException(int code, int[] errorInfo, List<TextEdit> sortedEdits)
    {
        if (code == 1)
        {
            var edit = sortedEdits[errorInfo[0]];
            return new InvalidOperationException(
                $"Invalid edit position: ({edit.StartLine},{edit.StartColumn})..({edit.EndLine},{edit.EndColumn}). " +
                "Lines are 1-based and columns must be non-negative.");
        }

        if (code == 2)
        {
            var edit = sortedEdits[errorInfo[0]];
            return new InvalidOperationException(
                $"Invalid edit range: ({edit.StartLine},{edit.StartColumn})..({edit.EndLine},{edit.EndColumn}) ends before it starts.");
        }

        if (code == 3)
        {
            var low = sortedEdits[errorInfo[0]];
            var high = sortedEdits[errorInfo[1]];
            return new InvalidOperationException(
                $"Overlapping edits detected: edit at ({low.StartLine},{low.StartColumn})..({low.EndLine},{low.EndColumn}) " +
                $"overlaps with edit at ({high.StartLine},{high.StartColumn})..({high.EndLine},{high.EndColumn})");
        }

        if (code == 4)
        {
            var edit = sortedEdits[errorInfo[0]];
            return new InvalidOperationException(
                $"Invalid edit range: ({edit.StartLine},{edit.StartColumn})..({edit.EndLine},{edit.EndColumn}) is outside the document.");
        }

        return new InvalidOperationException("N# fix applicator kernel rejected the edit validation.");
    }

    private static EditInputs MaterializeEditInputs(IReadOnlyList<TextEdit> edits)
    {
        var count = edits.Count;
        var startLines = new int[count];
        var startColumns = new int[count];
        var endLines = new int[count];
        var endColumns = new int[count];
        var newTexts = new string[count];

        for (var i = 0; i < count; i++)
        {
            var edit = edits[i];
            startLines[i] = edit.StartLine;
            startColumns[i] = edit.StartColumn;
            endLines[i] = edit.EndLine;
            endColumns[i] = edit.EndColumn;
            newTexts[i] = edit.NewText;
        }

        return new EditInputs(startLines, startColumns, endLines, endColumns, newTexts, count);
    }

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# fix applicator kernels are unavailable.");

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<FixValidateOrderedTextEdits>(
                programType,
                "FixValidateOrderedTextEdits"),
            DogfoodKernelLoader.CreateDelegate<FixApplyOrderedTextEdits>(
                programType,
                "FixApplyOrderedTextEdits")));

    private delegate int FixValidateOrderedTextEdits(
        string source,
        int hasSource,
        int[] startLines,
        int[] startColumns,
        int[] endLines,
        int[] endColumns,
        string[] newTexts,
        int count,
        int[] errorInfo);

    private delegate int FixApplyOrderedTextEdits(
        string source,
        int[] startLines,
        int[] startColumns,
        int[] endLines,
        int[] endColumns,
        string[] newTexts,
        int count,
        string[] output);

    private sealed record Bindings(
        FixValidateOrderedTextEdits ValidateOrderedTextEdits,
        FixApplyOrderedTextEdits ApplyOrderedTextEdits);

    private readonly record struct EditInputs(
        int[] StartLines,
        int[] StartColumns,
        int[] EndLines,
        int[] EndColumns,
        string[] NewTexts,
        int Count);

    /// <summary>
    /// Collect all fixable diagnostics for a file and return the code actions.
    /// </summary>
    public static List<CodeAction> GetFixesForFile(string filePath, string source)
    {
        // Parse
        var lexer = new Lexer(source, filePath);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, filePath, source);
        var parseResult = parser.ParseCompilationUnit();

        var ast = parseResult.CompilationUnit ?? new CompilationUnit(
            null,
            new List<ImportDirective>(),
            new List<Statement>(),
            null,
            new List<Declaration>(),
            1,
            1);

        // Lint to get fixable diagnostics only after parsing succeeds.
        var fileDir = System.IO.Path.GetDirectoryName(filePath) ?? System.IO.Directory.GetCurrentDirectory();
        var linter = new Linter(LinterConfig.FromEditorConfig(fileDir));
        var diagnostics = parseResult.CompilationUnit == null
            ? new List<Diagnostic>()
            : linter.Lint(ast, filePath, source);

        // Get fixes from CodeFixService
        var fixService = new CodeFixService();
        var allActions = new List<CodeAction>();

        foreach (var diagnostic in diagnostics)
        {
            var actions = fixService.GetCodeActions(diagnostic, ast, source);
            allActions.AddRange(actions);
        }

        return allActions;
    }
}
