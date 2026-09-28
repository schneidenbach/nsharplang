namespace NSharpLang.CensusByRefForwarding.Tests

import System
import System.Threading


// CENSUS — A `&T` PARAMETER IN VALUE POSITION.
//
// `v: &int` and `ref v: int` are the same CLR `int&`, and inside the body both names ARE the caller's
// storage: a read is its value and a write goes through to it. The analyzer typed the `&` spelling's
// name `&int`, so `v + 1` was refused (NL202, "'+' doesn't work with '&int' and 'int'") and so was
// `v = x` ("expected '&int' but got 'int'"), while the `ref` spelling of the same body compiled. Every
// row here writes through a `&T` parameter the way a `ref` parameter is written, and every row is
// observable: the caller reads its OWN storage afterwards, which a copy anywhere would leave untouched.
//
// Compound assignment and `++`/`--` on a by-reference parameter declined in the EMITTER for both
// spellings (NL103: it looked for the operator on `int&`, the reference, rather than on `int`); they
// now load and store through the reference, and the `ref` spelling is pinned beside the `&` one.
// A generic call inferred nothing from a `ref` argument (`Swap(ref a, ref b)` declined for both
// spellings; only `Swap<int>(...)` emitted), and now binds `T` from the storage the argument names.
//
// The rows cover arithmetic read-modify-write, compound assignment and increment, a class REFERENCE
// rebound and a struct replaced whole, a string, a generic swap, a read that copies (a later write
// through the parameter does not reach the copy), a `&T` value passed on BY VALUE, a comparison and a
// condition, a constructor's `&T` parameter, and the same body in both spellings side by side. A
// narrowed `string?` passed by reference is the `string?` storage (it was refused NL202 as `&string`
// in both spellings), and the callee's write of null is what the caller reads afterwards.
struct Point {
    X: int
    Y: int
}

class Node {
    Name: string

    constructor(name: string) {
        Name = name
    }
}

func IncInt(v: &int) {
    v = v + 1
}

func IncIntRef(ref v: int) {
    v = v + 1
}

func AddCompound(v: &int, amount: int) {
    v += amount
}

func PostIncrement(v: &int) {
    v++
}

func CountDown(v: &long, amount: long) {
    v -= amount
    v--
}

func AddCompoundRef(ref v: int, amount: int) {
    v += amount
    v++
}

func AppendQuestion(s: &string) {
    s += "?"
}

func RebindNode(n: &Node) {
    n = new Node("x")
}

func Replace(p: &Point) {
    p = new Point { X: p.Y, Y: p.X }
}

func Exclaim(s: &string) {
    s = s + "!"
}

func Swap<T>(a: &T, b: &T) {
    t := a
    a = b
    b = t
}

func ReadThenOverwrite(v: &int): int {
    copy := v
    v = 100
    return copy
}

func Twice(value: int): int {
    return value * 2
}

func DoubleInPlace(v: &int) {
    v = Twice(v)
}

func ClampToZero(v: &int): bool {
    if v < 0 {
        v = 0
        return true
    }

    return false
}

func Larger(a: &int, b: &int): int {
    return Math.Max(a, b)
}

func ClearText(s: &string?) {
    s = null
}

func ClearTextRef(ref s: string?) {
    s = null
}

// A narrowed `string?` is passed by reference as the `string?` STORAGE it is: the callee may write
// null into it, and the caller's read after the call sees that write.
func ClearedLength(useAmpersand: bool): int {
    text: string? = "abc"
    if text != null {
        if useAmpersand {
            ClearText(ref text)
        } else {
            ClearTextRef(ref text)
        }

        if text == null {
            return -1
        }

        return text.Length
    }

    return 0
}

func ExchangedLength(): int {
    text: string? = "abc"
    if text != null {
        previous := Interlocked.Exchange(ref text, "longer")
        return previous.Length + text.Length
    }

    return 0
}

class Ticket {
    Number: int

    constructor(next: &int) {
        Number = next
        next = next + 1
    }
}
