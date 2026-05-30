using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// ADDITIVE IL-validity coverage for <c>foreach</c> over <see cref="System.Span{T}"/> /
/// <see cref="System.ReadOnlySpan{T}"/>.
///
/// A span is a byref-like <em>ref struct</em>: boxing it, storing it in an object-typed slot, or
/// constructing an enumerator object over it all produce verification failures or escape a stack-only
/// type to the heap. The existing <see cref="IlShapeRegressionTests"/> only pins
/// <c>newobj == 0</c> for a <c>params ReadOnlySpan&lt;int&gt;</c>. These fill the gap with the
/// stronger ref-struct safety invariants and add the <em>mutable</em> <c>Span&lt;int&gt;</c> case:
/// the iteration must use a <c>get_Length</c> + indexer loop with NO <c>box</c> of the span, NO
/// enumerator allocation, and NO <c>constrained.</c>/<c>callvirt</c> interface dispatch.
/// </summary>
public class SpanForeachILShapeTests
{
    private static string[] OpcodeNames(MethodInfo method) =>
        ILShapeInspector.Decode(method).Select(i => i.OpCode.Name).ToArray();

    [Fact]
    public void ForeachOverReadOnlySpan_NoBox_NoEnumerator_NoVirtualDispatch()
    {
        const string source = @"
import System

func sumReadOnly(numbers: ReadOnlySpan<int>): int {
    sum := 0
    foreach num in numbers {
        sum = sum + num
    }
    return sum
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "sumReadOnly");
            var names = OpcodeNames(method);

            // The span ref struct must never be boxed nor escape to the heap.
            ILShapeInspector.AssertNoBoxing(method);
            Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Newobj));

            // Allocation-free index loop: no enumerator object, no interface dispatch.
            Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Callvirt));
            Assert.DoesNotContain("constrained.", names);

            // Positive proof it is the Length + indexer loop (calls get_Length / get_Item by ref).
            Assert.True(
                ILShapeInspector.CountOpcode(method, OpCodes.Call) >= 2,
                "Expected the span loop to call get_Length and get_Item.");
            return 0;
        });
    }

    [Fact]
    public void ForeachOverMutableSpan_NoBox_NoEnumerator()
    {
        // The mutable Span<int> case is not covered elsewhere. Same ref-struct safety must hold.
        const string source = @"
import System

func sumSpan(numbers: Span<int>): int {
    sum := 0
    foreach num in numbers {
        sum = sum + num
    }
    return sum
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "sumSpan");

            ILShapeInspector.AssertNoBoxing(method);
            Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Newobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Callvirt));
            return 0;
        });
    }

    [Fact]
    public void ForeachOverParamsSpan_FromCallSite_NoBoxAtBoundary()
    {
        // End-to-end: a params Span<int> call site materializes a verifiable heap array (proven by
        // ILShapeBaselineTests) and the callee iterates it allocation-free. Here we pin that the
        // callee body neither boxes the span nor allocates an enumerator, and the whole thing runs.
        const string source = @"
import System

func sum(params numbers: Span<int>): int {
    total := 0
    foreach n in numbers {
        total = total + n
    }
    return total
}

func main(): int {
    return sum(2, 4, 6, 8)
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var sum = ILShapeInspector.GetProgramMethod(assembly, "sum");
            ILShapeInspector.AssertNoBoxing(sum);
            Assert.Equal(0, ILShapeInspector.CountOpcode(sum, OpCodes.Newobj));

            var main = ILShapeInspector.GetProgramMethod(assembly, "main");
            Assert.Equal(20, main.Invoke(null, null));
            return 0;
        });
    }
}
