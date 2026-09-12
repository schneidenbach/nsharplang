namespace NSharpLang.ExternalGenericConstruction.Tests

import System
import System.Collections.Generic
import System.Numerics
import System.Reflection

// The subject surface: constructing, operating on, indexing and reducing CONSTRUCTED EXTERNAL GENERIC
// types. `System.Numerics.Vector<T>` is used throughout precisely because the compiler models nothing
// about it -- every line below resolves through ordinary CLR constructor, operator, indexer and
// generic-method lookup, and a `List<int>` / `Dictionary<string, int>` control proves the same paths
// serve an unremarkable BCL generic.

// ---------------------------------------------------------------------- construction
func LoadBlock(values: int[], index: int): Vector<int> {
    block := new Vector<int>(values, index)
    return block
}

func LoadBlockDirect(values: int[], index: int): Vector<int> {
    return new Vector<int>(values, index)
}

func LoadLongBlock(values: long[], index: int, lanes: int): Vector<long> {
    return new Vector<long>(values, index + lanes)
}

func Broadcast(value: int): Vector<int> {
    return new Vector<int>(value)
}

func BroadcastLong(value: long): Vector<long> {
    return new Vector<long>(value)
}

func ZeroBlock(): Vector<int> {
    return new Vector<int>()
}

func SumOfBlockArgument(values: int[], index: int): int {
    return Vector.Sum(new Vector<int>(values, index))
}

func BroadcastFieldHolder(value: int): VectorHolder {
    holder := new VectorHolder()
    holder.Value = new Vector<int>(value)
    return holder
}

// ---------------------------------------------------------------------- operators

func AddVectors(a: Vector<int>, b: Vector<int>): Vector<int> {
    return a + b
}

func SubtractVectors(a: Vector<int>, b: Vector<int>): Vector<int> {
    return a - b
}

func MultiplyVectors(a: Vector<int>, b: Vector<int>): Vector<int> {
    return a * b
}

func AndVectors(a: Vector<int>, b: Vector<int>): Vector<int> {
    return a & b
}

func OrVectors(a: Vector<int>, b: Vector<int>): Vector<int> {
    return a | b
}

func XorVectors(a: Vector<int>, b: Vector<int>): Vector<int> {
    return a ^ b
}

func ComplementVector(a: Vector<int>): Vector<int> {
    return ~a
}

func NegateVector(a: Vector<int>): Vector<int> {
    return -a
}

func VectorsEqual(a: Vector<int>, b: Vector<int>): bool {
    return a == b
}

func VectorsNotEqual(a: Vector<int>, b: Vector<int>): bool {
    return a != b
}

func AddLongVectors(a: Vector<long>, b: Vector<long>): Vector<long> {
    return a + b
}

// ---------------------------------------------------------------------- indexer

func Lane(a: Vector<int>, index: int): int {
    return a[index]
}

func LongLane(a: Vector<long>, index: int): long {
    return a[index]
}

// ---------------------------------------------------------------------- generic static calls

func Reduce(a: Vector<int>): int {
    return Vector.Sum(a)
}

func ReduceLong(a: Vector<long>): long {
    return Vector.Sum(a)
}

func MinOf(a: Vector<int>, b: Vector<int>): Vector<int> {
    return Vector.Min(a, b)
}

func MaxOf(a: Vector<int>, b: Vector<int>): Vector<int> {
    return Vector.Max(a, b)
}

func EqualityMask(a: Vector<int>, b: Vector<int>): Vector<int> {
    return Vector.Equals(a, b)
}

func InequalityMaskedValues(a: Vector<int>, b: Vector<int>): Vector<int> {
    return ~Vector.Equals(a, b) & a
}

func AtLeast(a: Vector<int>, b: Vector<int>): Vector<int> {
    return Vector.GreaterThanOrEqual(a, b)
}

func AtMost(a: Vector<int>, b: Vector<int>): Vector<int> {
    return Vector.LessThanOrEqual(a, b)
}

func Chosen(mask: Vector<int>, a: Vector<int>, b: Vector<int>): Vector<int> {
    return Vector.ConditionalSelect(mask, a, b)
}

func Magnitude(a: Vector<int>): Vector<int> {
    return Vector.Abs(a)
}

func Inverted(a: Vector<int>): Vector<int> {
    return Vector.Negate(a)
}

func DotProduct(a: Vector<int>, b: Vector<int>): int {
    return Vector.Dot(a, b)
}

func InRangeCount(values: Vector<int>, low: Vector<int>, high: Vector<int>): Vector<int> {
    return Vector.GreaterThanOrEqual(values, low) & Vector.LessThanOrEqual(values, high)
}

