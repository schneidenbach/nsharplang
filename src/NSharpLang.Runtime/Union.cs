using System;
using System.Collections.Generic;

namespace NSharpLang.Runtime;

/// <summary>
/// Runtime representation for N# anonymous two-arm union types.
/// </summary>
public readonly struct Union<T0, T1> : IEquatable<Union<T0, T1>>
{
    private readonly object? _value;
    private readonly byte _indexPlusOne;

    public Union(T0 value)
    {
        _value = value;
        _indexPlusOne = 1;
    }

    public Union(T1 value)
    {
        _value = value;
        _indexPlusOne = 2;
    }

    public int Index => _indexPlusOne - 1;

    public object? Value
    {
        get
        {
            ThrowIfUninitialized();
            return _value;
        }
    }

    public bool Is<T>() => ActiveArmCanBeAssignedTo(typeof(T));

    public bool TryGet<T>(out T value)
    {
        if (Is<T>() && _value is T typed)
        {
            value = typed;
            return true;
        }

        if (Is<T>() && _value is null && default(T) is null)
        {
            value = default!;
            return true;
        }

        value = default!;
        return false;
    }

    public T As<T>()
    {
        if (TryGet<T>(out var value))
            return value;

        var requested = typeof(T).FullName ?? typeof(T).Name;
        throw new InvalidCastException($"Union value at index {Index} cannot be read as '{requested}'.");
    }

    public TResult Match<TResult>(Func<T0, TResult> arm0, Func<T1, TResult> arm1)
    {
        ArgumentNullException.ThrowIfNull(arm0);
        ArgumentNullException.ThrowIfNull(arm1);

        return _indexPlusOne switch
        {
            1 => arm0((T0)_value!),
            2 => arm1((T1)_value!),
            _ => throw CreateUninitializedException()
        };
    }

    public void Switch(Action<T0> arm0, Action<T1> arm1)
    {
        ArgumentNullException.ThrowIfNull(arm0);
        ArgumentNullException.ThrowIfNull(arm1);

        switch (_indexPlusOne)
        {
            case 1:
                arm0((T0)_value!);
                return;
            case 2:
                arm1((T1)_value!);
                return;
            default:
                throw CreateUninitializedException();
        }
    }

    public bool Equals(Union<T0, T1> other)
    {
        if (_indexPlusOne != other._indexPlusOne)
            return false;

        if (_indexPlusOne == 0)
            return true;

        return EqualityComparer<object?>.Default.Equals(_value, other._value);
    }

    public override bool Equals(object? obj)
        => obj is Union<T0, T1> other && Equals(other);

    public override int GetHashCode()
        => HashCode.Combine(_indexPlusOne, _value);

    public override string ToString()
        => _indexPlusOne == 0 ? string.Empty : _value?.ToString() ?? string.Empty;

    public static bool operator ==(Union<T0, T1> left, Union<T0, T1> right)
        => left.Equals(right);

    public static bool operator !=(Union<T0, T1> left, Union<T0, T1> right)
        => !left.Equals(right);

    public static implicit operator Union<T0, T1>(T0 value) => new(value);

    public static implicit operator Union<T0, T1>(T1 value) => new(value);

    private bool ActiveArmCanBeAssignedTo(Type requestedType)
    {
        ThrowIfUninitialized();

        var activeArmType = _indexPlusOne switch
        {
            1 => typeof(T0),
            2 => typeof(T1),
            _ => throw CreateUninitializedException()
        };

        return requestedType.IsAssignableFrom(activeArmType);
    }

    private void ThrowIfUninitialized()
    {
        if (_indexPlusOne == 0)
            throw CreateUninitializedException();
    }

    private static InvalidOperationException CreateUninitializedException()
        => new("The union value was not initialized with either arm.");
}
