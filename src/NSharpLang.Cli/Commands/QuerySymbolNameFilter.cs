using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Commands;

internal static class QuerySymbolNameFilter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";

    [ThreadStatic]
    private static Scratch? t_scratch;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryFilter(
        IReadOnlyList<SymbolResult> symbols,
        string pattern,
        int limit,
        out List<SymbolResult> filteredSymbols)
    {
        filteredSymbols = new List<SymbolResult>();

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (limit <= 0 || symbols.Count == 0)
            return true;

        if (!IsAscii(pattern))
            return false;

        var useGlob = pattern.Contains('*');
        var symbolCount = symbols.Count;
        var resultCapacity = Math.Min(symbolCount, limit);
        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(symbolCount, resultCapacity);

        try
        {
            for (var i = 0; i < symbolCount; i++)
            {
                var name = symbols[i].Name;
                if (!IsAscii(name))
                {
                    filteredSymbols = new List<SymbolResult>();
                    return false;
                }

                scratch.Names[i] = name;
            }

            var filteredCount = useGlob
                ? bindings.CliSymbolNameGlobFilterIndices(
                    scratch.Names,
                    pattern,
                    resultCapacity,
                    scratch.ResultIndices)
                : bindings.CliSymbolNameSubstringFilterIndices(
                    scratch.Names,
                    pattern,
                    resultCapacity,
                    scratch.ResultIndices);

            if (filteredCount < 0 || filteredCount > resultCapacity || filteredCount > scratch.ResultIndices.Length)
            {
                filteredSymbols = new List<SymbolResult>();
                return false;
            }

            filteredSymbols = new List<SymbolResult>(filteredCount);
            for (var i = 0; i < filteredCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= symbolCount)
                {
                    filteredSymbols = new List<SymbolResult>();
                    return false;
                }

                filteredSymbols.Add(symbols[sourceIndex]);
            }

            return true;
        }
        catch
        {
            filteredSymbols = new List<SymbolResult>();
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
                CreateDelegate<CliSymbolNameGlobFilterIndicesInto>(programType, "CliSymbolNameGlobFilterIndicesInto"),
                CreateDelegate<CliSymbolNameSubstringFilterIndicesInto>(programType, "CliSymbolNameSubstringFilterIndicesInto"));
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

    private static bool IsAscii(string value)
    {
        for (var i = 0; i < value.Length; i++)
        {
            if (value[i] > 0x7f)
                return false;
        }

        return true;
    }

    private delegate int CliSymbolNameGlobFilterIndicesInto(
        string[] names,
        string pattern,
        int limit,
        int[] resultIndices);

    private delegate int CliSymbolNameSubstringFilterIndicesInto(
        string[] names,
        string pattern,
        int limit,
        int[] resultIndices);

    private sealed record Bindings(
        CliSymbolNameGlobFilterIndicesInto CliSymbolNameGlobFilterIndices,
        CliSymbolNameSubstringFilterIndicesInto CliSymbolNameSubstringFilterIndices);

    private sealed class Scratch
    {
        internal string[] Names = Array.Empty<string>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int symbolCount, int resultCapacity)
        {
            if (Names.Length != symbolCount)
                Names = new string[symbolCount];

            if (ResultIndices.Length != resultCapacity)
                ResultIndices = new int[resultCapacity];
        }
    }
}