// ---------------------------------------------------------------------- compound assignment

func Accumulate(a: Vector<int>, b: Vector<int>): Vector<int> {
    acc := a
    acc += b
    acc -= b
    return acc
}

func AccumulateFourWay(values: int[], lanes: int): int {
    a0 := new Vector<int>(0)
    a1 := new Vector<int>(0)
    a2 := new Vector<int>(0)
    a3 := new Vector<int>(0)
    step := lanes * 4
    i := 0
    while i <= values.Length - step {
        a0 += new Vector<int>(values, i)
        a1 += new Vector<int>(values, i + lanes)
        a2 += new Vector<int>(values, i + lanes * 2)
        a3 += new Vector<int>(values, i + lanes * 3)
        i = i + step
    }

    total := Vector.Sum(a0 + a1 + a2 + a3)
    while i < values.Length {
        total = total + values[i]
        i = i + 1
    }

    return total
}

func CountInRange(values: int[], lanes: int, low: int, high: int): int {
    accumulator := new Vector<int>(0)
    lowVector := new Vector<int>(low)
    highVector := new Vector<int>(high)
    i := 0
    while i <= values.Length - lanes {
        block := new Vector<int>(values, i)
        accumulator -= Vector.GreaterThanOrEqual(block, lowVector) & Vector.LessThanOrEqual(block, highVector)
        i = i + lanes
    }

    count := Vector.Sum(accumulator)
    while i < values.Length {
        if values[i] >= low && values[i] <= high {
            count = count + 1
        }
        i = i + 1
    }

    return count
}

class VectorHolder {
    Value: Vector<int>
    Money: decimal
}

func AccumulateIntoField(holder: VectorHolder, b: Vector<int>) {
    holder.Value += b
}

func SubtractFromField(holder: VectorHolder, b: Vector<int>) {
    holder.Value -= b
}

func AccumulateMoneyField(holder: VectorHolder, amount: decimal) {
    holder.Money += amount
}

func AccumulateIntoIntElement(totals: int[], index: int, amount: int) {
    totals[index] += amount
}

// ---------------------------------------------------------------------- evaluation order

class EvaluationLog {
    Tags: List<int>

    constructor() {
        Tags = new List<int>()
    }

    func Record(tag: int) {
        Tags.Add(tag)
    }
}

func LoggedArray(log: EvaluationLog, values: int[], tag: int): int[] {
    log.Record(tag)
    return values
}

func LoggedIndex(log: EvaluationLog, index: int, tag: int): int {
    log.Record(tag)
    return index
}

func ConstructInEvaluationOrder(log: EvaluationLog, values: int[], index: int): Vector<int> {
    return new Vector<int>(LoggedArray(log, values, 1), LoggedIndex(log, index, 2))
}

func ReduceInEvaluationOrder(log: EvaluationLog, a: Vector<int>, b: Vector<int>): Vector<int> {
    return Vector.Min(LoggedVector(log, a, 1), LoggedVector(log, b, 2))
}

func LoggedVector(log: EvaluationLog, value: Vector<int>, tag: int): Vector<int> {
    log.Record(tag)
    return value
}

// ---------------------------------------------------------------------- exceptions

func LoadPastEnd(values: int[]): bool {
    try {
        block := new Vector<int>(values, values.Length - 1)
        return Vector.Sum(block) == 0 && false
    } catch ex: ArgumentOutOfRangeException {
        return true
    }
}

// The exception a bad lane index actually raises, named rather than assumed: `Vector<T>`'s indexer
// raises ArgumentOutOfRangeException, not the IndexOutOfRangeException an array subscript would. The
// point of the row is that the BCL's own behaviour reaches the caller unaltered, so the test asserts
// what the BCL does.
func LaneOutOfRangeExceptionName(a: Vector<int>, index: int): string {
    try {
        lane := a[index]
        if lane == 0 {
            return "no throw"
        }
        return "no throw"
    } catch ex: ArgumentOutOfRangeException {
        return "System.ArgumentOutOfRangeException"
    } catch ex: IndexOutOfRangeException {
        return "System.IndexOutOfRangeException"
    } catch ex: Exception {
        return "some other exception"
    }
}

// ---------------------------------------------------------------------- ordinary BCL generic control

func BuildList(capacity: int, first: int, second: int): List<int> {
    values := new List<int>(capacity)
    values.Add(first)
    values.Add(second)
    return values
}

func CopyList(source: List<int>): List<int> {
    return new List<int>(source)
}

