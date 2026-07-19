namespace NSharpLang.PrimitiveBinary.Tests

// A holder used to exercise primitive binary operators nested inside constructor arguments.
class IntBox {
    Value: int

    constructor(value: int) {
        this.Value = value
    }
}

// --- Integer arithmetic: results persisted through locals and a return ---
func IntArithmetic(a: int, b: int): int {
    added := a + b
    subtracted := a - b
    multiplied := a * b
    divided := a / b
    remainder := a % b
    return added + subtracted + multiplied + divided + remainder
}

func IntSubtract(a: int, b: int): int {
    return a - b
}

func IntMultiply(a: int, b: int): int {
    return a * b
}

func IntDivide(a: int, b: int): int {
    return a / b
}

func IntRemainder(a: int, b: int): int {
    return a % b
}

func LongArithmetic(a: long, b: long): long {
    return a * b - a / b + a % b
}

// Unsigned division and remainder select the unsigned opcodes.
func UintDivide(a: uint, b: uint): uint {
    return a / b
}

func UintRemainder(a: uint, b: uint): uint {
    return a % b
}

func UlongDivide(a: ulong, b: ulong): ulong {
    return a / b
}

func DoubleArithmetic(a: double, b: double): double {
    return a * b + a / b - b
}

func FloatArithmetic(a: float, b: float): float {
    return a + b
}

// char never survives arithmetic: the result promotes to int.
func CharDistance(a: char, b: char): int {
    return a - b
}

func DecimalArithmetic(a: decimal, b: decimal): decimal {
    return a * b - a / b + a % b
}

// --- Bitwise operators over the integral surface ---
func IntBitwise(a: int, b: int): int {
    andValue := a & b
    orValue := a | b
    xorValue := a ^ b
    return andValue + orValue + xorValue
}

func LongAnd(a: long, b: long): long {
    return a & b
}

func UintOr(a: uint, b: uint): uint {
    return a | b
}

func UlongXor(a: ulong, b: ulong): ulong {
    return a ^ b
}

// --- Shifts: signed and unsigned right shift selection ---
func IntLeftShift(a: int, count: int): int {
    return a << count
}

func LongRightShift(a: long, count: int): long {
    return a >> count
}

func UlongRightShift(a: ulong, count: int): ulong {
    return a >> count
}

// --- Ordering comparisons producing bool ---
func IntLess(a: int, b: int): bool {
    return a < b
}

func IntLessEqual(a: int, b: int): bool {
    return a <= b
}

func IntGreater(a: int, b: int): bool {
    return a > b
}

func IntGreaterEqual(a: int, b: int): bool {
    return a >= b
}

func UintGreater(a: uint, b: uint): bool {
    return a > b
}

func DoubleLessEqual(a: double, b: double): bool {
    return a <= b
}

func DoubleGreaterEqual(a: double, b: double): bool {
    return a >= b
}

func CharLess(a: char, b: char): bool {
    return a < b
}

func LongGreater(a: long, b: long): bool {
    return a > b
}

func DecimalLess(a: decimal, b: decimal): bool {
    return a < b
}

// --- Equality and inequality ---
func IntEqual(a: int, b: int): bool {
    return a == b
}

func IntNotEqual(a: int, b: int): bool {
    return a != b
}

func BoolEqual(a: bool, b: bool): bool {
    return a == b
}

func BoolNotEqual(a: bool, b: bool): bool {
    return a != b
}

func DoubleEqual(a: double, b: double): bool {
    return a == b
}

func CharEqual(a: char, b: char): bool {
    return a == b
}

func DecimalEqual(a: decimal, b: decimal): bool {
    return a == b
}

// String concatenation is owned; string equality remains on the legacy owner.
func StringConcat(a: string, b: string): string {
    return a + b
}

func StringEqual(a: string, b: string): bool {
    return a == b
}

// --- checked / unchecked overflow forms computing non-overflowing values ---
func CheckedIntAdd(a: int, b: int): int {
    return checked(a + b)
}

func CheckedIntSubtract(a: int, b: int): int {
    return checked(a - b)
}

func CheckedIntMultiply(a: int, b: int): int {
    return checked(a * b)
}

func UncheckedIntAdd(a: int, b: int): int {
    return unchecked(a + b)
}

func CheckedUintAdd(a: uint, b: uint): uint {
    return checked(a + b)
}

func CheckedLongMultiply(a: long, b: long): long {
    return checked(a * b)
}

// --- Operators nested inside index expressions ---
func IndexBySum(values: int[], a: int, b: int): int {
    return values[a + b]
}

func IndexByShift(values: int[], i: int): int {
    return values[i << 1]
}

func IndexByLastOffset(values: int[]): int {
    return values[values.Length - 1]
}

// --- Operators nested inside constructor arguments ---
func BoxedSum(a: int, b: int): int {
    box := new IntBox(a + b)
    return box.Value
}

func SizedArrayLength(a: int, b: int): int {
    buffer := new int[a * b]
    return buffer.Length
}

// --- Left-associative arithmetic chain recursing through the planner ---
func ArithmeticChain(a: int, b: int, c: int): int {
    return a * b + c - a
}

// --- Cast operands inside binaries: the Conv-opcode slice of the case-16 table ---
func UintLiteralEquals(x: uint): bool {
    return x == (uint)42
}

func IntCharLiteralEquals(i: int): bool {
    return (int)'a' == i
}

func LongCastAdd(i: int): long {
    return (long)i + 1L
}

func UlongCastFromUint(u: uint): ulong {
    return (ulong)u + 2UL
}

func UlongCastFromInt(i: int): ulong {
    return (ulong)i + 2UL
}

func CharCastEquals(i: int): bool {
    return (char)i == 'a'
}

func ByteCastAdd(i: int): int {
    return (byte)i + 1
}

func SbyteCastAdd(i: int): int {
    return (sbyte)i + 1
}

func ShortCastMultiply(i: int): int {
    return (short)i * 2
}

func DoubleCastLess(i: int): bool {
    return (double)i < 4.5
}

func FloatCastAdd(i: int): float {
    return (float)i + 1.5f
}

func IntCastTruncate(d: double): int {
    return (int)d + 1
}

func UintCastNarrow(l: long, r: uint): bool {
    return (uint)l == r
}

// --- Decimal literal operands inside binaries ---
func DecimalLiteralEquals(d: decimal): bool {
    return d == 24.5m
}

func DecimalLiteralAdd(): decimal {
    return 1.5m + 2.5m
}

func DecimalIntegerLiteralAdd(): decimal {
    return 5m + 2m
}

func DecimalLiteralCompare(d: decimal): bool {
    return d < 0.5m
}

// --- Bare sibling-function calls as binary operands ---
// A module-level function called by a sibling compiles to a static call. When it appears as a
// binary operand, the whole binary must plan through the N# route.
func Answer(): int {
    return 42
}

func Doubled(value: int): int {
    return value * 2
}

func SiblingEqualsLiteral(): bool {
    return Answer() == 42
}

func SiblingSumOfCalls(value: int): int {
    return Answer() + Doubled(value)
}

func SiblingCallLess(value: int): bool {
    return Doubled(value) < Answer()
}

// A sibling call nested inside a constructor argument.
func BoxedSiblingSum(value: int): int {
    box := new IntBox(Answer() + Doubled(value))
    return box.Value
}

// A sibling call nested inside an index expression.
func IndexBySibling(values: int[], value: int): int {
    return values[Doubled(value)]
}
