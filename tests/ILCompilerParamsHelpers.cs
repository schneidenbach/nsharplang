using System;
using System.Collections.Generic;
using System.Linq;

namespace NSharpLang.Tests;

public static class ILCompilerParamsHelpers
{
    public static int SumReadOnlySpan(ReadOnlySpan<int> values)
    {
        return values[0] + values[1] + values[2];
    }

    public static int MutateAndSumSpan(Span<int> values)
    {
        values[0] += 1;
        values[1] += 1;
        values[2] += 1;
        return values[0] + values[1] + values[2];
    }

    public static int SumEnumerable(IEnumerable<int> values)
    {
        return values.Sum();
    }

    public static int DescribeList(List<string> values)
    {
        return values.Count * 10 + values[0].Length + values[1].Length;
    }

    public static int SumReadOnlyList(IReadOnlyList<int> values)
    {
        return values.Count * 100 + values[0] + values[1] + values[2];
    }
}
