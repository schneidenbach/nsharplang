using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using NSharpLang.Compiler;

namespace NSharpLang.Cli;

internal static class NSharpCliDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";

    [ThreadStatic]
    private static ReferenceTypeFilterScratch? t_referenceTypeFilterScratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings);

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

    private static Bindings? LoadBindings()
    {
        try
        {
            var assembly = TryLoadDogfoodAssembly();
            var programType = assembly?.GetType("Program");
            if (programType == null)
                return null;

            return new Bindings(
                CreateDelegate<CliFirstPositionalArgIndex>(programType, "CliFirstPositionalArgIndex"),
                CreateDelegate<CliReferenceTypeFilterIndicesInto>(programType, "CliReferenceTypeFilterIndicesInto"));
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

    private delegate int CliFirstPositionalArgIndex(
        string[] args,
        string[] optionsWithValues);

    private delegate int CliReferenceTypeFilterIndicesInto(
        int[] typeRanks,
        int targetTypeRank,
        int[] resultIndices);

    private sealed record Bindings(
        CliFirstPositionalArgIndex CliFirstPositionalArgIndex,
        CliReferenceTypeFilterIndicesInto CliReferenceTypeFilterIndices);

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

        internal void EnsureCapacity(int dependencyCount)
        {
            if (TypeRanks.Length != dependencyCount || ResultIndices.Length != dependencyCount)
            {
                TypeRanks = new int[dependencyCount];
                ResultIndices = new int[dependencyCount];
            }
        }
    }
}
