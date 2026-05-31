using System;
using System.Reflection;
using Xunit;

namespace NSharpLang.Tests;

public partial class ILCompilerTests
{
    private static T InvokeStatic<T>(Assembly assembly, string methodName)
    {
        var programType = assembly.GetType("Program");
        Assert.NotNull(programType);

        var method = programType!.GetMethod(methodName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
        Assert.NotNull(method);

        return Assert.IsType<T>(method!.Invoke(null, null));
    }

    [Fact]
    public void ILCompiler_PrimitiveArithmeticOperators_ExecuteExpectedResults()
    {
        var source = """
func intOps(): int {
    return (20 + 6) * 2 - 10 / 2 + 17 % 5
}

func integerDivisionTruncates(): int {
    return 7 / 2
}

func byteAndShortPromoteToInt(): int {
    left: byte = (byte)250
    right: short = (short)8
    return left + right
}

func byteAndBytePromoteToInt(): int {
    left: byte = (byte)200
    right: byte = (byte)55
    return left + right
}

func charArithmeticPromotesToInt(): int {
    letter: char = 'A'
    return letter + 2
}

func intLongPromotesToLong(): long {
    left: long = (long)40
    return left + 2
}

func intFloatPromotesToFloat(): float {
    value: float = 1.5f
    return value + 2
}

func intDoubleDivisionPromotesToDouble(): double {
    left := 5
    right := 2.0
    return left / right
}

func decimalArithmeticUsesRuntimeOperators(): decimal {
    first: decimal = 10.5m
    second: decimal = 2.5m
    return first + second * 2m - 1m
}
""";

        CompileAndInspect(source, assembly =>
        {
            Assert.Equal(49, InvokeStatic<int>(assembly, "intOps"));
            Assert.Equal(3, InvokeStatic<int>(assembly, "integerDivisionTruncates"));
            Assert.Equal(258, InvokeStatic<int>(assembly, "byteAndShortPromoteToInt"));
            Assert.Equal(255, InvokeStatic<int>(assembly, "byteAndBytePromoteToInt"));
            Assert.Equal(67, InvokeStatic<int>(assembly, "charArithmeticPromotesToInt"));
            Assert.Equal(42L, InvokeStatic<long>(assembly, "intLongPromotesToLong"));
            Assert.Equal(3.5f, InvokeStatic<float>(assembly, "intFloatPromotesToFloat"), precision: 5);
            Assert.Equal(2.5, InvokeStatic<double>(assembly, "intDoubleDivisionPromotesToDouble"), precision: 5);
            Assert.Equal(14.5m, InvokeStatic<decimal>(assembly, "decimalArithmeticUsesRuntimeOperators"));
            return true;
        });
    }

    [Fact]
    public void ILCompiler_PrimitiveComparisonAndEqualityOperators_ExecuteExpectedResults()
    {
        var source = """
class Box {
    Value: int
}

func comparisonScore(): int {
    score := 0

    if 4 == 4 {
        score += 1
    }

    if 4 != 5 {
        score += 2
    }

    if 2 < 3 {
        score += 4
    }

    if 3 <= 3 {
        score += 8
    }

    if 5 > 4 {
        score += 16
    }

    if 5 >= 5 {
        score += 32
    }

    if 3 < 3.5 {
        score += 64
    }

    return score
}

func stringEqualityIsValueBased(): int {
    left := "he" + "llo"
    right := "hello"

    if left == right && left != "world" {
        return 1
    }

    return 0
}

func referenceEqualityScore(): int {
    first := new Box { Value: 1 }
    same := first
    other := new Box { Value: 1 }
    score := 0

    if first == same {
        score += 1
    }

    if first != other {
        score += 2
    }

    return score
}

func nanComparisonScore(): int {
    nan := 0.0 / 0.0
    score := 0

    if !(nan < 1.0) {
        score += 1
    }

    if !(nan > 1.0) {
        score += 2
    }

    if !(nan <= 1.0) {
        score += 4
    }

    if !(nan >= 1.0) {
        score += 8
    }

    if nan != nan {
        score += 16
    }

    return score
}
""";

        CompileAndInspect(source, assembly =>
        {
            Assert.Equal(127, InvokeStatic<int>(assembly, "comparisonScore"));
            Assert.Equal(1, InvokeStatic<int>(assembly, "stringEqualityIsValueBased"));
            Assert.Equal(3, InvokeStatic<int>(assembly, "referenceEqualityScore"));
            Assert.Equal(31, InvokeStatic<int>(assembly, "nanComparisonScore"));
            return true;
        });
    }

    [Fact]
    public void ILCompiler_BitwiseShiftAndUnsignedOperators_ExecuteExpectedResults()
    {
        var source = """
func signedBitwiseAndShift(): int {
    return (6 & 3) * 1000 + (6 | 3) * 100 + (6 ^ 3) * 10 + ((1 << 4) >> 2)
}

func unsignedRightShiftZeroFills(): uint {
    value: uint = unchecked((uint)(-2147483647 - 1))
    return value >> 1
}

func unsignedDivisionUsesUnsignedOpcode(): uint {
    value: uint = unchecked((uint)-2)
    return value / (uint)2
}

func unsignedRemainderUsesUnsignedOpcode(): uint {
    value: uint = unchecked((uint)-2)
    return value % (uint)5
}

func unsignedComparisonScore(): int {
    small: uint = (uint)1
    large: uint = unchecked((uint)-1)
    score := 0

    if small < large {
        score += 1
    }

    if small <= large {
        score += 2
    }

    if large > small {
        score += 4
    }

    if large >= small {
        score += 8
    }

    return score
}
""";

        CompileAndInspect(source, assembly =>
        {
            Assert.Equal(2754, InvokeStatic<int>(assembly, "signedBitwiseAndShift"));
            Assert.Equal(1073741824u, InvokeStatic<uint>(assembly, "unsignedRightShiftZeroFills"));
            Assert.Equal(2147483647u, InvokeStatic<uint>(assembly, "unsignedDivisionUsesUnsignedOpcode"));
            Assert.Equal(4u, InvokeStatic<uint>(assembly, "unsignedRemainderUsesUnsignedOpcode"));
            Assert.Equal(15, InvokeStatic<int>(assembly, "unsignedComparisonScore"));
            return true;
        });
    }

    [Fact]
    public void ILCompiler_LogicalOperatorsShortCircuit()
    {
        var source = """
func bump(ref value: int): bool {
    value += 1
    return true
}

func andShortCircuits(): int {
    value := 0

    if false && bump(ref value) {
        return 99
    }

    return value
}

func orShortCircuits(): int {
    value := 0

    if true || bump(ref value) {
        return value
    }

    return 99
}

func logicalResultsStillCompose(): int {
    first := true
    second := false
    score := 0

    if first && !second {
        score += 1
    }

    if second || first {
        score += 2
    }

    return score
}
""";

        CompileAndInspect(source, assembly =>
        {
            Assert.Equal(0, InvokeStatic<int>(assembly, "andShortCircuits"));
            Assert.Equal(0, InvokeStatic<int>(assembly, "orShortCircuits"));
            Assert.Equal(3, InvokeStatic<int>(assembly, "logicalResultsStillCompose"));
            return true;
        });
    }

    [Fact]
    public void ILCompiler_CompoundAssignmentOperators_ExecuteExpectedResults()
    {
        var source = """
class Counter {
    Value: int
}

func localCompoundAssignments(): int {
    value := 5
    value += 7
    value -= 3
    value *= 4
    value /= 6
    return value
}

func memberCompoundAssignments(): int {
    counter := new Counter { Value: 10 }
    counter.Value += 5
    counter.Value -= 3
    counter.Value *= 2
    counter.Value /= 4
    return counter.Value
}

func stringPlusAssignConcatenates(): string {
    value := "N"
    value += "#"
    return value
}
""";

        CompileAndInspect(source, assembly =>
        {
            Assert.Equal(6, InvokeStatic<int>(assembly, "localCompoundAssignments"));
            Assert.Equal(6, InvokeStatic<int>(assembly, "memberCompoundAssignments"));
            Assert.Equal("N#", InvokeStatic<string>(assembly, "stringPlusAssignConcatenates"));
            return true;
        });
    }
}
