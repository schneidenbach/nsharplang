namespace NSharpLang.CensusConversions.Tests

import System

test "an EXTERNAL value type is unboxed out of an object by a written cast" {
    moment := new DateTime(2021, 5, 6, 7, 0, 0)

    assert BoxedExternalThroughCast(moment) == 2021
    assert BoxedExternalThroughCast("not a date") == -1
}

test "the same value reaches its members through an `is` binding" {
    moment := new DateTime(2021, 5, 6, 7, 0, 0)

    assert BoxedExternalThroughBinding(moment) == 5
    assert BoxedExternalThroughBinding(12) == -1
}

test "an INTERFACE the boxed type implements is a legal source for the unbox" {
    moment := new DateTime(2021, 5, 6, 7, 0, 0)

    assert BoxedExternalThroughInterfaceSource(moment) == 6
}

test "a SOURCE struct unboxes the same way it always did" {
    point := new SourcePoint()
    point.X = 9

    assert BoxedSourceStructThroughCast(point) == 9
    assert BoxedSourceStructThroughCast("no") == -1
}

test "`as T?` answers the value on a match and the empty nullable on a miss" {
    moment := new DateTime(2021, 5, 6, 7, 0, 0)

    assert BoxedExternalAsNullable(moment) == 7
    // A MISS IS NOT A THROW. `isinst` replaces the mismatch with null and `unbox.any Nullable<T>`
    // reads null as the empty value, which is the whole of what `as` promises over a value type.
    assert BoxedExternalAsNullable("not a date") == -1
    assert BoxedExternalAsNullable(null) == -1
}

test "a reflective invocation whose callee returns a ValueTask is reachable" {
    assert AwaitReflectedValueTask()
}
