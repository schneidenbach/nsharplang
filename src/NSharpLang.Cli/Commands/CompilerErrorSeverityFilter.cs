using System;
using System.Collections.Generic;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

internal static class CompilerErrorSeverityFilter
{
    [ThreadStatic]
    private static Scratch? t_scratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static List<CompilerError> Filter(
        IReadOnlyList<CompilerError> errors,
        ErrorSeverity severity)
    {
        var targetSeverityId = (int)severity;
        if (targetSeverityId < 0 || targetSeverityId > (int)ErrorSeverity.Error)
            throw new InvalidOperationException("N# diagnostic severity filter kernel rejected the severity.");

        var errorCount = errors.Count;
        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(errorCount);

        for (var i = 0; i < errorCount; i++)
        {
            scratch.SeverityRanks[i] = (int)errors[i].Severity;
        }

        var filteredCount = RequiredBindings.DiagnosticSeverityFilter(
            scratch.SeverityRanks,
            targetSeverityId,
            scratch.ResultIndices);

        if (filteredCount < 0 || filteredCount > errorCount || filteredCount > scratch.ResultIndices.Length)
            throw new InvalidOperationException("N# diagnostic severity filter kernel rejected the diagnostics.");

        var filteredErrors = new List<CompilerError>(filteredCount);
        for (var i = 0; i < filteredCount; i++)
        {
            var sourceIndex = scratch.ResultIndices[i];
            if (sourceIndex < 0 || sourceIndex >= errorCount)
                throw new InvalidOperationException("N# diagnostic severity filter kernel rejected the diagnostics.");

            filteredErrors.Add(errors[sourceIndex]);
        }

        return filteredErrors;
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<DiagnosticSeverityFilterIndicesInto>(
                programType,
                "DiagnosticSeverityFilterIndicesInto")));

    private delegate int DiagnosticSeverityFilterIndicesInto(
        int[] severityRanks,
        int targetRank,
        int[] resultIndices);

    private sealed record Bindings(DiagnosticSeverityFilterIndicesInto DiagnosticSeverityFilter);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# diagnostic severity filter kernels are unavailable.");

    private sealed class Scratch
    {
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SeverityRanks = Array.Empty<int>();

        internal void EnsureCapacity(int errorCount)
        {
            if (SeverityRanks.Length != errorCount)
            {
                SeverityRanks = new int[errorCount];
                ResultIndices = new int[errorCount];
            }
        }
    }
}
