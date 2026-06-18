using System;

namespace NSharpLang.Cli;

internal static class BuildCommandKernels
{
    [ThreadStatic]
    private static OperandScratch? t_operandScratch;

    [ThreadStatic]
    private static int[]? t_optionResultIndices;

    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetOperandSummary(string[] args, out int count, out int firstOperandIndex)
    {
        count = 0;
        firstOperandIndex = -1;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        if (args.Length == 0)
            return true;

        var scratch = t_operandScratch ??= new OperandScratch();
        scratch.EnsureCapacity(args.Length);

        try
        {
            firstOperandIndex = bindings.BuildFirstOperandIndex(
                args,
                scratch.KindIds,
                scratch.NextIndices,
                scratch.PreviousIndices,
                scratch.NextOptionIndices,
                scratch.ResultIndices);
            if (firstOperandIndex < -1 || firstOperandIndex >= args.Length)
            {
                count = 0;
                firstOperandIndex = -1;
                return false;
            }

            count = firstOperandIndex >= 0 ? 1 : 0;
            return true;
        }
        catch
        {
            count = 0;
            firstOperandIndex = -1;
            return false;
        }
    }

    internal static bool TryGetOptionSummary(string[] args, out BuildOptionSummary summary)
    {
        summary = default;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        var resultIndices = t_optionResultIndices ??= new int[9];
        try
        {
            var code = bindings.BuildOptionSummary(args, resultIndices);
            if (code != 0)
                return false;

            if (!TryGetOptionalArg(args, resultIndices[0], out var output)
                || !TryGetOptionalArg(args, resultIndices[1], out var backend)
                || !TryGetOptionalArg(args, resultIndices[2], out var project))
            {
                summary = default;
                return false;
            }

            summary = new BuildOptionSummary(
                output,
                backend,
                project,
                resultIndices[3] != 0,
                resultIndices[4] != 0,
                resultIndices[5] != 0,
                resultIndices[6] != 0,
                resultIndices[7] != 0);
            return true;
        }
        catch
        {
            summary = default;
            return false;
        }
    }

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliBuildFirstOperandIndexInto>(
                programType,
                "CliBuildFirstOperandIndexInto"),
            DogfoodKernelLoader.CreateDelegate<CliBuildOptionSummaryInto>(
                programType,
                "CliBuildOptionSummaryInto")));

    private delegate int CliBuildFirstOperandIndexInto(
        string[] args,
        int[] kindIds,
        int[] nextIndices,
        int[] previousIndices,
        int[] nextOptionIndices,
        int[] resultIndices);

    private delegate int CliBuildOptionSummaryInto(string[] args, int[] resultIndices);

    private sealed record Bindings(
        CliBuildFirstOperandIndexInto BuildFirstOperandIndex,
        CliBuildOptionSummaryInto BuildOptionSummary);

    private static bool TryGetOptionalArg(string[] args, int index, out string? value)
    {
        value = null;
        if (index == -1)
            return true;

        if (index < 0 || index >= args.Length)
            return false;

        value = args[index];
        return true;
    }

    private sealed class OperandScratch
    {
        internal int[] KindIds = Array.Empty<int>();
        internal int[] NextIndices = Array.Empty<int>();
        internal int[] NextOptionIndices = Array.Empty<int>();
        internal int[] PreviousIndices = Array.Empty<int>();
        internal int[] ResultIndices = Array.Empty<int>();

        internal void EnsureCapacity(int count)
        {
            if (KindIds.Length != count)
                KindIds = new int[count];

            if (NextIndices.Length != count)
                NextIndices = new int[count];

            if (NextOptionIndices.Length != count)
                NextOptionIndices = new int[count];

            if (PreviousIndices.Length != count)
                PreviousIndices = new int[count];

            if (ResultIndices.Length != count)
                ResultIndices = new int[count];
        }
    }
}
