namespace Census.FreeFunctionIdentity.MemberShadow

import System
import System.Collections.Generic


// A MEMBER OF THE ENCLOSING TYPE HIDES A FREE FUNCTION OF THE SAME NAME.
//
// Inside a type body a bare name is looked up in the type before the namespace, as C# does it: the
// member wins whether the free function sits in this file, in another file of the namespace, or in a
// referenced assembly, and whether the member is the type's own or inherited. The emitter used to ask
// its sibling table first, so `Direct()` below called the free `Label` and returned its value while
// `check` — which binds the member — reported nothing.
//
// EVERY FREE FUNCTION HERE RETURNS AN `int` AND NO MEMBER OF ITS NAME DOES. A body that bound the
// free function would not type-check, so the analyzer's half of the rule is held at compile time and the
// emitter's half by the values the rows read.
//
// `Label`, `Kind` and `Contains` are declared in THIS file on purpose: the analyzer's scope stack holds
// a file's own free functions in its global scope, which it walks before it asks the enclosing type
// for an INHERITED member, so a same-file free function beat an inherited one there — `Inherited()`
// and `HasFirst()` below were NL202 until the two were ordered.
func Label(): int => 1

func Kind(): int => 2

func Contains(item: string): int => item.Length

// A lambda written in a FREE function has no type around it, so nothing hides the free function.
func LabelFromFreeLambda(): int {
    read := () => Label()
    return read()
}

class ShadowBase {
    func Kind(): string => "base member"
}

class Shadowing: ShadowBase {
    Pick: Func<string>
    fromConstructor: string

    constructor() {
        Pick = () => "delegate member"
        fromConstructor = Label()
    }

    func Label(): string => "member"
    func Title(): string => "cross-file member"
    static func Tag(): string => "static member"

    func Direct(): string => Label()
    func FromConstructor(): string => fromConstructor
    func CrossFile(): string => Title()
    func Inherited(): string => Kind()
    func DelegateField(): string => Pick()
    static func FromStaticBody(): string => Tag()
    func FromInstanceBodyToStatic(): string => Tag()

    func InLambda(): string {
        read := () => Label()
        return read()
    }

    func InNestedLambda(): string {
        outer := () => CallThrough(() => Label())
        return outer()
    }

    func InLocalFunction(): string {
        func local(): string => Label()
        return local()
    }

    func AsMethodGroup(): string {
        read: Func<string> = Label
        return read()
    }
}

struct ShadowingValue {
    Seed: int

    func Label(): string => "struct member"
    func Direct(): string => Label()
}

// An EXTERNAL base's members hide too: `Contains` is `List<string>.Contains`, not the free `int` one.
class ShadowingNames: List<string> {
    func HasFirst(): bool => Contains("first")
}
