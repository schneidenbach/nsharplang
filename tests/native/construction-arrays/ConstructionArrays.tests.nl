namespace NSharpLang.ConstructionArrays.Tests

import System
import System.Text.Json
import NSharpLang.ConstructionArrays.Left
import NSharpLang.ConstructionArrays.Left as LeftNamespace
import NSharpLang.ConstructionArrays.Right as RightNamespace
import "./Left" as LeftFile
import "./Right" as RightFile

type LeftWidgetAlias = LeftNamespace.Widget
type BuilderAlias = System.Text.StringBuilder
type IntBoxAlias = GenericBox<int>
type IntDefaultAlias = GenericDefault<int>
type IntOptionalAlias = GenericOptional<int>
type RuntimeIntListAlias = System.Collections.Generic.List<int>
type IntTupleAlias = System.ValueTuple<int, int>
type IntObjectInitializerAlias = GenericObjectInitializer<int>
type MappedObjectInitializerAlias = MappedObjectInitializerDerived<int, long>
type NumberAlias = AliasNumber

func RetainIntBoxAlias(value: IntBoxAlias): IntBoxAlias {
    return value
}

func RetainedAliasGenericBox(left: int, right: int): IntBoxAlias {
    return new IntBoxAlias(left + right)
}

func RetainedAliasGenericOptional(left: int, right: int): IntOptionalAlias {
    return new IntOptionalAlias(left + right)
}

func RetainedAliasRuntimeList(left: int, right: int): RuntimeIntListAlias {
    return new RuntimeIntListAlias(left + right)
}

func RetainedAliasValueTuple(left: int, right: int): IntTupleAlias {
    return new IntTupleAlias(left + right, right + 1)
}

func RetainedInheritedObjectInitializer(left: long, right: long): MappedObjectInitializerAlias {
    return new MappedObjectInitializerAlias {
        Fixed: "retained",
        Reordered: left + right
    }
}

class FileAliasEnumDefaulted {
    Seed: int
    Selected: RightFile.Selection

    constructor(seed: int, selected: RightFile.Selection = RightFile.Selection.Value) {
        this.Seed = seed
        this.Selected = selected
    }

    func SelectedText(): string {
        return Selected.ToString() ?? ""
    }
}

test "inferred arrays persist every fixed and typed element store family" {
    bools := PairBool(false, true)
    chars := PairChar('a', 'z')
    ints := PairInt(1, 2)
    uints := PairUInt((uint)3, (uint)4)
    longs := PairLong(5L, 6L)
    ulongs := PairULong((ulong)7, (ulong)8)
    floats := PairFloat(1.5f, 2.5f)
    doubles := PairDouble(3.5, 4.5)
    strings := PairString("left", "right")
    bytes := PairByte((byte)9, (byte)10)
    sbytes := PairSByte((sbyte)11, (sbyte)12)
    shorts := PairShort((short)13, (short)14)
    ushorts := PairUShort((ushort)15, (ushort)16)
    values := PairStoreValue(new StoreValue(17), new StoreValue(18))
    genericStrings := PairGeneric<string>("generic-left", "generic-right")
    genericInts := PairGeneric<int>(19, 20)

    assert bools.Length == 2
    assert bools[1]
    assert chars[1] == 'z'
    assert ints[1] == 2
    assert uints[1] == (uint)4
    assert longs[1] == 6L
    assert ulongs[1] == (ulong)8
    assert floats[1] == 2.5f
    assert doubles[1] == 4.5
    assert strings[1] == "right"
    assert bytes[1] == (byte)10
    assert sbytes[1] == (sbyte)12
    assert shorts[1] == (short)14
    assert ushorts[1] == (ushort)16
    assert values[1].Value == 18
    assert genericStrings[1] == "generic-right"
    assert genericInts[1] == 20
}

test "sized arrays retain top-level and enclosing generic parameter handles" {
    ints := AllocateGeneric<int>(3)
    strings := AllocateGeneric<string>(2)
    allocator := new GenericAllocator<string>()
    memberStrings := allocator.Allocate(4)
    lambdaAllocator := new GenericLambdaAllocator<string>(5)
    lambdaLength := lambdaAllocator.Allocate()

    assert ints.Length == 3
    assert ints[0] == 0
    assert strings.Length == 2
    assert strings[0] == null
    assert memberStrings.Length == 4
    assert memberStrings[0] == null
    assert lambdaLength == 5
}

