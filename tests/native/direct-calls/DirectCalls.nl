namespace NSharpLang.DirectCalls.Tests

// `Func<...>` is parser-owned function-type syntax even when a source generic collides.
class Func<T, R> {}

type ByteArrayPool = System.Buffers.ArrayPool<byte>

class DirectCallLog {
    value: int

    constructor(initialValue: int) {
        this.value = initialValue
    }
}

class DirectReferenceReceiver {
    value: int

    constructor(initialValue: int) {
        this.value = initialValue
    }

    func Select(_label: string, amount: int): int {
        return value + amount + 200
    }

    func Select(amount: int, _label: string): int {
        return value + amount + 100
    }

    func Record(nextValue: int): void {
        this.value = nextValue
    }

    func SelectBare(amount: int, label: string): int {
        return Select(amount, label)
    }

    func SelectExplicit(amount: int, label: string): int {
        return this.Select(amount, label)
    }
}

struct DirectValueReceiver {
    value: int

    constructor(initialValue: int) {
        this.value = initialValue
    }

    func Select(amount: int, _label: string): int {
        return value + amount + 300
    }
}

class DirectValueFieldHolder {
    receiver: DirectValueReceiver

    constructor(initialValue: int) {
        this.receiver = new DirectValueReceiver(initialValue)
    }

    func SelectFromField(): int {
        return this.receiver.Select(2, "field")
    }
}

struct DirectImplicitSource {
    value: int

    constructor(initialValue: int) {
        this.value = initialValue
    }

    implicit operator int(source: DirectImplicitSource) {
        return source.value
    }
}

record DirectReferenceRecord(value: int) {
    Value: int => value
}

record struct DirectValueRecord(value: int) {
    Value: int => value
}

class DirectHiddenBase {
    func Select(amount: int, _label: string): int {
        return amount + 600
    }
}

class DirectHiddenDerived: DirectHiddenBase {
    func Select(amount: int, _label: string): int {
        return amount + 700
    }
}

class DirectStaticCalls {
    static func Select(amount: int, _label: string): int {
        return amount + 10
    }

    static func Select(_label: string, amount: int): int {
        return amount + 20
    }

    static func Add(left: int, right: int): int {
        return left + right
    }

    static func Identity(value: int): int {
        return value
    }

    static func Scale(value: double): double {
        return value * 2.0
    }

    static func Measure(value: string): int {
        return value.Length
    }

    static func Record(log: DirectCallLog, nextValue: int): void {
        log.value = nextValue
    }

    static func CreateReference(initialValue: int): DirectReferenceReceiver {
        return new DirectReferenceReceiver(initialValue)
    }

    static func CreateValue(initialValue: int): DirectValueReceiver {
        return new DirectValueReceiver(initialValue)
    }

    static func FromEnd(_label: string, count: int): int {
        return count
    }

    static func RangeStart(start: int, _label: string): int {
        return start
    }

    static func RangeEnd(_label: string, end: int): int {
        return end
    }

    static func SelectBare(amount: int, label: string): int {
        return Select(amount, label)
    }
}

class DirectConvertedCalls {
    static func AcceptNullable(_value: int?): int {
        return 31
    }

    static func AcceptWidenedNullable(_value: long?): int {
        return 32
    }

    static func AcceptSmallNullable(_value: byte?): int {
        return 37
    }

    static func AcceptReference(_value: string?): int {
        return 33
    }

    static func AcceptSpan(_values: Span<int>): int {
        return 34
    }

    static func AcceptReadOnlySpan(_values: ReadOnlySpan<int>): int {
        return 35
    }

    static func AcceptUnion(_value: int | string): int {
        return 36
    }

    static func AcceptImplicit(value: int): int {
        return value + 40
    }
}

func SelectThroughReferenceParameter(receiver: DirectReferenceReceiver): int {
    return receiver.Select(3, "parameter")
}

func SelectThroughValueParameter(receiver: DirectValueReceiver): int {
    return receiver.Select(4, "parameter")
}

func ComposeNestedCalls(receiver: DirectReferenceReceiver): int {
    return DirectStaticCalls.Add(receiver.Select(2, "instance"), DirectStaticCalls.Select("static", 3))
}

