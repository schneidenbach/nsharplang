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
    private CSharpTaggedResult[] _csharpResults = [];

    public enum ResultWorkload
    {
        SumOkValues,
        SumErrValues,
        BranchAndCopy,
    }

    [Params(
        ResultWorkload.SumOkValues,
        ResultWorkload.SumErrValues,
        ResultWorkload.BranchAndCopy)]
    public ResultWorkload Workload { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _results = new Result<int, int>[4096];
        _csharpResults = new CSharpTaggedResult[_results.Length];
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
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpTaggedStruct() => Workload switch
    {
        ResultWorkload.SumOkValues => CSharpSumOkValues(_csharpResults),
        ResultWorkload.SumErrValues => CSharpSumErrValues(_csharpResults),
        ResultWorkload.BranchAndCopy => CSharpBranchAndCopy(_csharpResults),
        _ => throw new InvalidOperationException()
    };

    [Benchmark]
    public int RuntimeResult() => Workload switch
    {
        ResultWorkload.SumOkValues => RuntimeSumOkValues(_results),
        ResultWorkload.SumErrValues => RuntimeSumErrValues(_results),
        ResultWorkload.BranchAndCopy => RuntimeBranchAndCopy(_results),
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
            if (result.IsOk)
            {
                result.TryGetOk(out var ok);
                sum += ok;
            }
            else
            {
                result.TryGetErr(out var err);
                sum -= err;
            }
        }

        return sum;
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

    private static int RuntimeBranchAndCopy(Result<int, int>[] results)
    {
        var sum = 0;
        foreach (var result in results)
        {
            if (result.IsOk)
            {
                result.TryGetOk(out var ok);
                sum += ok;
            }
            else
            {
                result.TryGetErr(out var err);
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
