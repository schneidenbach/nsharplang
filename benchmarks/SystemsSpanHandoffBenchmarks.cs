using System;
using BenchmarkDotNet.Attributes;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Systems N# span-handoff benchmarks. These rows cover zero-copy calls over
/// <see cref="ReadOnlySpan{T}"/>/<see cref="Span{T}"/> and the N# array-to-span coercion path used
/// when caller-owned arrays are handed to span-based hot functions.
/// </summary>
[MemoryDiagnoser]
public class SystemsSpanHandoffBenchmarks
{
    public delegate int ReadOnlySpanIntDelegate(ReadOnlySpan<int> values);

    public delegate int SpanCopyDelegate(ReadOnlySpan<int> source, Span<int> destination);

    private const string Source = """
import System

[hot]
func sumSpan(values: ReadOnlySpan<int>): int {
    sum := 0
    for i := 0; i < values.Length; i++ {
        sum = sum + values[i]
    }

    return sum
}

[hot]
func countEven(values: ReadOnlySpan<int>): int {
    count := 0
    for i := 0; i < values.Length; i++ {
        if (values[i] & 1) == 0 {
            count = count + 1
        }
    }

    return count
}

[hot]
func copyUntilNegative(src: ReadOnlySpan<int>, dst: Span<int>): int {
    written := 0
    for i := 0; i < src.Length; i++ {
        value := src[i]
        if value < 0 {
            return written
        }

        dst[written] = value
        written = written + 1
    }

    return written
}

[hot]
func reverseCopy(src: ReadOnlySpan<int>, dst: Span<int>): int {
    len := src.Length
    if dst.Length < len {
        return -1
    }

    for i := 0; i < len; i++ {
        dst[i] = src[(len - 1) - i]
    }

    return len
}

[hot]
func arrayToSpanCaller(values: int[]): int {
    return sumSpan(values)
}

[hot]
func copyPositive(src: ReadOnlySpan<int>, dst: Span<int>): int {
    written := 0
    for i := 0; i < src.Length; i++ {
        value := src[i]
        if value >= 0 {
            dst[written] = value
            written = written + 1
        }
    }

    return written
}

[hot]
func checksumAndCopy(src: ReadOnlySpan<int>, dst: Span<int>): int {
    if dst.Length < src.Length {
        return -1
    }

    checksum := 0
    for i := 0; i < src.Length; i++ {
        value := src[i]
        checksum = checksum + value
        dst[i] = value
    }

    return checksum
}
""";

    private int[] _source = Array.Empty<int>();
    private int[] _destination = Array.Empty<int>();
    private ReadOnlySpanIntDelegate _csharpSumSpan = null!;
    private ReadOnlySpanIntDelegate _csharpCountEven = null!;
    private SpanCopyDelegate _csharpCopyUntilNegative = null!;
    private SpanCopyDelegate _csharpReverseCopy = null!;
    private SpanCopyDelegate _csharpCopyPositive = null!;
    private SpanCopyDelegate _csharpChecksumAndCopy = null!;
    private Func<int[], int> _csharpArrayToSpanCaller = null!;
    private ReadOnlySpanIntDelegate _sumSpan = null!;
    private ReadOnlySpanIntDelegate _countEven = null!;
    private SpanCopyDelegate _copyUntilNegative = null!;
    private SpanCopyDelegate _reverseCopy = null!;
    private SpanCopyDelegate _copyPositive = null!;
    private SpanCopyDelegate _checksumAndCopy = null!;
    private Func<int[], int> _arrayToSpanCaller = null!;

    public enum SpanHandoffWorkload
    {
        SumSpan,
        CountEven,
        CopyUntilNegative,
        ReverseCopy,
        ArrayToSpanCaller,
        CopyPositive,
        ChecksumAndCopy,
    }

    [Params(
        SpanHandoffWorkload.SumSpan,
        SpanHandoffWorkload.CountEven,
        SpanHandoffWorkload.CopyUntilNegative,
        SpanHandoffWorkload.ReverseCopy,
        SpanHandoffWorkload.ArrayToSpanCaller,
        SpanHandoffWorkload.CopyPositive,
        SpanHandoffWorkload.ChecksumAndCopy)]
    public SpanHandoffWorkload Workload { get; set; }

