using System.Collections;
using System.Collections.Generic;
using System;
using System.Linq;

namespace NSharpLang.Tests;

public enum ILCompilerCallMode
{
    Slow = 1,
    Fast = 7
}

[AttributeUsage(AttributeTargets.All, AllowMultiple = false)]
public sealed class RuntimeCoverageAttribute(int code, string[] tags) : Attribute
{
    public int Code { get; } = code;

    public string[] Tags { get; } = tags;

    public bool Enabled { get; set; }

    public ILCompilerCallMode Mode { get; set; }

    public Type? RuntimeType { get; set; }

    public AttributeTargets Targets { get; set; }
}

public static class ILCompilerCallHelpers
{
    public static int Pick(object value)
    {
        return 1;
    }

    public static int Pick(string value)
    {
        return 2;
    }

    public static int Format(int a, int b = 2, int c = 3)
    {
        return a * 100 + b * 10 + c;
    }

    public static long AddLong(long value, long delta = 5L)
    {
        return value + delta;
    }

    public static int ModeValue(ILCompilerCallMode mode = ILCompilerCallMode.Fast)
    {
        return (int)mode;
    }

    public static int Sum(params int[] values)
    {
        return values.Sum();
    }

    public static T Identity<T>(T value)
    {
        return value;
    }

    public static int ScorePair<T>((T, T) pair, Func<T, string> format)
    {
        return format(pair.Item1).Length * 10 + format(pair.Item2).Length;
    }

    public static int DescribeGeneric<T>(T value, int prefix = 1, params T[] rest)
    {
        return prefix * 100 + rest.Length * 10 + value!.ToString()!.Length;
    }

    public static int DecimalDefaultScaled(decimal value = 1.25m)
    {
        return (int)(value * 100m);
    }

    public static int NullableOrDefault(int? value = null)
    {
        return value ?? 17;
    }
}

public static class RuntimeCoverageMetadata
{
    public const int DefaultCode = 19;

    public static string Label => "runtime";

    public static ILCompilerCallMode DefaultMode => ILCompilerCallMode.Fast;

    public static AttributeTargets SupportedTargets => AttributeTargets.Class | AttributeTargets.Struct;
}

public sealed class RuntimeCoverageBag : IEnumerable<int>
{
    private readonly Dictionary<int, int> _items = new();
    private readonly List<int> _values = new();

    public static int StaticField;
    public static int StaticProperty { get; set; }

    public int Field;
    public int Property { get; set; }

    public int this[int index]
    {
        get => _items.TryGetValue(index, out var value) ? value : 0;
        set => _items[index] = value;
    }

    public int ValuesCount => _values.Count;

    public int ValuesSum => _values.Sum();

    public void Add(int value)
    {
        _values.Add(value);
    }

    public IEnumerator<int> GetEnumerator()
    {
        return _values.GetEnumerator();
    }

    IEnumerator IEnumerable.GetEnumerator()
    {
        return GetEnumerator();
    }
}

public struct RuntimeCoverageStruct
{
    public int Field;

    public int Property { get; set; }
}

public sealed class IntAddBag : IEnumerable<int>
{
    private readonly List<int> _values = new();

    public void Add(int value)
    {
        _values.Add(value);
    }

    public int Sum()
    {
        return _values.Sum();
    }

    public IEnumerator<int> GetEnumerator()
    {
        return _values.GetEnumerator();
    }

    IEnumerator IEnumerable.GetEnumerator()
    {
        return GetEnumerator();
    }
}

public sealed class IntEnqueueBag : IEnumerable<int>
{
    private readonly Queue<int> _values = new();

    public void Enqueue(int value)
    {
        _values.Enqueue(value);
    }

    public int ReadAsDigits()
    {
        var result = 0;
        foreach (var value in _values)
        {
            result = result * 10 + value;
        }

        return result;
    }

    public IEnumerator<int> GetEnumerator()
    {
        return _values.GetEnumerator();
    }

    IEnumerator IEnumerable.GetEnumerator()
    {
        return GetEnumerator();
    }
}

public sealed class IntEnumerableBox : IEnumerable<int>
{
    private readonly List<int> _values;

    public IntEnumerableBox(IEnumerable<int> values)
    {
        _values = values.ToList();
    }

    public int Signature()
    {
        return _values.Count * 100 + _values[0] * 10 + _values[^1];
    }

    public IEnumerator<int> GetEnumerator()
    {
        return _values.GetEnumerator();
    }

    IEnumerator IEnumerable.GetEnumerator()
    {
        return GetEnumerator();
    }
}
