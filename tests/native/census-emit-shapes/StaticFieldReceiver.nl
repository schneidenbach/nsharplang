namespace NSharpLang.CensusEmitShapes.Tests

import System.Collections.Generic


// A BARE STATIC FIELD IS A VALUE RECEIVER, NOT A TYPE NAME. `Entries.Add(name)` inside the declaring
// type reads the field and calls a member on it; the call door used to ask only whether the name was
// an INSTANCE member before deciding it must be a type, so a static-field receiver went to the
// static-call door as a type called `Entries` and declined at `emit.expression-statement.call` — even
// though the bare READ of the same field emits `ldsfld`. Both statement position and expression
// position are exercised, from a static and from an instance body.
class Registry {
    static readonly Entries: List<string> = new List<string>()
    static readonly Counts: Dictionary<string, int> = new Dictionary<string, int>()

    Label: string = "registry"

    static func Record(name: string) {
        Entries.Add(name)
    }

    static func RecordCount(name: string, count: int) {
        Counts[name] = count
    }

    static func Total(): int {
        return Entries.Count
    }

    static func Joined(): string {
        return string.Join(",", Entries)
    }

    static func Reset() {
        Entries.Clear()
        Counts.Clear()
    }

    // The same receiver read from an INSTANCE body: a static member is in scope wherever the type's
    // own code is.
    func Describe(): string {
        return Label + ":" + Entries.Count as string
    }
}
