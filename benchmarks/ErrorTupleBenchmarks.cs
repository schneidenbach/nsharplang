using System;
using BenchmarkDotNet.Attributes;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Pattern 6: the Go-style <c>(result, err) := call()</c> error tuple. On the success path the
/// initializer does not throw, so no exception is unwound. IL ratchet:
/// <c>Gate_ErrorTupleSuccessPath_SynthesizesNoThrow</c>.
/// </summary>
[MemoryDiagnoser]
public class ErrorTupleBenchmarks
{
    private const string Source = """
import System

func Divide(a: int, b: int): int {
    if b == 0 {
        throw new Exception("Cannot divide by zero")
    }
    return a / b
}

func RunSuccess(): int {
    result, err := Divide(10, 2)
    if err != null {
        return -1
    }
    return result
}
""";

    private Func<int> _nsharp = null!;

    [GlobalSetup]
    public void Setup() => _nsharp = NSharpCompiledMethod.Bind<Func<int>>(Source, "RunSuccess");

    [Benchmark(Baseline = true)]
    public int CSharp()
    {
        // Matched C#: a try/catch that captures the error as a value, never throwing on success.
        int result;
        Exception? err = null;
        try
        {
            result = Divide(10, 2);
        }
        catch (Exception ex)
        {
            result = 0;
            err = ex;
        }

        return err != null ? -1 : result;
    }

    private static int Divide(int a, int b)
    {
        if (b == 0)
        {
            throw new InvalidOperationException("Cannot divide by zero");
        }

        return a / b;
    }

    [Benchmark]
    public int NSharp() => _nsharp();
}
