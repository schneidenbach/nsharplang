namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Diagnostics
import System.IO
import System.Reflection
import System.Text
import System.Threading
import System.Threading.Tasks

// THE BCL SURFACE THE COMPILER SPELLS BY HAND, OWNED ONCE.
//
// A canonical name the source wrote — `int`, `nint`, `StringBuilder` — has to become a runtime
// `Type` before anything can be emitted against it, and there is no metadata question that answers
// it: the names are the LANGUAGE's, so the table is the compiler's. Two owners carried the same
// table twice over, arm for arm: `ColumnarCanonicalTypeResolver` and `ColumnarTypeOfPlanner` each
// had a builtin-keyword resolver and a special-known-type resolver, and the only textual difference
// between each pair was what the `out` parameter held on the path that returns FALSE.
//
// That difference is preserved at the call site rather than here, because a caller that reads an
// `out` value after a false return is relying on it. Both wrappers are two lines and say which
// value they leave behind.
//
// WHAT IS NOT HERE, AND WHY. The audit read twenty-three owners of "canonical spelling → BCL type"
// and proposed one catalogue with thin projections. Four of them are projections of one relation
// and are consolidated here. The rest are NOT the same relation with a different codomain: they
// admit different KEY SETS. `ColumnarBindingScopeFacts.TryResolveExplicitBuiltin` admits `object`
// and refuses `IntPtr`, `DateTime`, `Index` and `Range`; its `TryResolveBuiltinOwner` admits
// `Int32` and `System.Int32` but not `nint`; `AnalyzerTypeReferenceFacts` answers a `TypeInfo` (and
// `BuiltInTypeSpellings` a CLR name string) for a third set. Making those one table means a row
// type with per-projection admission rules — a design change with resolution consequences, not a
// deletion — and it is a PR of its own. Stating that here is cheaper than rediscovering it.
static class WellKnownTypeCatalog {

    // ── THE LANGUAGE'S OWN SPELLINGS ──────────────────────────────────────────
    //
    // `object` is deliberately absent: neither owner of this table admitted it, because `object` is
    // resolved earlier on both paths.
    static func TryResolveBuiltinType(canonical: string, out result: Type): bool {
        result = null
        if canonical == "int" {
            result = typeof(int)
        } else if canonical == "long" {
            result = typeof(long)
        } else if canonical == "uint" {
            result = typeof(uint)
        } else if canonical == "ulong" {
            result = typeof(ulong)
        } else if canonical == "short" {
            result = typeof(short)
        } else if canonical == "ushort" {
            result = typeof(ushort)
        } else if canonical == "byte" {
            result = typeof(byte)
        } else if canonical == "sbyte" {
            result = typeof(sbyte)
        } else if canonical == "bool" {
            result = typeof(bool)
        } else if canonical == "char" {
            result = typeof(char)
        } else if canonical == "double" {
            result = typeof(double)
        } else if canonical == "float" {
            result = typeof(float)
        } else if canonical == "decimal" {
            result = typeof(decimal)
        } else if canonical == "string" {
            result = typeof(string)
        } else if canonical == "IntPtr" || canonical == "nint" {
            result = typeof(IntPtr)
        } else if canonical == "UIntPtr" || canonical == "nuint" {
            result = typeof(UIntPtr)
        } else if canonical == "DateTime" {
            result = typeof(DateTime)
        } else if canonical == "Index" {
            result = typeof(Index)
        } else if canonical == "Range" {
            result = typeof(Range)
        } else {
            return false
        }

        return true
    }

    // ── THE BCL TYPES THE COMPILER NAMES DIRECTLY ─────────────────────────────
    //
    // Every arm but one is a `typeof` the emit host can always answer. `IComparable` is the
    // exception: it is reached through `Type.GetType` and may decline, in which case this answers
    // false like any unknown name.
    static func TryResolveSpecialKnownType(canonical: string, out result: Type): bool {
        result = null
        if canonical == "StringBuilder" {
            result = typeof(StringBuilder)
        } else if canonical == "object" {
            result = typeof(object)
        } else if canonical == "StringComparer" {
            result = typeof(StringComparer)
        } else if canonical == "SearchOption" {
            result = typeof(SearchOption)
        } else if canonical == "IList" {
            result = typeof(IList)
        } else if canonical == "Type" {
            result = typeof(Type)
        } else if canonical == "Version" {
            result = typeof(Version)
        } else if canonical == "TimeSpan" {
            result = typeof(TimeSpan)
        } else if canonical == "Random" {
            result = typeof(Random)
        } else if canonical == "Process" {
            result = typeof(Process)
        } else if canonical == "ProcessStartInfo" {
            result = typeof(ProcessStartInfo)
        } else if canonical == "StreamReader" {
            result = typeof(StreamReader)
        } else if canonical == "Stream" {
            result = typeof(Stream)
        } else if canonical == "CancellationToken" {
            result = typeof(CancellationToken)
        } else if canonical == "Task" {
            result = typeof(Task)
        } else if canonical == "ValueTask" {
            result = typeof(ValueTask)
        } else if canonical == "Assembly" {
            result = typeof(Assembly)
        } else {
            return false
        }

        return true
    }

    // The same catalogue plus `IComparable`, which only `typeof` planning ever asked for. The arms
    // are equality tests on distinct names, so admitting one more changes nothing about the others.
    static func TryResolveSpecialKnownTypeOrComparable(canonical: string, out result: Type): bool {
        result = null
        if canonical == "IComparable" {
            comparable := Type.GetType("System.IComparable")
            if comparable == null {
                return false
            }

            result = comparable
            return true
        }

        return TryResolveSpecialKnownType(canonical, out result)
    }
}