test "source constructors preserve defaults aliases and exact namespace identity" {
    exact := new ExactArityConstructed(7)
    defaults := new DefaultConstructed(8)
    runtimeEnumDefault := new RuntimeEnumDefaulted(9)
    fileAliasEnumDefault := new FileAliasEnumDefaulted(10)
    leftExact := new NSharpLang.ConstructionArrays.Left.Widget(1)
    leftNamespace := new LeftNamespace.Widget(2)
    leftFile := new LeftFile.Widget(3)
    leftAlias := new LeftWidgetAlias(4)
    rightNamespace := new RightNamespace.Widget(5)
    rightDefaultDirect := new RightNamespace.EnumDefaulted(6)
    rightDefaultRetained := new RightNamespace.EnumDefaulted(3 + 4)
    rightPrimaryDefault := new RightNamespace.PrimaryEnumDefaulted(8)
    builder := new BuilderAlias()
    genericBox := new IntBoxAlias(11)
    retainedGenericBox := RetainIntBoxAlias(genericBox)
    genericDefault := new IntDefaultAlias()
    genericOptionalDirect := new GenericOptional<int>(13)
    genericOptionalAlias := new IntOptionalAlias(14)
    genericList := new RuntimeIntListAlias()
    genericList.Add(12)
    builder.Append("alias")

    assert exact.Value == 7, "exact arity value"
    assert exact.Label == "exact", "exact arity selection"
    assert defaults.Required == 8, "default required value"
    assert defaults.Enabled, "default bool"
    assert defaults.Count == 19, "default int"
    assert defaults.Label == "fallback", "default string"
    assert defaults.Note == null, "default null"
    assert defaults.Mode == DefaultMode.Enabled, "default enum member"
    assert runtimeEnumDefault.Seed == 9, "runtime enum default required value"
    assert (int)runtimeEnumDefault.Day == 5, "runtime enum member default"
    assert fileAliasEnumDefault.Seed == 10, "file alias enum default required value"
    assert fileAliasEnumDefault.SelectedText() == "right", "file alias enum member default"
    assert leftExact.Value == 1, "fully qualified left value"
    assert leftNamespace.Value == 2, "namespace alias left value"
    assert leftFile.Value == 3, "file alias left value"
    assert leftAlias.Value == 4, "type alias left value"
    assert rightNamespace.Value == 5, "namespace alias right value"
    assert leftExact.Side() == "left", "fully qualified left identity"
    assert leftNamespace.Side() == "left", "namespace alias left identity"
    assert leftFile.Side() == "left", "file alias left identity"
    assert leftAlias.Side() == "left", "type alias left identity"
    assert rightNamespace.Side() == "right", "namespace alias right identity"
    assert rightDefaultDirect.Required == 6, "direct aliased enum default required"
    assert rightDefaultDirect.Selected == "right", "direct aliased enum default identity"
    assert rightDefaultRetained.Required == 7, "retained aliased enum default required"
    assert rightDefaultRetained.Selected == "right", "retained aliased enum default identity"
    assert rightPrimaryDefault.RequiredValue() == 8, "primary aliased enum default required"
    assert rightPrimaryDefault.SelectedValue() == "right", "primary aliased enum default identity"
    assert genericBox.Value == 11, "closed source generic alias constructor"
    assert retainedGenericBox.Value == 11, "closed source generic alias signature"
    assert genericDefault.Value == 0, "closed source generic synthesized default constructor"
    assert genericOptionalDirect.Value == 13, "closed source generic direct optional constructor"
    assert genericOptionalDirect.Count == 17, "closed source generic direct optional default"
    assert genericOptionalAlias.Value == 14, "closed source generic alias optional constructor"
    assert genericOptionalAlias.Count == 17, "closed source generic alias optional default"
    assert genericList[0] == 12, "closed runtime generic alias constructor"
    assert builder.ToString() == "alias"
}

