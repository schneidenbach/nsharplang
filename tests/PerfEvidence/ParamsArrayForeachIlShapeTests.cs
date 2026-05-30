using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Regression guards for IL emitted when a method declares a <c>params</c> array and then iterates
/// it. Two distinct defects produced unverifiable IL that <c>dotnet ilverify</c> rejected with
/// <c>[StackUnexpected]</c> (PR #172 baseline entries for <c>ParamsArrays.dll</c>):
///
/// <list type="number">
/// <item>
/// <b>Mixed-width arithmetic.</b> <c>sum / values.Length</c> divides a <c>double</c> (R8) by the
/// array length (<c>int32</c>). The emitter pushed both operands raw and emitted <c>div</c> over
/// mismatched stack types. The fix applies ECMA-335 binary numeric promotion, widening the int
/// length to <c>float64</c> via <c>conv.r8</c> before <c>div</c>.
/// </item>
/// <item>
/// <b>Unboxed generic hole.</b> An interpolated-string hole of an unconstrained generic type
/// parameter <c>T</c> routed through <c>AppendFormatted(object, int, string)</c> but was not boxed,
/// leaving a <c>T</c> on the stack where <c>object</c> was required. The fix boxes generic-parameter
/// holes (<c>box !!T</c>) just like value-type holes on that overload.
/// </list>
///
/// These tests pin the IL shape so the defects cannot silently return when the (separate) blocking
/// <c>ilverify</c> CI gate is not run locally.
/// </summary>
public class ParamsArrayForeachIlShapeTests
{
    // Top-level functions emit onto the synthesized `Program` type, exactly as the failing
    // examples/03-functions/ParamsArrays.nl does. This is the scenario that reproduced the
    // unverifiable IL (generic functions become generic methods whose T is a real
    // GenericTypeParameterBuilder, forcing the boxed object-overload interpolation path).
    private const string Source = @"
func Average(params values: double[]): double {
    if values.Length == 0 {
        return 0.0
    }

    sum := 0.0
    for val in values {
        sum = sum + val
    }

    return sum / values.Length
}

func PrintAll<T>(prefix: string, params items: T[]) {
    for item in items {
        print $""{prefix}{item}""
    }
}

func Main() {
    print ""run""
}
";

    [Fact]
    public void ParamsDoubleArray_AverageDivision_WidensIntLengthToDouble()
    {
        ILShapeInspector.Compile(Source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "Average");
            var instructions = ILShapeInspector.Decode(method);

            // The division of `sum / values.Length` must convert the int32 length to float64 first;
            // otherwise `div` sees R8 vs I4 and the IL is unverifiable.
            Assert.True(
                ILShapeInspector.CountOpcode(instructions, OpCodes.Div) >= 1,
                "Average must emit a `div` for `sum / values.Length`.");
            Assert.True(
                ILShapeInspector.CountOpcode(instructions, OpCodes.Conv_R8) >= 1,
                "Average must widen the int32 array length to float64 (conv.r8) before dividing.");

            // The conv.r8 must immediately precede the div (the right operand is the int length).
            for (var i = 0; i < instructions.Count; i++)
            {
                if (instructions[i].OpCode == OpCodes.Div)
                {
                    Assert.True(i > 0, "div cannot be the first instruction.");
                    Assert.Equal(OpCodes.Conv_R8, instructions[i - 1].OpCode);
                    return 0;
                }
            }

            Assert.Fail("Expected a div instruction in Average.");
            return 0;
        });
    }

    [Fact]
    public void GenericParamsArray_InterpolatedHole_BoxesTypeParameter()
    {
        ILShapeInspector.Compile(Source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "PrintAll");

            // The generic `{item}` hole is an unconstrained T, which is not statically object-
            // assignable: it must be boxed before the AppendFormatted(object, ...) overload.
            Assert.True(
                ILShapeInspector.CountBoxing(method) >= 1,
                "Generic interpolated-string hole of type T must be boxed before AppendFormatted(object, ...).");
            return 0;
        });
    }
}
