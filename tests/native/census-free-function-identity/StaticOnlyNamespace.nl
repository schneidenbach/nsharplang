namespace Census.FreeFunctionIdentity.StaticOnly

import System


// A NAMESPACE WHOSE ONLY LAMBDAS ARE IN STATIC BODIES.
//
// `TypesOnly` beside this file covers the INSTANCE bodies. This one covers the static ones, and
// they were a different answer: the placement decision read the emitter's INSTANCE-context marker,
// which is null in a static method, a static field initializer and a `.cctor` alike, so every
// lambda written in one was treated as FILE LEVEL and lowered onto the namespace's `Program`
// holder. Resolving that holder is what defines it, so a namespace that declares no free function
// at all acquired a public `Program` for owning nothing but lowered lambdas.
//
// That is not a cosmetic surplus type. `NSharpLang.Cli.Program` and `NSharpLang.Cli.Commands.Program`
// in the emitted `Compiler` assembly each held exactly two such lambdas and nothing else, and the
// first of them is what made `src/NSharpLang.Cli/Program.cs` — a C# file in the same namespace —
// warn CS0436 against its own compiler on every build. Two referenced assemblies in that state make
// the name unusable outright (CS0433).
//
// A lambda in a static body belongs to the type whose static member is being emitted, and the body
// gains NO instance context by moving there.
class StaticHost {
    static readonly Seeded: Func<int> = () => 41

    static func PlusOne(value: int): int {
        step: Func<int, int> = x => x + 1
        return step(value)
    }

    static func Inferred(value: int): int {
        step := (x: int) => x + Seeded()
        return step(value)
    }

    static func Captured(value: int): int {
        captured := Seeded()
        step: Func<int, int> = x => x + captured
        return step(value)
    }
}
