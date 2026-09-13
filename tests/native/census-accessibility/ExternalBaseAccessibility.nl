namespace NSharpLang.CensusAccessibility.Tests

import System.Collections.ObjectModel
import System.IO


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
