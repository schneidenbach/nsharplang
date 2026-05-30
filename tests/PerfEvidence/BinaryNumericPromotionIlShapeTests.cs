using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Regression guard for binary numeric promotion in arithmetic codegen. When the two
/// operands of <c>+ - * / %</c> (or a relational compare) have different primitive
/// numeric types — e.g. <c>intField / (double)other</c> — the emitter must coerce the
/// narrower operand up to the common type BEFORE emitting the raw <c>div</c>/<c>mul</c>
/// opcode. Without that promotion the verifier rejects the IL with
/// <c>[StackUnexpected] found Int32, expected Double</c> (and the arithmetic is wrong at
/// runtime). This was the defect behind the <c>ConversionOperators.dll</c> ilverify
/// findings on <c>Fraction::op_Explicit</c> and <c>Fraction::FromDouble</c>.
/// </summary>
public class BinaryNumericPromotionIlShapeTests
{
    // Mirrors examples/11-advanced-features/ConversionOperators: an explicit conversion
    // operator that divides an int field by a double, and a factory that multiplies a
    // double parameter by an int parameter.
    private const string Source = @"
struct Fraction {
    Numerator: int
    Denominator: int

    explicit operator double(f: Fraction) {
        return f.Numerator / (double)f.Denominator
    }

    static func FromDouble(value: double, precision: int): Fraction {
        numerator := (int)(value * precision)
        return new Fraction { Numerator: numerator, Denominator: precision }
    }
}
";

    [Fact]
    public void ExplicitConversionOperator_PromotesIntOperandBeforeDivide()
    {
        ILShapeInspector.Compile(Source, assembly =>
        {
            var fraction = assembly.GetType("Fraction");
            Assert.NotNull(fraction);
            Assert.True(fraction!.IsValueType, "Fraction should be emitted as a value type.");

            var opExplicit = fraction.GetMethod(
                "op_Explicit",
                BindingFlags.Public | BindingFlags.Static,
                binder: null,
                types: new[] { fraction },
                modifiers: null);
            Assert.NotNull(opExplicit);
            Assert.Equal(typeof(double), opExplicit!.ReturnType);

            var instructions = ILShapeInspector.Decode(opExplicit);

            // The int Numerator must be widened to double before the div, so the div
            // operates on two doubles and the method returns a double (verifiable).
            AssertConvR8PrecedesArithmetic(instructions, OpCodes.Div, "op_Explicit");

            // Behaviour: 3/4 == 0.75 (true floating-point division, not integer 0).
            // Build the Fraction via the factory to avoid boxed-struct field mutation.
            var fromDouble = fraction.GetMethod(
                "FromDouble",
                BindingFlags.Public | BindingFlags.Static,
                binder: null,
                types: new[] { typeof(double), typeof(int) },
                modifiers: null);
            Assert.NotNull(fromDouble);
            // FromDouble(0.75, 4) -> Numerator (int)(0.75*4)=3, Denominator 4.
            var instance = fromDouble!.Invoke(null, new object[] { 0.75, 4 })!;
            var converted = (double)opExplicit.Invoke(null, new[] { instance })!;
            Assert.Equal(0.75, converted, precision: 10);

            return 0;
        });
    }

    [Fact]
    public void Factory_PromotesIntOperandBeforeMultiply()
    {
        ILShapeInspector.Compile(Source, assembly =>
        {
            var fraction = assembly.GetType("Fraction");
            Assert.NotNull(fraction);

            var fromDouble = fraction!.GetMethod(
                "FromDouble",
                BindingFlags.Public | BindingFlags.Static,
                binder: null,
                types: new[] { typeof(double), typeof(int) },
                modifiers: null);
            Assert.NotNull(fromDouble);

            var instructions = ILShapeInspector.Decode(fromDouble!);

            // The int precision must be widened to double before the mul, so the mul
            // operates on two doubles (verifiable) before the explicit (int) cast.
            AssertConvR8PrecedesArithmetic(instructions, OpCodes.Mul, "FromDouble");

            // Behaviour: FromDouble(0.75, 1000) -> Numerator 750, Denominator 1000.
            var result = fromDouble!.Invoke(null, new object[] { 0.75, 1000 })!;
            var numerator = (int)fraction.GetField("Numerator")!.GetValue(result)!;
            var denominator = (int)fraction.GetField("Denominator")!.GetValue(result)!;
            Assert.Equal(750, numerator);
            Assert.Equal(1000, denominator);

            return 0;
        });
    }

    /// <summary>
    /// Asserts that a <c>conv.r8</c> appears before the first occurrence of
    /// <paramref name="arithmetic"/>, evidencing that the narrower (int) operand was
    /// promoted to double prior to the mixed-numeric arithmetic opcode.
    /// </summary>
    private static void AssertConvR8PrecedesArithmetic(
        System.Collections.Generic.IReadOnlyList<ILInstruction> instructions,
        OpCode arithmetic,
        string methodName)
    {
        var arithmeticIndex = -1;
        for (var i = 0; i < instructions.Count; i++)
        {
            if (instructions[i].OpCode == arithmetic)
            {
                arithmeticIndex = i;
                break;
            }
        }

        Assert.True(arithmeticIndex >= 0, $"Expected a '{arithmetic.Name}' instruction in {methodName}.");

        var hasPrecedingConvR8 = instructions
            .Take(arithmeticIndex)
            .Any(instruction => instruction.OpCode == OpCodes.Conv_R8);

        Assert.True(
            hasPrecedingConvR8,
            $"Expected a 'conv.r8' before '{arithmetic.Name}' in {methodName}; the narrower int operand " +
            "must be promoted to double so the arithmetic operates on a single CLI stack type.");
    }
}
