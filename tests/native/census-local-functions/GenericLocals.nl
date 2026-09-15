namespace NSharpLang.CensusLocalFunctions.Tests

import System.Collections.Generic

interface GenericLocalMarker {
}

class GenericLocalMarked: GenericLocalMarker {
    Value: string
}

class GenericLocalBase {
    Value: string
}

class GenericLocalDerived: GenericLocalBase {
}

class GenericLocalCreated {
}

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
// Enclosing type parameters remain in scope. A capture-free synthesized method copies them ahead
// of its own parameters; a capturing local puts them on its display type and keeps its own method
// parameters on the method. The two CLR owners stay distinct even when both parameters have ordinal
// zero. An `async` generic local function remains refused for the same reason a generic `async func`
// is refused.

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

// CAPTURE-FREE: both T and U are method parameters on the synthesized static method. T is copied
// from the enclosing declaration and U belongs to the local declaration.
func NoCaptureEnclosingType<T>(value: T): T {
    func choose<U>(outer: T, _other: U): T {
        return outer
    }

    return choose<int>(value, 1)
}

// CAPTURING: T belongs to the generic display type and U belongs to its generic instance method.
// Their constraints must remain on those exact owners.
func CaptureEnclosingType<T>(value: T): T where T: class {
    func choose<U>(_other: U): T where U: struct {
        return value
    }

    return choose<int>(1)
}

func CaptureEnclosingInterface<T>(value: T): T where T: GenericLocalMarker {
    func choose<U>(_other: U): T where U: struct {
        return value
    }

    return choose<int>(1)
}

func NoCaptureDependent<T, U>(value: T): T where T: U where U: class {
    func choose<V>(outer: T, _other: V): T {
        return outer
    }

    return choose<int>(value, 1)
}

func CaptureEnclosingBase<T>(value: T): T where T: GenericLocalBase {
    func choose<U>(_other: U): T {
        return value
    }

    return choose<int>(1)
}

func NoCaptureNew<T>(value: T): T where T: new() {
    func choose<U>(outer: T, _other: U): T {
        return outer
    }

    return choose<int>(value, 1)
}

func LocalConstraintNamesEnclosing<T>(value: T): T where T: class {
    func choose<U>(input: U): U where U: T {
        return input
    }

    return choose<T>(value)
}

class GenericLocalMemberOwner {
    func NoCapture<T>(value: T): T {
        func choose<U>(outer: T, _other: U): T {
            return outer
        }

        return choose<int>(value, 1)
    }

    func Capture<T>(value: T): T where T: class {
        func choose<U>(_other: U): T where U: struct {
            return value
        }

        return choose<int>(1)
    }
}
