namespace NSharpLang.ConstructionArrays.Tests

import System
import System.Diagnostics
import System.IO
import System.Text
import System.Text.Json
import YamlDotNet.Core.Events
import YamlDotNet.Serialization

struct StoreValue {
    Value: int

    constructor(value: int) {
        this.Value = value
    }
}

class ExactArityConstructed {
    Value: int
    Label: string

    constructor(value: int) {
        this.Value = value
        this.Label = "exact"
    }

    constructor(value: int, label: string = "defaulted") {
        this.Value = value
        this.Label = label
    }
}

enum DefaultMode {
    Disabled,
    Enabled
}

class DefaultConstructed {
    Required: int
    Enabled: bool
    Count: int
    Label: string
    Note: string?
    Mode: DefaultMode

    constructor(requiredValue: int, enabled: bool = true, count: int = 19, label: string = "fallback", note: string? = null, mode: DefaultMode = DefaultMode.Enabled) {
        this.Required = requiredValue
        this.Enabled = enabled
        this.Count = count
        this.Label = label
        this.Note = note
        this.Mode = mode
    }
}

class RuntimeEnumDefaulted {
    Seed: int
    Day: System.DayOfWeek

    constructor(seed: int, day: System.DayOfWeek = System.DayOfWeek.Friday) {
        this.Seed = seed
        this.Day = day
    }
}

class GenericAllocator<T> {
    constructor() {
    }

    func Allocate(length: int): T[] {
        return new T[length]
    }
}

class GenericLambdaAllocator<T> {
    Count: int

    constructor(count: int) {
        this.Count = count
    }

    func Allocate(): int {
        make: Func<int> = () => {
            values := new T[Count]
            return values.Length
        }

        return make()
    }
}

class GenericBox<T> {
    Value: T

    constructor(value: T) {
        this.Value = value
    }
}

class GenericDefault<T> {
    Value: T
}

class GenericOptional<T> {
    Value: T
    Count: int

    constructor(value: T, count: int = 17) {
        this.Value = value
        this.Count = count
    }
}

class AliasNumber {
    Value: int

    constructor(value: int) {
        this.Value = value
    }

    static func operator +(left: AliasNumber, right: AliasNumber): AliasNumber {
        return new AliasNumber(left.Value + right.Value)
    }

    static func operator -(value: AliasNumber): AliasNumber {
        return new AliasNumber(0 - value.Value)
    }
}

class AliasNumberConstructed {
    Value: AliasNumber

    constructor(value: AliasNumber) {
        this.Value = value
    }
}

class LexicalOuter {
    class Sibling {
        Value: int

        constructor(value: int) {
            this.Value = value
        }
    }

    class Middle {
        class Inner {
            func Echo(value: Sibling): Sibling {
                return value
            }
        }
    }
}

struct ZeroValue {
    Value: int
}

class ObjectInitializerClass {
    FieldValue: int
    UnsignedValue: uint
    DecimalValue: decimal
    propertyValue: int

    PropertyValue: int {
        get {
            return propertyValue
        }
        set {
            propertyValue = value
        }
    }
}

struct ObjectInitializerValue {
    Small: sbyte
    Count: int
    MaybeByte: byte?
}

class GenericObjectInitializer<T> {
    Value: T
}

class NullableLiteralObjectInitializer {
    ByteValue: byte?
    ShortValue: short?
    UIntValue: uint?
    Marker: int
}

class NestedObjectInitializerInner {
    Value: int
}

class NestedObjectInitializerOuter {
    Inner: NestedObjectInitializerInner
}

class MappedObjectInitializerBase<A, B> {
    Fixed: A
    reordered: B

    Reordered: B {
        get {
            return reordered
        }
        set {
            reordered = value
        }
    }
}

class MappedObjectInitializerMiddle<T>: MappedObjectInitializerBase<string, T> {
}

class MappedObjectInitializerDerived<X, Y>: MappedObjectInitializerMiddle<Y> {
}

class TargetConstructed {
    Value: int

    constructor(value: int) {
        this.Value = value
    }
}

class RetainedOverload {
    Kind: string
    Number: int

    constructor(value: object, number: int) {
        this.Kind = "object"
        this.Number = number
    }

    constructor(value: string, number: int) {
        this.Kind = "string"
        this.Number = number
    }
}

union ResidualChoice {
    Empty
    Value { number: int }
}

func PairBool(first: bool, second: bool): bool[] {
    return [first, second]
}

func PairChar(first: char, second: char): char[] {
    return [first, second]
}

func PairInt(first: int, second: int): int[] {
    return [first, second]
}

func PairUInt(first: uint, second: uint): uint[] {
    return [first, second]
}

func PairLong(first: long, second: long): long[] {
    return [first, second]
}

