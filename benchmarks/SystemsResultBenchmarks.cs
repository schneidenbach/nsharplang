using System;
using System.Runtime.CompilerServices;
using BenchmarkDotNet.Attributes;
using NSharpLang.Runtime;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Systems N# Result ABI benchmarks. The hot path is direct tag inspection through
/// <c>TryGet*</c> and <c>Is*</c>; delegate-based <c>Match</c> is intentionally not the systems
/// hot-path shape because it cannot match direct tagged-struct dispatch.
/// </summary>
[MemoryDiagnoser]
public class SystemsResultBenchmarks
{
    private const int InnerOperations = 16;
    private const MethodImplOptions HotPathImpl =
        MethodImplOptions.AggressiveInlining | MethodImplOptions.AggressiveOptimization;

    private Result<int, int>[] _results = [];
    private Result<int, int>[] _allOkResults = [];
    private Result<int, int>[] _allErrResults = [];
    private Result<int, int>[] _lateErrResults = [];
    private CSharpTaggedResult<int, int>[] _csharpResults = [];
    private CSharpTaggedResult<int, int>[] _allOkCSharpResults = [];
    private CSharpTaggedResult<int, int>[] _allErrCSharpResults = [];
    private CSharpTaggedResult<int, int>[] _lateErrCSharpResults = [];

    public enum ResultWorkload
    {
        SumOkValues,
        SumErrValues,
        BranchAndCopy,
        AllOkFastPath,
        AllErrFastPath,
        FirstErrOrSum,
        ValidateAllOkAscending,
    }

    [Params(
        ResultWorkload.SumOkValues,
        ResultWorkload.SumErrValues,
        ResultWorkload.BranchAndCopy,
        ResultWorkload.AllOkFastPath,
        ResultWorkload.AllErrFastPath,
        ResultWorkload.FirstErrOrSum,
        ResultWorkload.ValidateAllOkAscending)]
    public ResultWorkload Workload { get; set; }

    [Params(64, 4096)]
    public int Size { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _results = new Result<int, int>[Size];
        _allOkResults = new Result<int, int>[Size];
        _allErrResults = new Result<int, int>[Size];
        _lateErrResults = new Result<int, int>[Size];
        _csharpResults = new CSharpTaggedResult<int, int>[_results.Length];
        _allOkCSharpResults = new CSharpTaggedResult<int, int>[_results.Length];
        _allErrCSharpResults = new CSharpTaggedResult<int, int>[_results.Length];
        _lateErrCSharpResults = new CSharpTaggedResult<int, int>[_results.Length];
        for (var i = 0; i < _results.Length; i++)
        {
            if ((i & 1) == 0)
            {
                _results[i] = Result<int, int>.Ok(i);
                _csharpResults[i] = CSharpTaggedResult<int, int>.Ok(i);
            }
            else
            {
                _results[i] = Result<int, int>.Err(-i);
                _csharpResults[i] = CSharpTaggedResult<int, int>.Err(-i);
            }

            _allOkResults[i] = Result<int, int>.Ok(i);
            _allOkCSharpResults[i] = CSharpTaggedResult<int, int>.Ok(i);
            _allErrResults[i] = Result<int, int>.Err(-i);
            _allErrCSharpResults[i] = CSharpTaggedResult<int, int>.Err(-i);
            if (i == _results.Length - 1)
            {
                _lateErrResults[i] = Result<int, int>.Err(-i);
                _lateErrCSharpResults[i] = CSharpTaggedResult<int, int>.Err(-i);
            }
            else
            {
                _lateErrResults[i] = Result<int, int>.Ok(i);
                _lateErrCSharpResults[i] = CSharpTaggedResult<int, int>.Ok(i);
            }
        }
    }

    public int CSharpAll() => CSharpAllResults(
        _csharpResults,
        _allOkCSharpResults,
        _allErrCSharpResults,
        _lateErrCSharpResults);

    [MethodImpl(HotPathImpl)]
    public int RuntimeAll() => RuntimeAllResults(
        _results,
        _allOkResults,
        _allErrResults,
        _lateErrResults);

