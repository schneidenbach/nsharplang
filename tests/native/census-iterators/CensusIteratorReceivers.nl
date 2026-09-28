namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic


// A BARE `this` INSIDE A GENERATOR BODY.
//
// Argument 0 of a generator's `MoveNext` is its state machine, never the object the source wrote
// `this` about. An instance generator keeps that object in a field of the machine (`<>__this`), so
// `this` as a value, as an argument and as a yielded element all read that field — the same owner
// that lowers `this` in an ordinary member body, which reads argument 0 itself.
func DescribeReceiver(widget: ReceiverWidget): string {
    return "widget " + widget.Tag
}

class ReceiverWidget {
    Tag: string = "t"

    func Same(other: ReceiverWidget): bool {
        return other == this
    }

    // `this` as an argument to a free function.
    func* Described(): IEnumerable<string> {
        yield DescribeReceiver(this)
    }

    // `this` as the yielded element itself.
    func* Selves(): IEnumerable<ReceiverWidget> {
        yield this
        yield this
    }

    // `this` as an argument to another receiver's method and to a BCL instance call.
    func* Recognized(other: ReceiverWidget): IEnumerable<bool> {
        yield other.Same(this)
        seen := new List<ReceiverWidget>()
        seen.Add(this)
        yield seen.Contains(this)
    }

    // `this.Member` is a member of the object, read through the captured receiver, and a member
    // access continues from it.
    func* TagLengths(): IEnumerable<int> {
        yield this.Tag.Length
        Tag = "longer"
        yield this.Tag.Length
    }

    // A lambda lowered onto the machine reaches `this` through the same captured receiver.
    func* Deferred(): IEnumerable<string> {
        describe: Func<string> = () => DescribeReceiver(this)
        yield describe()
    }

    // A per-iteration display keeps its own copy of the receiver beside the machine.
    func* PerIteration(): IEnumerable<Func<string>> {
        for n in [1, 2] {
            yield () => DescribeReceiver(this) + n.ToString()
        }
    }

    // Ordinary member bodies take the same owner, reading argument 0 itself.
    func Itself(): ReceiverWidget {
        return this
    }

    func DescribedNow(): string {
        me := this
        return DescribeReceiver(me)
    }

    func DescribedLater(): Func<string> {
        return () => DescribeReceiver(this)
    }

    func DescribedTwoLambdasDeep(): Func<Func<string>> {
        return () => () => DescribeReceiver(this)
    }
}

// A STRUCT'S `this` IS A COPY. Its generator captures the instance by value when it is called, and an
// ordinary body's `this` is the value argument 0 points at, so writing the copy never writes the
// receiver.
struct ReceiverPoint {
    X: int

    func* Selves(): IEnumerable<ReceiverPoint> {
        yield this
    }

    func* Xs(): IEnumerable<int> {
        yield X
        yield this.X
    }

    func Copied(): ReceiverPoint {
        return this
    }

    func BumpedCopy(): int {
        copy := this
        copy.X = copy.X + 1
        return X * 100 + copy.X
    }
}