test "runtime constructor catalog persists every admitted signature family" {
    characters := ['a', 'b', 'c']
    emptyBuilder := RuntimeEmptyBuilder()
    capacityBuilder := RuntimeCapacityBuilder()
    version := RuntimeVersion()
    runtimeObject := RuntimeObject()
    startInfo := RuntimeProcessStartInfo()
    process := RuntimeProcess()
    options := RuntimeJsonOptions()
    deserializer := RuntimeDeserializer()
    scalar := RuntimeScalar("scalar")
    mappingStart := RuntimeMappingStart()
    mappingEnd := RuntimeMappingEnd()
    emptyException := RuntimeException()
    invalidOperation := RuntimeInvalidOperation("invalid")
    argument := RuntimeArgument("bad argument", "value")

    assert RuntimeRepeatText() == "xxxx"
    assert RuntimeSliceText(characters) == "bc"
    assert emptyBuilder != null
    assert capacityBuilder != null
    assert version != null
    assert version.ToString() == "1.2.3.4"
    assert runtimeObject != null
    assert startInfo != null
    assert process != null
    assert options != null
    assert throws ArgumentNullException {
        RuntimeReader(null)
    }

    assert deserializer != null
    assert scalar != null
    assert scalar.Value == "scalar"
    assert mappingStart != null
    assert mappingEnd != null
    assert emptyException != null
    assert invalidOperation != null
    assert invalidOperation.Message == "invalid"
    assert argument != null
    assert argument.Message.Contains("bad argument")
}

test "aliases preserve declared operators and deep lexical nested type lookup" {
    left: NumberAlias = new NumberAlias(20)
    right: NumberAlias = new NumberAlias(22)
    sum := left + right
    negated := -left
    sibling := new LexicalOuter.Sibling(42)
    inner := new LexicalOuter.Middle.Inner()

    assert sum.Value == 42
    assert negated.Value == -20
    assert inner.Echo(sibling).Value == 42
    assert typeof(LexicalOuter.Sibling).IsNested
    assert typeof(LexicalOuter.Middle.Inner).IsNested
}

test "retained contextual construction families remain executable" {
    zero := new ZeroValue()
    choice := new ResidualChoice.Value(41)
    target: TargetConstructed = new(42)
    contextual := ContextualValueArray()
    json := new JsonElement()
    sourceWithExpression := RetainedSourceConstructor(20, 22)
    directGenericWithExpression := RetainedDirectGenericBox(20, 22)
    aliasGenericWithExpression := RetainedAliasGenericBox(19, 23)
    directGenericOptionalWithExpression := RetainedDirectGenericOptional(18, 24)
    aliasGenericOptionalWithExpression := RetainedAliasGenericOptional(17, 25)
    directRuntimeWithExpression := RetainedDirectRuntimeList(15, 17)
    aliasRuntimeWithExpression := RetainedAliasRuntimeList(14, 18)
    directTupleWithExpressions := RetainedDirectValueTuple(20, 22)
    aliasTupleWithExpressions := RetainedAliasValueTuple(19, 23)
    nestedOverload := RetainedNestedOverload(20, 22)
    scalarWithExpression := RetainedRuntimeScalar("left", "-right")
    qualifiedScalarWithExpression := RetainedQualifiedRuntimeScalar("qualified", "-runtime")
    qualifiedSourceWithExpression := RetainedQualifiedSourceConstructor(19, 23)
    sizedWithExpression := RetainedSizedArray(2)
    inferredWithExpressions := RetainedInferredArray(3, 7)
    sourceOperatorWithExpression := RetainedSourceOperatorConstructor(
        new AliasNumber(20),
        new AliasNumber(22)
    )
    floatLeft := 1.25f
    floatRight := 2.75f
    retainedFloatArray := [
        floatLeft + floatRight,
        floatLeft + 0.75f
    ]
    initializerChoice := new ResidualChoice.Value(17)
    unsignedLeft := (uint)20
    unsignedRight := (uint)22
    decimalLeft := 1.5m
    decimalRight := 2.5m
    retainedObjectInitializer := new ObjectInitializerClass {
        FieldValue: ReadResidualChoice(initializerChoice),
        UnsignedValue: unsignedLeft + unsignedRight,
        DecimalValue: decimalLeft + decimalRight
    }

    assert zero.Value == 0
    assert ReadResidualChoice(choice) == 41
    assert target.Value == 42
    assert contextual.Length == 2
    assert contextual[0].Value == 3
    assert contextual[1].Value == 5
    assert json.ValueKind == JsonValueKind.Undefined
    assert sourceWithExpression.Value == 42
    assert directGenericWithExpression.Value == 42
    assert aliasGenericWithExpression.Value == 42
    assert directGenericOptionalWithExpression.Value == 42
    assert directGenericOptionalWithExpression.Count == 17
    assert aliasGenericOptionalWithExpression.Value == 42
    assert aliasGenericOptionalWithExpression.Count == 17
    assert directRuntimeWithExpression.Capacity == 32
    assert aliasRuntimeWithExpression.Capacity == 32
    assert directTupleWithExpressions.Item1 == 42
    assert directTupleWithExpressions.Item2 == 23
    assert aliasTupleWithExpressions.Item1 == 42
    assert aliasTupleWithExpressions.Item2 == 24
    assert nestedOverload.Kind == "object"
    assert nestedOverload.Number == 42
    assert scalarWithExpression.Value == "left-right"
    assert qualifiedScalarWithExpression.Value == "qualified-runtime"
    assert qualifiedSourceWithExpression.Value == 42
    assert qualifiedSourceWithExpression.Side() == "left"
    assert sizedWithExpression.Length == 3
    assert inferredWithExpressions[0] == 4
    assert inferredWithExpressions[1] == 8
    assert sourceOperatorWithExpression.Value.Value == 42
    assert retainedFloatArray[0] == 4.0f
    assert retainedFloatArray[1] == 2.0f
    assert retainedObjectInitializer.FieldValue == 17
    assert retainedObjectInitializer.UnsignedValue == (uint)42
    assert retainedObjectInitializer.DecimalValue == 4.0m
}

