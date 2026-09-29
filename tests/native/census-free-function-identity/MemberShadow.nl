namespace Census.FreeFunctionIdentity.MemberShadow

import System
import System.Collections.Generic


// MEMBER CALLS THAT SHARE A NAME WITH FREE FUNCTIONS SAY `this.` EXPLICITLY.
//
// Inside a type, a same-name bare member/free-function use is NL209. These execution rows spell
// member uses with `this.` so they keep the old member behavior without relying on implicit hiding.
//
// These functions keep same-file free groups present beside the member examples below.
//
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
        this.Pick = () => "delegate member"
        fromConstructor = this.Label()
    }

    func Label(): string => "member"
    func Title(): string => "cross-file member"
    static func Tag(): string => "static member"

    func Direct(): string => this.Label()
    func SameNamespaceFreeFunction(): int => Census.FreeFunctionIdentity.MemberShadow.Label()
    func FromConstructor(): string => fromConstructor
    func CrossFile(): string => this.Title()
    func Inherited(): string => this.Kind()
    func DelegateField(): string => this.Pick()
    static func FromStaticBody(): string => Shadowing.Tag()
    func FromInstanceBodyToStatic(): string => Shadowing.Tag()

    func InLambda(): string {
        read := () => this.Label()
        return read()
    }

    func InNestedLambda(): string {
        outer := () => CallThrough(() => this.Label())
        return outer()
    }

    func InLocalFunction(): string {
        func local(): string => this.Label()
        return local()
    }

    func AsMethodGroup(): string {
        read: Func<string> = this.Label
        return read()
    }

    // A member GENERATOR runs on a state machine that holds this instance in a field, so member calls
    // use explicit receiver spellings just like ordinary member bodies.
    func* InIterator(): IEnumerable<string> {
        yield this.Label()
        yield this.Title()
        yield Shadowing.Tag()
        yield this.Kind()
    }
}

struct ShadowingValue {
    Seed: int

    func Label(): string => "struct member"
    func Direct(): string => this.Label()

    func* InIterator(): IEnumerable<string> {
        yield this.Label()
    }
}

// An EXTERNAL base's member shares the name; `this.` selects `List<string>.Contains` explicitly.
class ShadowingNames: List<string> {
    func HasFirst(): bool => this.Contains("first")

    func* Presence(): IEnumerable<bool> {
        yield this.Contains("first")
    }
}
