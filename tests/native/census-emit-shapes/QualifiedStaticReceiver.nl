namespace NSharpLang.CensusEmitShapes.Tests

import System.Collections.Generic
import System.Linq


// A RECEIVER THAT NAMES A TYPE IS A STATIC RECEIVER, WHATEVER ITS SPELLING.
//
// Only a BARE identifier in front of a `.` was read as a possible type name, so the same static
// call written with the type's namespace in front of it had no static arm at all: it fell through
// to the instance arm, which tried to put `System.IO` on the stack and declined the whole statement
// at `emit.call.receiver` — a sentence about the RECEIVER, when nothing about the receiver was
// unsupported. The imported spelling of the identical call emitted, which is what made the
// misclassification visible.
//
// The second half of the same story is the ARGUMENT. `Directory.CreateDirectory(must p)` emitted
// and the qualified spelling did not, because a `must` unwrap had no PREFLIGHT type: overload
// resolution could not see what the argument produced, so the call fell past the scoring tier even
// once the receiver was classified. A `must` is a null assert, not a conversion — it produces its
// operand's type, and a `Nullable<T>` operand produces `T`.
class QualifiedStatics {

    // The census reproduction, exactly: a fully-qualified static receiver and a `must`-unwrapped
    // argument in the same call.
    static func MakeDirectory(path: string?): string {
        System.IO.Directory.CreateDirectory(must path)
        return path
    }

    static func DirectoryExists(path: string?): bool {
        return System.IO.Directory.Exists(must path)
    }

    static func DeleteDirectory(path: string?) {
        System.IO.Directory.Delete(must path)
    }

    // The same receiver with an argument that is neither a bare name nor a `must`.
    static func Joined(left: string, right: string): string {
        return System.String.Concat(left + "-", right)
    }

    // A `must` argument at a site with SEVERAL arity-1 declarations: the preflight type is what
    // chooses `WriteLine(string)` over `WriteLine(object)` and the rest.
    static func Describe(value: string?): string {
        return System.String.Concat("<", must value, ">")
    }

    // `must` over a `Nullable<T>` unwraps to `T`, and `T` is what picks the overload: `Math.Max`
    // declares `(int, int)`, `(long, long)`, `(double, double)` and more at the same arity.
    static func LargerInt(value: int?): int {
        return System.Math.Max(must value, 3)
    }

    static func LargerDouble(value: double?): double {
        return System.Math.Max(must value, 3.5)
    }

    // A qualified GENERIC static, with its type argument written out.
    static func EmptyInts(): int[] {
        return System.Linq.Enumerable.ToArray<int>(System.Linq.Enumerable.Empty<int>())
    }

    static func CountQualified(values: List<int>): int {
        return System.Linq.Enumerable.Count<int>(values)
    }
}

// The same rule for a type THIS compilation declares: its namespace-qualified spelling is a type
// name too, and the static it owns is reached through it.
class QualifiedHelper {
    static func Doubled(value: int): int {
        return value * 2
    }
}

class QualifiedHelperCaller {
    static func Through(value: int): int {
        return NSharpLang.CensusEmitShapes.Tests.QualifiedHelper.Doubled(value)
    }
}

// A HOP IN A RECEIVER CHAIN IS AN ORDINARY MEMBER READ.
//
// A generic extension call re-resolves its receiver name by name, and each hop was answered by a
// hand-written table of BCL properties. Every OTHER readable member a referenced assembly declares
// was therefore unreachable through a chain: `d.Values.OfType<string>()` declined at
// `emit.call.generic-unresolved` while `values := d.Values` followed by `values.OfType<string>()` —
// the same two reads, one of them stored in a local — emitted.
class ChainedGenericExtensions {
    Entries: Dictionary<string, object> = new Dictionary<string, object>()

    func Add(key: string, value: object): ChainedGenericExtensions {
        Entries[key] = value
        return this
    }

    func StringValueCount(): int {
        return Entries.Values.OfType<string>().Count()
    }

    func KeyCount(): int {
        return Entries.Keys.OfType<string>().Count()
    }
}

class ChainedGenericExtensionCallers {
    static func ValuesThroughParameter(source: Dictionary<string, object>): int {
        return source.Values.OfType<string>().Count()
    }

    static func KeysThroughParameter(source: Dictionary<string, object>): int {
        return source.Keys.Cast<string>().Count()
    }

    // The chain that already emitted, kept beside the ones that did not: the answer must be the
    // same whether the hop is stored in a local or written inline.
    static func ValuesThroughLocal(source: Dictionary<string, object>): int {
        values := source.Values
        return values.OfType<string>().Count()
    }

    // A hop through a SOURCE type's own property, then a hop through an external one.
    static func ThroughSourceOwner(owner: ChainedGenericExtensions): int {
        return owner.Entries.Values.OfType<string>().Count()
    }
}
