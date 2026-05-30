using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// ADDITIVE IL-validity coverage for payload-carrying discriminated unions
/// (<c>union Shape { Circle { radius: int } ... }</c>) — construction and match/case payload
/// extraction.
///
/// The existing <see cref="IlShapeRegressionTests.Gate_ValueStructUnion_DoesNotBox"/> only covers a
/// <em>payload-free</em> value-struct union. Payload-carrying unions lower to a class hierarchy
/// (each case a derived type); matching a case is an <c>isinst</c> type-test plus <c>ldfld</c> reads
/// of the case's payload fields. The verifiability risks here are: a stray <c>box</c> of the union
/// reference, an unbalanced <c>isinst</c>/<c>dup</c>/<c>pop</c> probe, or extracting a payload field
/// without first narrowing the reference to the case type. These tests pin that shape.
/// </summary>
public class UnionPayloadILShapeTests
{
    private const string ShapeUnion = @"
union Shape {
    Circle { radius: int }
    Rect { w: int, h: int }
}
";

    private static IReadOnlyList<ILInstruction> Decode(Assembly assembly, string method) =>
        ILShapeInspector.Decode(ILShapeInspector.GetProgramMethod(assembly, method));

    [Fact]
    public void PayloadUnionMatch_ExtractsFieldsViaIsinstAndLdfld_NoBoxing()
    {
        const string source = ShapeUnion + @"
func area(s: Shape): int {
    return match s {
        Shape.Circle { radius } => radius * radius,
        Shape.Rect { w, h } => w * h
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var instructions = Decode(assembly, "area");
            var area = ILShapeInspector.GetProgramMethod(assembly, "area");

            // Payload-carrying union => reference class hierarchy.
            var shapeType = assembly.GetType("Shape");
            Assert.NotNull(shapeType);
            Assert.False(shapeType!.IsValueType, "A payload-carrying union lowers to a reference class hierarchy.");

            // Two cases => two isinst probes, each bracketed by a dup, each no-match path popping.
            var isinst = ILShapeInspector.CountOpcode(instructions, OpCodes.Isinst);
            Assert.Equal(2, isinst);
            for (var i = 0; i < instructions.Count; i++)
            {
                if (instructions[i].OpCode == OpCodes.Isinst)
                {
                    Assert.True(
                        i + 1 < instructions.Count && instructions[i + 1].OpCode == OpCodes.Dup,
                        "Each union-case isinst probe must be bracketed by a dup.");
                }
            }
            Assert.True(
                ILShapeInspector.CountOpcode(instructions, OpCodes.Pop) >= isinst,
                "Each union-case no-match path must pop the duplicated reference.");

            // Payload extraction reads case fields: Circle.radius (1) + Rect.w + Rect.h (2) => >= 3 ldfld.
            Assert.True(
                ILShapeInspector.CountOpcode(instructions, OpCodes.Ldfld) >= 3,
                "Payload extraction must read the case fields via ldfld.");

            // Matching a reference union must not box the union reference.
            ILShapeInspector.AssertNoBoxing(area);
            return 0;
        });
    }

    [Fact]
    public void PayloadUnionConstruction_AllocatesCaseType_AndExecutes()
    {
        // Construction (new Shape.Circle(r)) must produce the case type and the round-trip
        // construct -> match -> extract must compute correctly at runtime (token validity).
        const string source = ShapeUnion + @"
func area(s: Shape): int {
    return match s {
        Shape.Circle { radius } => radius * radius,
        Shape.Rect { w, h } => w * h
    }
}

func circleArea(r: int): int {
    c := new Shape.Circle(r)
    return area(c)
}

func rectArea(w: int, h: int): int {
    r := new Shape.Rect(w, h)
    return area(r)
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            // Constructing a reference-union case allocates the case object (newobj).
            var circleArea = ILShapeInspector.GetProgramMethod(assembly, "circleArea");
            Assert.True(
                ILShapeInspector.CountOpcode(circleArea, OpCodes.Newobj) >= 1,
                "Constructing a payload union case must allocate the case object via newobj.");

            Assert.Equal(25, circleArea.Invoke(null, new object[] { 5 }));

            var rectArea = ILShapeInspector.GetProgramMethod(assembly, "rectArea");
            Assert.Equal(12, rectArea.Invoke(null, new object[] { 3, 4 }));
            return 0;
        });
    }

    [Fact]
    public void PayloadFreeUnionMatch_StaysValueStruct_AndDoesNotBox()
    {
        // Companion to the payload case: a mixed-construct check that a payload-FREE union remains a
        // value struct and matching it does not box (complements Gate_ValueStructUnion_DoesNotBox with
        // a more-than-two-case shape and an int extraction in the body).
        const string source = @"
union Signal {
    Red
    Yellow
    Green
}

func cost(s: Signal): int {
    return match s {
        Signal.Red => 3,
        Signal.Yellow => 2,
        Signal.Green => 1
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var signalType = assembly.GetType("Signal");
            Assert.NotNull(signalType);
            Assert.True(signalType!.IsValueType, "Payload-free union must lower to a value struct.");

            var cost = ILShapeInspector.GetProgramMethod(assembly, "cost");
            ILShapeInspector.AssertNoBoxing(cost);
            return 0;
        });
    }
}
