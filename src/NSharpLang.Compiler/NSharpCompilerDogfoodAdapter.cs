using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace NSharpLang.Compiler;

internal static class NSharpCompilerDogfoodAdapter
{
    private const string DogfoodAssemblyName = "NSharpLang.Compiler.Dogfood";
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static ParserTokenCompactionScratch? t_parserTokenCompactionScratch;
    [ThreadStatic]
    private static FirstDistinctTypeKeyScratch? t_firstDistinctTypeKeyScratch;

    internal static bool IsAvailable => s_bindings.Value != null;

    internal static bool TryCompactParserTokens(IReadOnlyList<Token> tokens, out List<Token> compactedTokens)
    {
        compactedTokens = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var tokenCount = tokens.Count;
        if (tokenCount == 0)
            return true;

        var scratch = t_parserTokenCompactionScratch ??= new ParserTokenCompactionScratch();
        scratch.EnsureCapacity(tokenCount);

        try
        {
            for (var i = 0; i < tokenCount; i++)
            {
                scratch.TokenKinds[i] = (int)tokens[i].Type;
            }

            var compactedCount = bindings.ParserTokenCompaction(
                scratch.TokenKinds,
                scratch.ResultIndices);

            if (compactedCount < 0 || compactedCount > tokenCount)
            {
                compactedTokens = [];
                return false;
            }

            var result = new List<Token>(compactedCount);
            for (var i = 0; i < compactedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= tokenCount)
                {
                    compactedTokens = [];
                    return false;
                }

                result.Add(tokens[sourceIndex]);
            }

            compactedTokens = result;
            return true;
        }
        catch
        {
            compactedTokens = [];
            return false;
        }
    }

    internal static bool TryDeduplicateFirstTypeKeys(
        IReadOnlyList<Type> types,
        Func<Type, string> getTypeKey,
        out List<Type> deduplicatedTypes)
    {
        deduplicatedTypes = [];

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var typeCount = types.Count;
        if (typeCount == 0)
            return true;

        var scratch = t_firstDistinctTypeKeyScratch ??= new FirstDistinctTypeKeyScratch();
        scratch.EnsureCapacity(typeCount);

        try
        {
            scratch.ResetKeys();
            for (var i = 0; i < typeCount; i++)
            {
                scratch.TypeRanks[i] = scratch.AddKey(getTypeKey(types[i]));
            }

            var deduplicatedCount = bindings.FirstDistinctRankIndices(
                scratch.TypeRanks,
                scratch.UniqueKeyCount,
                scratch.SeenRanks,
                scratch.ResultIndices);

            if (deduplicatedCount < 0 || deduplicatedCount > typeCount || deduplicatedCount > scratch.ResultIndices.Length)
            {
                deduplicatedTypes = [];
                return false;
            }

            var result = new List<Type>(deduplicatedCount);
            for (var i = 0; i < deduplicatedCount; i++)
            {
                var sourceIndex = scratch.ResultIndices[i];
                if (sourceIndex < 0 || sourceIndex >= typeCount)
                {
                    deduplicatedTypes = [];
                    return false;
                }

                result.Add(types[sourceIndex]);
            }

            deduplicatedTypes = result;
            return true;
        }
        catch
        {
            deduplicatedTypes = [];
            return false;
        }
        finally
        {
            scratch.ResetKeys();
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
                CreateDelegate<ParserTokenCompactionIndicesInto>(
                    programType,
                    "ParserTokenCompactionIndicesInto"),
                CreateDelegate<FirstDistinctRankIndicesInto>(
                    programType,
                    "FirstDistinctRankIndicesInto"));
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

    private delegate int ParserTokenCompactionIndicesInto(int[] tokenKinds, int[] resultIndices);
    private delegate int FirstDistinctRankIndicesInto(
        int[] ranks,
        int uniqueRankCount,
        int[] seenRanks,
        int[] resultIndices);

    private sealed record Bindings(
        ParserTokenCompactionIndicesInto ParserTokenCompaction,
        FirstDistinctRankIndicesInto FirstDistinctRankIndices);

    private sealed class ParserTokenCompactionScratch
    {
        public int[] ResultIndices = Array.Empty<int>();
        public int[] TokenKinds = Array.Empty<int>();

        public void EnsureCapacity(int count)
        {
            if (TokenKinds.Length != count)
            {
                TokenKinds = new int[count];
                ResultIndices = new int[count];
            }
        }
    }

    private sealed class FirstDistinctTypeKeyScratch
    {
        private readonly Dictionary<string, int> _keyRanks = new(StringComparer.Ordinal);

        public int[] ResultIndices = Array.Empty<int>();
        public int[] SeenRanks = Array.Empty<int>();
        public int[] TypeRanks = Array.Empty<int>();
        public int UniqueKeyCount;

        public void EnsureCapacity(int count)
        {
            if (TypeRanks.Length != count)
            {
                TypeRanks = new int[count];
                ResultIndices = new int[count];
            }

            var rankCapacity = count + 1;
            if (SeenRanks.Length != rankCapacity)
            {
                SeenRanks = new int[rankCapacity];
            }
        }

        public int AddKey(string key)
        {
            if (_keyRanks.TryGetValue(key, out var rank))
                return rank;

            rank = ++UniqueKeyCount;
            _keyRanks.Add(key, rank);
            return rank;
        }

        public void ResetKeys()
        {
            _keyRanks.Clear();
            UniqueKeyCount = 0;
        }
    }
}
