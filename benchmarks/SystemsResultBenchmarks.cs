using System;
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
    private Result<int, int>[] _results = [];
    private Result<int, int>[] _allOkResults = [];
    private Result<int, int>[] _allErrResults = [];
    private Result<int, int>[] _lateErrResults = [];
    private CSharpTaggedResult[] _csharpResults = [];
    private CSharpTaggedResult[] _allOkCSharpResults = [];
    private CSharpTaggedResult[] _allErrCSharpResults = [];
    private CSharpTaggedResult[] _lateErrCSharpResults = [];

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
        _csharpResults = new CSharpTaggedResult[_results.Length];
        _allOkCSharpResults = new CSharpTaggedResult[_results.Length];
        _allErrCSharpResults = new CSharpTaggedResult[_results.Length];
        _lateErrCSharpResults = new CSharpTaggedResult[_results.Length];
        for (var i = 0; i < _results.Length; i++)
        {
            if ((i & 1) == 0)
            {
                _results[i] = Result<int, int>.Ok(i);
                _csharpResults[i] = CSharpTaggedResult.Ok(i);
            }
            else
            {
                _results[i] = Result<int, int>.Err(-i);
                _csharpResults[i] = CSharpTaggedResult.Err(-i);
            }

            _allOkResults[i] = Result<int, int>.Ok(i);
            _allOkCSharpResults[i] = CSharpTaggedResult.Ok(i);
            _allErrResults[i] = Result<int, int>.Err(-i);
            _allErrCSharpResults[i] = CSharpTaggedResult.Err(-i);
            if (i == _results.Length - 1)
            {
                _lateErrResults[i] = Result<int, int>.Err(-i);
                _lateErrCSharpResults[i] = CSharpTaggedResult.Err(-i);
            }
            else
            {
                _lateErrResults[i] = Result<int, int>.Ok(i);
                _lateErrCSharpResults[i] = CSharpTaggedResult.Ok(i);
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpTaggedStruct() => Workload switch
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

    [Benchmark]
    public int RuntimeResult() => Workload switch
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

    private static int CSharpSumOkValues(CSharpTaggedResult[] results)
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

    private static int CSharpSumErrValues(CSharpTaggedResult[] results)
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

    private static int CSharpBranchAndCopy(CSharpTaggedResult[] results)
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

    private static int CSharpAllOkFastPath(CSharpTaggedResult[] results)
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

    private static int CSharpAllErrFastPath(CSharpTaggedResult[] results)
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

    private static int CSharpFirstErrOrSum(CSharpTaggedResult[] results)
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

    private static int CSharpValidateAllOkAscending(CSharpTaggedResult[] results)
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

    private static int RuntimeSumOkValues(Result<int, int>[] results)
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

    private static int RuntimeAllOkFastPath(Result<int, int>[] results)
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

    private static int RuntimeAllErrFastPath(Result<int, int>[] results)
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

    private static int RuntimeSumErrValues(Result<int, int>[] results)
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

    private static int RuntimeFirstErrOrSum(Result<int, int>[] results)
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

    private static int RuntimeValidateAllOkAscending(Result<int, int>[] results)
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

    private static int RuntimeBranchAndCopy(Result<int, int>[] results)
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

    private readonly struct CSharpTaggedResult
    {
        private readonly int _ok;
        private readonly int _err;
        private readonly byte _state;

        private CSharpTaggedResult(int ok, int err, byte state)
        {
            _ok = ok;
            _err = err;
            _state = state;
        }

        public bool IsOk => _state == 1;

        public static CSharpTaggedResult Ok(int value) => new(value, 0, 1);

        public static CSharpTaggedResult Err(int error) => new(0, error, 2);

        public bool TryGetOk(out int value)
        {
            if (_state == 1)
            {
                value = _ok;
                return true;
            }

            value = default;
            return false;
        }

        public bool TryGetErr(out int value)
        {
            if (_state == 2)
            {
                value = _err;
                return true;
            }

            value = default;
            return false;
        }
    }
}
