namespace NSharpLang.CensusClosures.Tests

import System
import System.Collections.Generic
import System.Threading.Tasks

// WHERE A DELEGATE LIVES DOES NOT CHANGE HOW IT IS CALLED.
//
// A delegate in a FIELD, a PROPERTY, a local or a parameter is invoked through the same `Invoke` on
// the delegate type, selected by ordinary member resolution. These shapes were reported as declining
// at emit; they are pinned here so the one invoke path stays one path.
class Loader {
    Read: Func<string>
    Transform: Func<string, string>
    Label: string

    constructor(read: Func<string>, transform: Func<string, string>, label: string) {
        Read = read
        Transform = transform
        Label = label
    }

    // Through the implicit receiver.
    func ReadThroughField(): string {
        return Read()
    }

    func TransformThroughField(value: string): string {
        return Transform(value)
    }

    // Through a PROPERTY rather than a field.
    Named: Func<string> {
        get {
            return Read
        }
    }

    func ReadThroughProperty(): string {
        return Named()
    }
}

// Through a WRITTEN receiver, which is the spelling the census reported.
func ReadFrom(loader: Loader): string {
    return loader.Read()
}

func TransformWith(loader: Loader, value: string): string {
    return loader.Transform(value)
}

func ReadFromProperty(loader: Loader): string {
    return loader.Named()
}

// A delegate in a LOCAL and in a PARAMETER, for the comparison the census drew.
func ReadThroughLocal(seed: string): string {
    let read: Func<string> = () => seed + "!"
    return read()
}

func ReadThroughParameter(read: Func<string>): string {
    return read()
}

// PER-ITERATION CAPTURE OF A WRITTEN LOOP BINDING, INSIDE AN ASYNC LAMBDA. Each pass round the loop
// binds a new `acc`; the write lands in that binding; the `Func<Task<int>>` collected there closes
// over its own. An async lambda's display is the same display a synchronous one gets.
func BuildAsyncAdders(count: int): List<Func<Task<int>>> {
    adders := new List<Func<Task<int>>>()
    for i := 0; i < count; i++ {
        acc := i
        acc = acc + 1
        adders.Add(async () => acc * 10)
    }

    return adders
}

// AN ARGUMENT LIST AFTER ANYTHING THAT PRODUCES A DELEGATE IS AN INVOCATION OF THAT DELEGATE, and
// that includes a CALL — `three(1)(2)(3)` is three invocations, each one's callee the previous one's
// result. The emitter's delegate-invoke door asks the preflight what its callee is worth, and the
// preflight had no case for a call node (nor for a delegate-typed binding's own name), so the second
// link declined with `emit.call.callee-kind` naming a node kind.
func Curry(): Func<int, Func<int, Func<int, int>>> {
    return a => b => c => a + b + c
}

func ChainedThroughALocal(): int {
    three := Curry()
    return three(1)(2)(3)
}

func ChainedFromACallResult(): int {
    return Curry()(1)(2)(3)
}

func ChainedThroughAParameter(three: Func<int, Func<int, Func<int, int>>>): int {
    return three(4)(5)(6)
}

// The links CAPTURE, so each one's answer depends on the one before it rather than on a constant.
func ChainedOverACapture(seed: int): int {
    let scale: Func<int, Func<int, int>> = factor => bump => seed * factor + bump
    return scale(3)(1)
}
