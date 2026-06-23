using System;
using System.IO;

namespace NSharpLang.Compiler.ILCompiler;

internal static class OverloadCandidateSelector
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static Scratch? t_scratch;

    /// <summary>
    /// Selects the winning declared-method overload index from a compact candidate table using the
    /// N# ranking kernel. The caller fills one entry per surviving candidate into the supplied
    /// buffers. The ranking is score &gt; non-generic &gt; non-params &gt; fewer-defaults, first-wins.
    /// </summary>
    internal static bool TrySelectBest(
        int candidateCapacity,
        ColumnFiller fillColumns,
        out int selectedIndex)
    {
        selectedIndex = -1;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (candidateCapacity < 0)
            return false;

        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(candidateCapacity);

        var count = fillColumns(
            scratch.ValidFlags,
            scratch.Scores,
            scratch.GenericFlags,
            scratch.ParamsFlags,
            scratch.DefaultsUsed);

        if (count < 0 || count > candidateCapacity)
            return false;

        var index = bindings.OverloadSelectBestCandidate(
            scratch.ValidFlags,
            scratch.Scores,
            scratch.GenericFlags,
            scratch.ParamsFlags,
            scratch.DefaultsUsed,
            count);

        if (index < -1 || index >= count)
            return false;

        selectedIndex = index;
        return true;
    }

    internal delegate int ColumnFiller(
        int[] validFlags,
        int[] scores,
        int[] genericFlags,
        int[] paramsFlags,
        int[] defaultsUsed);

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<OverloadSelectBestCandidate>(
                programType,
                "OverloadSelectBestCandidate")));

    private delegate int OverloadSelectBestCandidate(
        int[] validFlags,
        int[] scores,
        int[] genericFlags,
        int[] paramsFlags,
        int[] defaultsUsed,
        int count);

    private sealed record Bindings(OverloadSelectBestCandidate OverloadSelectBestCandidate);

    private sealed class Scratch
    {
        internal int[] ValidFlags = Array.Empty<int>();
        internal int[] Scores = Array.Empty<int>();
        internal int[] GenericFlags = Array.Empty<int>();
        internal int[] ParamsFlags = Array.Empty<int>();
        internal int[] DefaultsUsed = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (ValidFlags.Length < count)
            {
                ValidFlags = new int[count];
                Scores = new int[count];
                GenericFlags = new int[count];
                ParamsFlags = new int[count];
                DefaultsUsed = new int[count];
            }
        }
    }
}
