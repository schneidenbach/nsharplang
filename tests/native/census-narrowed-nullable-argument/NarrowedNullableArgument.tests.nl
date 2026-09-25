namespace NSharpLang.CensusNarrowedNullableArgument.Tests

test "the reported shape compiles without the unwrap and agrees with it" {
    assert Facts.IsCallableSymbol(SymbolKind.Method)
    assert !Facts.IsCallableSymbol(SymbolKind.Field)
    assert !Facts.IsCallableSymbol(null)
    assert Facts.IsCallableSymbolUnwrapped(SymbolKind.Method) == Facts.IsCallableSymbol(SymbolKind.Method)
    assert Facts.IsCallableSymbolUnwrapped(SymbolKind.Field) == Facts.IsCallableSymbol(SymbolKind.Field)
}

test "a narrowed nullable reaches a source static declared over the bare type" {
    assert Facts.TwiceOrZero(4) == 8
    assert Facts.TwiceOrZero(null) == 0
}

test "the same argument reaches an external static and an external generic instance method" {
    assert Facts.ClampedOrZero(4) == 4
    assert Facts.ClampedOrZero(99) == 10
    assert Facts.ClampedOrZero(null) == 0
    assert Facts.HashOrZero(4) != Facts.HashOrZero(5)
    assert Facts.HashOrZero(null) == 0
}

test "a parameter that is itself nullable still takes the narrowed name" {
    assert Facts.PassThroughNullable(4) == 1
    assert Facts.PassThroughNullable(null) == 0
}

test "the positions that never selected on argument types still emit" {
    assert Facts.ReturnedDirectly(7) == 7
    assert Facts.TypedLocal(7) == 7
    assert Facts.Doubled(7) == 14
    assert Facts.ReturnedDirectly(null) == 0
}

test "the narrowed argument is read once, before the argument written after it" {
    reader := new Reader()
    assert reader.Run() == 15
    assert reader.Reads.Count == 2
    assert reader.Reads[0] == "value"
    assert reader.Reads[1] == "ceiling"
}
