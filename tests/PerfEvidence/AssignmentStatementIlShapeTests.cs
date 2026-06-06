using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Regression tests for statement-context assignment lowering.
///
/// Assignment expressions still produce the assigned value when that value is consumed by an
/// enclosing expression. Plain assignment statements, however, must not reload that value only for
/// the expression-statement emitter to pop it. The compiler-service dogfood scanners are dense with
/// local and indexed assignment statements, so this shape is part of the systems-code hot path.
/// </summary>
public class AssignmentStatementIlShapeTests
{
    [Fact]
    public void AssignmentStatements_DoNotReloadAssignedValuesToPop()
    {
        const string source = """
func store(buffer: int[]): int {
    i := 0
    buffer[i] = 42
    i = i + 1
    return buffer[0] + i
}
""";

        var il = ILShapeInspector.DecodeProgramMethod(source, "store");

        Assert.Equal(0, ILShapeInspector.CountOpcode(il, OpCodes.Pop));
        Assert.Equal(1, ILShapeInspector.CountOpcode(il, OpCodes.Stelem_I4));
    }

    [Fact]
    public void NestedAssignmentExpression_StillReturnsAssignedValue()
    {
        const string source = """
func chain(): int {
    x := 0
    y := 0
    x = y = 5
    return x + y
}
""";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "chain");

            Assert.Equal(10, method.Invoke(null, null));
            Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Pop));
            return 0;
        });
    }
}
