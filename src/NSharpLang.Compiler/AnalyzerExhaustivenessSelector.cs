using System;
using System.Collections.Generic;
using System.IO;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

internal static class AnalyzerExhaustivenessSelector
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static MissingEnumMemberScratch? t_missingEnumMemberScratch;
    [ThreadStatic]
    private static MissingUnionCaseScratch? t_missingUnionCaseScratch;

    internal static bool TrySelectMissingEnumMembers(
        IReadOnlyList<EnumMember> members,
        ISet<string> coveredMembers,
        out List<string> missingMembers)
    {
        missingMembers = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var memberCount = members.Count;
        if (memberCount == 0)
            return true;

        var scratch = t_missingEnumMemberScratch ??= new MissingEnumMemberScratch();
        scratch.EnsureCapacity(memberCount);

        try
        {
            scratch.ResetNames();
            for (var i = 0; i < memberCount; i++)
            {
                var memberName = members[i].Name;
                if (!scratch.AddName(memberName))
                    return false;

                scratch.CoveredFlags[i] = coveredMembers.Contains(memberName) ? 1 : 0;
            }

            var missingCount = bindings.AnalyzerMissingMemberIndices(
                scratch.CoveredFlags,
                memberCount,
                scratch.ResultIndices);

            if (missingCount < 0 || missingCount > memberCount || missingCount > scratch.ResultIndices.Length)
            {
                missingMembers = [];
                return false;
            }

            var result = new List<string>(missingCount);
            for (var i = 0; i < missingCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= memberCount)
                {
                    missingMembers = [];
                    return false;
                }

                result.Add(members[sourceIndex].Name);
            }

            missingMembers = result;
            return true;
        }
        catch
        {
            missingMembers = [];
            return false;
        }
        finally
        {
            scratch.ResetNames();
        }
    }

    internal static bool TrySelectMissingUnionCasesFromFlags(
        IReadOnlyList<UnionCase> cases,
        int[] coveredFlags,
        int[] partialFlags,
        int count,
        out List<string> missingCases,
        out List<string> partialMissingCases,
        out List<string> neverCoveredCases)
    {
        missingCases = [];
        partialMissingCases = [];
        neverCoveredCases = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (count < 0 || count > cases.Count || count > coveredFlags.Length || count > partialFlags.Length)
            return false;

        if (count == 0)
            return true;

        var scratch = t_missingUnionCaseScratch ??= new MissingUnionCaseScratch();
        scratch.EnsureCapacity(count);

        try
        {
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
                missingCases = [];
                partialMissingCases = [];
                neverCoveredCases = [];
                return false;
            }

            missingCases = MaterializeCaseNames(cases, scratch.MissingIndices, missingCount);
            partialMissingCases = MaterializeCaseNames(cases, scratch.PartialMissingIndices, partialMissingCount);
            neverCoveredCases = MaterializeCaseNames(cases, scratch.NeverCoveredIndices, neverCoveredCount);
            return true;
        }
        catch
        {
            missingCases = [];
            partialMissingCases = [];
            neverCoveredCases = [];
            return false;
        }
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
        private readonly HashSet<string> _seenNames = new(StringComparer.Ordinal);

        internal int[] CoveredFlags = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal bool AddName(string name) => _seenNames.Add(name);

        internal void EnsureCapacity(int count)
        {
            if (CoveredFlags.Length < count)
            {
                CoveredFlags = new int[count];
                ResultIndices = new int[count];
            }
        }

        internal void ResetNames()
        {
            _seenNames.Clear();
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
