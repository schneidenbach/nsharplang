using System;
using BenchmarkDotNet.Attributes;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Pattern 4: interface dispatch on a generic value-type receiver via a <c>constrained.</c> +
/// <c>callvirt</c>, with no boxing of the receiver. IL ratchet:
/// <c>Gate_ConstrainedGenericDispatch_UsesConstrainedCallvirt_AndDoesNotBox</c>.
/// </summary>
[MemoryDiagnoser]
public class ConstrainedDispatchBenchmarks
{
    private const string Source = """
interface IShape {
    func Area(): int
}

struct Square : IShape {
    side: int

    func Area(): int {
        return side * side
    }
}

func areaOf<T>(shape: T): int where T : IShape {
    return shape.Area()
}

func run(side: int): int {
    sq := new Square { side: side }
    return areaOf(sq)
}
""";

    // Matched C# baseline: the same constrained-generic dispatch shape over a value-type struct.
    private interface IShape
    {
        int Area();
    }

    private readonly struct Square : IShape
    {
        private readonly int _side;

        public Square(int side) => _side = side;

        public int Area() => _side * _side;
    }

    private static int AreaOf<T>(T shape) where T : IShape => shape.Area();

    private Func<int, int> _nsharp = null!;

    [GlobalSetup]
    public void Setup() => _nsharp = NSharpCompiledMethod.Bind<Func<int, int>>(Source, "run");

    [Benchmark(Baseline = true)]
    public int CSharp() => AreaOf(new Square(6));

    [Benchmark]
    public int NSharp() => _nsharp(6);
}