func BuildMap(first: string, firstValue: int): Dictionary<string, int> {
    map := new Dictionary<string, int>(4, StringComparer.Ordinal)
    map[first] = firstValue
    return map
}

func CopyMap(source: Dictionary<string, int>): Dictionary<string, int> {
    return new Dictionary<string, int>(source, StringComparer.Ordinal)
}

func BuildSet(source: List<int>): HashSet<int> {
    return new HashSet<int>(source)
}

func BumpMapValue(map: Dictionary<string, int>, key: string, amount: int) {
    map[key] += amount
}

// ---------------------------------------------------------------------- non-generic external operators

func Elapsed(start: DateTime, finish: DateTime): TimeSpan {
    return finish - start
}

func Shift(start: DateTime, offset: TimeSpan): DateTime {
    return start + offset
}

func Money(a: decimal, b: decimal): decimal {
    return a * b + a
}

// ---------------------------------------------------------------------- scalar oracles

func ScalarSum(values: int[], start: int, count: int): int {
    total := 0
    index := 0
    while index < count {
        total = total + values[start + index]
        index = index + 1
    }

    return total
}

func ScalarSumAll(values: int[]): int {
    total := 0
    index := 0
    while index < values.Length {
        total = total + values[index]
        index = index + 1
    }

    return total
}

func ScalarCountInRange(values: int[], low: int, high: int): int {
    count := 0
    index := 0
    while index < values.Length {
        if values[index] >= low && values[index] <= high {
            count = count + 1
        }
        index = index + 1
    }

    return count
}

// ---------------------------------------------------------------------- lane count, never hardcoded

func LaneCount(): int {
    property := typeof(Vector<int>).GetProperty("Count")
    if property == null {
        throw new InvalidOperationException("System.Numerics.Vector<int>.Count was not found.")
    }

    boxed := property.GetValue(null)
    if boxed == null {
        throw new InvalidOperationException("System.Numerics.Vector<int>.Count produced no value.")
    }

    return Convert.ToInt32(boxed)
}

func LongLaneCount(): int {
    property := typeof(Vector<long>).GetProperty("Count")
    if property == null {
        throw new InvalidOperationException("System.Numerics.Vector<long>.Count was not found.")
    }

    boxed := property.GetValue(null)
    if boxed == null {
        throw new InvalidOperationException("System.Numerics.Vector<long>.Count produced no value.")
    }

    return Convert.ToInt32(boxed)
}

// ---------------------------------------------------------------------- lane readback and inputs

func LanesOf(a: Vector<int>, lanes: int): int[] {
    result := new int[](lanes)
    index := 0
    while index < lanes {
        result[index] = a[index]
        index = index + 1
    }

    return result
}

func LongLanesOf(a: Vector<long>, lanes: int): long[] {
    result := new long[](lanes)
    index := 0
    while index < lanes {
        result[index] = a[index]
        index = index + 1
    }

    return result
}

// A deterministic pseudo-random fill, so a failure is reproducible. The multiply is written unchecked
// because the whole point of the generator is that it wraps.
func PseudoRandom(length: int, seed: int): int[] {
    values := new int[](length)
    state := seed
    index := 0
    while index < length {
        state = unchecked(state * 1103515245 + 12345)
        values[index] = state
        index = index + 1
    }

    return values
}

func Ramp(length: int, start: int): int[] {
    values := new int[](length)
    index := 0
    while index < length {
        values[index] = start + index
        index = index + 1
    }

    return values
}

func LongRamp(length: int, start: long): long[] {
    values := new long[](length)
    index := 0
    while index < length {
        values[index] = start + index
        index = index + 1
    }

    return values
}

func ArraysEqual(left: int[], right: int[]): bool {
    if left.Length != right.Length {
        return false
    }

    index := 0
    while index < left.Length {
        if left[index] != right[index] {
            return false
        }
        index = index + 1
    }

    return true
}

func LongArraysEqual(left: long[], right: long[]): bool {
    if left.Length != right.Length {
        return false
    }

    index := 0
    while index < left.Length {
        if left[index] != right[index] {
            return false
        }
        index = index + 1
    }

    return true
}

func Slice(values: int[], start: int, length: int): int[] {
    result := new int[](length)
    index := 0
    while index < length {
        result[index] = values[start + index]
        index = index + 1
    }

    return result
}

func LongSlice(values: long[], start: int, length: int): long[] {
    result := new long[](length)
    index := 0
    while index < length {
        result[index] = values[start + index]
        index = index + 1
    }

    return result
}
