using System;
using System.Collections.Generic;
using NSharpLang.Compiler;

namespace NSharpLang.Cli;

internal static class CompilationReferenceResolverKernels
{
    [ThreadStatic]
    private static ReferenceTypeFilterScratch? t_referenceTypeFilterScratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryFilterReferencesByType(
        IReadOnlyList<Reference> references,
        ReferenceType targetType,
        out List<Reference> filteredReferences)
    {
        filteredReferences = new List<Reference>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var referenceCount = references.Count;
        if (referenceCount == 0)
            return true;

        var targetTypeRank = GetReferenceTypeRank(targetType);
        if (targetTypeRank <= 0)
            return false;

        var scratch = t_referenceTypeFilterScratch ??= new ReferenceTypeFilterScratch();
        scratch.EnsureCapacity(referenceCount);

        try
        {
            for (var i = 0; i < referenceCount; i++)
                scratch.TypeRanks[i] = GetReferenceTypeRank(references[i].Type);

            var filteredCount = bindings.ReferenceTypeFilterIndices(
                scratch.TypeRanks,
                targetTypeRank,
                scratch.ResultIndices);

            if (filteredCount < 0 || filteredCount > referenceCount || filteredCount > scratch.ResultIndices.Length)
                return false;

            filteredReferences = new List<Reference>(filteredCount);
            for (var i = 0; i < filteredCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= referenceCount)
                {
                    filteredReferences = new List<Reference>();
                    return false;
                }

                var reference = references[sourceIndex];
                if (reference.Type != targetType)
                {
                    filteredReferences = new List<Reference>();
                    return false;
                }

                filteredReferences.Add(reference);
            }

            return true;
        }
        catch
        {
            filteredReferences = new List<Reference>();
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
                DogfoodKernelLoader.CreateDelegate<CliReferenceTypeFilterIndicesInto>(
                    programType,
                    "CliReferenceTypeFilterIndicesInto"));
        }
        catch
        {
            return null;
        }
    }

    private delegate int CliReferenceTypeFilterIndicesInto(
        int[] typeRanks,
        int targetTypeRank,
        int[] resultIndices);

    private sealed record Bindings(CliReferenceTypeFilterIndicesInto ReferenceTypeFilterIndices);

    private static int GetReferenceTypeRank(ReferenceType type) =>
        type switch
        {
            ReferenceType.NuGet => 1,
            ReferenceType.Dll => 2,
            ReferenceType.Project => 3,
            ReferenceType.Framework => 4,
            _ => 0
        };

    private sealed class ReferenceTypeFilterScratch
    {
        internal int[] TypeRanks = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int referenceCount)
        {
            if (TypeRanks.Length != referenceCount)
                TypeRanks = new int[referenceCount];

            if (ResultIndices.Length != referenceCount)
                ResultIndices = new int[referenceCount];
        }
    }
}
