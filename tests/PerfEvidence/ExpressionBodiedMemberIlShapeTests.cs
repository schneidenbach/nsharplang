using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Regression guard for expression-bodied member codegen. An expression-bodied property getter
/// (or method) whose expression's natural type differs from the declared return type must emit
/// the implicit conversion to that return type before <c>ret</c>, exactly as the statement form
/// <c>{ return expr }</c> does via <c>EmitReturn</c>.
///
/// Without the conversion, an int-typed expression returned from a <c>double</c> getter leaves an
/// <c>int32</c> on the evaluation stack at <c>ret</c>, which <c>dotnet ilverify</c> rejects with
/// <c>[StackUnexpected]</c> (the same defect class the blocking ilverify CI gate catches). This was
/// observed on <c>Rectangle::get_Perimeter()</c> in examples/03-functions/ExpressionBodiedMembers.nl.
/// These tests pin the IL shape so the defect cannot silently return when the ilverify gate is not
/// run locally.
/// </summary>
public class ExpressionBodiedMemberIlShapeTests
{
    // `Perimeter`'s expression `2 * (Width + Height)` mixes an int literal with double fields, so its
    // product must be converted to the declared `double` return type before `ret`. `Area` is already
    // double-typed and serves as a control: it must still end cleanly in a single `ret`.
    private const string Source = @"
class Rectangle {
    readonly Width: double
    readonly Height: double

    Area: double => Width * Height
    Perimeter: double => 2 * (Width + Height)

    func Scale(factor: int): double => Width * factor

    constructor(width: double, height: double) {
        Width = width
        Height = height
    }
}
";

    [Fact]
    public void ExpressionBodiedDoubleGetter_ConvertsIntExpressionBeforeRet()
    {
        ILShapeInspector.Compile(Source, assembly =>
        {
            var rectangle = assembly.GetType("Rectangle");
            Assert.NotNull(rectangle);

            var getter = rectangle!.GetMethod("get_Perimeter", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(getter);
            Assert.Equal(typeof(double), ((MethodInfo)getter!).ReturnType);

            var instructions = ILShapeInspector.Decode(getter);

            // The int-valued product must be widened to float64 before being returned.
            Assert.True(
                ILShapeInspector.CountOpcode(instructions, OpCodes.Conv_R8) >= 1,
                "Expected a conv.r8 widening the int expression to the double return type in get_Perimeter.");

            AssertSingleTrailingRet(instructions, "get_Perimeter");
            return 0;
        });
    }

    [Fact]
    public void ExpressionBodiedDoubleGetter_AlreadyDoubleTyped_HasSingleRet()
    {
        // Control: a getter whose expression is already the declared return type must not regress to
        // emitting a stray extra `ret` (the previous code emitted two consecutive `ret` opcodes).
        ILShapeInspector.Compile(Source, assembly =>
        {
            var rectangle = assembly.GetType("Rectangle");
            Assert.NotNull(rectangle);

            var getter = rectangle!.GetMethod("get_Area", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(getter);

            var instructions = ILShapeInspector.Decode(getter);
            AssertSingleTrailingRet(instructions, "get_Area");
            return 0;
        });
    }

    [Fact]
    public void ExpressionBodiedDoubleMethod_ConvertsIntExpressionBeforeRet()
    {
        // Methods share the EmitFunctionBody expression-body path; the same conversion must apply.
        ILShapeInspector.Compile(Source, assembly =>
        {
            var rectangle = assembly.GetType("Rectangle");
            Assert.NotNull(rectangle);

            var scale = rectangle!.GetMethod("Scale", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(scale);
            Assert.Equal(typeof(double), scale!.ReturnType);

            var instructions = ILShapeInspector.Decode(scale);
            Assert.True(
                ILShapeInspector.CountOpcode(instructions, OpCodes.Conv_R8) >= 1,
                "Expected a conv.r8 widening the int factor to the double return type in Scale.");

            AssertSingleTrailingRet(instructions, "Scale");
            return 0;
        });
    }

    /// <summary>
    /// Asserts the decoded body contains exactly one <c>ret</c> and that it is the final instruction.
    /// Guards against the previous double-<c>ret</c> emission in the property expression-body path.
    /// </summary>
    private static void AssertSingleTrailingRet(System.Collections.Generic.IReadOnlyList<ILInstruction> instructions, string methodName)
    {
        var retCount = instructions.Count(instruction => instruction.OpCode == OpCodes.Ret);
        Assert.True(retCount == 1, $"Expected exactly one ret in {methodName} but found {retCount}.");
        Assert.True(
            instructions.Count > 0 && instructions[^1].OpCode == OpCodes.Ret,
            $"Expected {methodName} to end with ret.");
    }
}
