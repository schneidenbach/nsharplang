using System;
using System.Collections.Generic;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

internal static class CompilerErrorSeverityFilter
{
    [ThreadStatic]
    private static Scratch? t_scratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryFilter(
        IReadOnlyList<CompilerError> errors,
        ErrorSeverity severity,
        out List<CompilerError> filteredErrors)
    {
        filteredErrors = new List<CompilerError>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var targetRank = GetSeverityRank(severity);
        if (targetRank == 0)
            return false;

        var errorCount = errors.Count;
        if (errorCount == 0)
            return true;

        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(errorCount);

        try
        {
            for (var i = 0; i < errorCount; i++)
            {
                scratch.SeverityRanks[i] = GetSeverityRank(errors[i].Severity);
            }

            var filteredCount = bindings.DiagnosticSeverityFilter(
                scratch.SeverityRanks,
                targetRank,
                scratch.ResultIndices);

            if (filteredCount < 0 || filteredCount > errorCount || filteredCount > scratch.ResultIndices.Length)
            {
                filteredErrors = new List<CompilerError>();
                return false;
            }

            filteredErrors = new List<CompilerError>(filteredCount);
            for (var i = 0; i < filteredCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= errorCount)
                {
                    filteredErrors = new List<CompilerError>();
                    return false;
                }

                filteredErrors.Add(errors[sourceIndex]);
            }

            return true;
        }
        catch
        {
            filteredErrors = new List<CompilerError>();
            return false;
        }
    }

    private static Bindings? LoadBindings()
    {
        try
        {
            var programType = DogfoodKernelLoader.TryGetProgramType();
            if (programType == null)
                return null;

            return new Bindings(
                DogfoodKernelLoader.CreateDelegate<DiagnosticSeverityFilterIndicesInto>(
                    programType,
                    "DiagnosticSeverityFilterIndicesInto"));
        }
        catch
        {
            return null;
        }
    }

    private static int GetSeverityRank(ErrorSeverity severity) =>
        severity switch
        {
            ErrorSeverity.Error => 1,
            ErrorSeverity.Warning => 2,
            _ => 0
        };

    private delegate int DiagnosticSeverityFilterIndicesInto(
        int[] severityRanks,
        int targetRank,
        int[] resultIndices);

    private sealed record Bindings(DiagnosticSeverityFilterIndicesInto DiagnosticSeverityFilter);

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
