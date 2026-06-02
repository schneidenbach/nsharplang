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
    private const int InnerOperations = 8;

    private const string Source = """
[hot]
func scanDigits(values: int[], len: int): int {
    count := 0
    for i := 0; i < len; i++ {
        value := values[i]
        if value < 48 || value > 57 {
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

[hot]
func copyDigits(src: int[], dst: int[], len: int): int {
    if dst.Length < len {
        return -1
    }

    for i := 0; i < len; i++ {
        value := src[i]
        if value < 48 || value > 57 {
            return -1
        }

        dst[i] = value - 48
    }

    return len
}

[hot]
func scanAndChecksumDigits(values: int[], len: int): int {
    checksum := 0
    for i := 0; i < len; i++ {
        value := values[i]
        if value < 48 || value > 57 {
            return -1
        }

        checksum = checksum + (value - 48)
    }

    return checksum
}

[hot]
func copyPositiveChecksum(src: int[], dst: int[], len: int): int {
    if dst.Length < len {
        return -1
    }

    written := 0
    checksum := 0
    for i := 0; i < len; i++ {
        value := src[i]
        if value >= 0 {
            dst[written] = value
            written = written + 1
            checksum = checksum + value
        }
    }

    return checksum + written
}
""";

    private int[] _digits = Array.Empty<int>();
    private int[] _payload = Array.Empty<int>();
    private int[] _destination = Array.Empty<int>();
    private int[] _scratch = Array.Empty<int>();
    private Func<int[], int, int> _csharpScanDigits = null!;
    private Func<int[], int[], int, int> _csharpWriteChecksum = null!;
    private Func<int[], int[], int, int> _csharpCopyDigits = null!;
    private Func<int[], int, int> _csharpScanAndChecksumDigits = null!;
    private Func<int[], int[], int, int> _csharpCopyPositiveChecksum = null!;
    private Func<int[], int, int> _scanDigits = null!;
    private Func<int[], int[], int, int> _writeChecksum = null!;
    private Func<int[], int[], int, int> _copyDigits = null!;
    private Func<int[], int, int> _scanAndChecksumDigits = null!;
    private Func<int[], int[], int, int> _copyPositiveChecksum = null!;

    public enum CombinationWorkload
    {
        ScanDigitsResult,
        WriteChecksumResult,
        CopyDigitsResult,
        ScanAndChecksumResult,
        CopyPositiveChecksumResult,
        ScanThenChecksumResult,
        ScanThenCopyDigitsResult,
        ChecksumThenFrameResult,
        CopyDigitsThenFrameResult,
        CopyPositiveThenFrameResult,
    }

    [Params(
        CombinationWorkload.ScanDigitsResult,
        CombinationWorkload.WriteChecksumResult,
        CombinationWorkload.CopyDigitsResult,
        CombinationWorkload.ScanAndChecksumResult,
        CombinationWorkload.CopyPositiveChecksumResult,
        CombinationWorkload.ScanThenChecksumResult,
        CombinationWorkload.ScanThenCopyDigitsResult,
        CombinationWorkload.ChecksumThenFrameResult,
        CombinationWorkload.CopyDigitsThenFrameResult,
        CombinationWorkload.CopyPositiveThenFrameResult)]
    public CombinationWorkload Workload { get; set; }

    [Params(64, 4096)]
    public int Size { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _digits = new int[Size];
        _payload = new int[Size];
        _destination = new int[_payload.Length + 1];
        _scratch = new int[_payload.Length + 1];
        for (var i = 0; i < _digits.Length; i++)
        {
            _digits[i] = 48 + (i % 10);
        }

        for (var i = 0; i < _payload.Length; i++)
        {
            var value = i & 0xff;
            _payload[i] = (i & 1) == 0 ? value : -value;
        }

        _csharpScanDigits = CSharpScanDigits;
        _csharpWriteChecksum = CSharpWriteChecksum;
        _csharpCopyDigits = CSharpCopyDigits;
        _csharpScanAndChecksumDigits = CSharpScanAndChecksumDigits;
        _csharpCopyPositiveChecksum = CSharpCopyPositiveChecksum;

        _scanDigits = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "scanDigits");
        _writeChecksum = NSharpCompiledMethod.Bind<Func<int[], int[], int, int>>(Source, "writeChecksum");
        _copyDigits = NSharpCompiledMethod.Bind<Func<int[], int[], int, int>>(Source, "copyDigits");
        _scanAndChecksumDigits = NSharpCompiledMethod.Bind<Func<int[], int, int>>(Source, "scanAndChecksumDigits");
        _copyPositiveChecksum = NSharpCompiledMethod.Bind<Func<int[], int[], int, int>>(Source, "copyPositiveChecksum");
    }

    public int CSharpAll()
    {
        var total = 0;
        for (var operation = 0; operation < InnerOperations; operation++)
        {
            total += Consume(CSharpScanDigitsResult(_digits, _digits.Length));
            total += Consume(CSharpWriteChecksumResult(_payload, _destination, _payload.Length));
            total += Consume(CSharpCopyDigitsResult(_digits, _destination, _digits.Length));
            total += Consume(CSharpScanAndChecksumResult(_digits, _digits.Length));
            total += Consume(CSharpCopyPositiveChecksumResult(_payload, _destination, _payload.Length));
            total += Consume(CSharpScanThenChecksumResult(_digits, _digits.Length));
            total += Consume(CSharpScanThenCopyDigitsResult(_digits, _destination, _digits.Length));
            total += Consume(CSharpChecksumThenFrameResult(_digits, _destination, _digits.Length));
            total += Consume(CSharpCopyDigitsThenFrameResult(_digits, _destination, _scratch, _digits.Length));
            total += Consume(CSharpCopyPositiveThenFrameResult(_payload, _destination, _scratch, _payload.Length));
        }

        return total;
    }

    public int NSharpAll()
    {
        var total = 0;
        for (var operation = 0; operation < InnerOperations; operation++)
        {
            total += Consume(NSharpScanDigitsResult(_digits, _digits.Length));
            total += Consume(NSharpWriteChecksumResult(_payload, _destination, _payload.Length));
            total += Consume(NSharpCopyDigitsResult(_digits, _destination, _digits.Length));
            total += Consume(NSharpScanAndChecksumResult(_digits, _digits.Length));
            total += Consume(NSharpCopyPositiveChecksumResult(_payload, _destination, _payload.Length));
            total += Consume(NSharpScanThenChecksumResult(_digits, _digits.Length));
            total += Consume(NSharpScanThenCopyDigitsResult(_digits, _destination, _digits.Length));
            total += Consume(NSharpChecksumThenFrameResult(_digits, _destination, _digits.Length));
            total += Consume(NSharpCopyDigitsThenFrameResult(_digits, _destination, _scratch, _digits.Length));
            total += Consume(NSharpCopyPositiveThenFrameResult(_payload, _destination, _scratch, _payload.Length));
        }

        return total;
    }

    [Benchmark(Baseline = true, OperationsPerInvoke = InnerOperations)]
    public int CSharp()
    {
        var total = 0;
        for (var operation = 0; operation < InnerOperations; operation++)
        {
            total += Workload switch
            {
                CombinationWorkload.ScanDigitsResult => Consume(CSharpScanDigitsResult(_digits, _digits.Length)),
                CombinationWorkload.WriteChecksumResult => Consume(CSharpWriteChecksumResult(_payload, _destination, _payload.Length)),
                CombinationWorkload.CopyDigitsResult => Consume(CSharpCopyDigitsResult(_digits, _destination, _digits.Length)),
                CombinationWorkload.ScanAndChecksumResult => Consume(CSharpScanAndChecksumResult(_digits, _digits.Length)),
                CombinationWorkload.CopyPositiveChecksumResult => Consume(CSharpCopyPositiveChecksumResult(_payload, _destination, _payload.Length)),
                CombinationWorkload.ScanThenChecksumResult => Consume(CSharpScanThenChecksumResult(_digits, _digits.Length)),
                CombinationWorkload.ScanThenCopyDigitsResult => Consume(CSharpScanThenCopyDigitsResult(_digits, _destination, _digits.Length)),
                CombinationWorkload.ChecksumThenFrameResult => Consume(CSharpChecksumThenFrameResult(_digits, _destination, _digits.Length)),
                CombinationWorkload.CopyDigitsThenFrameResult => Consume(CSharpCopyDigitsThenFrameResult(_digits, _destination, _scratch, _digits.Length)),
                CombinationWorkload.CopyPositiveThenFrameResult => Consume(CSharpCopyPositiveThenFrameResult(_payload, _destination, _scratch, _payload.Length)),
                _ => throw new InvalidOperationException()
            };
        }

        return total;
    }

    [Benchmark(OperationsPerInvoke = InnerOperations)]
    public int NSharp()
    {
        var total = 0;
        for (var operation = 0; operation < InnerOperations; operation++)
        {
            total += Workload switch
            {
                CombinationWorkload.ScanDigitsResult => Consume(NSharpScanDigitsResult(_digits, _digits.Length)),
                CombinationWorkload.WriteChecksumResult => Consume(NSharpWriteChecksumResult(_payload, _destination, _payload.Length)),
                CombinationWorkload.CopyDigitsResult => Consume(NSharpCopyDigitsResult(_digits, _destination, _digits.Length)),
                CombinationWorkload.ScanAndChecksumResult => Consume(NSharpScanAndChecksumResult(_digits, _digits.Length)),
                CombinationWorkload.CopyPositiveChecksumResult => Consume(NSharpCopyPositiveChecksumResult(_payload, _destination, _payload.Length)),
                CombinationWorkload.ScanThenChecksumResult => Consume(NSharpScanThenChecksumResult(_digits, _digits.Length)),
                CombinationWorkload.ScanThenCopyDigitsResult => Consume(NSharpScanThenCopyDigitsResult(_digits, _destination, _digits.Length)),
                CombinationWorkload.ChecksumThenFrameResult => Consume(NSharpChecksumThenFrameResult(_digits, _destination, _digits.Length)),
                CombinationWorkload.CopyDigitsThenFrameResult => Consume(NSharpCopyDigitsThenFrameResult(_digits, _destination, _scratch, _digits.Length)),
                CombinationWorkload.CopyPositiveThenFrameResult => Consume(NSharpCopyPositiveThenFrameResult(_payload, _destination, _scratch, _payload.Length)),
                _ => throw new InvalidOperationException()
            };
        }

        return total;
    }

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

    private Result<int, int> NSharpCopyDigitsResult(int[] source, int[] destination, int len)
    {
        var written = _copyDigits(source, destination, len);
        return written >= 0 ? Result<int, int>.Ok(written) : Result<int, int>.Err(-1);
    }

    private Result<int, int> NSharpScanAndChecksumResult(int[] values, int len)
    {
        var checksum = _scanAndChecksumDigits(values, len);
        return checksum >= 0 ? Result<int, int>.Ok(checksum) : Result<int, int>.Err(-1);
    }

    private Result<int, int> NSharpCopyPositiveChecksumResult(int[] source, int[] destination, int len)
    {
        var checksum = _copyPositiveChecksum(source, destination, len);
        return checksum >= 0 ? Result<int, int>.Ok(checksum) : Result<int, int>.Err(-1);
    }

    private Result<int, int> NSharpScanThenChecksumResult(int[] values, int len)
    {
        var scanned = _scanDigits(values, len);
        if (scanned < 0)
        {
            return Result<int, int>.Err(-1);
        }

        var checksum = _scanAndChecksumDigits(values, len);
        return checksum >= 0 ? Result<int, int>.Ok(scanned + checksum) : Result<int, int>.Err(-2);
    }

    private Result<int, int> NSharpScanThenCopyDigitsResult(int[] source, int[] destination, int len)
    {
        var scanned = _scanDigits(source, len);
        if (scanned < 0)
        {
            return Result<int, int>.Err(-1);
        }

        var written = _copyDigits(source, destination, len);
        return written >= 0 ? Result<int, int>.Ok(scanned + written) : Result<int, int>.Err(-2);
    }

    private Result<int, int> NSharpChecksumThenFrameResult(int[] source, int[] destination, int len)
    {
        var checksum = _scanAndChecksumDigits(source, len);
        if (checksum < 0)
        {
            return Result<int, int>.Err(-1);
        }

        var written = _writeChecksum(source, destination, len);
        return written >= 0 ? Result<int, int>.Ok(checksum + written) : Result<int, int>.Err(-2);
    }

    private Result<int, int> NSharpCopyDigitsThenFrameResult(int[] source, int[] destination, int[] scratch, int len)
    {
        var copied = _copyDigits(source, destination, len);
        if (copied < 0)
        {
            return Result<int, int>.Err(-1);
        }

        var written = _writeChecksum(destination, scratch, len);
        return written >= 0 ? Result<int, int>.Ok(copied + written) : Result<int, int>.Err(-2);
    }

    private Result<int, int> NSharpCopyPositiveThenFrameResult(int[] source, int[] destination, int[] scratch, int len)
    {
        var checksum = _copyPositiveChecksum(source, destination, len);
        if (checksum < 0)
        {
            return Result<int, int>.Err(-1);
        }

        var written = _writeChecksum(destination, scratch, len);
        return written >= 0 ? Result<int, int>.Ok(checksum + written) : Result<int, int>.Err(-2);
    }

    private Result<int, int> CSharpScanDigitsResult(int[] values, int len)
    {
        var scanned = _csharpScanDigits(values, len);
        return scanned >= 0 ? Result<int, int>.Ok(scanned) : Result<int, int>.Err(-1);
    }

    private Result<int, int> CSharpWriteChecksumResult(int[] source, int[] destination, int len)
    {
        var written = _csharpWriteChecksum(source, destination, len);
        return written >= 0 ? Result<int, int>.Ok(written) : Result<int, int>.Err(-1);
    }

    private Result<int, int> CSharpCopyDigitsResult(int[] source, int[] destination, int len)
    {
        var written = _csharpCopyDigits(source, destination, len);
        return written >= 0 ? Result<int, int>.Ok(written) : Result<int, int>.Err(-1);
    }

    private Result<int, int> CSharpScanAndChecksumResult(int[] values, int len)
    {
        var checksum = _csharpScanAndChecksumDigits(values, len);
        return checksum >= 0 ? Result<int, int>.Ok(checksum) : Result<int, int>.Err(-1);
    }

    private Result<int, int> CSharpCopyPositiveChecksumResult(int[] source, int[] destination, int len)
    {
        var checksum = _csharpCopyPositiveChecksum(source, destination, len);
        return checksum >= 0 ? Result<int, int>.Ok(checksum) : Result<int, int>.Err(-1);
    }

    private Result<int, int> CSharpScanThenChecksumResult(int[] values, int len)
    {
        var scanned = _csharpScanDigits(values, len);
        if (scanned < 0)
        {
            return Result<int, int>.Err(-1);
        }

        var checksum = _csharpScanAndChecksumDigits(values, len);
        return checksum >= 0 ? Result<int, int>.Ok(scanned + checksum) : Result<int, int>.Err(-2);
    }

    private Result<int, int> CSharpScanThenCopyDigitsResult(int[] source, int[] destination, int len)
    {
        var scanned = _csharpScanDigits(source, len);
        if (scanned < 0)
        {
            return Result<int, int>.Err(-1);
        }

        var written = _csharpCopyDigits(source, destination, len);
        return written >= 0 ? Result<int, int>.Ok(scanned + written) : Result<int, int>.Err(-2);
    }

    private Result<int, int> CSharpChecksumThenFrameResult(int[] source, int[] destination, int len)
    {
        var checksum = _csharpScanAndChecksumDigits(source, len);
        if (checksum < 0)
        {
            return Result<int, int>.Err(-1);
        }

        var written = _csharpWriteChecksum(source, destination, len);
        return written >= 0 ? Result<int, int>.Ok(checksum + written) : Result<int, int>.Err(-2);
    }

    private Result<int, int> CSharpCopyDigitsThenFrameResult(int[] source, int[] destination, int[] scratch, int len)
    {
        var copied = _csharpCopyDigits(source, destination, len);
        if (copied < 0)
        {
            return Result<int, int>.Err(-1);
        }

        var written = _csharpWriteChecksum(destination, scratch, len);
        return written >= 0 ? Result<int, int>.Ok(copied + written) : Result<int, int>.Err(-2);
    }

    private Result<int, int> CSharpCopyPositiveThenFrameResult(int[] source, int[] destination, int[] scratch, int len)
    {
        var checksum = _csharpCopyPositiveChecksum(source, destination, len);
        if (checksum < 0)
        {
            return Result<int, int>.Err(-1);
        }

        var written = _csharpWriteChecksum(destination, scratch, len);
        return written >= 0 ? Result<int, int>.Ok(checksum + written) : Result<int, int>.Err(-2);
    }

    private static int Consume(Result<int, int> result)
        => result.IsOk ? result.OkValueUnchecked : 0;

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

    private static int CSharpCopyDigits(int[] source, int[] destination, int len)
    {
        if (destination.Length < len)
        {
            return -1;
        }

        for (var i = 0; i < len; i++)
        {
            var value = source[i];
            if (value < 48 || value > 57)
            {
                return -1;
            }

            destination[i] = value - 48;
        }

        return len;
    }

    private static int CSharpScanAndChecksumDigits(int[] values, int len)
    {
        var checksum = 0;
        for (var i = 0; i < len; i++)
        {
            var value = values[i];
            if (value < 48 || value > 57)
            {
                return -1;
            }

            checksum += value - 48;
        }

        return checksum;
    }

    private static int CSharpCopyPositiveChecksum(int[] source, int[] destination, int len)
    {
        if (destination.Length < len)
        {
            return -1;
        }

        var written = 0;
        var checksum = 0;
        for (var i = 0; i < len; i++)
        {
            var value = source[i];
            if (value >= 0)
            {
                destination[written] = value;
                written++;
                checksum += value;
            }
        }

        return checksum + written;
    }
}
