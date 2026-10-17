namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit
import System.Runtime.CompilerServices

func DefaultValueConstant(kind: int, text: string, parameterType: Type): object {
    decoded := ColumnarParameterDefaultValue.FromSource(kind, text, parameterType)
    assert decoded != null, "'" + text + "' should decode as a default for " + parameterType.Name
    assert decoded.Form == ColumnarParameterDefaultValue.ConstantForm, "'" + text + "' should be a constant"
    known := decoded.Constant
    assert known != null
    return known
}

func AssertDefaultConstant(kind: int, text: string, parameterType: Type, expected: object) {
    known := DefaultValueConstant(kind, text, parameterType)
    assert known.GetType() == expected.GetType(), "'" + text + "' decoded as " + known.GetType().Name + ", not " + expected.GetType().Name
    assert known.Equals(expected), "'" + text + "' decoded to the wrong value"
}

func AssertDefaultDeclines(kind: int, text: string?, parameterType: Type) {
    assert ColumnarParameterDefaultValue.FromSource(kind, text, parameterType) == null, "'" + (text ?? "<null>") + "' should not be a default for " + parameterType.Name
}

test "an integer literal default is held as its parameter's own integral type" {
    AssertDefaultConstant(1, "7", typeof(byte), (byte)7)
    AssertDefaultConstant(1, "255", typeof(byte), (byte)255)
    AssertDefaultConstant(1, "-128", typeof(sbyte), (sbyte)-128)
    AssertDefaultConstant(1, "-32768", typeof(short), (short)-32768)
    AssertDefaultConstant(1, "65535", typeof(ushort), (ushort)65535)
    AssertDefaultConstant(1, "- 2147483648", typeof(int), -2147483648)
    AssertDefaultConstant(1, "0x7F", typeof(int), 127)
    AssertDefaultConstant(1, "1_000", typeof(int), 1000)
    AssertDefaultConstant(1, "4000000000u", typeof(uint), 4000000000u)
    AssertDefaultConstant(1, "42", typeof(long), 42L)
    AssertDefaultConstant(1, "5000000000L", typeof(long), 5000000000L)
    AssertDefaultConstant(1, "-9223372036854775808L", typeof(long), -9223372036854775807L - 1L)
    AssertDefaultConstant(1, "7u", typeof(long), 7L)
    AssertDefaultConstant(1, "18446744073709551615UL", typeof(ulong), 18446744073709551615UL)
    AssertDefaultConstant(1, "65", typeof(char), 'A')
}

test "an integer literal default widens into a floating or decimal parameter" {
    AssertDefaultConstant(1, "3", typeof(double), 3.0)
    AssertDefaultConstant(1, "-3", typeof(float), -3.0f)
    AssertDefaultConstant(1, "5000000000L", typeof(decimal), 5000000000m)
}

test "a floating, decimal and character literal default keeps its own type" {
    AssertDefaultConstant(2, "2.5", typeof(double), 2.5)
    AssertDefaultConstant(2, "-0.125", typeof(double), -0.125)
    AssertDefaultConstant(2, "1e3", typeof(double), 1000.0)
    AssertDefaultConstant(2, "1.5f", typeof(float), 1.5f)
    AssertDefaultConstant(2, "1.5f", typeof(double), 1.5)
    AssertDefaultConstant(2, "1.25m", typeof(decimal), 1.25m)
    AssertDefaultConstant(1, "5m", typeof(decimal), 5m)
    AssertDefaultConstant(2, "-79.125m", typeof(decimal), -79.125m)
    AssertDefaultConstant(3, "'z'", typeof(char), 'z')
    AssertDefaultConstant(3, "'\\n'", typeof(char), '\n')
    AssertDefaultConstant(3, "'a'", typeof(int), 97)
    AssertDefaultConstant(3, "'a'", typeof(double), 97.0)
}

test "a constant for a Nullable or an enum parameter is held as the type underneath" {
    AssertDefaultConstant(1, "12", typeof(int?), 12)
    AssertDefaultConstant(2, "2.5m", typeof(decimal?), 2.5m)
    AssertDefaultConstant(1, "3", typeof(DayOfWeek), 3)
}

