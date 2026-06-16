using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using NSharpLang.Compiler;

namespace NSharpLang.Cli;

internal static class NSharpCliDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";

    private static BuildOperandScratch? t_buildOperandScratch;
    [ThreadStatic]
    private static ReferenceTypeFilterScratch? t_referenceTypeFilterScratch;
    [ThreadStatic]
    private static StableDistinctScratch? t_stableDistinctScratch;
    [ThreadStatic]
    private static int[]? t_publishOptionIndices;
    [ThreadStatic]
    private static TestOutcomeSummaryScratch? t_testOutcomeSummaryScratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings);

    internal static bool TryGetBuildOperandSummary(string[] args, out int count, out int firstOperandIndex)
    {
        count = 0;
        firstOperandIndex = -1;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length == 0)
            return true;

        var scratch = t_buildOperandScratch ??= new BuildOperandScratch();
        scratch.EnsureCapacity(args.Length);

        try
        {
            firstOperandIndex = bindings.CliBuildFirstOperandIndex(
                args,
                scratch.KindIds,
                scratch.NextIndices,
                scratch.PreviousIndices,
                scratch.NextOptionIndices,
                scratch.ResultIndices);
            if (firstOperandIndex < -1 || firstOperandIndex >= args.Length)
            {
                count = 0;
                firstOperandIndex = -1;
                return false;
            }

            count = firstOperandIndex >= 0 ? 1 : 0;
            return true;
        }
        catch
        {
            count = 0;
            firstOperandIndex = -1;
            return false;
        }
    }

    internal static bool TryGetRunSourceOperand(string[] args, out string? operand)
    {
        operand = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var index = bindings.CliRunFirstOperandIndex(args);
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            operand = args[index];
            return true;
        }
        catch
        {
            operand = null;
            return false;
        }
    }

    internal static bool TryGetPublishArgumentSummary(string[] args, out PublishArgumentSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length != 0)
            return false;

        var resultIndices = t_publishOptionIndices ??= new int[8];
        try
        {
            var code = bindings.CliPublishOptionsInto(args, resultIndices);
            if (code < 0 || code > 4)
                return false;

            var validationError = GetPublishValidationError(args, code, resultIndices[7]);
            if (validationError != null)
            {
                summary = new PublishArgumentSummary(
                    validationError,
                    null,
                    null,
                    "Release",
                    null,
                    null,
                    false,
                    false);
                return true;
            }

            if (!TryGetOptionalArg(args, resultIndices[0], out var projectOption)
                || !TryGetOptionalArg(args, resultIndices[1], out var backendOption)
                || !TryGetOptionalArg(args, resultIndices[2], out var configuration)
                || !TryGetOptionalArg(args, resultIndices[3], out var output)
                || !TryGetOptionalArg(args, resultIndices[4], out var runtime))
            {
                summary = default;
                return false;
            }

            summary = new PublishArgumentSummary(
                null,
                projectOption,
                backendOption,
                configuration ?? "Release",
                output,
                runtime,
                resultIndices[5] != 0,
                resultIndices[6] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    private static string? GetPublishValidationError(string[] args, int code, int errorArgIndex)
    {
        if (code == 0)
            return null;

        if (code == 2)
        {
            return "Target-platform publishing is expressed as --runtime <rid>, and nlc publish does not support cross-runtime publishing yet.";
        }

        if (errorArgIndex < 0 || errorArgIndex >= args.Length)
            return null;

        return code switch
        {
            1 => $"Option '{args[errorArgIndex]}' requires a value.",
            3 => $"Unknown publish option '{args[errorArgIndex]}'. Run 'nlc publish --help' for supported options.",
            4 => $"Unexpected publish argument '{args[errorArgIndex]}'. Run 'nlc publish --help' for usage.",
            _ => null
        };
    }

    private static bool TryGetOptionalArg(string[] args, int index, out string? value)
    {
        value = null;
        if (index == -1)
            return true;

        if (index < 0 || index >= args.Length)
            return false;

        value = args[index];
        return true;
    }

    internal static bool TryGetFirstPositionalArg(
        string[] args,
        string[] optionsWithValues,
        out string? positional)
    {
        positional = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var index = bindings.CliFirstPositionalArgIndex(args, optionsWithValues);
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            positional = args[index];
            return true;
        }
        catch
        {
            positional = null;
            return false;
        }
    }

    internal static bool TryGetExportCSharpInputOperand(string[] args, out string? operand)
    {
        operand = null;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length == 0)
            return true;

        var scratch = t_buildOperandScratch ??= new BuildOperandScratch();
        scratch.EnsureCapacity(args.Length);

        try
        {
            var index = bindings.CliExportCSharpFirstOperandIndex(
                args,
                scratch.KindIds,
                scratch.NextIndices,
                scratch.PreviousIndices,
                scratch.NextOptionIndices,
                scratch.ResultIndices);
            if (index == -1)
                return true;

            if (index < 0 || index >= args.Length)
                return false;

            operand = args[index];
            return true;
        }
        catch
        {
            operand = null;
            return false;
        }
    }

    internal static bool TryFilterReferencesByType(
        IReadOnlyList<Reference> dependencies,
        ReferenceType targetType,
        out List<Reference> filteredDependencies)
    {
        filteredDependencies = new List<Reference>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var dependencyCount = dependencies.Count;
        if (dependencyCount == 0)
            return true;

        var targetTypeRank = GetReferenceTypeRank(targetType);
        if (targetTypeRank <= 0)
            return false;

        var scratch = t_referenceTypeFilterScratch ??= new ReferenceTypeFilterScratch();
        scratch.EnsureCapacity(dependencyCount);

        try
        {
            for (var i = 0; i < dependencyCount; i++)
                scratch.TypeRanks[i] = GetReferenceTypeRank(dependencies[i].Type);

            var filteredCount = bindings.CliReferenceTypeFilterIndices(
                scratch.TypeRanks,
                targetTypeRank,
                scratch.ResultIndices);

            if (filteredCount < 0 || filteredCount > dependencyCount || filteredCount > scratch.ResultIndices.Length)
                return false;

            filteredDependencies = new List<Reference>(filteredCount);
            for (var i = 0; i < filteredCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= dependencyCount)
                {
                    filteredDependencies = new List<Reference>();
                    return false;
                }

                var dependency = dependencies[sourceIndex];
                if (dependency.Type != targetType)
                {
                    filteredDependencies = new List<Reference>();
                    return false;
                }

                filteredDependencies.Add(dependency);
            }

            return true;
        }
        catch
        {
            filteredDependencies = new List<Reference>();
            return false;
        }
    }

    internal static bool TryDeduplicateExportReferences<T>(
        IReadOnlyList<T> values,
        IEqualityComparer<T>? comparer,
        out List<T> deduplicatedValues)
        where T : notnull
        => TryDeduplicateStable(values, comparer, out deduplicatedValues);

    internal static bool TryDeduplicateStable<T>(
        IReadOnlyList<T> values,
        IEqualityComparer<T>? comparer,
        out List<T> deduplicatedValues)
        where T : notnull
    {
        deduplicatedValues = new List<T>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var valueCount = values.Count;
        if (valueCount == 0)
            return true;

        var scratch = t_stableDistinctScratch ??= new StableDistinctScratch();
        scratch.EnsureCapacity(valueCount);

        try
        {
            var ranksByValue = comparer == null
                ? new Dictionary<T, int>()
                : new Dictionary<T, int>(comparer);
            var uniqueRankCount = 0;

            for (var i = 0; i < valueCount; i++)
            {
                var value = values[i];
                if (!ranksByValue.TryGetValue(value, out var rank))
                {
                    rank = ++uniqueRankCount;
                    ranksByValue.Add(value, rank);
                }

                scratch.Ranks[i] = rank;
            }

            scratch.EnsureRankCapacity(uniqueRankCount);
            var resultCount = bindings.CliStableDistinctRankIndices(
                scratch.Ranks,
                uniqueRankCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            if (resultCount < 0 || resultCount > valueCount || resultCount > scratch.ResultIndices.Length)
            {
                deduplicatedValues = new List<T>();
                return false;
            }

            var result = new List<T>(resultCount);
            for (var i = 0; i < resultCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= valueCount)
                {
                    deduplicatedValues = new List<T>();
                    return false;
                }

                result.Add(values[sourceIndex]);
            }

            deduplicatedValues = result;
            return true;
        }
        catch
        {
            deduplicatedValues = new List<T>();
            return false;
        }
    }

    internal static bool TrySummarizeTestOutcomeRanks(
        int[] outcomeRanks,
        int outcomeCount,
        out (bool Ok, int Passed, int Failed, int Skipped) summary)
    {
        summary = (true, 0, 0, 0);

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (outcomeCount < 0 || outcomeCount > outcomeRanks.Length)
            return false;

        if (outcomeCount == 0)
            return true;

        var scratch = t_testOutcomeSummaryScratch ??= new TestOutcomeSummaryScratch();
        scratch.EnsureCapacity();

        try
        {
            var summarizedCount = bindings.CliTestOutcomeSummary(
                outcomeRanks,
                outcomeCount,
                scratch.SummaryCounts);

            var passed = scratch.SummaryCounts[0];
            var failed = scratch.SummaryCounts[1];
            var skipped = scratch.SummaryCounts[2];
            var nonOk = scratch.SummaryCounts[3];
            if (summarizedCount != outcomeCount ||
                passed < 0 ||
                failed < 0 ||
                skipped < 0 ||
                nonOk < 0 ||
                passed > outcomeCount ||
                failed > outcomeCount ||
                skipped > outcomeCount ||
                nonOk > outcomeCount ||
                passed + failed + skipped > outcomeCount ||
                nonOk < failed)
            {
                summary = (true, 0, 0, 0);
                return false;
            }

            summary = (nonOk == 0, passed, failed, skipped);
            return true;
        }
        catch
        {
            summary = (true, 0, 0, 0);
            return false;
        }
    }

    private static Bindings? LoadBindings()
    {
        try
        {
            var assembly = TryLoadDogfoodAssembly();
            var programType = assembly?.GetType("Program");
            if (programType == null)
                return null;

            return new Bindings(
                CreateDelegate<CliBuildFirstOperandIndexInto>(programType, "CliBuildFirstOperandIndexInto"),
                CreateDelegate<CliExportCSharpFirstOperandIndexInto>(programType, "CliExportCSharpFirstOperandIndexInto"),
                CreateDelegate<CliRunFirstOperandIndex>(programType, "CliRunFirstOperandIndex"),
                CreateDelegate<CliPublishOptionsInto>(programType, "CliPublishOptionsInto"),
                CreateDelegate<CliFirstPositionalArgIndex>(programType, "CliFirstPositionalArgIndex"),
                CreateDelegate<CliReferenceTypeFilterIndicesInto>(programType, "CliReferenceTypeFilterIndicesInto"),
                CreateDelegate<CliTestOutcomeSummaryInto>(programType, "CliTestOutcomeSummaryInto"),
                CreateDelegate<CliStableDistinctRankIndicesInto>(programType, "CliStableDistinctRankIndicesInto"));
        }
        catch
        {
            return null;
        }
    }

    private static Assembly? TryLoadDogfoodAssembly()
    {
        try
        {
            return Assembly.Load(new AssemblyName(DogfoodAssemblyName));
        }
        catch
        {
            var assemblyPath = Path.Combine(AppContext.BaseDirectory, $"{DogfoodAssemblyName}.dll");
            return File.Exists(assemblyPath)
                ? Assembly.LoadFrom(assemblyPath)
                : null;
        }
    }

    private static TDelegate CreateDelegate<TDelegate>(Type programType, string methodName)
        where TDelegate : Delegate
    {
        var method = programType.GetMethod(
                methodName,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new MissingMethodException(programType.FullName, methodName);

        return (TDelegate)Delegate.CreateDelegate(typeof(TDelegate), method);
    }

    private delegate int CliBuildFirstOperandIndexInto(
        string[] args,
        int[] kindIds,
        int[] nextIndices,
        int[] previousIndices,
        int[] nextOptionIndices,
        int[] resultIndices);

    private delegate int CliExportCSharpFirstOperandIndexInto(
        string[] args,
        int[] kindIds,
        int[] nextIndices,
        int[] previousIndices,
        int[] nextOptionIndices,
        int[] resultIndices);

    private delegate int CliRunFirstOperandIndex(string[] args);

    private delegate int CliPublishOptionsInto(string[] args, int[] resultIndices);

    private delegate int CliFirstPositionalArgIndex(
        string[] args,
        string[] optionsWithValues);

    private delegate int CliReferenceTypeFilterIndicesInto(
        int[] typeRanks,
        int targetTypeRank,
        int[] resultIndices);

    private delegate int CliStableDistinctRankIndicesInto(
        int[] ranks,
        int uniqueRankCount,
        int[] seenRanks,
        int[] resultIndices);

    private delegate int CliTestOutcomeSummaryInto(
        int[] outcomeRanks,
        int count,
        int[] resultCounts);

    private sealed record Bindings(
        CliBuildFirstOperandIndexInto CliBuildFirstOperandIndex,
        CliExportCSharpFirstOperandIndexInto CliExportCSharpFirstOperandIndex,
        CliRunFirstOperandIndex CliRunFirstOperandIndex,
        CliPublishOptionsInto CliPublishOptionsInto,
        CliFirstPositionalArgIndex CliFirstPositionalArgIndex,
        CliReferenceTypeFilterIndicesInto CliReferenceTypeFilterIndices,
        CliTestOutcomeSummaryInto CliTestOutcomeSummary,
        CliStableDistinctRankIndicesInto CliStableDistinctRankIndices);

    private static int GetReferenceTypeRank(ReferenceType type) =>
        type switch
        {
            ReferenceType.NuGet => 1,
            ReferenceType.Dll => 2,
            ReferenceType.Project => 3,
            ReferenceType.Framework => 4,
            _ => 0
        };

    private sealed class BuildOperandScratch
    {
        internal int[] KindIds = Array.Empty<int>();
        internal int[] NextIndices = Array.Empty<int>();
        internal int[] NextOptionIndices = Array.Empty<int>();
        internal int[] PreviousIndices = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (KindIds.Length != count)
            {
                KindIds = new int[count];
                NextIndices = new int[count];
                NextOptionIndices = new int[count];
                PreviousIndices = new int[count];
                ResultIndices = new int[count];
            }
        }
    }

    private sealed class ReferenceTypeFilterScratch
    {
        internal int[] TypeRanks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int dependencyCount)
        {
            if (TypeRanks.Length != dependencyCount || ResultIndices.Length != dependencyCount)
            {
                TypeRanks = new int[dependencyCount];
                ResultIndices = new int[dependencyCount];
            }
        }
    }

    private sealed class StableDistinctScratch
    {
        internal int[] Ranks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] SeenRanks = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (Ranks.Length != count || ResultIndices.Length != count)
            {
                Ranks = new int[count];
                ResultIndices = new int[count];
            }
        }

        internal void EnsureRankCapacity(int uniqueRankCount)
        {
            var rankCapacity = uniqueRankCount + 1;
            if (SeenRanks.Length != rankCapacity)
            {
                SeenRanks = new int[rankCapacity];
            }
        }
    }

    private sealed class TestOutcomeSummaryScratch
    {
        internal int[] SummaryCounts = Array.Empty<int>();

        internal void EnsureCapacity()
        {
            if (SummaryCounts.Length != 4)
            {
                SummaryCounts = new int[4];
            }
        }
    }
}
