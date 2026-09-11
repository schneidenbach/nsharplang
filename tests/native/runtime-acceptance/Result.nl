namespace NSharpLang.RuntimeAcceptance

import System
import System.Collections.Generic

// A FAITHFUL N# TRANSLATION OF `src/NSharpLang.Runtime/Result.cs`, MEMBER FOR MEMBER.
//
// The runtime's `Result<TOk, TErr>` is the allocation-free two-arm result the Systems N# hot APIs
// return, and it is C# today because the Runtime assembly has its own migration owner. This file is
// the same type written in N#, under a test namespace, so the LANGUAGE can be held to it: every
// member below is the same member with the same signature, the same exceptions, the same messages
// and the same values, and `Result.tests.nl` asserts that side by side with the real C# type on the
// same inputs. A member that cannot be written here is a compiler gap, not a translation choice.
//
// TWO SPELLINGS DIFFER FROM THE C#, AND NEITHER IS A SEMANTIC CHANGE:
//
//   * C#'s payload fields are `TOk? _ok` / `TErr? _err`. On an UNCONSTRAINED type parameter C#'s `?`
//     is an annotation with no runtime meaning — `TOk?` and `TOk` are the same CLR type, and the
//     nullable metadata only tells a nullable-aware reader "may be null when the arm is not taken".
//     N#'s `TOk?` is NOT that: it is a real `Nullable<TOk>` for a value instantiation, a different
//     type with a different layout. The faithful translation of the C# field is therefore the plain
//     `TOk`, which is what the CLR sees in both languages.
//   * N# has no leading-underscore identifiers (NL903): PascalCase is public and camelCase is not,
//     and the name carries the visibility. `_ok` is `ok`, and the two members whose PARAMETER shares
//     that name say `this.ok` for the field, exactly as the constructor does.
//
// `[MethodImpl(...)]` IS ABSENT, AND THAT IS A RECORDED GAP, NOT A CHOICE. The C# marks its hot
// members `MethodImplOptions.AggressiveInlining | MethodImplOptions.AggressiveOptimization`. N#
// parses attributes but the columnar backend preserves only those with no constructor arguments or
// positional string arguments (website/docs/basics.md), so an attribute whose single argument is an
// ENUM FLAGS COMBINATION cannot be written. Inlining hints do not change observable behaviour, so
// every assertion in the test file holds without them.
readonly struct Result<TOk, TErr>: IEquatable<Result<TOk, TErr>> {
    readonly ok: TOk
    readonly err: TErr
    readonly state: byte

    private constructor(ok: TOk, err: TErr, state: byte) {
        this.ok = ok
        this.err = err
        this.state = state
    }

    IsOk: bool => state == 1

    IsErr: bool => state == 2

    OkValue: TOk {
        get {
            throwIfNotOk()
            return ok
        }
    }

    ErrValue: TErr {
        get {
            throwIfNotErr()
            return err
        }
    }

    // Gets the Ok payload without checking the tag. Systems hot paths should only use this after
    // proving `IsOk` for the same value.
    OkValueUnchecked: TOk => ok

    // Gets the Err payload without checking the tag. Systems hot paths should only use this after
    // proving `IsErr` for the same value.
    ErrValueUnchecked: TErr => err

    static func Ok(value: TOk): Result<TOk, TErr> {
        return new Result<TOk, TErr>(value, default, 1)
    }

    static func Err(error: TErr): Result<TOk, TErr> {
        return new Result<TOk, TErr>(default, error, 2)
    }

    func TryGetOk(out value: TOk): bool {
        if state == 1 {
            value = ok
            return true
        }

        value = default
        return false
    }

    func TryGetErr(out error: TErr): bool {
        if state == 2 {
            error = err
            return true
        }

        error = default
        return false
    }

    // C# writes the three arms as a `switch` expression over `_state`. N#'s `match` is a pattern
    // construct over unions and constants; an integer tag with a throwing default is an `if` chain,
    // which is the same order of tests and the same exception on the same input.
    func Match<TResult>(ok: Func<TOk, TResult>, err: Func<TErr, TResult>): TResult {
        ArgumentNullException.ThrowIfNull(ok)
        ArgumentNullException.ThrowIfNull(err)

        if state == 1 {
            return ok(this.ok)
        }

        if state == 2 {
            return err(this.err)
        }

        throw createUninitializedException()
    }

    func Equals(other: Result<TOk, TErr>): bool {
        if state != other.state {
            return false
        }

        if state == 0 {
            return true
        }

        if state == 1 {
            return EqualityComparer<TOk>.Default.Equals(ok, other.ok)
        }

        if state == 2 {
            return EqualityComparer<TErr>.Default.Equals(err, other.err)
        }

        return false
    }

    override func Equals(obj: object?): bool {
        return obj is Result<TOk, TErr> other && Equals(other)
    }

    override func GetHashCode(): int {
        if state == 1 {
            return HashCode.Combine(state, ok)
        }

        if state == 2 {
            return HashCode.Combine(state, err)
        }

        return 0
    }

    override func ToString(): string {
        if state == 1 {
            return ok?.ToString() ?? string.Empty
        }

        if state == 2 {
            return err?.ToString() ?? string.Empty
        }

        return string.Empty
    }

    static func operator ==(left: Result<TOk, TErr>, right: Result<TOk, TErr>): bool => left.Equals(right)

    static func operator !=(left: Result<TOk, TErr>, right: Result<TOk, TErr>): bool => !left.Equals(right)

    func throwIfNotOk() {
        if state != 1 {
            throw new InvalidOperationException("Result does not contain an Ok value.")
        }
    }

    func throwIfNotErr() {
        if state != 2 {
            throw new InvalidOperationException("Result does not contain an Err value.")
        }
    }

    static func createUninitializedException(): InvalidOperationException {
        return new InvalidOperationException("The result value was not initialized with either arm.")
    }
}

class ResultFactory {
    static func Ok<TOk, TErr>(value: TOk): Result<TOk, TErr> {
        return Result<TOk, TErr>.Ok(value)
    }

    static func Err<TOk, TErr>(error: TErr): Result<TOk, TErr> {
        return Result<TOk, TErr>.Err(error)
    }
}
