namespace NSharpLang.CensusConversions.Tests

import System
import System.Threading.Tasks


// A BOXED VALUE TYPE THAT A REFERENCED ASSEMBLY DECLARES, READ BACK OUT OF AN `object`.
//
// `MethodInfo.Invoke` returns `object?`, so every reflective caller whose callee returns a struct
// meets this shape; the census filed it as "an `object` holding a `ValueTask` cannot be unboxed",
// and it is not about `ValueTask`. `TryEmitCastConversion` had an arm for a struct THIS compilation
// writes (`unbox.any` on its `TypeBuilder`) and an arm for the scalars, and nothing in between — so
// `DateTime`, `TimeSpan`, `ValueTask` and every other externally declared value type fell past
// every arm. `as T?` was refused a step earlier, by the type-test target rule.
struct SourcePoint {
    X: int
    Y: int
}

func BoxedExternalThroughCast(value: object?): int {
    if value is DateTime {
        moment := (DateTime)value
        return moment.Year
    }
    return -1
}

func BoxedExternalThroughBinding(value: object?): int {
    if value is DateTime moment {
        return moment.Month
    }
    return -1
}

func BoxedExternalThroughInterfaceSource(value: IComparable?): int {
    if value == null {
        return -1
    }
    moment := (DateTime)value
    return moment.Day
}

func BoxedSourceStructThroughCast(value: object?): int {
    if value is SourcePoint {
        point := (SourcePoint)value
        return point.X
    }
    return -1
}

func BoxedExternalAsNullable(value: object?): int {
    moment: DateTime? = value as DateTime?
    if moment == null {
        return -1
    }
    return moment.Hour
}

// The shape the census entry actually wrote: a reflective invocation whose result is a `ValueTask`.
func AwaitReflectedValueTask(): bool {
    method := typeof(BoxedValueTypeSource).GetMethod("Pending")
    if method == null {
        return false
    }
    result := method.Invoke(null, new object[](0))
    if result is ValueTask pending {
        pending.AsTask().Wait()
        return true
    }
    return false
}

class BoxedValueTypeSource {
    static func Pending(): ValueTask {
        return new ValueTask(Task.CompletedTask)
    }
}
