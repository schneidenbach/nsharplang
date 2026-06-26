using System;
using System.Collections.Generic;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class OutputFormatterDiagnosticClusterKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static DiagnosticClusterGroupingScratch? t_diagnosticClusterGroupingScratch;

    internal static (int[] Categories, int[] SourceConstructs) ClassifyDiagnosticClusterTraits(
        IReadOnlyList<DiagnosticResult> diagnostics)
    {
        var count = diagnostics.Count;
        var codes = new string[count];
        var messages = new string[count];
        var snippets = new string[count];
        var categories = new int[count];
        var sourceConstructs = new int[count];

        for (var i = 0; i < count; i++)
        {
            var diagnostic = diagnostics[i];
            codes[i] = diagnostic.Code ?? string.Empty;
            messages[i] = diagnostic.Message ?? string.Empty;
            snippets[i] = diagnostic.SourceSnippet ?? string.Empty;
        }

        var classified = RequiredBindings.DiagnosticClusterTraits(
            codes,
            messages,
            snippets,
            categories,
            sourceConstructs);

        return (categories, sourceConstructs);
    }

    internal static DiagnosticClusterGrouping GroupDiagnosticClusters(
        IReadOnlyList<DiagnosticResult> diagnostics,
        int[] categoryIds,
        int[] sourceConstructIds,
        string[] messagePatterns)
    {
        var count = diagnostics.Count;
        if (categoryIds.Length < count || sourceConstructIds.Length < count || messagePatterns.Length < count)
            throw new InvalidOperationException("N# diagnostic cluster grouping kernel received incomplete classification inputs.");

        var scratch = t_diagnosticClusterGroupingScratch ??= new DiagnosticClusterGroupingScratch();
        scratch.EnsureCapacity(count);

        try
        {
            scratch.ResetIds();
            for (var i = 0; i < count; i++)
            {
                var diagnostic = diagnostics[i];
                var category = categoryIds[i];

                scratch.CodeIds[i] = scratch.GetCodeId(diagnostic.Code ?? string.Empty);
                scratch.SeverityIds[i] = scratch.GetSeverityId(diagnostic.Severity ?? string.Empty);
                scratch.CategoryIds[i] = category;
                scratch.SourceConstructIds[i] = sourceConstructIds[i];
                scratch.RecipeIds[i] = category;
                scratch.RiskIds[i] = category;
                scratch.MessagePatternIds[i] = scratch.GetMessagePatternId(messagePatterns[i] ?? string.Empty);
                scratch.Files[i] = diagnostic.File ?? string.Empty;
                scratch.Lines[i] = diagnostic.Line;
                scratch.Columns[i] = diagnostic.Column;
            }

            var groupCount = RequiredBindings.DiagnosticClusterCompactGroups(
                scratch.CodeIds,
                scratch.SeverityIds,
                scratch.CategoryIds,
                scratch.SourceConstructIds,
                scratch.RecipeIds,
                scratch.RiskIds,
                scratch.MessagePatternIds,
                scratch.Files,
                scratch.Lines,
                scratch.Columns,
                scratch.SlotGroups,
                scratch.GroupKeyIndices,
                scratch.RootIndices,
                scratch.Counts);

            var memberTotal = RequiredBindings.DiagnosticClusterCompactGroupMembers(
                scratch.CodeIds,
                scratch.SeverityIds,
                scratch.CategoryIds,
                scratch.SourceConstructIds,
                scratch.RecipeIds,
                scratch.RiskIds,
                scratch.MessagePatternIds,
                scratch.Files,
                scratch.Lines,
                scratch.Columns,
                scratch.RootIndices,
                scratch.Counts,
                groupCount,
                scratch.SlotGroups,
                scratch.GroupFirstMemberIndices,
                scratch.MemberNextIndices,
                scratch.MemberStarts,
                scratch.MemberIndices);

            return new DiagnosticClusterGrouping(
                groupCount,
                scratch.RootIndices,
                scratch.Counts,
                scratch.MemberStarts,
                scratch.MemberIndices);
        }
        finally
        {
            scratch.ClearFiles(count);
            scratch.ResetIds();
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<DiagnosticClusterTraitsInto>(
                programType,
                "DiagnosticClusterTraitsInto"),
            DogfoodKernelLoader.CreateDelegate<DiagnosticClusterCompactGroupsInto>(
                programType,
                "DiagnosticClusterCompactGroupsInto"),
            DogfoodKernelLoader.CreateDelegate<DiagnosticClusterCompactGroupMembersInto>(
                programType,
                "DiagnosticClusterCompactGroupMembersInto")));

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# diagnostic cluster kernels are unavailable.");

    private delegate int DiagnosticClusterTraitsInto(
        string[] codes,
        string[] messages,
        string[] snippets,
        int[] resultCategories,
        int[] resultSourceConstructs);

    private delegate int DiagnosticClusterCompactGroupsInto(
        int[] codeIds,
        int[] severityIds,
        int[] categoryIds,
        int[] sourceConstructIds,
        int[] recipeIds,
        int[] riskIds,
        int[] messagePatternIds,
        string[] files,
        int[] lines,
        int[] columns,
        int[] slotGroups,
        int[] groupKeyIndices,
        int[] resultRootIndices,
        int[] resultCounts);

    private delegate int DiagnosticClusterCompactGroupMembersInto(
        int[] codeIds,
        int[] severityIds,
        int[] categoryIds,
        int[] sourceConstructIds,
        int[] recipeIds,
        int[] riskIds,
        int[] messagePatternIds,
        string[] files,
        int[] lines,
        int[] columns,
        int[] groupRootIndices,
        int[] groupCounts,
        int groupCount,
        int[] slotGroups,
        int[] groupFirstMemberIndices,
        int[] memberNextIndices,
        int[] resultStarts,
        int[] resultMemberIndices);

    private sealed record Bindings(
        DiagnosticClusterTraitsInto DiagnosticClusterTraits,
        DiagnosticClusterCompactGroupsInto DiagnosticClusterCompactGroups,
        DiagnosticClusterCompactGroupMembersInto DiagnosticClusterCompactGroupMembers);

}