test "a literal its parameter cannot hold is not a default" {
    AssertDefaultDeclines(1, "256", typeof(byte))
    AssertDefaultDeclines(1, "-1", typeof(byte))
    AssertDefaultDeclines(1, "-129", typeof(sbyte))
    AssertDefaultDeclines(1, "-1", typeof(uint))
    AssertDefaultDeclines(1, "2147483648", typeof(int))
    AssertDefaultDeclines(1, "1L", typeof(int))
    AssertDefaultDeclines(1, "1u", typeof(int))
    AssertDefaultDeclines(1, "-1u", typeof(long))
    AssertDefaultDeclines(2, "2.5", typeof(float))
    AssertDefaultDeclines(2, "2.5", typeof(decimal))
    AssertDefaultDeclines(2, "2.5m", typeof(double))
    AssertDefaultDeclines(2, "1.5", typeof(int))
    AssertDefaultDeclines(3, "'a'", typeof(byte))
    AssertDefaultDeclines(3, "'a'", typeof(string))
    AssertDefaultDeclines(4, "\"7\"", typeof(int))
    AssertDefaultDeclines(4, null, typeof(string))
    AssertDefaultDeclines(44, "true", typeof(int))
    AssertDefaultDeclines(1, "1", typeof(string))
    AssertDefaultDeclines(1, "1", typeof(object))
    AssertDefaultDeclines(46, "null", typeof(int))
    AssertDefaultDeclines(46, "null", typeof(DateTime))
    AssertDefaultDeclines(1, "1", typeof(int).MakeByRefType())
}

test "null and default take the form their parameter's type gives them" {
    referenceNull := ColumnarParameterDefaultValue.FromSource(46, "null", typeof(string))
    assert referenceNull != null
    assert referenceNull.Form == ColumnarParameterDefaultValue.NullReferenceForm

    nullableNull := ColumnarParameterDefaultValue.FromSource(46, "null", typeof(int?))
    assert nullableNull != null
    assert nullableNull.Form == ColumnarParameterDefaultValue.ZeroValueForm

    structDefault := ColumnarParameterDefaultValue.FromSource(34, "default", typeof(DateTime))
    assert structDefault != null
    assert structDefault.Form == ColumnarParameterDefaultValue.ZeroValueForm

    referenceDefault := ColumnarParameterDefaultValue.FromSource(34, "default", typeof(string))
    assert referenceDefault != null
    assert referenceDefault.Form == ColumnarParameterDefaultValue.NullReferenceForm

    nullableDefault := ColumnarParameterDefaultValue.FromSource(34, "default", typeof(long?))
    assert nullableDefault != null
    assert nullableDefault.Form == ColumnarParameterDefaultValue.ZeroValueForm

    AssertDefaultConstant(34, "default", typeof(int), 0)
    AssertDefaultConstant(34, "default", typeof(ulong), 0UL)
    AssertDefaultConstant(34, "default", typeof(bool), false)
    AssertDefaultConstant(34, "default", typeof(char), (char)0)
    AssertDefaultConstant(34, "default", typeof(double), 0.0)
    AssertDefaultConstant(34, "default", typeof(decimal), 0m)
    AssertDefaultConstant(34, "default", typeof(DayOfWeek), 0)
}

// THE ROUND TRIP A C# CALLER DEPENDS ON: a source default written into a parameter row, the row
// read back through reflection, and the value that comes out is the value that went in. `decimal`
// is the one that is not a `Constant` row at all.
func DefaultValueProbeTypes(): Type[] {
    types := new Type[](7)
    types[0] = typeof(long)
    types[1] = typeof(decimal)
    types[2] = typeof(char)
    types[3] = typeof(DateTime)
    types[4] = typeof(int?)
    types[5] = typeof(float)
    types[6] = typeof(int?)
    return types
}

func DefaultValueProbeParameters(): ParameterInfo[] {
    owner := TypeOfCreateBuilder("ParameterDefaultValueRoundTrip", "ColumnarParameterDefaultValueControls.RoundTrip", 0)
    types := DefaultValueProbeTypes()
    method := owner.DefineMethod("Probe", (MethodAttributes)22, ExecutorVoidType(), types)
    kinds := new int[](7)
    kinds[0] = 1
    kinds[1] = 2
    kinds[2] = 3
    kinds[3] = 34
    kinds[4] = 46
    kinds[5] = 2
    kinds[6] = 1
    texts := new string[](7)
    texts[0] = "-5000000000L"
    texts[1] = "-79.125m"
    texts[2] = "'q'"
    texts[3] = "default"
    texts[4] = "null"
    texts[5] = "0.25f"
    texts[6] = "-3"
    names := new string[](7)
    names[0] = "width"
    names[1] = "ratio"
    names[2] = "mark"
    names[3] = "moment"
    names[4] = "limit"
    names[5] = "scale"
    names[6] = "offset"
    assert ColumnarParameterDefaultEmitter.DefineMethodParameterMetadata(method, types, names, new int[](7), kinds, texts, ParameterDefaultEmptyRegistry())
    TypeOfMethodBuilderIL(method).Emit(OpCodes.Ret)
    baked := PlanFixtureBake(owner)
    probe := baked.GetMethod("Probe")
    assert probe != null
    return probe.GetParameters()
}

