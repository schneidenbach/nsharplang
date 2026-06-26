using System;
using System.Collections.Generic;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class CodeIntelligenceResultKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static DiagnosticShadowSuppressionScratch? t_diagnosticShadowSuppressionScratch;
    private static DiagnosticDeduplicationScratch? t_diagnosticDeduplicationScratch;
    [ThreadStatic]
    private static ReferenceDeduplicationScratch? t_referenceDeduplicationScratch;

    internal static (int[] ResultIndices, int Count) SuppressLintShadowingDiagnostics(
        IReadOnlyList<DiagnosticResult> diagnostics,
        IReadOnlyList<string> shadowedFiles)
    {
        var diagnosticCount = diagnostics.Count;
        if (diagnosticCount == 0)
            return (Array.Empty<int>(), 0);

        var scratch = t_diagnosticShadowSuppressionScratch ??= new DiagnosticShadowSuppressionScratch();
        scratch.EnsureCapacity(diagnosticCount, shadowedFiles.Count);

        try
        {
            scratch.Reset();
            var targetCodeId = scratch.GetCodeId("NL020");
            for (var i = 0; i < diagnosticCount; i++)
            {
                var diagnostic = diagnostics[i];
                var file = diagnostic.File ?? string.Empty;
                scratch.CodeIds[i] = scratch.GetCodeId(diagnostic.Code ?? string.Empty);
                scratch.Files[i] = file;
                scratch.AddFile(file);
            }

            for (var i = 0; i < shadowedFiles.Count; i++)
            {
                scratch.AddFile(shadowedFiles[i] ?? string.Empty);
            }

            scratch.BuildFileRanks();
            for (var i = 0; i < diagnosticCount; i++)
            {
                scratch.FileRanks[i] = scratch.GetFileRank(scratch.Files[i]);
            }

            scratch.ClearShadowFileFlags();
            for (var i = 0; i < shadowedFiles.Count; i++)
            {
                var rank = scratch.GetFileRank(shadowedFiles[i] ?? string.Empty);
                if (rank >= 0 && rank < scratch.ShadowFileFlags.Length)
                {
                    scratch.ShadowFileFlags[rank] = 1;
                }
            }

            var count = RequiredBindings.DiagnosticShadowSuppression(
                scratch.CodeIds,
                scratch.FileRanks,
                targetCodeId,
                scratch.ShadowFileFlags,
                scratch.ResultIndices);

            return (scratch.ResultIndices, count);
        }
        finally
        {
            scratch.ClearFiles(diagnosticCount);
            scratch.Reset();
        }
    }

    internal static (int[] ResultIndices, int Count) DeduplicateDiagnostics(
        IReadOnlyList<DiagnosticResult> diagnostics)
    {
        var diagnosticCount = diagnostics.Count;
        if (diagnosticCount == 0)
            return (Array.Empty<int>(), 0);

        var scratch = t_diagnosticDeduplicationScratch ??= new DiagnosticDeduplicationScratch();
        scratch.EnsureCapacity(diagnosticCount);

        try
        {
            scratch.ResetIds();
            for (var i = 0; i < diagnosticCount; i++)
            {
                var diagnostic = diagnostics[i];
                scratch.CodeIds[i] = scratch.GetCodeId(diagnostic.Code);
                scratch.LineNumbers[i] = diagnostic.Line;
                scratch.Columns[i] = diagnostic.Column;
                scratch.MessageIds[i] = scratch.GetMessageId(diagnostic.Message);
                scratch.Files[i] = diagnostic.File;
                scratch.AddFile(diagnostic.File);
            }

            scratch.BuildFileRanks();
            for (var i = 0; i < diagnosticCount; i++)
            {
                scratch.FileRanks[i] = scratch.GetFileRank(scratch.Files[i]);
            }

            var count = RequiredBindings.DiagnosticDeduplicateCompact(
                scratch.CodeIds,
                scratch.FileRanks,
                scratch.LineNumbers,
                scratch.Columns,
                scratch.MessageIds,
                scratch.SlotIndices,
                scratch.ResultIndices);

            return (scratch.ResultIndices, count);
        }
        finally
        {
            scratch.ClearFiles(diagnosticCount);
            scratch.ResetIds();
        }
    }

    internal static (int[] ResultIndices, int Count) DeduplicateDiagnosticsPreservingOrder(
        IReadOnlyList<DiagnosticResult> diagnostics)
    {
        var diagnosticCount = diagnostics.Count;
        if (diagnosticCount == 0)
            return (Array.Empty<int>(), 0);

        var scratch = t_diagnosticDeduplicationScratch ??= new DiagnosticDeduplicationScratch();
        scratch.EnsureCapacity(diagnosticCount);

        try
        {
            scratch.ResetIds();
            for (var i = 0; i < diagnosticCount; i++)
            {
                var diagnostic = diagnostics[i];
                scratch.CodeIds[i] = scratch.GetCodeId(diagnostic.Code);
                scratch.FileRanks[i] = scratch.GetFileId(diagnostic.File);
                scratch.LineNumbers[i] = diagnostic.Line;
                scratch.Columns[i] = diagnostic.Column;
                scratch.MessageIds[i] = scratch.GetMessageId(diagnostic.Message);
            }

            var count = RequiredBindings.DiagnosticDeduplicateStable(
                scratch.CodeIds,
                scratch.FileRanks,
                scratch.LineNumbers,
                scratch.Columns,
                scratch.MessageIds,
                scratch.SlotIndices,
                scratch.ResultIndices);

            return (scratch.ResultIndices, count);
        }
        finally
        {
            scratch.ResetIds();
        }
    }

    internal static (int[] ResultIndices, int Count) DeduplicateReferences(
        IReadOnlyList<ReferenceResult> references)
    {
        var referenceCount = references.Count;
        if (referenceCount == 0)
            return (Array.Empty<int>(), 0);

        var scratch = t_referenceDeduplicationScratch ??= new ReferenceDeduplicationScratch();
        scratch.EnsureCapacity(referenceCount);

        try
        {
            scratch.ResetFiles();
            for (var i = 0; i < referenceCount; i++)
            {
                var reference = references[i];
                scratch.LineNumbers[i] = reference.Line;
                scratch.Columns[i] = reference.Column;
                scratch.Files[i] = reference.File;
                scratch.AddFile(reference.File);
            }

            scratch.BuildFileRanks();
            for (var i = 0; i < referenceCount; i++)
            {
                scratch.FileRanks[i] = scratch.GetFileRank(scratch.Files[i]);
            }

            var count = RequiredBindings.ReferenceDeduplicateCompact(
                scratch.FileRanks,
                scratch.LineNumbers,
                scratch.Columns,
                scratch.SlotIndices,
                scratch.ResultIndices);

            return (scratch.ResultIndices, count);
        }
        finally
        {
            scratch.ClearFiles(referenceCount);
            scratch.ResetFiles();
        }
    }

    internal static bool MatchesFilePath(string fullPath, string queryPath)
        => RequiredBindings.PathMatches(fullPath, queryPath) != 0;

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<DiagnosticShadowSuppressionIndicesInto>(
                programType,
                "DiagnosticShadowSuppressionIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<DiagnosticDeduplicateCompactInto>(
                programType,
                "DiagnosticDeduplicateCompactInto"),
            DogfoodKernelLoader.CreateDelegate<DiagnosticDeduplicateCompactInto>(
                programType,
                "DiagnosticDeduplicateStableInto"),
            DogfoodKernelLoader.CreateDelegate<ReferenceDeduplicateCompactInto>(
                programType,
                "ReferenceDeduplicateCompactInto"),
            DogfoodKernelLoader.CreateDelegate<CodeIntelligencePathMatches>(
                programType,
                "CodeIntelligencePathMatches")));

    private delegate int DiagnosticShadowSuppressionIndicesInto(
        int[] codeIds,
        int[] fileRanks,
        int targetCodeId,
        int[] shadowFileFlags,
        int[] resultIndices);

    private delegate int DiagnosticDeduplicateCompactInto(
        int[] codeIds,
        int[] fileRanks,
        int[] lineNumbers,
        int[] columns,
        int[] messageIds,
        int[] slotIndices,
        int[] resultIndices);

    private delegate int ReferenceDeduplicateCompactInto(
        int[] fileRanks,
        int[] lineNumbers,
        int[] columns,
        int[] slotIndices,
        int[] resultIndices);

    private delegate int CodeIntelligencePathMatches(string fullPath, string queryPath);

    private sealed record Bindings(
        DiagnosticShadowSuppressionIndicesInto DiagnosticShadowSuppression,
        DiagnosticDeduplicateCompactInto DiagnosticDeduplicateCompact,
        DiagnosticDeduplicateCompactInto DiagnosticDeduplicateStable,
        ReferenceDeduplicateCompactInto ReferenceDeduplicateCompact,
        CodeIntelligencePathMatches PathMatches);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# code intelligence result kernels are unavailable.");

}