test "object initializers persist source runtime generic and union assignments" {
    source := new ObjectInitializerClass {
        FieldValue: 21,
        PropertyValue: 22
    }
    value := new ObjectInitializerValue {
        Small: -8,
        Count: 23,
        MaybeByte: 255
    }
    generic := new IntObjectInitializerAlias { Value: 24 }
    choice: ResidualChoice = new ResidualChoice.Value { number: 25 }
    options := new JsonSerializerOptions { WriteIndented: true }
    nested := new NestedObjectInitializerOuter {
        Inner: new NestedObjectInitializerInner { Value: 26 }
    }
    inherited := new MappedObjectInitializerAlias {
        Fixed: "owned",
        Reordered: 27L
    }
    retainedInherited := RetainedInheritedObjectInitializer(13L, 15L)
    nullableOwned := new NullableLiteralObjectInitializer {
        ByteValue: 255,
        ShortValue: 32767,
        UIntValue: 2147483647,
        Marker: 29
    }
    nullableRetained := RetainedNullableLiteralObjectInitializer(14, 16)
    nullableNested := [
        new NullableLiteralObjectInitializer {
            ByteValue: 31,
            ShortValue: 32,
            UIntValue: 33,
            Marker: 34
        },
        new NullableLiteralObjectInitializer {
            ByteValue: 35,
            ShortValue: 36,
            UIntValue: 37,
            Marker: 38
        }
    ]

    assert source.FieldValue == 21, "source field initializer"
    assert source.PropertyValue == 22, "source property initializer"
    assert value.Small == (sbyte)-8, "value-struct target-typed initializer"
    assert value.Count == 23, "value-struct field initializer"
    assert (value.MaybeByte ?? 0) == (byte)255, "value-struct nullable literal initializer"
    assert generic.Value == 24, "closed generic alias initializer"
    assert ReadResidualChoice(choice) == 25, "union case initializer"
    assert options.WriteIndented, "runtime property initializer"
    assert nested.Inner.Value == 26, "nested object initializer"
    assert inherited.Fixed == "owned", "mapped inherited generic field initializer"
    assert inherited.Reordered == 27L, "mapped inherited generic property initializer"
    assert retainedInherited.Fixed == "retained", "retained mapped inherited generic field initializer"
    assert retainedInherited.Reordered == 28L, "retained mapped inherited generic property initializer"
    assert (nullableOwned.ByteValue ?? 0) == (byte)255, "owned nullable byte literal boundary"
    assert (nullableOwned.ShortValue ?? 0) == (short)32767, "owned nullable short literal boundary"
    assert (nullableOwned.UIntValue ?? 0) == (uint)2147483647, "owned nullable uint literal boundary"
    assert nullableOwned.Marker == 29, "owned nullable literal initializer marker"
    assert (nullableRetained.ByteValue ?? 0) == (byte)255, "retained nullable byte literal parity"
    assert (nullableRetained.ShortValue ?? 0) == (short)32767, "retained nullable short literal parity"
    assert (nullableRetained.UIntValue ?? 0) == (uint)2147483647, "retained nullable uint literal parity"
    assert nullableRetained.Marker == 30, "retained nullable literal initializer marker"
    assert nullableNested.Length == 2, "nested nullable initializer array length"
    assert (nullableNested[0].ByteValue ?? 0) == (byte)31, "nested nullable initializer first element"
    assert (nullableNested[1].UIntValue ?? 0) == (uint)37, "nested nullable initializer second element"
}
