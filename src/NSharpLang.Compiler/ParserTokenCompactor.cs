using System;
using System.Collections.Generic;
using System.IO;

namespace NSharpLang.Compiler;

internal static class ParserTokenCompactor
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static Scratch? t_scratch;

    internal static bool TryCompact(IReadOnlyList<Token> tokens, out List<Token> compactedTokens)
    {
        compactedTokens = [];

        var bindings = s_bindings.Value;

        var tokenCount = tokens.Count;
        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(tokenCount);

            for (var i = 0; i < tokenCount; i++)
            {
                scratch.TokenKinds[i] = (int)tokens[i].Type;
            }

            var compactedCount = bindings.ParserTokenCompactionCounted(
                scratch.TokenKinds,
                tokenCount,
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

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<ParserTokenCompactionIndicesCountedInto>(
                programType,
                "ParserTokenCompactionIndicesCountedInto")));

    private delegate int ParserTokenCompactionIndicesCountedInto(int[] tokenKinds, int tokenCount, int[] resultIndices);

    private sealed record Bindings(ParserTokenCompactionIndicesCountedInto ParserTokenCompactionCounted);

    private sealed class Scratch
    {
        internal int[] ResultIndices = Array.Empty<int>();
        internal int[] TokenKinds = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (TokenKinds.Length != count)
            {
                TokenKinds = new int[count];
                ResultIndices = new int[count];
            }
        }
    }
}