    [Benchmark(Baseline = true, OperationsPerInvoke = InnerOperations)]
    public int CSharpTaggedStruct()
    {
        var total = 0;
        for (var operation = 0; operation < InnerOperations; operation++)
        {
            total += Workload switch
            {
                ResultWorkload.SumOkValues => CSharpSumOkValues(_csharpResults),
                ResultWorkload.SumErrValues => CSharpSumErrValues(_csharpResults),
                ResultWorkload.BranchAndCopy => CSharpBranchAndCopy(_csharpResults),
                ResultWorkload.AllOkFastPath => CSharpAllOkFastPath(_allOkCSharpResults),
                ResultWorkload.AllErrFastPath => CSharpAllErrFastPath(_allErrCSharpResults),
                ResultWorkload.FirstErrOrSum => CSharpFirstErrOrSum(_lateErrCSharpResults),
                ResultWorkload.ValidateAllOkAscending => CSharpValidateAllOkAscending(_allOkCSharpResults),
                _ => throw new InvalidOperationException()
            };
        }

        return total;
    }

    [Benchmark(OperationsPerInvoke = InnerOperations)]
    public int RuntimeResult()
    {
        var total = 0;
        for (var operation = 0; operation < InnerOperations; operation++)
        {
            total += Workload switch
            {
                ResultWorkload.SumOkValues => RuntimeSumOkValues(_results),
                ResultWorkload.SumErrValues => RuntimeSumErrValues(_results),
                ResultWorkload.BranchAndCopy => RuntimeBranchAndCopy(_results),
                ResultWorkload.AllOkFastPath => RuntimeAllOkFastPath(_allOkResults),
                ResultWorkload.AllErrFastPath => RuntimeAllErrFastPath(_allErrResults),
                ResultWorkload.FirstErrOrSum => RuntimeFirstErrOrSum(_lateErrResults),
                ResultWorkload.ValidateAllOkAscending => RuntimeValidateAllOkAscending(_allOkResults),
                _ => throw new InvalidOperationException()
            };
        }

        return total;
    }

    private static int CSharpSumOkValues(CSharpTaggedResult<int, int>[] results)
    {
        var sum = 0;
        foreach (var result in results)
        {
            if (result.TryGetOk(out var value))
            {
                sum += value;
            }
        }

        return sum;
    }

    private static int CSharpSumErrValues(CSharpTaggedResult<int, int>[] results)
    {
        var sum = 0;
        foreach (var result in results)
        {
            if (result.TryGetErr(out var value))
            {
                sum += value;
            }
        }

        return sum;
    }

    private static int CSharpBranchAndCopy(CSharpTaggedResult<int, int>[] results)
    {
        var sum = 0;
        foreach (var result in results)
        {
            if (result.TryGetOk(out var ok))
            {
                sum += ok;
            }
            else if (result.TryGetErr(out var err))
            {
                sum -= err;
            }
        }

        return sum;
    }

    private static int CSharpAllOkFastPath(CSharpTaggedResult<int, int>[] results)
    {
        var sum = 0;
        foreach (var result in results)
        {
            if (!result.IsOk)
            {
                return -1;
            }

            result.TryGetOk(out var value);
            sum += value;
        }

        return sum;
    }

    private static int CSharpAllErrFastPath(CSharpTaggedResult<int, int>[] results)
    {
        var sum = 0;
        foreach (var result in results)
        {
            if (result.IsOk)
            {
                return -1;
            }

            result.TryGetErr(out var value);
            sum += value;
        }

        return sum;
    }

    private static int CSharpFirstErrOrSum(CSharpTaggedResult<int, int>[] results)
    {
        var sum = 0;
        foreach (var result in results)
        {
            if (result.TryGetErr(out var error))
            {
                return error;
            }

            result.TryGetOk(out var value);
            sum += value;
        }

        return sum;
    }

    private static int CSharpValidateAllOkAscending(CSharpTaggedResult<int, int>[] results)
    {
        var previous = -1;
        var count = 0;
        foreach (var result in results)
        {
            if (!result.IsOk)
            {
                return -1;
            }

            result.TryGetOk(out var value);
            if (value <= previous)
            {
                return -2;
            }

            previous = value;
            count++;
        }

        return count;
    }

    [MethodImpl(HotPathImpl)]
    private static int RuntimeSumOkValues(Result<int, int>[] results)
    {
        var sum = 0;
        for (var i = 0; i < results.Length; i++)
        {
            var result = results[i];
            if (result.IsOk)
            {
                sum += result.OkValueUnchecked;
            }
        }

        return sum;
    }

    [MethodImpl(HotPathImpl)]
    private static int RuntimeAllOkFastPath(Result<int, int>[] results)
    {
        var sum = 0;
        for (var i = 0; i < results.Length; i++)
        {
            var result = results[i];
            if (!result.IsOk)
            {
                return -1;
            }

            sum += result.OkValueUnchecked;
        }

        return sum;
    }

