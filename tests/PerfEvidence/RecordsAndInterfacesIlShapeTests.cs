using System;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Regression guards for two unverifiable-IL defects in the records/interfaces surface that
/// <c>dotnet ilverify</c> previously rejected (see scripts/ilverify-baseline.txt):
///
/// (A) Mixed-type built-in arithmetic such as <c>4 * sideDouble</c> emitted <c>ldc.i4; ldfld float64;
///     mul</c> with no binary numeric promotion, leaving an Int32 result where a Double was expected
///     (<c>[IL:StackUnexpected] found Int32, expected Double</c>). The fix promotes the integer operand
///     to the common numeric type before the arithmetic opcode.
///
/// (B) A class implementing an interface that declared a default method (DIM) failed metadata
///     verification (<c>[MD] Class implements interface but not method ... Missing method
///     IShape.Describe()</c>) because the emitter declared every interface method abstract and never
///     emitted the default body. The fix emits the default body and marks the method virtual-concrete
///     so implementers need not override it.
///
/// These pin the IL shape so the defects cannot silently return when the (separate) blocking
/// <c>ilverify</c> CI gate is not run locally.
/// </summary>
public class RecordsAndInterfacesIlShapeTests
{
    private const string MixedArithmeticSource = @"
class Square {
    readonly Side: double

    constructor(side: double) {
        Side = side
    }

    func CalculatePerimeter(): double {
        return 4 * Side
    }
}
";

    private const string DefaultInterfaceMethodSource = @"
interface IShape {
    func GetArea(): double

    func Describe(): string {
        return ""shape""
    }
}

class Circle: IShape {
    readonly Radius: double

    constructor(radius: double) {
        Radius = radius
    }

    func GetArea(): double {
        return Radius * Radius
    }
}
";

    [Fact]
    public void MixedIntDoubleArithmetic_PromotesIntegerOperandToDouble()
    {
        ILShapeInspector.Compile(MixedArithmeticSource, assembly =>
        {
            var squareType = assembly.GetType("Square");
            Assert.NotNull(squareType);

            var method = squareType!.GetMethod("CalculatePerimeter");
            Assert.NotNull(method);
            Assert.Equal(typeof(double), method!.ReturnType);

            var instructions = ILShapeInspector.Decode(method);

            // The integer literal operand must be widened to double (conv.r8) so the `mul` operates
            // on two Double operands and leaves a Double on the stack for `ret`. Without promotion
            // the body is unverifiable (StackUnexpected: found Int32, expected Double).
            Assert.True(
                instructions.Any(i => i.OpCode == OpCodes.Conv_R8),
                "Expected a conv.r8 to promote the integer operand of `4 * Side` to double, " +
                "but none was emitted (mixed int/double arithmetic must undergo binary numeric promotion).");

            return 0;
        });
    }

    [Fact]
    public void Interface_WithDefaultMethod_EmitsConcreteVirtualBody()
    {
        ILShapeInspector.Compile(DefaultInterfaceMethodSource, assembly =>
        {
            var shapeType = assembly.GetType("IShape");
            Assert.NotNull(shapeType);
            Assert.True(shapeType!.IsInterface, "IShape should be emitted as an interface.");

            var describe = shapeType.GetMethod("Describe");
            Assert.NotNull(describe);

            // A default interface method is virtual but NOT abstract, and must carry an IL body.
            Assert.True(describe!.IsVirtual, "Default interface method Describe must be virtual.");
            Assert.False(describe.IsAbstract, "Default interface method Describe must not be abstract.");

            var body = describe.GetMethodBody();
            Assert.NotNull(body);
            Assert.NotEmpty(body!.GetILAsByteArray() ?? Array.Empty<byte>());

            // The abstract sibling has no default body and must remain abstract.
            var getArea = shapeType.GetMethod("GetArea");
            Assert.NotNull(getArea);
            Assert.True(getArea!.IsAbstract, "GetArea has no body and must remain abstract.");

            return 0;
        });
    }

    [Fact]
    public void Class_ImplementingInterfaceWithDefaultMethod_NeedNotOverrideDefault()
    {
        ILShapeInspector.Compile(DefaultInterfaceMethodSource, assembly =>
        {
            var shapeType = assembly.GetType("IShape");
            var circleType = assembly.GetType("Circle");
            Assert.NotNull(shapeType);
            Assert.NotNull(circleType);

            // Circle implements IShape...
            Assert.Contains(shapeType, circleType!.GetInterfaces());

            // ...but does NOT (and need not) provide its own Describe: it inherits the interface
            // default. The interface map must resolve Describe to the interface's own slot.
            var map = circleType.GetInterfaceMap(shapeType!);
            var describeIndex = Array.FindIndex(
                map.InterfaceMethods,
                m => string.Equals(m.Name, "Describe", StringComparison.Ordinal));
            Assert.True(describeIndex >= 0, "IShape.Describe must appear in Circle's interface map.");

            var target = map.TargetMethods[describeIndex];
            Assert.Equal(shapeType, target.DeclaringType);

            return 0;
        });
    }
}