func PairULong(first: ulong, second: ulong): ulong[] {
    return [first, second]
}

func PairFloat(first: float, second: float): float[] {
    return [first, second]
}

func PairDouble(first: double, second: double): double[] {
    return [first, second]
}

func PairString(first: string, second: string): string[] {
    return [first, second]
}

func PairByte(first: byte, second: byte): byte[] {
    return [first, second]
}

func PairSByte(first: sbyte, second: sbyte): sbyte[] {
    return [first, second]
}

func PairShort(first: short, second: short): short[] {
    return [first, second]
}

func PairUShort(first: ushort, second: ushort): ushort[] {
    return [first, second]
}

func PairStoreValue(first: StoreValue, second: StoreValue): StoreValue[] {
    return [first, second]
}

func PairGeneric<T>(first: T, second: T): T[] {
    return [first, second]
}

func AllocateGeneric<T>(length: int): T[] {
    return new T[length]
}

func RuntimeRepeatText(): string {
    return new string('x', 4)
}

func RuntimeSliceText(characters: char[]): string {
    return new string(characters, 1, 2)
}

func RuntimeEmptyBuilder(): StringBuilder {
    return new StringBuilder()
}

func RuntimeCapacityBuilder(): StringBuilder {
    return new StringBuilder(32)
}

func RuntimeVersion(): Version {
    return new Version(1, 2, 3, 4)
}

func RuntimeObject(): object {
    return new object()
}

func RuntimeProcessStartInfo(): ProcessStartInfo {
    return new ProcessStartInfo()
}

func RuntimeProcess(): Process {
    return new Process()
}

func RuntimeJsonOptions(): JsonSerializerOptions {
    return new JsonSerializerOptions()
}

func RuntimeReader(stream: Stream): StreamReader {
    return new StreamReader(stream)
}

func RuntimeDeserializer(): DeserializerBuilder {
    return new DeserializerBuilder()
}

func RuntimeScalar(value: string): Scalar {
    return new Scalar(value)
}

func RuntimeMappingStart(): MappingStart {
    return new MappingStart()
}

func RuntimeMappingEnd(): MappingEnd {
    return new MappingEnd()
}

func RuntimeException(): Exception {
    return new Exception()
}

func RuntimeInvalidOperation(message: string): InvalidOperationException {
    return new InvalidOperationException(message)
}

func RuntimeArgument(message: string, parameterName: string): ArgumentException {
    return new ArgumentException(message, parameterName)
}

func ReadResidualChoice(value: ResidualChoice): int {
    return match value {
        ResidualChoice.Empty => 0,
        ResidualChoice.Value { number } => number
    }
}

func ContextualValueArray(): ZeroValue[] {
    return [new ZeroValue { Value: 3 }, new ZeroValue { Value: 5 }]
}

func RetainedSourceConstructor(left: int, right: int): ExactArityConstructed {
    return new ExactArityConstructed(left + right)
}

func RetainedSourceOperatorConstructor(
    left: AliasNumber,
    right: AliasNumber
): AliasNumberConstructed {
    return new AliasNumberConstructed(left + right)
}

func RetainedDirectGenericBox(left: int, right: int): GenericBox<int> {
    return new GenericBox<int>(left + right)
}

func RetainedDirectGenericOptional(left: int, right: int): GenericOptional<int> {
    return new GenericOptional<int>(left + right)
}

func RetainedDirectRuntimeList(left: int, right: int): System.Collections.Generic.List<int> {
    return new System.Collections.Generic.List<int>(left + right)
}

func RetainedDirectValueTuple(left: int, right: int): ValueTuple<int, int> {
    return new ValueTuple<int, int>(left + right, right + 1)
}

func RetainedNestedOverload(left: int, right: int): RetainedOverload {
    return new RetainedOverload(new object(), left + right)
}

func RetainedRuntimeScalar(left: string, right: string): Scalar {
    return new Scalar(left + right)
}

func RetainedQualifiedRuntimeScalar(left: string, right: string): YamlDotNet.Core.Events.Scalar {
    return new YamlDotNet.Core.Events.Scalar(left + right)
}

func RetainedQualifiedSourceConstructor(left: int, right: int): NSharpLang.ConstructionArrays.Left.Widget {
    return new NSharpLang.ConstructionArrays.Left.Widget(left + right)
}

func RetainedSizedArray(length: int): int[] {
    return new int[length + 1]
}

func RetainedInferredArray(first: int, second: int): int[] {
    return [first + 1, second + 1]
}

func RetainedNullableLiteralObjectInitializer(
    left: int,
    right: int
): NullableLiteralObjectInitializer {
    return new NullableLiteralObjectInitializer {
        ByteValue: 255,
        ShortValue: 32767,
        UIntValue: 2147483647,
        Marker: left + right
    }
}
