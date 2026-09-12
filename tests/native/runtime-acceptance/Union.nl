namespace NSharpLang.RuntimeAcceptance

import System
import System.Collections.Generic

// A FAITHFUL N# TRANSLATION OF `src/NSharpLang.Runtime/Union.cs`, MEMBER FOR MEMBER.
//
// `Union<T0, T1>` is the runtime representation of N#'s anonymous two-arm union types, and the same
// reasons that put `Result` in this project put it here: the type is C# because the Runtime assembly
// has its own migration owner, and the language has to be able to write it. Every member below is the
// same member with the same signature, the same exceptions, the same messages and the same values,
// and `Union.tests.nl` asserts that side by side with the real C# type on the same inputs.
//
// THE SPELLING DIFFERENCES ARE THE SAME TWO AS `Result`'s, plus one more:
//
//   * `_value` / `_indexPlusOne` are `value` / `indexPlusOne`: N# has no leading-underscore
//     identifiers (NL903), and camelCase is what makes a member private.
//   * C#'s `default(T) is null` asks "is this instantiation's zero value a null reference", which is
//     the test that separates a reference argument from a value one. N#'s `is` is a TYPE test and has
//     no `null` pattern, so the same question is asked with `== null` — which on an unconstrained
//     type parameter N# compiles to the boxed-value null test, i.e. false for every value
//     instantiation and a real null test for every reference one. Same question, same answer.
//   * The `switch` expressions over `_indexPlusOne` are `if` chains with the same throwing default,
//     for the reason recorded on `Result.Match`.
readonly struct Union<T0, T1>: IEquatable<Union<T0, T1>> {
    readonly value: object?
    readonly indexPlusOne: byte

    constructor(value: T0) {
        this.value = value
        indexPlusOne = 1
    }

    constructor(value: T1) {
        this.value = value
        indexPlusOne = 2
    }

    Index: int => indexPlusOne - 1

    Value: object? {
        get {
            throwIfUninitialized()
            return value
        }
    }

    func Is<T>(): bool {
        return activeArmCanBeAssignedTo(typeof(T))
    }

    func TryGet<T>(out result: T): bool {
        if Is<T>() && value is T typed {
            result = typed
            return true
        }

        if Is<T>() && value == null && defaultIsNull<T>() {
            result = default
            return true
        }

        result = default
        return false
    }

    func As<T>(): T {
        result: T = default
        if TryGet<T>(out result) {
            return result
        }

        requested := typeof(T).FullName ?? typeof(T).Name
        throw new InvalidCastException($"Union value at index {Index} cannot be read as '{requested}'.")
    }

    func Match<TResult>(arm0: Func<T0, TResult>, arm1: Func<T1, TResult>): TResult {
        ArgumentNullException.ThrowIfNull(arm0)
        ArgumentNullException.ThrowIfNull(arm1)

        if indexPlusOne == 1 {
            return arm0((T0)value)
        }

        if indexPlusOne == 2 {
            return arm1((T1)value)
        }

        throw createUninitializedException()
    }

    func Switch(arm0: Action<T0>, arm1: Action<T1>) {
        ArgumentNullException.ThrowIfNull(arm0)
        ArgumentNullException.ThrowIfNull(arm1)

        if indexPlusOne == 1 {
            arm0((T0)value)
            return
        }

        if indexPlusOne == 2 {
            arm1((T1)value)
            return
        }

        throw createUninitializedException()
    }

    func Equals(other: Union<T0, T1>): bool {
        if indexPlusOne != other.indexPlusOne {
            return false
        }

        if indexPlusOne == 0 {
            return true
        }

        return EqualityComparer<object?>.Default.Equals(value, other.value)
    }

    override func Equals(obj: object?): bool {
        return obj is Union<T0, T1> other && Equals(other)
    }

    override func GetHashCode(): int {
        return HashCode.Combine(indexPlusOne, value)
    }

    override func ToString(): string {
        if indexPlusOne == 0 {
            return string.Empty
        }

        return value?.ToString() ?? string.Empty
    }

    static func operator ==(left: Union<T0, T1>, right: Union<T0, T1>): bool => left.Equals(right)

    static func operator !=(left: Union<T0, T1>, right: Union<T0, T1>): bool => !left.Equals(right)

    implicit operator Union<T0, T1>(value: T0) => new Union<T0, T1>(value)

    implicit operator Union<T0, T1>(value: T1) => new Union<T0, T1>(value)

    // `default(T) is null` in one place, so the two call sites read the same question.
    static func defaultIsNull<T>(): bool {
        zero: T = default
        return zero == null
    }

    func activeArmCanBeAssignedTo(requestedType: Type): bool {
        throwIfUninitialized()

        activeArmType: Type = typeof(T0)
        if indexPlusOne == 2 {
            activeArmType = typeof(T1)
        } else if indexPlusOne != 1 {
            throw createUninitializedException()
        }

        return requestedType.IsAssignableFrom(activeArmType)
    }

    func throwIfUninitialized() {
        if indexPlusOne == 0 {
            throw createUninitializedException()
        }
    }

    static func createUninitializedException(): InvalidOperationException {
        return new InvalidOperationException("The union value was not initialized with either arm.")
    }
}
