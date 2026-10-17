namespace NSharpLang.CensusParameterDefaults.Tests

import System
import System.Reflection
import System.Runtime.CompilerServices
import NSharpLang.CensusParameterDefaults.Library

// A DEFAULT IN THIS PROJECT, OMITTED IN ANOTHER FILE. Every value below is the one `Calls.nl` got
// back by leaving its argument out; the declarations are in `Declarations.nl`.
test "an omitted integral default is filled at its parameter's own type" {
    assert omittedLong() == 5000000000L
    assert omittedNegativeLong() == -9000000000L
    assert omittedAdoptedLong() == 42L
    assert omittedByte() == (byte)255
    assert omittedSByte() == (sbyte)-128
    assert omittedShort() == (short)-32768
    assert omittedUShort() == (ushort)65535
    assert omittedUInt() == 4000000000u
    assert omittedULong() == 18446744073709551615UL
    assert omittedNegativeInt() == -2147483648
    assert omittedHexInt() == 127
}

test "an omitted character default is filled" {
    assert omittedChar() == 'z'
    assert omittedEscapedChar() == '\n'
}

test "an omitted floating default is filled" {
    assert omittedFloat() == 1.5f
    assert omittedDouble() == 2.5
    assert omittedNegativeDouble() == -0.125
    assert omittedIntegerDouble() == 3.0
}

test "an omitted decimal default is filled" {
    assert omittedDecimal() == 1.25m
    assert omittedNegativeDecimal() == -0.5m
    assert omittedNullableDecimal() == 2.5m
}

test "an omitted nullable default is filled with no value or with its constant" {
    assert omittedNullableInt() == "none"
    assert omittedNullableValue() == 12
    assert omittedNullableDate() == "none"
}

test "an omitted `default` is the zero value of every kind of type" {
    assert omittedDate() == 0L
    assert omittedIntZero() == 0
    assert omittedDecimalZero() == 0m
    assert omittedEnumZero() == Level.Low
    assert omittedStructZero() == 0
    assert omittedStringNull() == "null"
}

test "an explicit argument still replaces each default" {
    assert longDefault(1L) == 1L
    assert charDefault('a') == 'a'
    assert doubleDefault(0.5) == 0.5
    assert floatDefault(2.0f) == 2.0f
    assert decimalDefault(3m) == 3m
    assert nullableIntDefault(4) == "some"
    assert dateDefault(new DateTime(10L)) == 10L
}

test "a constructor fills every omitted default, and named arguments skip the ones between" {
    meter := omittedConstructor()
    assert meter.Width == 5000000000L
    assert meter.Ratio == 1.25m
    assert meter.Mark == 'm'
    assert meter.Limit == null
    assert meter.Moment.Ticks == 0L

    tail := omittedConstructorTail()
    assert tail.Width == 1L
    assert tail.Ratio == 2m
    assert tail.Mark == 'm'

    named := omittedNamedConstructor()
    assert named.Width == 5000000000L
    assert named.Mark == 'x'
    assert named.Limit == null
}

test "instance and static methods fill their omitted defaults" {
    assert omittedMethodFactor() == 0.5
    assert omittedMethodOffset() == 10m
    assert omittedStaticMethod()
}

test "a struct constructor and a primary constructor fill their omitted defaults" {
    gauge := omittedStructConstructor()
    assert gauge.Scale == -1.5
    assert gauge.Extra == 7u

    window := omittedPrimaryConstructor()
    assert window.Width() == 640L
    assert window.Ratio() == 1.5m
    assert window.Title() == 'w'
}

test "a default omitted in the test file itself is filled the same way" {
    direct := new Meter(limit: 3)
    assert direct.Width == 5000000000L
    assert direct.Limit == 3
    assert new Meter().Factor() == 0.5
    assert decimalDefault() == 1.25m
}

// THE METADATA A C# CALLER READS. A default is a `Constant` row of the parameter's own type —
// `.param = int64(5000000000)` — except a `decimal`, which the format cannot store and C# writes as
// `[DecimalConstant]` beside the `[Optional]` flag, and a struct's or a `Nullable<T>`'s `default`,
// which is the null row Roslyn writes.
func MeterConstructorParameters(): ParameterInfo[] {
    constructors := typeof(Meter).GetConstructors()
    assert constructors.Length == 1
    return constructors[0].GetParameters()
}

test "each default is written into the parameter's metadata as C# writes it" {
    parameters := MeterConstructorParameters()
    assert parameters.Length == 5

    width := parameters[0]
    assert width.IsOptional
    assert width.HasDefaultValue
    assert width.DefaultValue is long
    assert Convert.ToInt64(width.DefaultValue) == 5000000000L

    ratio := parameters[1]
    assert ratio.IsOptional
    assert (ratio.Attributes & ParameterAttributes.HasDefault) == ParameterAttributes.None
    decimalConstant := ratio.GetCustomAttribute<DecimalConstantAttribute>()
    assert decimalConstant != null
    assert decimalConstant.Value == 1.25m
    assert Convert.ToDecimal(ratio.DefaultValue) == 1.25m

    mark := parameters[2]
    assert mark.DefaultValue is char
    assert Convert.ToChar(mark.DefaultValue) == 'm'

    limit := parameters[3]
    assert limit.HasDefaultValue
    assert limit.DefaultValue == null

    moment := parameters[4]
    assert moment.HasDefaultValue
    assert moment.DefaultValue == null
}

func MeterMethodParameters(name: string): ParameterInfo[] {
    method := typeof(Meter).GetMethod(name)
    assert method != null
    return method.GetParameters()
}

test "a method's floating and decimal defaults are in its metadata" {
    factor := MeterMethodParameters("Factor")[0]
    assert factor.DefaultValue is double
    assert Convert.ToDouble(factor.DefaultValue) == 0.5

    pick := MeterMethodParameters("Pick")
    assert pick[0].DefaultValue is byte
    assert pick[2].DefaultValue is float
    assert Convert.ToSingle(pick[2].DefaultValue) == 0.75f
}

// A DEFAULT IN ANOTHER ASSEMBLY, read back out of the metadata the fixture's own compile wrote.
test "an omitted default declared in a referenced N# assembly is read from its metadata" {
    assert ReflectedDefaults.Long() == -5000000000L
    assert ReflectedDefaults.Byte() == (byte)200
    assert ReflectedDefaults.UInt() == 4000000000u
    assert ReflectedDefaults.ULong() == 18446744073709551615UL
    assert ReflectedDefaults.Char() == 'q'
    assert ReflectedDefaults.Float() == 0.25f
    assert ReflectedDefaults.Double() == -2.5
    assert ReflectedDefaults.Decimal() == -79.125m
    assert ReflectedDefaults.NullableInt() == "none"
    assert ReflectedDefaults.NullableLong() == 7L
    assert ReflectedDefaults.Date() == 0L
    assert ReflectedDefaults.ToneDefault() == Tone.Quiet
}

test "a referenced constructor and instance method fill their omitted defaults from metadata" {
    reflected := new ReflectedDefaults()
    assert reflected.Width == 5000000000L
    assert reflected.Ratio == 1.25m
    assert reflected.Mark == 'm'
    assert reflected.Limit == null
    assert reflected.Factor() == 0.5
    assert reflected.Offset() == 10m

    named := new ReflectedDefaults(mark: 'n')
    assert named.Mark == 'n'
    assert named.Ratio == 1.25m
}
