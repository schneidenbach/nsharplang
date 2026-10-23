using System;
using System.Threading;
using System.Threading.Tasks;

namespace NSharpLang.AsyncConstructorReflectionFixtures;

public sealed class CancellationTokenTestFacts
{
    public TaskCreationOptions RunContinuationsAsynchronouslyOptions() =>
        TaskCreationOptions.RunContinuationsAsynchronously;

    public string FrameworkTrimSmoke()
    {
        var source = new TaskCompletionSource<int>();
        source.SetException(new AggregateException("outer", new Exception("inner")));
        var failure = source.Task.Exception!;
        var nestedFailure = (AggregateException)failure.InnerExceptions[0];
        var innerCount = nestedFailure.InnerExceptions.Count;
        var firstMessage = nestedFailure.InnerExceptions[0].Message;
        var messages = new string[innerCount];
        var index = 0;
        foreach (Exception inner in nestedFailure.InnerExceptions)
        {
            messages[index++] = inner.Message;
        }

        return $"exceptions={innerCount}:{firstMessage}:{string.Join(",", messages)}|join={string.Join("|", new[] { "alpha", "beta" })}|clamp={Math.Clamp(9, 0, 5)}";
    }

    public bool Matches(Exception exception, CancellationToken expected) =>
        exception is OperationCanceledException canceled && canceled.CancellationToken == expected;

    public bool MatchesExactCancellation(Exception exception, string expectedMessage, CancellationToken expectedToken) =>
        exception.GetType() == typeof(OperationCanceledException) &&
        exception.Message == expectedMessage &&
        ((OperationCanceledException)exception).CancellationToken == expectedToken;

    public string DescribeCancellation(Exception exception, CancellationToken expectedToken) =>
        $"{exception.GetType().FullName}|{exception.Message}|token-match={exception is OperationCanceledException canceled && canceled.CancellationToken == expectedToken}";

    public async Task<int> CreateCanceledTaskAfterYield(CancellationToken token)
    {
        await Task.Yield();
        throw new OperationCanceledException("marker", token);
    }

    public async Task CreateCanceledTaskWithoutResultAfterYield(CancellationToken token)
    {
        await Task.Yield();
        throw new OperationCanceledException("marker", token);
    }

    public bool MatchesInvalidOperation(Exception exception, string expectedMessage) =>
        exception is InvalidOperationException failure && failure.Message == expectedMessage;

    public bool HasTaskFailureCount(Task task, int expectedCount)
    {
        AggregateException? failure = task.Exception;
        return task.IsFaulted && failure != null && failure.InnerExceptions.Count == expectedCount;
    }

    public Task<int> CreateFaultedTaskWithMultipleExceptions()
    {
        var source = new TaskCompletionSource<int>();
        source.SetException(new Exception[]
        {
            new InvalidOperationException("first-failure"),
            new ArgumentException("second-failure")
        });
        return source.Task;
    }

    public Task<int> CreateFaultedTaskWithNestedAggregate()
    {
        var source = new TaskCompletionSource<int>();
        source.SetException(new AggregateException(
            "outer-failure",
            new AggregateException("inner-failure", new InvalidOperationException("nested-failure"))));
        return source.Task;
    }

    public bool HasNestedAggregateFailure(Task task)
    {
        AggregateException? outer = task.Exception;
        if (!task.IsFaulted || outer == null)
        {
            return false;
        }
        return ContainsNestedAggregate(outer);
    }

    public bool PreservesTaskFailureShape(Task source, Task forwarded)
    {
        AggregateException? sourceFailure = source.Exception;
        AggregateException? forwardedFailure = forwarded.Exception;
        return source.IsFaulted && forwarded.IsFaulted && sourceFailure != null && forwardedFailure != null &&
            SameExceptionShape(sourceFailure, forwardedFailure);
    }

    private static bool ContainsNestedAggregate(Exception failure)
    {
        if (failure is not AggregateException aggregate)
        {
            return false;
        }
        foreach (Exception inner in aggregate.InnerExceptions)
        {
            if (inner is AggregateException || ContainsNestedAggregate(inner))
            {
                return true;
            }
        }
        return false;
    }

    private static bool SameExceptionShape(Exception left, Exception right)
    {
        if (left.GetType() != right.GetType() || left.Message != right.Message)
        {
            return false;
        }
        if (left is not AggregateException leftAggregate)
        {
            return right is not AggregateException;
        }
        if (right is not AggregateException rightAggregate || leftAggregate.InnerExceptions.Count != rightAggregate.InnerExceptions.Count)
        {
            return false;
        }
        for (int index = 0; index < leftAggregate.InnerExceptions.Count; index++)
        {
            if (!SameExceptionShape(leftAggregate.InnerExceptions[index], rightAggregate.InnerExceptions[index]))
            {
                return false;
            }
        }
        return true;
    }
}

public sealed class ReflectedArrayBox<T> { }

public sealed class ReflectedConstructorArrayShapes
{
    private readonly int shape;

    public ReflectedConstructorArrayShapes(ReflectedArrayBox<int[]> vector)
    {
        shape = vector is null ? 11 : 1;
    }

    public ReflectedConstructorArrayShapes(ReflectedArrayBox<int[,]> matrix)
    {
        shape = matrix is null ? 22 : 2;
    }

    public int GetShape() => shape;
}

public sealed class ReflectedRefConstructor
{
    private readonly int observed;

    public ReflectedRefConstructor(ref int value)
    {
        value += 6;
        observed = value;
    }

    public int GetValue() => observed;
}

public sealed class ReflectedOutConstructor
{
    private readonly int observed;

    public ReflectedOutConstructor(out int value)
    {
        value = 73;
        observed = value;
    }

    public int GetValue() => observed;
}

public sealed class ReflectedInConstructor
{
    private readonly int observed;

    public ReflectedInConstructor(in int value)
    {
        observed = value;
    }

    public int GetValue() => observed;
}
