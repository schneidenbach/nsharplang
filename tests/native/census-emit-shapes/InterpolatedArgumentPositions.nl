namespace NSharpLang.CensusEmitShapes.Tests

import System
import System.Text

// AN INTERPOLATED STRING WRITTEN AS AN ARGUMENT, AT EVERY POSITION.
//
// The recursive expression door plans no interpolated string, so a construction or call with one
// among its arguments is handed back to the host emitter whole. The host's runtime-exception arm used
// to be a hand-picked subset of constructors -- `()`, `(string)` and `(string, string)` -- so
// `new Exception($"{a} {b}", inner)` declined at `emit.return.expression` while the same argument at
// a source constructor or a method call emitted. Each shape below pins one position (first, middle,
// last) at one, two and three holes, beside a sibling argument that is not a string.
class Framed {
    Text: string
    Count: int
    Inner: Exception?

    constructor(text: string, count: int, inner: Exception?) {
        Text = text
        Count = count
        Inner = inner
    }

    constructor(count: int, text: string, inner: Exception?) {
        Text = text
        Count = count
        Inner = inner
    }

    constructor(count: int, inner: Exception?, text: string) {
        Text = text
        Count = count
        Inner = inner
    }

    func Describe(text: string, count: int): string => text + "#" + count.ToString() + "@" + Count.ToString()
}

func InnerMessage(inner: Exception?): string => inner == null ? "none" : inner.Message

func TextFirst(text: string, count: int, inner: Exception?): string => text + "|" + count.ToString() + "|" + InnerMessage(inner)

func TextMiddle(count: int, text: string, inner: Exception?): string => count.ToString() + "|" + text + "|" + InnerMessage(inner)

func TextLast(count: int, inner: Exception?, text: string): string => count.ToString() + "|" + InnerMessage(inner) + "|" + text

// Runtime exception constructors: the arm that declined.
func ExceptionFirstOneHole(a: string, inner: Exception?): Exception => new Exception($"{a}", inner)

func ExceptionFirstTwoHoles(a: string, b: string, inner: Exception?): Exception => new Exception($"{a} {b}", inner)

func ExceptionFirstThreeHoles(a: string, b: string, c: int, inner: Exception?): Exception => new InvalidOperationException($"{a} {b} after {c}", inner)

func ExceptionMiddleOneHole(message: string, a: string, inner: Exception?): ArgumentException => new ArgumentException(message, $"{a}", inner)

func ExceptionMiddleTwoHoles(message: string, a: string, b: string, inner: Exception?): ArgumentException => new ArgumentException(message, $"{a}{b}", inner)

func ExceptionMiddleThreeHoles(message: string, a: string, b: string, c: string, inner: Exception?): ArgumentException => new ArgumentException(message, $"{a}_{b}_{c}", inner)

func ExceptionLastOneHole(name: string, actual: object, a: string): ArgumentOutOfRangeException => new ArgumentOutOfRangeException(name, actual, $"{a}")

func ExceptionLastTwoHoles(name: string, actual: object, a: string, b: int): ArgumentOutOfRangeException => new ArgumentOutOfRangeException(name, actual, $"{a} of {b}")

func ExceptionLastThreeHoles(name: string, actual: object, a: string, b: int, c: int): ArgumentOutOfRangeException => new ArgumentOutOfRangeException(name, actual, $"{a} of {b}..{c}")

// A source constructor, one overload per position.
func SourceFirst(a: string, b: string, c: string, count: int, inner: Exception?): Framed => new Framed($"{a}-{b}-{c}", count, inner)

func SourceMiddle(a: string, b: string, count: int, inner: Exception?): Framed => new Framed(count, $"{a}-{b}", inner)

func SourceLast(a: string, count: int, inner: Exception?): Framed => new Framed(count, inner, $"<{a}>")

// A referenced generic constructor.
func TupleFirst(a: string, count: int, inner: Exception?): Tuple<string, int, Exception?> => new Tuple<string, int, Exception?>($"{a}!", count, inner)

func TupleMiddle(a: string, b: string, count: int, inner: Exception?): Tuple<int, string, Exception?> => new Tuple<int, string, Exception?>(count, $"{a}+{b}", inner)

func TupleLast(a: string, b: string, c: string, count: int, inner: Exception?): Tuple<int, Exception?, string> => new Tuple<int, Exception?, string>(count, inner, $"{a}{b}{c}")

// Method calls: source free functions, a source instance method, and referenced methods.
func CallFirst(a: string, count: int, inner: Exception?): string => TextFirst($"[{a}]", count, inner)

func CallMiddle(a: string, b: string, count: int, inner: Exception?): string => TextMiddle(count, $"[{a}/{b}]", inner)

func CallLast(a: string, b: string, c: string, count: int, inner: Exception?): string => TextLast(count, inner, $"[{a}/{b}/{c}]")

func InstanceFirst(framed: Framed, a: string, b: string, count: int): string => framed.Describe($"{a}.{b}", count)

func ReferencedStaticFirst(a: string, b: string, c: string, inner: Exception): string => string.Format($"{a} {b} {c} {{0}}", inner.Message)

func ReferencedInstanceLast(a: string, b: string, index: int): string => new StringBuilder("ab").Insert(index, $"({a}{b})").ToString()

func ReferencedStaticMiddle(a: string, parts: string[]): string => string.Join($"<{a}>", parts, 0, parts.Length)
