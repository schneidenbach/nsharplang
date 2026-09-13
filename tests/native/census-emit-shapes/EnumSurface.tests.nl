namespace NSharpLang.CensusEmitShapes.Tests


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

test "a source enum converts to its underlying value, exactly as a reflected enum does" {
    assert AccessOrdinal(Access.None) == 0
    assert AccessOrdinal(Access.Read) == 1
    assert AccessOrdinal(Access.All) == 3
    assert AccessOrdinalWide(Access.Write) == 2L
    assert ExternalOrdinal(DayOfWeek.Wednesday) == 3
}

test "the emitted enum really derives from System.Enum and carries an Int32 underlying type" {
    enumType := typeof(Access)
    assert enumType.IsEnum
    assert enumType.BaseType == typeof(Enum)
    assert Enum.GetUnderlyingType(enumType) == typeof(int)
}