test "every source default is written as the metadata row C# writes for it" {
    parameters := DefaultValueProbeParameters()
    assert parameters.Length == 7
    for parameter in parameters {
        assert parameter.IsOptional
    }

    assert (parameters[0].Attributes & ParameterAttributes.HasDefault) != ParameterAttributes.None
    assert Convert.ToInt64(parameters[0].RawDefaultValue) == -5000000000L

    // `[Optional]` and `[DecimalConstant]`, and no `Constant` row.
    assert (parameters[1].Attributes & ParameterAttributes.HasDefault) == ParameterAttributes.None
    decimalConstant := parameters[1].GetCustomAttribute<DecimalConstantAttribute>()
    assert decimalConstant != null
    assert decimalConstant.Value == -79.125m

    assert Convert.ToChar(parameters[2].RawDefaultValue) == 'q'
    assert parameters[3].HasDefaultValue
    assert parameters[3].RawDefaultValue == null
    assert parameters[4].HasDefaultValue
    assert parameters[4].RawDefaultValue == null
    assert Convert.ToSingle(parameters[5].RawDefaultValue) == 0.25f
    assert Convert.ToInt32(parameters[6].RawDefaultValue) == -3
}

test "a metadata default reads back as the value that was written, and spells back as a source default" {
    parameters := DefaultValueProbeParameters()
    types := DefaultValueProbeTypes()
    index := 0
    while index < parameters.Length {
        read := ColumnarParameterDefaultValue.FromMetadata(parameters[index], types[index])
        assert read != null, "parameter " + index.ToString() + " has no readable default"

        kind := 0
        text := ""
        assert read.TrySpellSource(out kind, out text), "parameter " + index.ToString() + " has no source spelling"
        respelled := ColumnarParameterDefaultValue.FromSource(kind, text, types[index])
        assert respelled != null, "'" + text + "' does not read back"
        assert respelled.Form == read.Form
        assert Object.Equals(respelled.Constant, read.Constant), "'" + text + "' reads back as a different value"
        index = index + 1
    }

    assert Convert.ToDecimal(ColumnarParameterDefaultValue.FromMetadata(parameters[1], typeof(decimal))?.Constant) == -79.125m
    assert ColumnarParameterDefaultValue.FromMetadata(parameters[3], typeof(DateTime))?.Form == ColumnarParameterDefaultValue.ZeroValueForm

    // An omitted argument is not a conversion site: a stored `long` is not an `int` default.
    assert ColumnarParameterDefaultValue.FromMetadata(parameters[0], typeof(int)) == null
    assert ColumnarParameterDefaultValue.FromMetadata(parameters[1], typeof(double)) == null
}

func DefaultValueInvoke(name: string, returnType: Type, value: ColumnarParameterDefaultValue?): object? {
    assert value != null, name + " has no default value"
    method := BoundDynamicMethod(name, typeof(object), new Type[](0))
    il := method.GetILGenerator()
    assert value.EmitTo(il), name + " did not emit"
    if returnType.IsValueType {
        il.Emit(OpCodes.Box, returnType)
    }
    il.Emit(OpCodes.Ret)
    return method.Invoke(null, new object[](0))
}

test "an omitted default executes as its parameter's own type" {
    assert Convert.ToInt64(DefaultValueInvoke("DefaultLong", typeof(long), ColumnarParameterDefaultValue.FromSource(1, "-5000000000L", typeof(long)))) == -5000000000L
    assert Convert.ToUInt64(DefaultValueInvoke("DefaultULong", typeof(ulong), ColumnarParameterDefaultValue.FromSource(1, "18446744073709551615UL", typeof(ulong)))) == 18446744073709551615UL
    assert Convert.ToUInt32(DefaultValueInvoke("DefaultUInt", typeof(uint), ColumnarParameterDefaultValue.FromSource(1, "4000000000u", typeof(uint)))) == 4000000000u
    assert Convert.ToChar(DefaultValueInvoke("DefaultChar", typeof(char), ColumnarParameterDefaultValue.FromSource(3, "'q'", typeof(char)))) == 'q'
    assert Convert.ToSingle(DefaultValueInvoke("DefaultFloat", typeof(float), ColumnarParameterDefaultValue.FromSource(2, "0.25f", typeof(float)))) == 0.25f
    assert Convert.ToDecimal(DefaultValueInvoke("DefaultDecimal", typeof(decimal), ColumnarParameterDefaultValue.FromSource(2, "-79.125m", typeof(decimal)))) == -79.125m
    assert Convert.ToInt32(DefaultValueInvoke("DefaultNullableValue", typeof(int?), ColumnarParameterDefaultValue.FromSource(1, "12", typeof(int?)))) == 12
    assert DefaultValueInvoke("DefaultNullableNone", typeof(int?), ColumnarParameterDefaultValue.FromSource(46, "null", typeof(int?))) == null
    assert Convert.ToInt64(Convert.ToDateTime(DefaultValueInvoke("DefaultDate", typeof(DateTime), ColumnarParameterDefaultValue.FromSource(34, "default", typeof(DateTime)))).Ticks) == 0L
    assert DefaultValueInvoke("DefaultReference", typeof(string), ColumnarParameterDefaultValue.FromSource(46, "null", typeof(string))) == null
}
