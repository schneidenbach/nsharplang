using System.Reflection.Emit;
using System.Runtime.CompilerServices;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Baseline IL-shape tests. These pin the IL emitted by the compiler on the current branch so
/// that the performance refactor can measure progress against a documented starting point. They
/// are intentionally descriptive of the <em>current</em> behaviour, not the desired end state —
/// when the refactor improves a shape (e.g. removes a display class or boxing), the corresponding
/// baseline assertion should be tightened in the same change.
/// </summary>
public class ILShapeBaselineTests
{
    [Fact]
    public void Baseline_SimpleArithmetic_HasNoBoxingOrVirtualCalls()
    {
        const string source = @"
func add(x: int, y: int): int {
    return x + y
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "add");

            // Pure integer arithmetic should not box or dispatch virtually.
            ILShapeInspector.AssertNoBoxing(method);
            ILShapeInspector.AssertCallCount(method, OpCodes.Callvirt, 0);
            ILShapeInspector.AssertCallCount(method, OpCodes.Newobj, 0);

            // It should contain an add and a return.
            Assert.Equal(1, ILShapeInspector.CountOpcode(method, OpCodes.Add));
            return 0;
        });
    }

    [Fact]
    public void Baseline_PrintBoxesValueType()
    {
        // Pinning current behaviour: printing an int routes through an object-typed sink,
        // which boxes the value. This documents a known allocation hotspot for the refactor.
        const string source = @"
func main() {
    print 42
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "main");
            var boxCount = ILShapeInspector.CountBoxing(method);

            Assert.True(boxCount >= 1, $"Expected print of an int to box at least once but found {boxCount}.");
            return 0;
        });
    }

    [Fact]
    public void Baseline_EscapingClosure_EmitsDisplayClassAndVirtualInvoke()
    {
        // Pinning current behaviour: a closure that escapes its defining function (returned as a
        // delegate) captures its environment in a generated display class, and invoking the
        // resulting delegate uses callvirt. The refactor aims to reduce these allocations and the
        // virtual-dispatch cost; this test documents the starting point.
        const string source = @"
import System

func makeAdder(amount: int): Func<int, int> {
    return (x) => x + amount
}

func main(): int {
    adder := makeAdder(10)
    return adder(5)
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var displayClasses = ILShapeInspector.FindDisplayClasses(assembly);
            Assert.True(
                displayClasses.Count >= 1,
                "Expected an escaping closure to emit at least one display class.");
            Assert.Contains(displayClasses, type => ILShapeInspector.IsDisplayClass(type));

            // Invoking the returned delegate dispatches virtually today.
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");
            Assert.True(
                ILShapeInspector.CountCallVirt(main) >= 1,
                "Expected the delegate invocation in main to use callvirt.");

            // Building the escaping closure allocates a delegate over the display class.
            var makeAdder = ILShapeInspector.GetProgramMethod(assembly, "makeAdder");
            Assert.True(
                ILShapeInspector.CountDelegateConstructions(makeAdder) >= 1,
                "Expected makeAdder to construct at least one delegate for the escaping closure.");
            return 0;
        });
    }


    [Fact]
    public void Baseline_ParamsSpanCall_UsesVerifiableHeapArrayNotLocalloc()
    {
        // Pins the CURRENT lowering of a `params Span<int>` argument: the call materializes the
        // arguments into a heap `int[]` (`newarr`) wrapped in a Span<int> via the verifiable
        // Span(T[]) constructor, and emits NO `localloc`. This keeps the emitted IL ilverify-clean.
        //
        // A future optimization may stack-allocate the buffer, but must do so with a verifiable
        // lowering (e.g. a synthesized [InlineArray] struct local, as the C# 13 compiler does) —
        // NOT a `localloc` + Span(void*, int), which ilverify rejects as an unmanaged pointer. When
        // that lands, tighten this assertion accordingly.
        const string source = @"
func sum(params numbers: Span<int>): int {
    total := 0
    for i := 0; i < numbers.Length; i++ {
        total += numbers[i]
    }

    return total
}

func main(): int {
    result := sum(1, 2, 3)
    return result
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(0, ILShapeInspector.CountOpcode(main, OpCodes.Localloc));
            Assert.True(
                ILShapeInspector.CountOpcode(main, OpCodes.Newarr) >= 1,
                "Expected the params Span<int> call to lower to a verifiable heap array (newarr).");
            return 0;
        });
    }

    [Fact]
    public void Interpolation_ValueTypeHoles_UseHandlerWithoutBoxingOrArrays()
    {
        // String interpolation lowers to DefaultInterpolatedStringHandler (stack-allocated ref struct).
        // Value-type holes must flow through the generic AppendFormatted<T>, never boxing and never
        // allocating the old string[] for string.Concat.
        const string source = @"
func main(): string {
    count := 7
    ratio := 3.14
    return $""items {count} ratio {ratio}""
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            // Zero boxing: value-type holes go through AppendFormatted<T>(T).
            ILShapeInspector.AssertNoBoxing(main);

            // The legacy concat path allocated a string[] (newarr) and called string.Concat.
            // The handler path does neither.
            Assert.Equal(0, ILShapeInspector.CountOpcode(main, OpCodes.Newarr));
            Assert.Equal(0, ILShapeInspector.CountCallsTo(main, typeof(string), "Concat"));

            // The handler is constructed and finalised exactly once.
            Assert.Equal(
                1,
                ILShapeInspector.CountCallsTo(main, typeof(DefaultInterpolatedStringHandler), ".ctor"));
            Assert.Equal(
                1,
                ILShapeInspector.CountCallsTo(main, typeof(DefaultInterpolatedStringHandler), "ToStringAndClear"));

            // Two value-type holes -> two AppendFormatted calls.
            Assert.Equal(
                2,
                ILShapeInspector.CountCallsTo(main, typeof(DefaultInterpolatedStringHandler), "AppendFormatted"));
            return 0;
        });
    }

    [Fact]
    public void Interpolation_NoHoles_FoldsToStringLiteralWithoutHandler()
    {
        // A purely literal interpolation is a constant string and must not allocate a handler at all.
        const string source = @"
func main(): string {
    return $""just literal text""
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.Equal(
                0,
                ILShapeInspector.CountCallsTo(main, typeof(DefaultInterpolatedStringHandler), ".ctor"));
            Assert.Equal(1, ILShapeInspector.CountOpcode(main, OpCodes.Ldstr));
            return 0;
        });
    }

    [Fact]
    public void Interpolation_EnumHole_BoxesThroughObjectOverload_AndVerifies()
    {
        // Regression: a hole whose type is defined in THIS compilation (an enum is an
        // EnumBuilder/TypeBuilder) must NOT flow through the generic AppendFormatted<T> — instantiating
        // that generic over a builder type emits an unresolvable MethodSpec token (unverifiable IL,
        // caught by ilverify and the integration ILVerify gate). Such holes are boxed and routed through
        // the non-generic AppendFormatted(object, ...) overload, which formats identically (the enum
        // member name). Executing the assembly proves the token resolves at runtime.
        const string source = @"
enum Priority { Low = 0, High = 2 }

func main(): string {
    p := Priority.High
    return $""Priority: {p}""
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");

            // The enum hole is boxed (the builder-type fallback), not passed unboxed to a generic.
            Assert.True(
                ILShapeInspector.CountOpcode(main, OpCodes.Box) >= 1,
                "Expected the enum interpolation hole to box for the AppendFormatted(object) overload.");

            // Exactly one AppendFormatted call, and the handler still constructed/finalised once.
            Assert.Equal(
                1,
                ILShapeInspector.CountCallsTo(main, typeof(DefaultInterpolatedStringHandler), "AppendFormatted"));
            Assert.Equal(
                1,
                ILShapeInspector.CountCallsTo(main, typeof(DefaultInterpolatedStringHandler), ".ctor"));

            // Token resolves and formatting is the member name, not the underlying value.
            var result = (string)main.Invoke(null, null)!;
            Assert.Equal("Priority: High", result);
            return 0;
        });
    }
}
