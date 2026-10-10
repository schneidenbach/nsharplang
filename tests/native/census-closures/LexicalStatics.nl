namespace NSharpLang.CensusClosures.Tests

import System


// THE LEXICAL OWNER OF A LAMBDA BODY. A lambda written inside a member of `LexicalStaticOwner` is
// still written inside `LexicalStaticOwner`, so that type's own statics — methods, fields and
// properties — are in scope in the lambda body exactly as they are in the member around it. The
// shapes here are deliberately the two that have NO captured receiver to ride on: a lambda in a
// STATIC member, and a lambda in an instance member that captures nothing.
class LexicalStaticOwner {
    static Seed: int = 7
    static Suffix: string = "!"

    Scale: int

    constructor(scale: int) {
        Scale = scale
    }

    static func Bump(value: int): int {
        return value + Seed
    }

    static func Label(value: int): string {
        return value.ToString() + Suffix
    }

    // A non-capturing lambda inside a STATIC member: there is no receiver anywhere, so the bare
    // call can only resolve through the lexical owner.
    static func BumpThroughLambda(value: int): int {
        bump: Func<int, int> = x => Bump(x)
        return bump(value)
    }

    // The same, with a statement body and a bare static FIELD read beside the call.
    static func BumpAndSeedThroughLambda(value: int): int {
        bump: Func<int, int> = x => {
            return Bump(x) + Seed
        }

        return bump(value)
    }

    // A zero-parameter lambda at an inferring position, in a static member.
    static func SeedThroughInferredLambda(): int {
        read := () => Seed
        return read()
    }

    // A lambda inside an INSTANCE member that captures nothing: the display is not built and there
    // is no `<>4__this`, so this is the same anchor question the static member asks.
    func LabelThroughNonCapturingLambda(value: int): string {
        label: Func<int, string> = x => Label(x)
        return label(value)
    }

    // A lambda in an instance member that DOES capture the receiver still reaches both the captured
    // field and the lexical owner's statics.
    func ScaleThroughCapturingLambda(value: int): int {
        scale: Func<int, int> = x => Bump(x) * Scale
        return scale(value)
    }

    // A lambda nested inside another lambda, where the outer one captured the receiver.
    func NestedThroughCapturingLambda(value: int): int {
        outer: Func<int, int> = x => {
            inner: Func<int, int> = y => Bump(y) + Scale
            return inner(x)
        }

        return outer(value)
    }
}
