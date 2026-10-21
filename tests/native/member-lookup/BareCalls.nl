namespace NSharpLang.MemberLookup.Tests

import System.Linq

// A BARE CALL THAT OMITS A DEFAULTED PARAMETER (GitHub #238). `Svc.Show(a)` and a call from `main`
// filled the default; the same call written without a qualifier inside the declaring type did not.
class Svc {
    Prefix: string

    constructor(prefix: string) {
        Prefix = prefix
    }

    static func Show(a: string, b: string = "-"): string => a + b

    static func Twice(a: string): string => Show(a) + Show(a, "!")

    static func Qualified(a: string): string => Svc.Show(a)

    static func Many(a: string, b: string = "B", c: int = 3): string => a + b + c.ToString()

    static func SkipMiddle(a: string): string => Many(a, c: 9)

    static func AllDefaults(a: string): string => Many(a)

    static func Named(a: string): string => Show(a, b: "n")

    func Tag(a: string, suffix: string = "."): string => Prefix + a + suffix

    func Both(a: string): string => Tag(a) + Tag(a, "!") + this.Tag(a)

    func FromInstance(a: string): string => Show(a)

    func Mapped(items: string[]): string[] => items.Select(item => Tag(item)).ToArray()

    func Order(first: string, second: string = "2"): string => Tag(first + second)

    func Chain(a: string): string => Order(a)
}

class Box<T> {
    Label: string

    constructor(label: string) {
        Label = label
    }

    func Render(value: T, mark: string = "!"): string => Label + ":" + value.ToString() + mark

    func Run(value: T): string => Render(value)

    static func Wrap(value: T, label: string = "box"): string => label + "/" + value.ToString()

    static func Make(value: T): string => Wrap(value)
}

// Overloads where one needs a default: the exact-arity overload must keep winning.
class Overloaded {
    static func Pick(a: int): string => "one" + a.ToString()

    static func Pick(a: int, b: int = 0): string => "two" + (a + b).ToString()

    static func Call(): string => Pick(1)

    static func CallWide(): string => Pick(1, 2)

    static func Fill(a: string, b: int = 5): string => a + b.ToString()

    static func Fill(a: int, b: int = 6): string => "int" + a.ToString() + b.ToString()

    static func CallFill(): string => Fill("s") + Fill(7)
}

// Conversion quality precedes the tie-break for omitted optional parameters, as in C#'s
// BetterFunctionMember rule: the exact-arity object overload must lose to the string overload.
class BetterOptionalOverload {
    static func Pick(value: object): string => "object:" + (value.ToString() ?? "")

    static func Pick(value: string, suffix: string = ""): string => "string:" + value + suffix

    static func Call(): string => Pick("x")

    static func CallNamed(): string => Pick(value: "named")
}

func freeShow(a: string, b: string = "-"): string => a + b

func freeTwice(a: string): string => freeShow(a) + freeShow(a, "!")
