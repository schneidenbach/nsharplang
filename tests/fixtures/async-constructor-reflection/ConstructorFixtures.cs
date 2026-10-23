using System;
using System.Threading;
using System.Threading.Tasks;

namespace NSharpLang.AsyncConstructorReflectionFixtures;

public sealed class CancellationTokenTestFacts
{
    public bool Matches(Exception exception, CancellationToken expected) =>
        exception is OperationCanceledException canceled && canceled.CancellationToken == expected;

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
