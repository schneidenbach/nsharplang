using System;
using BenchmarkDotNet.Attributes;
using NSharpLang.Runtime;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Combined systems benchmarks: hot N# loops over caller-owned storage with explicit
/// <see cref="Result{TOk, TErr}"/> handoff at the boundary.
/// </summary>
[MemoryDiagnoser]
public class SystemsCombinationBenchmarks
{
    private const string Source = """
[hot]
func scanDigits(values: int[], len: int): int {
    count := 0
    for i := 0; i < len; i++ {
        value := values[i]
        if value < 48 {
            return -1
        }
        if value > 57 {
            return -1
        }

        count = count + 1
    }

    return count
}

[hot]
func writeChecksum(src: int[], dst: int[], len: int): int {
    if dst.Length < len + 1 {
        return -1
    }

    checksum := 0
    for i := 0; i < len; i++ {
        value := src[i]
        checksum = checksum + value
        dst[i + 1] = value
    }

    dst[0] = checksum
    return len + 1
}
""";

    private int[] _digits = Array.Empty<int>();
    private int[] _payload = Array.Empty<int>();
    private int[] _destination = Array.Empty<int>();
    private Func<int[], int, int> _scanDigits = null!;
    private Func<int[], int[], int, int> _writeChecksum = null!;

    public enum CombinationWorkload
    {
        ScanDigitsResult,
        WriteChecksumResult,
    }

    [Params(CombinationWorkload.ScanDigitsResult, CombinationWorkload.WriteChecksumResult)]
    public CombinationWorkload Workload { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _digits = new int[4096];
        _payload = new int[4096];
        _destination = new int[_payload.Length + 1];
        for (var i = 0; i < _digits.Length; i++)
        {
            _digits[i] = 48 + (i % 10);
        }

        for (var i = 0; i < _payload.Length; i++)
        {
            _payload[i] = i & 0xff;
        }

        _scanDigits = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "scanDigits");
        _writeChecksum = NSharpCompiledMethod.Bind<Func<int[], int[], int, int>>(Source, "writeChecksum");
    }

    [Benchmark(Baseline = true)]
    public int CSharp() => Workload switch
    {
        CombinationWorkload.ScanDigitsResult => Consume(CSharpScanDigitsResult(_digits, _digits.Length)),
        CombinationWorkload.WriteChecksumResult => Consume(CSharpWriteChecksumResult(_payload, _destination, _payload.Length)),
        _ => throw new InvalidOperationException()
    };

    [Benchmark]
    public int NSharp() => Workload switch
    {
        CombinationWorkload.ScanDigitsResult => Consume(NSharpScanDigitsResult(_digits, _digits.Length)),
        CombinationWorkload.WriteChecksumResult => Consume(NSharpWriteChecksumResult(_payload, _destination, _payload.Length)),
        _ => throw new InvalidOperationException()
    };

    private Result<int, int> NSharpScanDigitsResult(int[] values, int len)
    {
        var scanned = _scanDigits(values, len);
        return scanned >= 0 ? Result<int, int>.Ok(scanned) : Result<int, int>.Err(-1);
    }

    private Result<int, int> NSharpWriteChecksumResult(int[] source, int[] destination, int len)
    {
        var written = _writeChecksum(source, destination, len);
        return written >= 0 ? Result<int, int>.Ok(written) : Result<int, int>.Err(-1);
    }

    private static Result<int, int> CSharpScanDigitsResult(int[] values, int len)
    {
        var scanned = CSharpScanDigits(values, len);
        return scanned >= 0 ? Result<int, int>.Ok(scanned) : Result<int, int>.Err(-1);
    }

    private static Result<int, int> CSharpWriteChecksumResult(int[] source, int[] destination, int len)
    {
        var written = CSharpWriteChecksum(source, destination, len);
        return written >= 0 ? Result<int, int>.Ok(written) : Result<int, int>.Err(-1);
    }

    private static int Consume(Result<int, int> result)
        => result.TryGetOk(out var value) ? value : 0;

    private static int CSharpScanDigits(int[] values, int len)
    {
        var count = 0;
        for (var i = 0; i < len; i++)
        {
            var value = values[i];
            if (value < 48 || value > 57)
            {
                return -1;
            }

            count++;
        }

        return count;
    }

    private static int CSharpWriteChecksum(int[] source, int[] destination, int len)
    {
        if (destination.Length < len + 1)
        {
            return -1;
        }

        var checksum = 0;
        for (var i = 0; i < len; i++)
        {
            var value = source[i];
            checksum += value;
            destination[i + 1] = value;
        }

        destination[0] = checksum;
        return len + 1;
    }
}
