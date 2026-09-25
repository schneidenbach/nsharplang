namespace NSharpLang.CensusEmitShapes.Tests

import System

test "a source enum's ToString is System.Enum's, so it is a non-null string and reads the member name" {
    assert AccessName(Access.Read) == "Read"
    assert AccessName(Access.None) == "None"
    assert AccessNameLowered(Access.Write) == "write"
}

test "a source enum inherits HasFlag from System.Enum and agrees with the bitwise spelling" {
    assert AccessHasFlag(Access.All, Access.Read)
    assert AccessHasFlag(Access.All, Access.Write)
    assert !AccessHasFlag(Access.Read, Access.Write)
    assert AccessHasFlagByMask(Access.All, Access.Read)
    assert AccessHasFlagByMask(Access.All, Access.Write)
    assert !AccessHasFlagByMask(Access.Read, Access.Write)
}

test "a source enum inherits GetTypeCode, which reports its i4 underlying type" {
    assert AccessTypeCode(Access.Read) == TypeCode.Int32
}

test "bitwise or over two source enum values keeps the enum type" {
    assert AccessCombined(Access.Read, Access.Write) == Access.All
    assert AccessCombined(Access.None, Access.Read) == Access.Read
}

test "a reflected enum member reads in ordinary position and converts to its underlying value" {
    assert ExternalOrdinal(DayOfWeek.Wednesday) == 3
    assert IsMidweek(DayOfWeek.Wednesday)
    assert !IsMidweek(DayOfWeek.Monday)
}

test "a reflected enum member reads inside an iterator body, yielded and formatted" {
    days := 0
    for day in Weekend() {
        days = days + 1
    }
    assert days == 2

    ordinals := 0
    for ordinal in WeekdayOrdinals() {
        ordinals = ordinals * 10 + ordinal
    }
    assert ordinals == 15
}

test "the emitted enum really derives from System.Enum and carries an Int32 underlying type" {
    enumType := typeof(Access)
    assert enumType.IsEnum
    assert enumType.BaseType == typeof(Enum)
    assert Enum.GetUnderlyingType(enumType) == typeof(int)
}
