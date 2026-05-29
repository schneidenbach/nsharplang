using System;
using Xunit;
using Xunit.Abstractions;
using NSharpLang.Tests.PerfEvidence;

namespace NSharpLang.Tests;

public class TempParamsSpanDump
{
    private readonly ITestOutputHelper _output;
    public TempParamsSpanDump(ITestOutputHelper output) => _output = output;

    [Fact]
    public void Dump()
    {
        var src = @"
import System

func SumReadOnlySpan(params numbers: ReadOnlySpan<int>): int {
    total := 0
    for i := 0; i < numbers.Length; i++ {
        total += numbers[i]
    }

    return total
}

func ModifyValues(params values: Span<int>): int {
    for i := 0; i < values.Length; i++ {
        values[i] = values[i] * 2
    }

    return values[0] + values[1] + values[2]
}

func main(): int {
    return SumReadOnlySpan(1, 2, 3) + ModifyValues(4, 5, 6)
}";
        var il = ILShapeInspector.DecodeProgramMethod(src, "main");
        foreach (var ins in il) _output.WriteLine(ins.ToString());
    }
}
