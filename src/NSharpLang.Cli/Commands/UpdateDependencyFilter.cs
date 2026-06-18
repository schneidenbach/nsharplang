using System;
using System.Collections.Generic;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

internal static class UpdateDependencyFilter
{
    [ThreadStatic]
    private static Scratch? t_scratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryFilterAllNuGetDependencies(
        IReadOnlyList<Reference> dependencies,
        out List<Reference> filteredDependencies)
    {
        filteredDependencies = new List<Reference>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var dependencyCount = dependencies.Count;
        if (dependencyCount == 0)
            return true;

        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(dependencyCount);

        try
        {
            for (var i = 0; i < dependencyCount; i++)
                scratch.NuGetFlags[i] = dependencies[i].Nuget == null ? 0 : 1;

            var filteredCount = bindings.AllNuGetDependencyIndices(
                scratch.NuGetFlags,
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
                if (dependency.Nuget == null)
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

    internal static bool TryFilterTargetNuGetDependencies(
        IReadOnlyList<Reference> dependencies,
        string targetPackage,
        out List<Reference> filteredDependencies)
    {
        filteredDependencies = new List<Reference>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var dependencyCount = dependencies.Count;
        if (dependencyCount == 0)
            return true;

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
                filteredDependencies = new List<Reference>();
                return true;
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

                filteredDependencies.Add(dependencies[sourceIndex]);
            }

            return true;
        }
        catch
        {
            filteredDependencies = new List<Reference>();
            return false;
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
