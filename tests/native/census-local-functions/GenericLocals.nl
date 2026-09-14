namespace NSharpLang.CensusLocalFunctions.Tests

import System.Collections.Generic


// A LOCAL FUNCTION'S TYPE PARAMETERS ARE ITS OWN.
//
// The statement kernel refused a local function that declared any (`isLocalFunction != 0 &&
// typeParamCount > 0`), so `func id<T>(v: T): T` inside a function was NL103 `parse.function` —
// the whole ENCLOSING function failed to parse into columnar input. C# admits them, and nothing
// about the lowering needed inventing: a generic local function is a generic method, declared in the
// order a generic top-level `func` is declared (define the method with no signature, declare its
// parameters, resolve the declared types IN THEIR SCOPE, set the signature), and closed at each call
// site by the same inference and the same `MakeGenericMethod` the generic sibling arm performs.
//
// WHAT IS STILL REFUSED, and why: a local function whose SIGNATURE names the ENCLOSING function's
// type parameter (generic or not — `func echo(v: T)` inside `func Outer<T>` declines exactly as it
// did before), because those parameters belong to a different method and C# lowers that shape by
// COPYING them onto the generated one; and an `async` generic local function, for the same reason a
// generic `async func` is refused. A generic local function INSIDE a generic function is fine as
// long as it names only its own parameters — the enclosing `T` can still be a type ARGUMENT at the
// call site, which is `OwnParametersInsideAGenericFunction` below.

// The type argument written out.
func ExplicitIdentity(): int {
    func id<T>(v: T): T {
        return v
    }

    return id<int>(5)
}

// And inferred from the argument, which is the ordinary spelling.
func InferredIdentity(): string {
    func id<T>(v: T): T {
        return v
    }

    return id("hi")
}

// TWO type parameters, only one of which the return names.
func FirstOfTwo(): int {
    func firstOf<A, B>(a: A, _b: B): A {
        return a
    }

    return firstOf(41, true)
}

// A CONSTRAINT rides with the declaration and is checked at the call site.
func FirstStruct(values: List<int>): int {
    func first<T>(items: List<T>): T where T: struct {
        return items[0]
    }

    return first(values)
}

// `T[]` in a parameter position, resolved in the local function's own scope.
func CountOfArray(): int {
    func count<T>(items: T[]): int {
        return items.Length
    }

    return count([1, 2, 3])
}

// RECURSION through the same open handle: each call closes it again.
func DepthOf(values: List<int>): int {
    func depth<T>(items: List<T>, at: int): int {
        if at >= items.Count {
            return at
        }

        return depth(items, at + 1)
    }

    return depth(values, 0)
}

// A GENERIC local function that CAPTURES. Its captures are the enclosing scope's, which never name
// its own type parameters, so the display holds them exactly as it holds a non-generic one's.
func ShiftedLength(bump: int): int {
    func shift<T>(_v: T, extra: int): int {
        return extra + bump
    }

    return shift("abc", 2)
}

// TWO generic local functions in one body, one calling the other — so an open handle is closed from
// inside another open one.
func Layered(values: List<int>): int {
    func countOf<T>(items: List<T>): int {
        return items.Count
    }

    func scaledCount<T>(items: List<T>, scale: int): int {
        return countOf(items) * scale
    }

    return scaledCount(values, 7)
}

// INSIDE a generic function, naming only its OWN parameter. The enclosing `T` reaches the call as a
// type ARGUMENT, which is an ordinary closed instantiation over an open parameter.
func OwnParametersInsideAGenericFunction<T>(value: T): T {
    func id<U>(v: U): U {
        return v
    }

    return id(value)
}
