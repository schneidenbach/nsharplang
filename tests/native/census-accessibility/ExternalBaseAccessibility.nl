namespace NSharpLang.CensusAccessibility.Tests

import System.Collections.ObjectModel


// WHAT A SOURCE TYPE INHERITS FROM AN EXTERNAL BASE INCLUDES ITS `protected` SURFACE.
//
// `Collection<T>` is designed to be extended through `SetItem`, `ClearItems`, `InsertItem` and
// `RemoveItem` — all `protected virtual` — and a source type that derived from it could not NAME any
// of them: metadata resolution asked for `BindingFlags.Public` only, so the analyzer answered NL303
// / NL412, and the emitter's candidate enumeration was public-only too.
//
// `Collection<string>` is a GENERIC external base and `StringWriter` is a plain one, so both shapes
// of the inherited-base walk are exercised.
class GuardedCollection: Collection<string> {
    func ReplaceThroughThis(index: int, item: string) {
        this.SetItem(index, item)
    }

    // THE SAME MEMBER NAMED WITH NO RECEIVER AT ALL. A bare name is `this.Name`, so this is the call
    // above written the other way — and it declined, because the bare-call entry gate enumerated the
    // base's PUBLIC methods only and bailed out before the arm that would have selected a `protected`
    // one ever ran.
    func ReplaceWithoutReceiver(index: int, item: string) {
        SetItem(index, item)
    }

    func InsertThroughBase(index: int, item: string) {
        base.InsertItem(index, item)
    }

    func ClearThroughBase() {
        base.ClearItems()
    }
}

// The same rule over a NON-GENERIC external base.
class LineAwareWriter: StringWriter {
    func ReleaseThroughThis() {
        this.Dispose(true)
    }

    func ReleaseThroughBase() {
        base.Dispose(true)
    }
}

// READING WHAT THE EXTERNAL BASE DECLARES, AT EVERY LEVEL A DERIVED TYPE MAY REACH AND AT EVERY
// RESULT TYPE.
//
// Calling an inherited `protected` method already worked; READING an inherited member did not, and
// it was not the accessibility that stopped it. The `this.`/bare-name read path selected a PUBLIC
// PROPERTY whose result type was on a modelled-value list, so three independent facts each declined
// the read on their own: `protected` (`Items`), being a FIELD rather than a property
// (`CoreNewLine`), and a result type off the list (`IList<string>`, `char[]`) — the last of which
// declined PUBLIC members too. An inherited external member is read by ordinary resolution now, at
// any result type the backend can hold.
class ReadingCollection: Collection<string> {

    // `Collection<T>.Items` is `protected` and typed `IList<T>` — two of the three.
    func ItemCountThroughThis(): int {
        return this.Items.Count
    }

    func ItemCountThroughBase(): int {
        return base.Items.Count
    }

    // ...and the same member named with no receiver at all, which IS `this.Items`.
    func FirstItem(): string? {
        return Items[0]
    }
}

// `TextWriter.CoreNewLine` is a `protected` FIELD typed `char[]`: storage rather than a property,
// and an array result.
class ReadingWriter: StringWriter {
    func NewLineLengthThroughThis(): int {
        return this.CoreNewLine.Length
    }

    func NewLineLengthThroughBase(): int {
        return base.CoreNewLine.Length
    }

    func NewLineFirst(): char {
        return CoreNewLine[0]
    }

    // The read is the base's own STORAGE, not a snapshot: writing the base's `NewLine` property
    // replaces the very array the two reads above address.
    func UseBangTerminator() {
        this.NewLine = "!"
    }
}
