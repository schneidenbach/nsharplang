namespace NSharpLang.SelfHostFrontDoor

import System

// `nameof` NAMES SOMETHING; IT DOES NOT READ IT.
//
// Every spelling below is one the compiler's own source uses to keep a string tied to the member it
// names, so a rename moves both. The front door used to refuse the first two with NL411, "Method 'X'
// must be called or passed to a delegate" -- the value-side rule applied to a position where a value
// was never asked for. 192 of the compiler's own `nameof`s were that diagnostic.
class NameofTargets {
    static func Helper(value: int): int => value + 1

    static func Overloaded(value: int): int => value
    static func Overloaded(value: string): string => value

    Instance: int
    event Changed: Action?

    constructor(instance: int) {
        Instance = instance
    }

    static func StaticMethodName(): string => nameof(NameofTargets.Helper)
    static func QualifiedMethodName(): string => nameof(NSharpLang.SelfHostFrontDoor.NameofTargets.Helper)
    static func OverloadedMethodName(): string => nameof(NameofTargets.Overloaded)
    static func ExternalMethodName(): string => nameof(string.Join)
    static func ValueMemberName(): string => nameof(NameofTargets.Instance)
    static func EventName(): string => nameof(NameofTargets.Changed)
    static func LocalName(): string {
        total := 0
        return nameof(total)
    }
}
