using System;
using System.Collections.Generic;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

internal static class UpdateDependencyFilter
{
    [ThreadStatic]
    private static Scratch? t_scratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static List<Reference> FilterAllNuGetDependencies(IReadOnlyList<Reference> dependencies)
    {
        var bindings = RequiredBindings;
        var dependencyCount = dependencies.Count;
        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(dependencyCount);

        for (var i = 0; i < dependencyCount; i++)
            scratch.NuGetFlags[i] = dependencies[i].Nuget == null ? 0 : 1;

        var filteredCount = bindings.AllNuGetDependencyIndices(
            scratch.NuGetFlags,
            scratch.ResultIndices);

        if (filteredCount < 0 || filteredCount > dependencyCount || filteredCount > scratch.ResultIndices.Length)
            throw new InvalidOperationException("N# update dependency filter kernel returned an invalid result count.");

        var filteredDependencies = new List<Reference>(filteredCount);
        for (var i = 0; i < filteredCount; i++)
        {
            var sourceIndex = scratch.ResultIndices[i];
            if (sourceIndex < 0 || sourceIndex >= dependencyCount)
                throw new InvalidOperationException("N# update dependency filter kernel returned an invalid dependency index.");

            var dependency = dependencies[sourceIndex];
            if (dependency.Nuget == null)
                throw new InvalidOperationException("N# update dependency filter kernel selected a non-NuGet dependency.");

            filteredDependencies.Add(dependency);
        }

        return filteredDependencies;
    }

    internal static List<Reference> FilterTargetNuGetDependencies(
        IReadOnlyList<Reference> dependencies,
        string targetPackage)
    {
        var bindings = RequiredBindings;
        var dependencyCount = dependencies.Count;
        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(dependencyCount);

        try
        {
            scratch.ResetNames();
            for (var i = 0; i < dependencyCount; i++)
            {
                var packageName = dependencies[i].Nuget;
                if (packageName != null)
                    scratch.AddName(packageName);
            }

            if (!scratch.TryGetNameRank(targetPackage, out var targetNameRank))
            {
                return new List<Reference>();
            }

            for (var i = 0; i < dependencyCount; i++)
            {
                var packageName = dependencies[i].Nuget;
                scratch.NameRanks[i] = packageName == null
                    ? 0
                    : scratch.GetNameRank(packageName);
            }

            var filteredCount = bindings.TargetNuGetDependencyIndices(
                scratch.NameRanks,
                targetNameRank,
                scratch.ResultIndices);

            if (filteredCount < 0 || filteredCount > dependencyCount || filteredCount > scratch.ResultIndices.Length)
                throw new InvalidOperationException("N# update target dependency filter kernel returned an invalid result count.");

            var filteredDependencies = new List<Reference>(filteredCount);
            for (var i = 0; i < filteredCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= dependencyCount)
                    throw new InvalidOperationException("N# update target dependency filter kernel returned an invalid dependency index.");

                filteredDependencies.Add(dependencies[sourceIndex]);
            }

            return filteredDependencies;
        }
        finally
        {
            scratch.ResetNames();
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliUpdateAllNuGetDependencyIndicesInto>(
                programType,
                "CliUpdateAllNuGetDependencyIndicesInto"),
            DogfoodKernelLoader.CreateDelegate<CliUpdateTargetNuGetDependencyIndicesInto>(
                programType,
                "CliUpdateTargetNuGetDependencyIndicesInto")));

    private static Bindings RequiredBindings
        => s_bindings.Value
            ?? throw new InvalidOperationException("N# update dependency filter kernels are unavailable.");

    private delegate int CliUpdateAllNuGetDependencyIndicesInto(
        int[] nugetFlags,
        int[] resultIndices);

    private delegate int CliUpdateTargetNuGetDependencyIndicesInto(
        int[] nameRanks,
        int targetNameRank,
        int[] resultIndices);

    private sealed record Bindings(
        CliUpdateAllNuGetDependencyIndicesInto AllNuGetDependencyIndices,
        CliUpdateTargetNuGetDependencyIndicesInto TargetNuGetDependencyIndices);

    private sealed class Scratch
    {
        private readonly Dictionary<string, int> _nameRanks = new(StringComparer.OrdinalIgnoreCase);

        internal int[] NameRanks = Array.Empty<int>();
        internal int[] NuGetFlags = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();
        internal int UniqueNameCount;

        internal void EnsureCapacity(int dependencyCount)
        {
            if (NuGetFlags.Length != dependencyCount
                || NameRanks.Length != dependencyCount
                || ResultIndices.Length != dependencyCount)
            {
                NuGetFlags = new int[dependencyCount];
                NameRanks = new int[dependencyCount];
                ResultIndices = new int[dependencyCount];
            }
        }

        internal void AddName(string name)
        {
            if (_nameRanks.ContainsKey(name))
                return;

            UniqueNameCount++;
            _nameRanks.Add(name, UniqueNameCount);
        }

        internal int GetNameRank(string name) => _nameRanks[name];

        internal bool TryGetNameRank(string name, out int rank) => _nameRanks.TryGetValue(name, out rank);

        internal void ResetNames()
        {
            _nameRanks.Clear();
            UniqueNameCount = 0;
        }
    }
}
