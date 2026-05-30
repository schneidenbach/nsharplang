using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Regression guard for compound-assignment string concatenation codegen
/// (the SpreadInFunctionCalls <c>ExpectedNumericType</c> findings).
/// <para>
/// <c>result += s</c> on a <see cref="string"/> target must lower to
/// <c>string.Concat(object, object)</c>, NOT the <c>add</c> arithmetic opcode. Emitting
/// <c>add</c> on two object references produces unverifiable IL that <c>dotnet ilverify</c>
/// rejects with <c>[ExpectedNumericType]</c>. Every compound-assignment emission site
/// (local, parameter, field, property, index, stack buffer) routes through
/// <c>EmitCompoundAssignmentOperation</c>, so this pins the IL shape against regressions
/// that the separate blocking ilverify CI gate would otherwise be the only line of defense for.
/// </para>
/// </summary>
public class StringCompoundConcatIlShapeTests
{
    // A params function that concatenates strings with `+=` over a spread-able array,
    // mirroring SpreadInFunctionCalls.Concatenate. No numeric arithmetic in the body other
    // than the loop counter, which is exercised by a separate guard below.
    private const string StringConcatNoLoopSource = @"
func Join(a: string, b: string, c: string): string {
    result := """"
    result += a
    result += b
    result += c
    return result
}

func Main() {
    print Join(""x"", ""y"", ""z"")
}
";

    private const string IntCompoundSource = @"
func AddUp(a: int, b: int, c: int): int {
    total := 0
    total += a
    total += b
    total += c
    return total
}

func Main() {
    print AddUp(1, 2, 3)
}
";

    [Fact]
    public void StringCompoundAssignment_LowersToConcat_NotAddOpcode()
    {
        ILShapeInspector.Compile(StringConcatNoLoopSource, assembly =>
        {
            var join = ILShapeInspector.GetProgramMethod(assembly, "Join");

            // The bug: `result += s` emitted `add` on two string references (ExpectedNumericType).
            // The body has no numeric arithmetic, so a verifiable lowering contains ZERO add/sub/mul/div.
            Assert.Equal(0, ILShapeInspector.CountOpcode(join, OpCodes.Add));
            Assert.Equal(0, ILShapeInspector.CountOpcode(join, OpCodes.Sub));
            Assert.Equal(0, ILShapeInspector.CountOpcode(join, OpCodes.Mul));
            Assert.Equal(0, ILShapeInspector.CountOpcode(join, OpCodes.Div));

            // Each of the three `+=` must lower to a string.Concat(object, object) call.
            Assert.Equal(3, ILShapeInspector.CountCallsTo(join, typeof(string), nameof(string.Concat)));
            return 0;
        });
    }

    [Fact]
    public void IntCompoundAssignment_StillUsesAddOpcode()
    {
        // Asymmetry guard: routing string `+=` through Concat must not break numeric `+=`,
        // which must still emit the `add` arithmetic opcode (and never string.Concat).
        ILShapeInspector.Compile(IntCompoundSource, assembly =>
        {
            var addUp = ILShapeInspector.GetProgramMethod(assembly, "AddUp");

            Assert.Equal(3, ILShapeInspector.CountOpcode(addUp, OpCodes.Add));
            Assert.Equal(0, ILShapeInspector.CountCallsTo(addUp, typeof(string), nameof(string.Concat)));
            return 0;
        });
    }
}
