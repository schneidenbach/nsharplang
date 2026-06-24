using System;
using System.Collections.Generic;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

internal static class AnalyzerExhaustivenessSelector
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static MissingUnionCaseScratch? t_missingUnionCaseScratch;

    internal static List<string> SelectMissingEnumMembers(
        IReadOnlyList<EnumMember> members,
        ISet<string> coveredMembers)
    {
        var bindings = RequiredBindings;

        var memberCount = members.Count;
        var memberNames = new string[memberCount];
        for (var i = 0; i < memberCount; i++)
        {
            memberNames[i] = members[i].Name;
        }

        var coveredNames = new string[coveredMembers.Count];
        coveredMembers.CopyTo(coveredNames, 0);

        var resultNames = new string[memberCount];
        var missingCount = bindings.AnalyzerMissingMemberNames(
            memberNames,
            coveredNames,
            resultNames);

        var result = new List<string>(missingCount);
        for (var i = 0; i < missingCount; i++)
        {
            result.Add(resultNames[i]);
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
            result.Add(cases[sourceIndex].Name);
        }

        return result;
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<AnalyzerMissingMemberNamesInto>(
                programType,
                "AnalyzerMissingMemberNamesInto"),
            DogfoodKernelLoader.CreateDelegate<AnalyzerUnionMissingCaseIndicesInto>(
                programType,
                "AnalyzerUnionMissingCaseIndicesInto")));

    private static Bindings RequiredBindings =>
        s_bindings.Value
        ?? throw new InvalidOperationException("N# analyzer exhaustiveness kernels are unavailable.");

    private delegate int AnalyzerMissingMemberNamesInto(string[] memberNames, string[] coveredNames, string[] resultNames);
    private delegate int AnalyzerUnionMissingCaseIndicesInto(
        int[] coveredFlags,
        int[] partialFlags,
        int count,
        int[] missingIndices,
        int[] partialMissingIndices,
        int[] neverCoveredIndices,
        int[] resultCounts);

    private sealed record Bindings(
        AnalyzerMissingMemberNamesInto AnalyzerMissingMemberNames,
        AnalyzerUnionMissingCaseIndicesInto AnalyzerUnionMissingCaseIndices);

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