    [Params(64, 4096)]
    public int Size { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _source = new int[Size];
        _destination = new int[Size];
        for (var i = 0; i < _source.Length; i++)
        {
            _source[i] = ((i * 13) + 5) & 0xff;
        }

        if (_source.Length > 0)
        {
            _source[^1] = -1;
        }

        _csharpSumSpan = CSharpSumSpan;
        _csharpCountEven = CSharpCountEven;
        _csharpCopyUntilNegative = CSharpCopyUntilNegative;
        _csharpReverseCopy = CSharpReverseCopy;
        _csharpCopyPositive = CSharpCopyPositive;
        _csharpChecksumAndCopy = CSharpChecksumAndCopy;
        _csharpArrayToSpanCaller = CSharpArrayToSpanCaller;

        _sumSpan = NSharpCompiledMethod.Bind<ReadOnlySpanIntDelegate>(Source, "sumSpan");
        _countEven = NSharpCompiledMethod.Bind<ReadOnlySpanIntDelegate>(Source, "countEven");
        _copyUntilNegative = NSharpCompiledMethod.Bind<SpanCopyDelegate>(Source, "copyUntilNegative");
        _reverseCopy = NSharpCompiledMethod.Bind<SpanCopyDelegate>(Source, "reverseCopy");
        _copyPositive = NSharpCompiledMethod.Bind<SpanCopyDelegate>(Source, "copyPositive");
        _checksumAndCopy = NSharpCompiledMethod.Bind<SpanCopyDelegate>(Source, "checksumAndCopy");
        _arrayToSpanCaller = NSharpCompiledMethod.Bind<Func<int[], int>>(Source, "arrayToSpanCaller");
    }

    [Benchmark(Baseline = true)]
    public int CSharp() => Workload switch
    {
        SpanHandoffWorkload.SumSpan => _csharpSumSpan(_source),
        SpanHandoffWorkload.CountEven => _csharpCountEven(_source),
        SpanHandoffWorkload.CopyUntilNegative => _csharpCopyUntilNegative(_source, _destination),
        SpanHandoffWorkload.ReverseCopy => _csharpReverseCopy(_source, _destination),
        SpanHandoffWorkload.ArrayToSpanCaller => _csharpArrayToSpanCaller(_source),
        SpanHandoffWorkload.CopyPositive => _csharpCopyPositive(_source, _destination),
        SpanHandoffWorkload.ChecksumAndCopy => _csharpChecksumAndCopy(_source, _destination),
        _ => throw new InvalidOperationException()
    };

    [Benchmark]
    public int NSharp() => Workload switch
    {
        SpanHandoffWorkload.SumSpan => _sumSpan(_source),
        SpanHandoffWorkload.CountEven => _countEven(_source),
        SpanHandoffWorkload.CopyUntilNegative => _copyUntilNegative(_source, _destination),
        SpanHandoffWorkload.ReverseCopy => _reverseCopy(_source, _destination),
        SpanHandoffWorkload.ArrayToSpanCaller => _arrayToSpanCaller(_source),
        SpanHandoffWorkload.CopyPositive => _copyPositive(_source, _destination),
        SpanHandoffWorkload.ChecksumAndCopy => _checksumAndCopy(_source, _destination),
        _ => throw new InvalidOperationException()
    };

    private static int CSharpArrayToSpanCaller(int[] values) => CSharpSumSpan(values);

    private static int CSharpSumSpan(ReadOnlySpan<int> values)
    {
        var sum = 0;
        for (var i = 0; i < values.Length; i++)
        {
            sum += values[i];
        }

        return sum;
    }

    private static int CSharpCountEven(ReadOnlySpan<int> values)
    {
        var count = 0;
        for (var i = 0; i < values.Length; i++)
        {
            if ((values[i] & 1) == 0)
            {
                count++;
            }
        }

        return count;
    }

    private static int CSharpCopyUntilNegative(ReadOnlySpan<int> source, Span<int> destination)
    {
        var written = 0;
        for (var i = 0; i < source.Length; i++)
        {
            var value = source[i];
            if (value < 0)
            {
                return written;
            }

            destination[written] = value;
            written++;
        }

        return written;
    }

    private static int CSharpReverseCopy(ReadOnlySpan<int> source, Span<int> destination)
    {
        var len = source.Length;
        if (destination.Length < len)
        {
            return -1;
        }

        for (var i = 0; i < len; i++)
        {
            destination[i] = source[(len - 1) - i];
        }

        return len;
    }

    private static int CSharpCopyPositive(ReadOnlySpan<int> source, Span<int> destination)
    {
        var written = 0;
        for (var i = 0; i < source.Length; i++)
        {
            var value = source[i];
            if (value >= 0)
            {
                destination[written] = value;
                written++;
            }
        }

        return written;
    }

    private static int CSharpChecksumAndCopy(ReadOnlySpan<int> source, Span<int> destination)
    {
        if (destination.Length < source.Length)
        {
            return -1;
        }

        var checksum = 0;
        for (var i = 0; i < source.Length; i++)
        {
            var value = source[i];
            checksum += value;
            destination[i] = value;
        }

        return checksum;
    }
}