func SelectFromCreatedReference(): int {
    return DirectStaticCalls.CreateReference(6).Select(7, "created")
}

func SelectFromCreatedValue(): int {
    return DirectStaticCalls.CreateValue(8).Select(9, "created")
}

func ReadByNestedCall(values: int[]): int {
    return values[^DirectStaticCalls.FromEnd("count", 2)]
}

func SliceByNestedCalls(values: int[]): int[] {
    return values[DirectStaticCalls.RangeStart(1, "start")..DirectStaticCalls.RangeEnd("end", 4)]
}

func PassIndexedValue(values: int[]): int {
    return DirectStaticCalls.Identity(values[^1])
}

func PassSlicedValue(value: string): int {
    return DirectStaticCalls.Measure(value[1..4])
}

func RecurseDirectCalls(value: int): int {
    return DirectStaticCalls.Identity(DirectStaticCalls.Identity(value))
}

func InvokeFunctionSyntax(callback: Func<int, int>, value: int): int {
    return callback(value)
}

func RentThroughExactPoolAlias(): int {
    buffer := ByteArrayPool.Shared.Rent(1)
    length := buffer.Length
    ByteArrayPool.Shared.Return(buffer)
    return length
}

func ParseRuntimeInt(value: string): int {
    return int.Parse(value)
}

func RuntimeTypeAssignable(): bool {
    return typeof(object).IsAssignableFrom(typeof(string))
}

func RuntimeObjectText(value: object): string? {
    return value.ToString()
}

func RuntimeAbsolute(value: int): int {
    return Math.Abs(value)
}

func DirectNullableValue(value: int): int {
    return DirectConvertedCalls.AcceptNullable(value)
}

func DirectNullableIdentity(value: int?): int {
    return DirectConvertedCalls.AcceptNullable(value)
}

func DirectNullableNull(): int {
    return DirectConvertedCalls.AcceptNullable(null)
}

func DirectWidenedNullable(value: int): int {
    return DirectConvertedCalls.AcceptWidenedNullable(value)
}

func DirectSmallNullableLiteral(): int {
    return DirectConvertedCalls.AcceptSmallNullable(255)
}

func DirectReferenceNull(): int {
    return DirectConvertedCalls.AcceptReference(null)
}

func DirectSpan(values: int[]): int {
    return DirectConvertedCalls.AcceptSpan(values)
}

func DirectReadOnlySpan(values: int[]): int {
    return DirectConvertedCalls.AcceptReadOnlySpan(values)
}

func DirectUnionInt(value: int): int {
    return DirectConvertedCalls.AcceptUnion(value)
}

func DirectUnionString(value: string): int {
    return DirectConvertedCalls.AcceptUnion(value)
}

func DirectImplicit(value: int): int {
    source := new DirectImplicitSource(value)
    return DirectConvertedCalls.AcceptImplicit(source)
}

func DirectReferenceRecordEquals(value: int): bool {
    left := new DirectReferenceRecord(value)
    right := new DirectReferenceRecord(value)
    return left.Equals(right)
}

func DirectReferenceRecordNotEquals(value: int): bool {
    left := new DirectReferenceRecord(value)
    right := new DirectReferenceRecord(value + 1)
    return !left.Equals(right)
}

func DirectReferenceRecordHashesMatch(value: int): bool {
    left := new DirectReferenceRecord(value)
    right := new DirectReferenceRecord(value)
    return left.GetHashCode() == right.GetHashCode()
}

func DirectValueRecordEquals(value: int): bool {
    left := new DirectValueRecord(value)
    right := new DirectValueRecord(value)
    return left.Equals(right)
}

func DirectValueRecordNotEquals(value: int): bool {
    left := new DirectValueRecord(value)
    right := new DirectValueRecord(value + 1)
    return !left.Equals(right)
}

func DirectValueRecordHashesMatch(value: int): bool {
    left := new DirectValueRecord(value)
    right := new DirectValueRecord(value)
    return left.GetHashCode() == right.GetHashCode()
}
