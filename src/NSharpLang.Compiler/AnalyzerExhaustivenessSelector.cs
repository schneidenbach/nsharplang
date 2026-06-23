using System;
using System.Collections.Generic;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

internal static class AnalyzerExhaustivenessSelector
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static MissingEnumMemberScratch? t_missingEnumMemberScratch;
    [ThreadStatic]
    private static MissingUnionCaseScratch? t_missingUnionCaseScratch;

    internal static List<string> SelectMissingEnumMembers(
        IReadOnlyList<EnumMember> members,
        ISet<string> coveredMembers)
    {
        var bindings = RequiredBindings;

        var memberCount = members.Count;
        var scratch = t_missingEnumMemberScratch ??= new MissingEnumMemberScratch();
        scratch.EnsureCapacity(memberCount);

        for (var i = 0; i < memberCount; i++)
        {
            scratch.CoveredFlags[i] = coveredMembers.Contains(members[i].Name) ? 1 : 0;
        }

        var missingCount = bindings.AnalyzerMissingMemberIndices(
            scratch.CoveredFlags,
            memberCount,
            scratch.ResultIndices);

        if (missingCount < 0 || missingCount > memberCount || missingCount > scratch.ResultIndices.Length)
            throw new InvalidOperationException("N# analyzer enum exhaustiveness kernel rejected the member table.");

        var result = new List<string>(missingCount);
        for (var i = 0; i < missingCount; i++)
        {
            var sourceIndex = scratch.ResultIndices[i];
            if (sourceIndex < 0 || sourceIndex >= memberCount)
                throw new InvalidOperationException("N# analyzer enum exhaustiveness kernel returned an invalid member index.");

            result.Add(members[sourceIndex].Name);
        }

        return result;
    }

    internal static void SelectMissingUnionCasesFromFlags(
        IReadOnlyList<UnionCase> cases,
        int[] coveredFlags,
        int[] partialFlags,
        int count,
        out List<string> missingCases,
        out List<string> partialMissingCases,
        out List<string> neverCoveredCases)
    {
        var bindings = RequiredBindings;

        if (count < 0 || count > cases.Count || count > coveredFlags.Length || count > partialFlags.Length)
            throw new InvalidOperationException("N# analyzer union exhaustiveness kernel received an invalid case count.");

        var scratch = t_missingUnionCaseScratch ??= new MissingUnionCaseScratch();
        scratch.EnsureCapacity(count);

        var missingCount = bindings.AnalyzerUnionMissingCaseIndices(
            coveredFlags,
            partialFlags,
            count,
            scratch.MissingIndices,
            scratch.PartialMissingIndices,
            scratch.NeverCoveredIndices,
            scratch.ResultCounts);

        var partialMissingCount = scratch.ResultCounts[1];
        var neverCoveredCount = scratch.ResultCounts[2];
        if (missingCount < 0 ||
            missingCount > count ||
            partialMissingCount < 0 ||
            partialMissingCount > missingCount ||
            neverCoveredCount < 0 ||
            neverCoveredCount > missingCount ||
            partialMissingCount + neverCoveredCount != missingCount)
        {
            throw new InvalidOperationException("N# analyzer union exhaustiveness kernel rejected the case table.");
        }

        missingCases = MaterializeCaseNames(cases, scratch.MissingIndices, missingCount);
        partialMissingCases = MaterializeCaseNames(cases, scratch.PartialMissingIndices, partialMissingCount);
        neverCoveredCases = MaterializeCaseNames(cases, scratch.NeverCoveredIndices, neverCoveredCount);
    }

    private static List<string> MaterializeCaseNames(
        IReadOnlyList<UnionCase> cases,
        int[] indices,
        int count)
    {
        var result = new List<string>(count);
        for (var i = 0; i < count; i++)
        {
            var sourceIndex = indices[i];
            if (sourceIndex < 0 || sourceIndex >= cases.Count)
                throw new InvalidOperationException("Dogfood union missing-case selection returned an invalid source index.");

            result.Add(cases[sourceIndex].Name);
        }

        return result;
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<AnalyzerMissingMemberIndicesInto>(
                programType,
                "AnalyzerMissingMemberIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<AnalyzerUnionMissingCaseIndicesInto>(
                programType,
                "AnalyzerUnionMissingCaseIndicesInto")));

    private static Bindings RequiredBindings =>
        s_bindings.Value
        ?? throw new InvalidOperationException("N# analyzer exhaustiveness kernels are unavailable.");

    private delegate int AnalyzerMissingMemberIndicesInto(int[] coveredFlags, int count, int[] resultIndices);
    private delegate int AnalyzerUnionMissingCaseIndicesInto(
        int[] coveredFlags,
        int[] partialFlags,
        int count,
        int[] missingIndices,
        int[] partialMissingIndices,
        int[] neverCoveredIndices,
        int[] resultCounts);

    private sealed record Bindings(
        AnalyzerMissingMemberIndicesInto AnalyzerMissingMemberIndices,
        AnalyzerUnionMissingCaseIndicesInto AnalyzerUnionMissingCaseIndices);

    private sealed class MissingEnumMemberScratch
    {
        internal int[] CoveredFlags = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (CoveredFlags.Length < count)
            {
                CoveredFlags = new int[count];
                ResultIndices = new int[count];
            }
        }
    }

    private sealed class MissingUnionCaseScratch
    {
        internal int[] MissingIndices = Array.Empty<int>();
        internal int[] NeverCoveredIndices = Array.Empty<int>();
        internal int[] PartialMissingIndices = Array.Empty<int>();
        internal int[] ResultCounts = new int[3];

        internal void EnsureCapacity(int count)
        {
            if (MissingIndices.Length < count)
            {
                MissingIndices = new int[count];
                NeverCoveredIndices = new int[count];
                PartialMissingIndices = new int[count];
            }

            if (ResultCounts.Length != 3)
            {
                ResultCounts = new int[3];
            }
        }
    }
}
