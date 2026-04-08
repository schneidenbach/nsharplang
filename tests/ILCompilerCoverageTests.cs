using System;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

public partial class ILCompilerTests
{
    [Fact]
    public void ILCompiler_CanExecuteLockStatementAndReleaseMonitor()
    {
        var source = @"
import System
import System.Threading

func main(): int {
    gate := new object()
    entered := false
    reacquired := false

    try {
        lock gate {
            entered = Monitor.IsEntered(gate)
            throw new Exception(""boom"")
        }
    } catch {
    }

    Monitor.Enter(gate)
    reacquired = Monitor.IsEntered(gate)
    Monitor.Exit(gate)

    if entered && reacquired {
        return 1
    }

    return 0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(1, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CheckedExpressionThrowsOnAdditionOverflow()
    {
        var source = @"
func main(): int {
    max := 2147483647
    return checked(max + 1)
}";

        Assert.Throws<OverflowException>(() => CompileAndInvoke(source));
    }

    [Fact]
    public void ILCompiler_CheckedExpressionThrowsOnMultiplicationOverflow()
    {
        var source = @"
func main(): int {
    return checked(50000 * 50000)
}";

        Assert.Throws<OverflowException>(() => CompileAndInvoke(source));
    }

    [Fact]
    public void ILCompiler_UncheckedExpressionWrapsOnOverflow()
    {
        var source = @"
func main(): int {
    max := 2147483647
    min := -2147483647 - 1
    expectedMin := -2147483647 - 1
    expectedMax := 2147483647
    wrappedAdd := unchecked(max + 1)
    wrappedSub := unchecked(min - 1)

    if wrappedAdd == expectedMin && wrappedSub == expectedMax {
        return 1
    }

    return 0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(1, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CheckedExpressionThrowsOnOverflowingCast()
    {
        var source = @"
func main(): int {
    value := checked((byte)256)
    return value
}";

        Assert.Throws<OverflowException>(() => CompileAndInvoke(source));
    }

    [Fact]
    public void ILCompiler_UncheckedExpressionWrapsOverflowingCast()
    {
        var source = @"
func main(): int {
    value := unchecked((byte)256)
    return value
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(0, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteEmptyStatements()
    {
        var source = @"
func main(): int {
    total := 0
    ;

    for i := 0; i < 3; i++ {
        ;
        total += 1
    }

    if total == 3 {
        ;
        return total
    }

    return 0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(3, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteFloatLiteralsWithSuffixes()
    {
        var source = @"
func main(): double {
    value: float = 1.25f
    bonus: double = 2.5d
    return (double)value + bonus
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(3.75, Assert.IsType<double>(result), precision: 5);
    }

    [Fact]
    public void ILCompiler_CanExecuteBuiltInUnaryOperators()
    {
        var source = @"
class Box {
    Value: int
}

func main(): int {
    count := 1
    flag := false
    mask := 5
    box := new Box { Value: 3 }
    values := [10]

    pre := ++count
    postMember := box.Value++
    postIndex := values[0]--

    if !flag && -count == -2 && ~mask == -6 {
        return pre * 10000 + postMember * 1000 + box.Value * 100 + postIndex * 10 + values[0]
    }

    return 0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(23509, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteNullLiteralsForReferenceAndNullableTypes()
    {
        var source = @"
class Node {
    Value: int
}

func main(): int {
    text: string = null
    node: Node = null
    maybe: int? = null
    value := maybe ?? 42

    if text == null && node == null && value == 42 {
        return 1
    }

    return 0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(1, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteStringConcatenationWithMixedOperands()
    {
        var source = @"
func main(): string {
    return ""sum="" + 42 + "",ok="" + true
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("sum=42,ok=True", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteStringIndexFromEndAndRange()
    {
        var source = @"
func main(): string {
    text := ""abcdef""
    middle := text[1..^1]
    tail := text[^2]
    return middle + ""|"" + tail
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("bcde|e", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_EmitsAttributesAcrossConstructorFieldPropertyAndIndexerTargets()
    {
        var source = @"
import System

class Annotated {
    [Obsolete(""field"")]
    data: int

    [Obsolete(""ctor"")]
    constructor([CLSCompliant(true)] seed: int) {
        data = seed
    }

    [Obsolete(""property"")]
    Value: int {
        get {
            return data
        }
    }

    [Obsolete(""indexer"")]
    func this[index: int]: int {
        get {
            return data + index
        }
    }
}";

        CompileAndInspect(source, assembly =>
        {
            var annotatedType = assembly.GetType("Annotated");
            Assert.NotNull(annotatedType);

            var field = annotatedType!.GetField("data", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.NotNull(field);
            var fieldAttribute = GetCustomAttribute(field!, "System.ObsoleteAttribute");
            Assert.Equal(new object?[] { "field" }, GetAttributeArguments(fieldAttribute));

            var constructor = Assert.Single(annotatedType.GetConstructors(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic));
            var constructorAttribute = GetCustomAttribute(constructor, "System.ObsoleteAttribute");
            Assert.Equal(new object?[] { "ctor" }, GetAttributeArguments(constructorAttribute));
            var constructorParameterAttribute = Assert.Single(constructor.GetParameters()[0].CustomAttributes);
            Assert.Equal("System.CLSCompliantAttribute", constructorParameterAttribute.AttributeType.FullName);

            var valueProperty = annotatedType.GetProperty("Value", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.NotNull(valueProperty);
            var propertyAttribute = GetCustomAttribute(valueProperty!, "System.ObsoleteAttribute");
            Assert.Equal(new object?[] { "property" }, GetAttributeArguments(propertyAttribute));

            var indexerProperty = annotatedType.GetProperty("Item", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.NotNull(indexerProperty);
            var indexerAttribute = GetCustomAttribute(indexerProperty!, "System.ObsoleteAttribute");
            Assert.Equal(new object?[] { "indexer" }, GetAttributeArguments(indexerAttribute));

            return 0;
        });
    }

    [Fact]
    public void ILCompiler_CanExecuteListPatternOnCustomIndexedTypeWithSliceBinding()
    {
        var source = @"
class Window {
    values: int[]

    constructor() {
        values = [1, 2, 3, 4]
    }

    Count: int {
        get {
            return values.Length
        }
    }

    func this[index: int]: int {
        get {
            return values[index]
        }
    }
}

func main(): int {
    window := new Window()
    return match window {
        [1, .. middle, 4] => middle[0] * 100 + middle[1] * 10 + middle.Length
        _ => 0
    }
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(232, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClrDecimalOptionalDefaultValue()
    {
        var source = @"
import NSharpLang.Tests

func main(): int {
    return ILCompilerCallHelpers.DecimalDefaultScaled()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(125, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClrNullableOptionalDefaultValue()
    {
        var source = @"
import NSharpLang.Tests

func main(): int {
    return ILCompilerCallHelpers.NullableOrDefault()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(17, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteCollectionExpressionIntoCustomAddCollection()
    {
        var source = @"
import NSharpLang.Tests

func main(): int {
    bag: IntAddBag = [1, 2, 3, 4]
    return bag.Sum()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(10, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteCollectionExpressionIntoCustomEnqueueCollection()
    {
        var source = @"
import NSharpLang.Tests

func main(): int {
    bag: IntEnqueueBag = [4, 2, 7]
    return bag.ReadAsDigits()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(427, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteCollectionExpressionIntoEnumerableConstructorCollection()
    {
        var source = @"
import NSharpLang.Tests

func main(): int {
    prefix := [1, 2]
    box: IntEnumerableBox = [0, ...prefix, 3]
    return box.Signature()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(403, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteCollectionExpressionIntoISetInterfaceTarget()
    {
        var source = @"
import System.Collections.Generic

func main(): int {
    values: ISet<int> = [1, 1, 2, 3]
    return values.Count
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(3, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanPassArrayDirectlyToClrParamsMethod()
    {
        var source = @"
import NSharpLang.Tests

func main(): int {
    items := [1, 2, 3, 4]
    return ILCompilerCallHelpers.Sum(items)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(10, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanInferCompositeGenericLocalFunctionTypes()
    {
        var source = @"
import System.Collections.Generic

func main(): int {
    func second<T>(items: T[]): T {
        return items[1]
    }

    func consume<T>(items: List<T>, projector: Func<T, int>): int {
        return 7
    }

    projector: Func<int, int> = x => x
    values: List<int> = [7, 8, 9]
    return second([4, 5, 6]) * 10
        + consume(values, projector)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(57, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanInferTupleGenericLocalFunctionTypes()
    {
        var source = @"
func main(): int {
    func score<TLeft, TRight>(pair: (TLeft, TRight)): int {
        return 4
    }

    return score((1, 4))
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(4, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteGenericLocalFunctionCapturingByRefParameter()
    {
        var source = @"
func adjust(ref current: int, delta: int): int {
    func project<T>(value: T): int {
        current += delta
        return current
    }

    return project(0)
}

func main(): int {
    value := 40
    return adjust(ref value, 2) + value
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(84, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteMemberAssignmentExpressionWithoutReevaluatingReferenceReceiver()
    {
        var source = @"
class Box {
    Value: int
}

class Source {
    Count: int

    func Next(): Box {
        Count += 1
        return new Box { Value: Count }
    }
}

func main(): int {
    source := new Source()
    assigned := source.Next().Value = 5
    return assigned * 10 + source.Count
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(51, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteStaticFieldAndPropertyLoads()
    {
        var source = @"
class State {
    static backing: int

    static Value: int {
        get {
            return State.backing
        }
        set {
            State.backing = value
        }
    }
}

func main(): int {
    State.Value = 4
    State.Value = State.Value + 5
    return State.Value * 10 + State.Value
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(99, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteValueTypeObjectInitializersWithFieldPropertyAndIndexer()
    {
        var source = @"
struct Bag {
    first: int
    second: int

    Sum: int {
        get {
            return first + second
        }
        set {
            second = value - first
        }
    }

    func this[index: int]: int {
        get {
            if index == 0 {
                return first
            }

            return second
        }
        set {
            if index == 0 {
                first = value
            } else {
                second = value
            }
        }
    }

    static func createPair(): Bag {
        return new Bag { first: 3, [1] = 4 }
    }

    static func createTotal(): Bag {
        return new Bag { first: 2, Sum: 9 }
    }
}

func main(): int {
    bag := Bag.createPair()
    other := Bag.createTotal()
    return bag.Sum * 100 + other.Sum * 10
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(790, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteStaticCompoundAndNullCoalesceAssignments()
    {
        var source = @"
class State {
    static Maybe: string
}

func main(): int {
    RuntimeCoverageBag.StaticField = 1
    RuntimeCoverageBag.StaticField += 2

    RuntimeCoverageBag.StaticProperty = 4
    RuntimeCoverageBag.StaticProperty += RuntimeCoverageBag.StaticField

    State.Maybe ??= ""go""
    State.Maybe ??= ""no""

    return RuntimeCoverageBag.StaticField * 100
        + RuntimeCoverageBag.StaticProperty * 10
        + State.Maybe.Length
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(372, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClrStaticMembersAndRuntimeObjectInitializers()
    {
        var source = @"
func touch(ref value: int): void {
    value += 1
}

func main(): int {
    RuntimeCoverageBag.StaticField = 3
    RuntimeCoverageBag.StaticProperty = RuntimeCoverageBag.StaticField + 4

    bag := new RuntimeCoverageBag { Field: 2, Property: 5, [1] = 6 }
    bag.Add(7)
    bag.Add(8)
    bag.Field = bag.Field + RuntimeCoverageBag.StaticField
    bag.Property += bag[1]
    bag[1] = bag[1] + bag.ValuesCount

    touch(ref bag.Field)
    touch(ref RuntimeCoverageBag.StaticField)

    return RuntimeCoverageBag.StaticField * 1000000
        + RuntimeCoverageBag.StaticProperty * 100000
        + bag.Field * 10000
        + bag.Property * 1000
        + bag[1] * 100
        + bag.ValuesCount * 10
        + bag.ValuesSum
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(4771835, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClrWithExpressionsOnClassAndStruct()
    {
        var source = @"
func main(): int {
    original := new RuntimeCoverageBag { Field: 2, Property: 3 }
    copy := original with { Field: 5, Property: original.Property + 4 }

    point := new RuntimeCoverageStruct { Field: 7, Property: 8 }
    pointCopy := point with { Field: 9, Property: point.Property + 1 }

    return original.Field * 10000000
        + original.Property * 1000000
        + copy.Field * 100000
        + copy.Property * 10000
        + point.Field * 1000
        + point.Property * 100
        + pointCopy.Field * 10
        + pointCopy.Property
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(23577899, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteGenericLocalFunctionWithExplicitTypeArgumentsNamedDefaultsAndParams()
    {
        var source = @"
func main(): int {
    seed := 7
    extras := [8, 9]

    func collect<T>(value: T, prefix: int = 1, params rest: T[]): int {
        return prefix * 100 + (rest.Length + 1) * 10 + seed
    }

    first := collect<int>(value: 5, prefix: 2)
    second := collect<int>(4, 3, extras)
    third := collect<int>(6)
    return first + second + third
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(671, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanAssignToHighIndexParameter()
    {
        var parameters = string.Join(", ", Enumerable.Range(0, 260).Select(index => $"p{index}: int"));
        var arguments = string.Join(", ", Enumerable.Range(0, 260));
        var source = $$"""
func mutate({{parameters}}): int {
    p259 = p259 + p1
    return p259
}

func main(): int {
    return mutate({{arguments}})
}
""";

        var result = CompileAndInvoke(source);
        Assert.Equal(260, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteRefParametersAcrossIndirectStorageKinds()
    {
        var source = @"
struct Pair {
    Left: int
    Right: int
}

func bumpByte(ref value: byte): void {
    value = (byte)(value + 1)
}

func bumpShort(ref value: short): void {
    value = (short)(value + 2)
}

func setChar(ref value: char): void {
    value = (char)90
}

func bumpLong(ref value: long): void {
    value += 3
}

func flipBool(ref value: bool): void {
    value = !value
}

func bumpFloat(ref value: float): void {
    value = value + 1.5f
}

func bumpDouble(ref value: double): void {
    value = value + 2.5d
}

func replacePair(ref value: Pair): void {
    value = new Pair { Left: value.Left + 4, Right: value.Right + 5 }
}

func decorate(ref value: string): void {
    value = value + ""!""
}

func bumpInt(ref value: int): void {
    value += 6
}

func main(): int {
    b: byte = 1
    s: short = 2
    c: char = (char)65
    l: long = 3
    flag := false
    f: float = 4.0f
    d: double = 5.0d
    pair := new Pair { Left: 6, Right: 7 }
    text := ""hi""
    values := [10, 20, 30]

    bumpByte(ref b)
    bumpShort(ref s)
    setChar(ref c)
    bumpLong(ref l)
    flipBool(ref flag)
    bumpFloat(ref f)
    bumpDouble(ref d)
    replacePair(ref pair)
    decorate(ref text)
    bumpInt(ref values[^1])

    boolDigit := flag ? 1 : 0
    return b * 100000000
        + s * 10000000
        + ((int)c - 60) * 1000000
        + (int)l * 100000
        + boolDigit * 10000
        + (int)f * 1000
        + (int)d * 100
        + pair.Left * 10
        + pair.Right
        + values[^1]
        + text.Length
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(270615851, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteArrayStoresForPrimitiveReferenceAndValueTypes()
    {
        var source = @"
struct Pair {
    Left: int
    Right: int
}

func main(): int {
    longs: long[] = [1, 2]
    flags: bool[] = [false, false]
    floats: float[] = [1.0f]
    doubles: double[] = [2.0d]
    texts: string[] = [""a""]
    pairs: Pair[] = [new Pair { Left: 3, Right: 4 }]

    longs[1] = 5
    flags[0] = true
    floats[0] = 6.5f
    doubles[0] = 7.5d
    texts[0] = ""ok""
    pairs[0] = new Pair { Left: 8, Right: 9 }

    return (int)longs[1] * 100000
        + (flags[0] ? 1 : 0) * 10000
        + (int)floats[0] * 1000
        + (int)doubles[0] * 100
        + texts[0].Length * 10
        + pairs[0].Left
        + pairs[0].Right
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(516737, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteGenericLocalFunctionInsideClosureWithClosureFieldCapture()
    {
        var source = @"
func main(): int {
    offset := 2

    compute := () => {
        baseline := 5

        func project<T>(value: T): int {
            return baseline * 10 + offset
        }

        return project<string>(""x"")
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(52, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_EmitsNUnitIgnoreMetadataForSkippedTests()
    {
        var source = @"
test ""needs network"" skip ""no network in CI"" {
    assert true
}";

        var config = new ProjectConfig { TestFramework = "nunit" };
        CompileAndInspect(source, config, assembly =>
        {
            var testType = assembly.GetType("NSharpTests");
            Assert.NotNull(testType);

            var testMethod = testType!.GetMethod("NeedsNetwork", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(testMethod);

            var ignoreAttribute = GetCustomAttribute(testMethod!, "NUnit.Framework.IgnoreAttribute");
            Assert.Equal(new object?[] { "no network in CI" }, GetAttributeArguments(ignoreAttribute));
            return true;
        });
    }

    [Fact]
    public void ILCompiler_CanExecuteUserDefinedBitwiseShiftAndUnaryOperatorOverloads()
    {
        var source = @"
struct Flags {
    Value: int

    static func operator &(a: Flags, b: Flags): Flags {
        return new Flags { Value: a.Value & b.Value }
    }

    static func operator |(a: Flags, b: Flags): Flags {
        return new Flags { Value: a.Value | b.Value }
    }

    static func operator ^(a: Flags, b: Flags): Flags {
        return new Flags { Value: a.Value ^ b.Value }
    }

    static func operator <<(a: Flags, amount: int): Flags {
        return new Flags { Value: a.Value << amount }
    }

    static func operator >>(a: Flags, amount: int): Flags {
        return new Flags { Value: a.Value >> amount }
    }

    static func operator ~(value: Flags): Flags {
        return new Flags { Value: ~value.Value }
    }
}

func main(): int {
    a := new Flags { Value: 6 }
    b := new Flags { Value: 3 }

    masked := a & b
    merged := a | b
    toggled := a ^ b
    shifted := (a << 1) >> 2
    inverted := ~b

    return masked.Value * 100000
        + merged.Value * 10000
        + toggled.Value * 1000
        + shifted.Value * 100
        + (0 - inverted.Value)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(275304, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithObjectInitializer()
    {
        var source = @"
class LambdaBox {
    Value: int
    Items: int[]
}

func main(): int {
    offset := 2
    box := new LambdaBox { Value: 5, Items: [6, 7] }

    compute := () => {
        box.Value = box.Value + offset
        snapshot := new LambdaBox { Value: box.Value + offset, Items: [offset, box.Items[0]] }
        return snapshot.Value * 100
            + snapshot.Items[1]
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(906, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithTuple()
    {
        var source = @"
func main(): int {
    offset := 2
    value := 5

    compute := () => {
        pair := (offset, value)
        return pair.Item1 * 100
            + pair.Item2
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(205, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithObjectInitializerAndTuple()
    {
        var source = @"
class LambdaBox {
    Value: int
    Items: int[]
}

func main(): int {
    offset := 2
    box := new LambdaBox { Value: 5, Items: [6, 7] }

    compute := () => {
        box.Value = box.Value + offset
        snapshot := new LambdaBox { Value: box.Value + offset, Items: [offset, box.Items[0]] }
        pair := (offset, box.Value)
        return snapshot.Value * 100
            + pair.Item2 * 10
            + snapshot.Items[1]
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(976, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithRangeSpreadAndIndexFromEnd()
    {
        var source = @"
func main(): int {
    offset := 2
    values := [1, 2, 3, 4]
    label := ""wxyz""

    compute := () => {
        pieces := [offset, ...values[1..3]]
        return pieces[0] * 100
            + pieces[1] * 10
            + pieces[2]
            + (int)label[^1]
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(345, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithNestedLambdaCheckedAndUnchecked()
    {
        var source = @"
func main(): int {
    offset := 2

    compute := () => {
        nested: Func<int> = () => offset + 1
        ternaryValue := offset > 1 ? nested() : 0
        checkedValue := checked(offset + 1)
        uncheckedValue := unchecked(2147483647 + 1)

        if uncheckedValue < 0 {
            return ternaryValue + checkedValue + 1
        }

        return 0
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(7, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithLockLoopsAndFinally()
    {
        var source = @"
import System

func main(): int {
    offset := 2
    values := [1, 2, 3]
    gate := new object()

    compute := () => {
        total := 0
        index := 0

        try {
            lock gate {
                for value in values {
                    total += value + offset
                }

                while index < 3 {
                    index += 1
                    if index == 2 {
                        continue
                    }

                    total += index

                    if index == 3 {
                        break
                    }
                }
            }
        } finally {
            total += offset
        }

        return total
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(18, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithPatternMatchAndIsBinding()
    {
        var source = @"
func main(): int {
    offset := 2
    values := [1, 2, 3, 4]
    maybe: object = ""hi""

    compute := () => {
        total := 0

        if maybe is string s {
            total += s.Length
        }

        matched := match values {
            [1, 2, 3, 4] => offset + 5
            _ => 0
        }

        return total + matched
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(9, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaWithSwitchAssertAndLocalFunction()
    {
        var source = @"
import System

func main(): int {
    seed := 2
    items := [1, 2, 3]
    maybe: object = ""xy""

    compute := () => {
        total := 0

        first, second := (seed, items[0])

        switch first + second {
            case 3 => total += 10
            default => total += 1
        }

        assert total == 10

        assert throws InvalidOperationException {
            throw new InvalidOperationException(""boom"")
        }

        print second

        func addLocal(value: int): int => value + seed

        if maybe is string text {
            total += addLocal(text.Length)
        }

        return total
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(14, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanInferGenericLocalFunctionFromDelegateAndArrayArguments()
    {
        var source = @"
func main(): int {
    prefix := 2
    formatter: Func<int, string> = value => ""v="" + (value + prefix)

    func project<T>(items: T[], format: Func<T, string>): int {
        return items.Length * 10 + prefix
    }

    value := project([3, 4], formatter)
    return value * 10 + formatter(5).Length
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(223, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_EmitsComplexClrAttributeArgumentShapes()
    {
        var source = @"
import System
import NSharpLang.Tests

[RuntimeCoverage(
    RuntimeCoverageMetadata.DefaultCode,
    [""alpha"", nameof(Covered), RuntimeCoverageMetadata.Label],
    Enabled = !false,
    Mode = RuntimeCoverageMetadata.DefaultMode,
    RuntimeType = typeof(RuntimeCoverageBag),
    Targets = AttributeTargets.Class | AttributeTargets.Struct)]
class Covered {
}";

        CompileAndInspect(source, assembly =>
        {
            var coveredType = assembly.GetType("Covered");
            Assert.NotNull(coveredType);

            var attribute = GetCustomAttribute(coveredType!, "NSharpLang.Tests.RuntimeCoverageAttribute");
            Assert.Equal(
                new object?[] { 19, new object?[] { "alpha", "Covered", "runtime" } },
                GetAttributeArguments(attribute));
            Assert.True(Assert.IsType<bool>(GetNamedAttributeValue(attribute, "Enabled")));
            Assert.Equal((int)ILCompilerCallMode.Fast, Assert.IsType<int>(GetNamedAttributeValue(attribute, "Mode")));
            Assert.Equal(typeof(RuntimeCoverageBag), Assert.IsAssignableFrom<Type>(GetNamedAttributeValue(attribute, "RuntimeType")));
            Assert.Equal(
                (int)(AttributeTargets.Class | AttributeTargets.Struct),
                Assert.IsType<int>(GetNamedAttributeValue(attribute, "Targets")));
            return true;
        });
    }

    [Fact]
    public void ILCompiler_EmitsExplicitFieldAndMethodVisibilityModifiers()
    {
        var source = @"
internal class VisibilityBox {
    public shown: int
    private hidden: int
    protected guarded: int
    internal shared: int
    protected internal bridge: int

    public func shownMethod(): int {
        return 0
    }

    private func hiddenMethod(): int {
        return 1
    }

    protected func guardedMethod(): int {
        return 2
    }

    internal func sharedMethod(): int {
        return 3
    }

    protected internal func bridgeMethod(): int {
        return 4
    }
}";

        CompileAndInspect(source, assembly =>
        {
            var type = assembly.GetType("VisibilityBox");
            Assert.NotNull(type);
            Assert.False(type!.IsPublic);

            var fields = type.GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.Contains(fields, field => field.Name == "shown" && field.IsPublic);
            Assert.Contains(fields, field => field.Name == "hidden" && field.IsPrivate);
            Assert.Contains(fields, field => field.Name == "guarded" && field.IsFamily);
            Assert.Contains(fields, field => field.Name == "shared" && field.IsAssembly);
            Assert.Contains(fields, field => field.Name == "bridge" && field.IsFamilyOrAssembly);

            var methods = type.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                .Where(method => !method.IsSpecialName)
                .ToArray();
            Assert.Contains(methods, method => method.Name == "shownMethod" && method.IsPublic);
            Assert.Contains(methods, method => method.Name == "hiddenMethod" && method.IsPrivate);
            Assert.Contains(methods, method => method.Name == "guardedMethod" && method.IsFamily);
            Assert.Contains(methods, method => method.Name == "sharedMethod" && method.IsAssembly);
            Assert.Contains(methods, method => method.Name == "bridgeMethod" && method.IsFamilyOrAssembly);
            return true;
        });
    }

    [Fact]
    public void ILCompiler_CanInferTopLevelGenericBindingsFromArrayArguments()
    {
        var source = @"
func second<T>(items: T[]): T {
    return items[1]
}

func main(): int {
    return second([3, 4, 5])
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(4, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteTopLevelGenericDelegateInvocationAcrossListAndTuple()
    {
        var source = @"
import System.Collections.Generic

func project<T>(items: List<T>, pair: (T, T), format: Func<T, string>): int {
    return items.Count * 100
        + format(pair.Item1).Length * 10
        + format(pair.Item2).Length
}

func main(): int {
    items := new List<int>()
    items.Add(7)
    items.Add(8)
    format: Func<int, string> = value => ""n"" + value
    return project<int>(items, (7, 8), format)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(222, Assert.IsType<int>(result));
    }

    [Fact]
    public async Task ILCompiler_CanWrapImplicitAsyncReturnTypesForEntryPointAndHelpersAsync()
    {
        var source = @"
import System.Threading.Tasks

async func helper(): int {
    await Task.Yield()
    return 7
}

async func main() {
    value := await helper()
    assert value == 7
}";

        var result = await CompileAndInvokeTaskResult(source);
        Assert.Equal("System.Threading.Tasks.VoidTaskResult", result?.GetType().FullName);
    }

    [Fact]
    public async Task ILCompiler_CanWrapImplicitAsyncReturnTypesForLocalFunctionsAsync()
    {
        var source = @"
import System.Threading.Tasks

async func main(): Task<int> {
    func async helper(): int {
        await Task.Yield()
        return 4
    }

    return await helper()
}";

        var result = await CompileAndInvokeTaskResult(source);
        Assert.Equal(4, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaCapturingHighIndexParameters()
    {
        var parameters = string.Join(", ", Enumerable.Range(0, 260).Select(index => $"p{index}: int"));
        var arguments = string.Join(", ", Enumerable.Range(0, 260));
        var source = $$"""
func capture({{parameters}}): int {
    compute := () => p0 + p1 + p2 + p3 + p4 + p259
    return compute()
}

func main(): int {
    return capture({{arguments}})
}
""";

        var result = CompileAndInvoke(source);
        Assert.Equal(269, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanInferGenericLocalFunctionAcrossNamedTupleDelegateAndParams()
    {
        var source = @"
import System.Collections.Generic

func main(): int {
    seed := 5

    func project<T>(items: List<T>, pair: (T, T), format: Func<T, string>, bonus: int = 2, params extras: T[]): int {
        return seed * 1000
            + bonus * 100
            + items.Count * 10
            + extras.Length
            + format(pair.Item2).Length
    }

    values: List<int> = [7, 8, 9]
    extras := [1, 2]
    formatter: Func<int, string> = value => ""v"" + value

    return project(items: values, pair: (7, 8), format: formatter, extras: extras)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(5234, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanInferClrGenericBindingsFromTupleAndDelegateArguments()
    {
        var source = @"
func main(): int {
    formatter: Func<int, string> = value => ""v"" + value
    return ILCompilerCallHelpers.ScorePair((7, 8), formatter)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(22, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanBindClrGenericNamedOptionalAndDirectParamsArrayArguments()
    {
        var source = @"
func main(): int {
    extras := [4, 5]
    return ILCompilerCallHelpers.DescribeGeneric(value: 7, rest: extras)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(121, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteClosureLambdaCapturingMultipleParameters()
    {
        var source = @"
func make(a: int, b: int, c: int, d: int, e: int): Func<int> {
    bonus := 1
    compute := () => a + b + c + d + e + bonus
    return compute
}

func main(): int {
    return make(1, 2, 3, 4, 5)()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(16, Assert.IsType<int>(result));
    }
}
