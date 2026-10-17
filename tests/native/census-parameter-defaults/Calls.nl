namespace NSharpLang.CensusParameterDefaults.Tests

// Every call here OMITS the defaulted argument, so the value each returns is the default the
// call site filled in from a declaration in another file.
func omittedLong(): long {
    return longDefault()
}

func omittedNegativeLong(): long {
    return negativeLongDefault()
}

func omittedAdoptedLong(): long {
    return adoptedLongDefault()
}

func omittedByte(): byte {
    return byteDefault()
}

func omittedSByte(): sbyte {
    return sbyteDefault()
}

func omittedShort(): short {
    return shortDefault()
}

func omittedUShort(): ushort {
    return ushortDefault()
}

func omittedUInt(): uint {
    return uintDefault()
}

func omittedULong(): ulong {
    return ulongDefault()
}

func omittedNegativeInt(): int {
    return negativeIntDefault()
}

func omittedHexInt(): int {
    return hexIntDefault()
}

func omittedChar(): char {
    return charDefault()
}

func omittedEscapedChar(): char {
    return escapedCharDefault()
}

func omittedFloat(): float {
    return floatDefault()
}

func omittedDouble(): double {
    return doubleDefault()
}

func omittedNegativeDouble(): double {
    return negativeDoubleDefault()
}

func omittedIntegerDouble(): double {
    return integerDoubleDefault()
}

func omittedDecimal(): decimal {
    return decimalDefault()
}

func omittedNegativeDecimal(): decimal {
    return negativeDecimalDefault()
}

func omittedNullableInt(): string {
    return nullableIntDefault()
}

func omittedNullableValue(): int {
    return nullableValueDefault()
}

func omittedNullableDecimal(): decimal {
    return nullableDecimalDefault()
}

func omittedDate(): long {
    return dateDefault()
}

func omittedIntZero(): int {
    return intZeroDefault()
}

func omittedDecimalZero(): decimal {
    return decimalZeroDefault()
}

func omittedEnumZero(): Level {
    return enumZeroDefault()
}

func omittedStructZero(): int {
    return structZeroDefault()
}

func omittedStringNull(): string {
    return stringNullDefault()
}

func omittedNullableDate(): string {
    return nullableDateDefault()
}

func omittedConstructor(): Meter {
    return new Meter()
}

func omittedConstructorTail(): Meter {
    return new Meter(1L, 2m)
}

func omittedNamedConstructor(): Meter {
    return new Meter(mark: 'x')
}

func omittedMethodFactor(): double {
    return new Meter().Factor()
}

func omittedMethodOffset(): decimal {
    return new Meter().Offset()
}

func omittedStaticMethod(): bool {
    return Meter.Pick()
}

func omittedStructConstructor(): Gauge {
    return new Gauge()
}

func omittedPrimaryConstructor(): Window {
    return new Window()
}
