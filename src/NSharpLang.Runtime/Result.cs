using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;

namespace NSharpLang.Runtime;

/// <summary>
/// Allocation-free two-arm result value used by Systems N# hot APIs.
/// </summary>
public readonly struct Result<TOk, TErr> : IEquatable<Result<TOk, TErr>>
{
    private readonly TOk? _ok;
    private readonly TErr? _err;
    private readonly byte _state;

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private Result(TOk ok)
    {
        _ok = ok;
        _err = default;
        _state = 1;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private Result(TErr err)
    {
        _ok = default;
        _err = err;
        _state = 2;
    }

    public bool IsOk
    {
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        get => _state == 1;
    }

    public bool IsErr
    {
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        get => _state == 2;
    }

    public TOk OkValue
    {
        get
        {
            ThrowIfNotOk();
            return _ok!;
        }
    }

    public TErr ErrValue
    {
        get
        {
            ThrowIfNotErr();
            return _err!;
        }
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Result<TOk, TErr> Ok(TOk value) => new(value);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Result<TOk, TErr> Err(TErr error) => new(error);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public bool TryGetOk(out TOk value)
    {
        if (IsOk)
        {
            value = _ok!;
            return true;
        }

        value = default!;
        return false;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public bool TryGetErr(out TErr error)
    {
        if (IsErr)
        {
            error = _err!;
            return true;
        }

        error = default!;
        return false;
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public TResult Match<TResult>(Func<TOk, TResult> ok, Func<TErr, TResult> err)
    {
        ArgumentNullException.ThrowIfNull(ok);
        ArgumentNullException.ThrowIfNull(err);

        return _state switch
        {
            1 => ok(_ok!),
            2 => err(_err!),
            _ => throw CreateUninitializedException()
        };
    }

    public bool Equals(Result<TOk, TErr> other)
    {
        if (_state != other._state)
            return false;

        return _state switch
        {
            0 => true,
            1 => EqualityComparer<TOk?>.Default.Equals(_ok, other._ok),
            2 => EqualityComparer<TErr?>.Default.Equals(_err, other._err),
            _ => false
        };
    }

    public override bool Equals(object? obj)
        => obj is Result<TOk, TErr> other && Equals(other);

    public override int GetHashCode()
        => _state switch
        {
            1 => HashCode.Combine(_state, _ok),
            2 => HashCode.Combine(_state, _err),
            _ => 0
        };

    public override string ToString()
        => _state switch
        {
            1 => _ok?.ToString() ?? string.Empty,
            2 => _err?.ToString() ?? string.Empty,
            _ => string.Empty
        };

    public static bool operator ==(Result<TOk, TErr> left, Result<TOk, TErr> right)
        => left.Equals(right);

    public static bool operator !=(Result<TOk, TErr> left, Result<TOk, TErr> right)
        => !left.Equals(right);

    private void ThrowIfNotOk()
    {
        if (!IsOk)
            throw new InvalidOperationException("Result does not contain an Ok value.");
    }

    private void ThrowIfNotErr()
    {
        if (!IsErr)
            throw new InvalidOperationException("Result does not contain an Err value.");
    }

    private static InvalidOperationException CreateUninitializedException()
        => new("The result value was not initialized with either arm.");
}