    [MethodImpl(HotPathImpl)]
    private static int RuntimeAllErrFastPath(Result<int, int>[] results)
    {
        var sum = 0;
        for (var i = 0; i < results.Length; i++)
        {
            var result = results[i];
            if (result.IsOk)
            {
                return -1;
            }

            sum += result.ErrValueUnchecked;
        }

        return sum;
    }

    [MethodImpl(HotPathImpl)]
    private static int RuntimeSumErrValues(Result<int, int>[] results)
    {
        var sum = 0;
        for (var i = 0; i < results.Length; i++)
        {
            var result = results[i];
            if (result.IsErr)
            {
                sum += result.ErrValueUnchecked;
            }
        }

        return sum;
    }

    [MethodImpl(HotPathImpl)]
    private static int RuntimeFirstErrOrSum(Result<int, int>[] results)
    {
        var sum = 0;
        for (var i = 0; i < results.Length; i++)
        {
            var result = results[i];
            if (result.IsErr)
            {
                return result.ErrValueUnchecked;
            }

            sum += result.OkValueUnchecked;
        }

        return sum;
    }

    [MethodImpl(HotPathImpl)]
    private static int RuntimeValidateAllOkAscending(Result<int, int>[] results)
    {
        var previous = -1;
        var count = 0;
        for (var i = 0; i < results.Length; i++)
        {
            var result = results[i];
            if (!result.IsOk)
            {
                return -1;
            }

            var value = result.OkValueUnchecked;
            if (value <= previous)
            {
                return -2;
            }

            previous = value;
            count++;
        }

        return count;
    }

    [MethodImpl(HotPathImpl)]
    private static int RuntimeBranchAndCopy(Result<int, int>[] results)
    {
        var sum = 0;
        for (var i = 0; i < results.Length; i++)
        {
            var result = results[i];
            if (result.IsOk)
            {
                sum += result.OkValueUnchecked;
            }
            else
            {
                sum -= result.ErrValueUnchecked;
            }
        }

        return sum;
    }

    private static int CSharpAllResults(
        CSharpTaggedResult<int, int>[] results,
        CSharpTaggedResult<int, int>[] allOkResults,
        CSharpTaggedResult<int, int>[] allErrResults,
        CSharpTaggedResult<int, int>[] lateErrResults)
        => CSharpSumOkValues(results)
           + CSharpSumErrValues(results)
           + CSharpBranchAndCopy(results)
           + CSharpAllOkFastPath(allOkResults)
           + CSharpAllErrFastPath(allErrResults)
           + CSharpFirstErrOrSum(lateErrResults)
           + CSharpValidateAllOkAscending(allOkResults);

    [MethodImpl(HotPathImpl)]
    private static int RuntimeAllResults(
        Result<int, int>[] results,
        Result<int, int>[] allOkResults,
        Result<int, int>[] allErrResults,
        Result<int, int>[] lateErrResults)
        => RuntimeSumOkValues(results)
           + RuntimeSumErrValues(results)
           + RuntimeBranchAndCopy(results)
           + RuntimeAllOkFastPath(allOkResults)
           + RuntimeAllErrFastPath(allErrResults)
           + RuntimeFirstErrOrSum(lateErrResults)
           + RuntimeValidateAllOkAscending(allOkResults);

    private readonly struct CSharpTaggedResult<TOk, TErr>
    {
        private readonly TOk _ok;
        private readonly TErr _err;
        private readonly byte _state;

        private CSharpTaggedResult(TOk ok, TErr err, byte state)
        {
            _ok = ok;
            _err = err;
            _state = state;
        }

        public bool IsOk => _state == 1;

        public bool IsErr => _state == 2;

        public TOk OkValueUnchecked => _ok;

        public TErr ErrValueUnchecked => _err;

        public static CSharpTaggedResult<TOk, TErr> Ok(TOk value) => new(value, default!, 1);

        public static CSharpTaggedResult<TOk, TErr> Err(TErr error) => new(default!, error, 2);

        public bool TryGetOk(out TOk value)
        {
            if (_state == 1)
            {
                value = _ok;
                return true;
            }

            value = default!;
            return false;
        }

        public bool TryGetErr(out TErr value)
        {
            if (_state == 2)
            {
                value = _err;
                return true;
            }

            value = default!;
            return false;
        }
    }
}
