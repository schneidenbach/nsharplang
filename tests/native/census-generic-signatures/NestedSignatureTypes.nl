namespace NSharpLang.CensusGenericSignatures

import System
import System.Collections.Concurrent
import System.Collections.Generic

// A SOURCE TYPE IS A GENERIC ARGUMENT WHEREVER IT IS DECLARED, INCLUDING INSIDE ITS OWNER.
//
// Every generic below closes over `Cached`, which is `private` and NESTED: the name is visible only
// to the lexical scope that declares it, so nothing at file or import scope can answer it. The
// spellings are written exactly as a reader would write them — bare `Cached`, never `Snapshots.Cached`
// — in a field, a property, a parameter, a return, a local annotation, a `new` expression, an array,
// a nullable, a tuple and a nested generic. Two of the heads (`ConcurrentDictionary`, `Lazy`) are
// deliberately NOT in any modelled-collection table, so they take the general external-construction
// arm and prove the lexical scope reaches it too.
class Snapshots {
    readonly byStamp: ConcurrentDictionary<string, Cached> = new ConcurrentDictionary<string, Cached>()
    readonly ordered: List<Cached> = new List<Cached>()
    readonly grouped: Dictionary<string, List<Cached>> = new Dictionary<string, List<Cached>>()
    readonly batches: Dictionary<string, Cached[]> = new Dictionary<string, Cached[]>()

    Count: int => ordered.Count

    func Add(stamp: string, note: string): Cached {
        entry := new Cached(stamp, note)
        byStamp[stamp] = entry
        ordered.Add(entry)
        return entry
    }

    func AddBatch(key: string, entries: Cached[]) {
        batches[key] = entries
    }

    func BatchSize(key: string): int {
        found: Cached[] = null
        if batches.TryGetValue(key, out found) {
            return found.Length
        }
        return 0
    }

    func Group(key: string, entries: List<Cached>) {
        grouped[key] = entries
    }

    func GroupedNote(key: string, index: int): string {
        entries: List<Cached> = null
        if grouped.TryGetValue(key, out entries) {
            return entries[index].Note
        }
        return ""
    }

    // The constructed type's members are reachable afterwards: `out cached` is typed by the nested
    // declaration the instantiation closed over.
    func NoteFor(stamp: string): string {
        cached: Cached = null
        if byStamp.TryGetValue(stamp, out cached) {
            return cached.Note
        }
        return ""
    }

    func Newest(): Cached {
        recent := new List<Cached>()
        for entry in ordered {
            recent.Add(entry)
        }
        return recent[recent.Count - 1]
    }

    func Labelled(): (Head: Cached, Size: int) {
        return (ordered[0], ordered.Count)
    }

    private sealed record Cached(Stamp: string, Note: string) {
    }
}

// THE SAME NAME AT TWO LEXICAL DEPTHS. `Leaf` inside `Mid` names `Deep.Mid.Leaf`; the owner walk
// climbs through every enclosing declaration, and the outer class names the same type by its
// qualified spelling. Both must select the identical CLR type.
class Deep {
    readonly outer: List<Mid.Leaf> = new List<Mid.Leaf>()

    func Add(value: int) {
        outer.Add(new Mid.Leaf(value))
    }

    func Sum(): int {
        total := 0
        for leaf in outer {
            total += leaf.Value
        }
        return total
    }

    class Mid {
        readonly inner: ConcurrentDictionary<string, Leaf> = new ConcurrentDictionary<string, Leaf>()
        readonly lazily: Lazy<Leaf> = new Lazy<Leaf>()

        func Put(key: string, value: int) {
            inner[key] = new Leaf(value)
        }

        func Get(key: string): int {
            found: Leaf = null
            if inner.TryGetValue(key, out found) {
                return found.Value
            }
            return -1
        }

        func LazyValue(): int {
            return lazily.Value.Value
        }

        sealed record Leaf(Value: int) {
            constructor() {
                this.Value = 0
            }
        }
    }
}
