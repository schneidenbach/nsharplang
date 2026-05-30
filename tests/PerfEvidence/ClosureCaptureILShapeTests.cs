using System;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// ADDITIVE IL-validity coverage for closure / display-class lowering.
///
/// The existing <see cref="StructClosureILShapeTests"/> covers a non-escaping mutated capture
/// (struct-box lowering) versus an escaping single-variable closure (heap display class). These fill
/// the remaining gaps:
/// <list type="bullet">
///   <item><b>this-capturing instance lambda</b> — a lambda inside an instance method that reads
///   <c>this.field</c> must lower to a non-static instance method on the declaring type, bound via
///   <c>ldarg.0</c> + <c>ldftn</c> + delegate <c>newobj</c>. It must NOT spuriously allocate a
///   display class (the receiver IS the closure environment), and must read the field with a plain
///   <c>ldfld</c>.</item>
///   <item><b>multi-variable capture lifting</b> — a lambda capturing two distinct locals must lift
///   both into a single display class with one field per captured variable.</item>
/// </list>
/// All shapes must be verifiable (proven end-to-end by <c>scripts/ilverify.sh</c>); these freeze the
/// structural invariants and prove behaviour at runtime.
/// </summary>
public class ClosureCaptureILShapeTests
{
    [Fact]
    public void InstanceThisCapturingLambda_BindsViaInstanceMethod_NoDisplayClass()
    {
        // A lambda that captures `this.offset` lowers to an instance method on Counter and binds with
        // ldarg.0 (this) + ldftn + delegate newobj. `this` is already the environment, so no separate
        // display class is needed.
        const string source = @"
import System

class Counter {
    offset: int

    constructor(b: int) {
        this.offset = b
    }

    func makeAdder(): Func<int, int> {
        return (x) => x + this.offset
    }
}

func main(): int {
    c := new Counter(10)
    adder := c.makeAdder()
    return adder(5)
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var counter = assembly.GetType("Counter");
            Assert.NotNull(counter);

            // The lambda body is an instance method on Counter (captures `this`, not a display class).
            ILShapeInspector.AssertNoDisplayClass(counter!);

            var lambda = counter!
                .GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static)
                .FirstOrDefault(m => m.Name.Contains("Lambda", StringComparison.Ordinal)
                    || m.Name.Contains("b__", StringComparison.Ordinal));
            Assert.NotNull(lambda);
            Assert.False(lambda!.IsStatic, "A this-capturing lambda must be a non-static instance method.");

            // The lambda reads the captured field directly off `this` via ldfld (no boxing).
            Assert.True(
                ILShapeInspector.CountOpcode(lambda, OpCodes.Ldfld) >= 1,
                "The this-capturing lambda must read the captured field via ldfld.");
            ILShapeInspector.AssertNoBoxing(lambda);

            // makeAdder binds the delegate over the instance method: ldftn + delegate newobj.
            var makeAdder = counter.GetMethod("makeAdder", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.NotNull(makeAdder);
            Assert.True(
                ILShapeInspector.CountOpcode(makeAdder!, OpCodes.Ldftn) >= 1,
                "makeAdder must load the lambda's function pointer with ldftn.");
            Assert.True(
                ILShapeInspector.CountDelegateConstructions(makeAdder!) >= 1,
                "makeAdder must construct exactly the delegate over the instance lambda.");

            // Behavioural proof the whole chain is valid and runs.
            Assert.Equal(15, ILShapeInspector.GetProgramMethod(assembly, "main").Invoke(null, null));
            return 0;
        });
    }

    [Fact]
    public void MultiVariableCapture_LiftsAllVariablesIntoOneDisplayClass()
    {
        // A lambda capturing two distinct locals must hoist both into a single display class, with one
        // instance field per captured variable. The delegate is bound over that display class.
        const string source = @"
import System

func make(a: int, b: int): Func<int, int> {
    return (x) => x + a + b
}

func main(): int {
    f := make(10, 20)
    return f(5)
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var displayClasses = ILShapeInspector.FindDisplayClasses(assembly);
            Assert.True(
                displayClasses.Count == 1,
                $"Expected exactly one display class for the two captured locals but found {displayClasses.Count}.");

            var fields = displayClasses[0]
                .GetFields(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.Equal(2, fields.Length);

            // make() allocates the display class and binds the delegate over it.
            var make = ILShapeInspector.GetProgramMethod(assembly, "make");
            Assert.True(
                ILShapeInspector.CountDelegateConstructions(make) >= 1,
                "make must construct a delegate over the display class.");

            // Behavioural proof: 5 + 10 + 20 = 35.
            Assert.Equal(35, ILShapeInspector.GetProgramMethod(assembly, "main").Invoke(null, null));
            return 0;
        });
    }

    [Fact]
    public void MultiVariableCapture_LambdaReadsLiftedFields_NoBoxing()
    {
        // The lambda body itself must read the lifted captures via ldfld off the display-class
        // instance, never boxing the captured value types.
        const string source = @"
import System

func make(a: int, b: int): Func<int, int> {
    return (x) => x + a + b
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var displayClasses = ILShapeInspector.FindDisplayClasses(assembly);
            Assert.Single(displayClasses);

            var lambda = displayClasses[0]
                .GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
                .FirstOrDefault(m => m.Name.Contains("Lambda", StringComparison.Ordinal)
                    || m.Name.Contains("b__", StringComparison.Ordinal));
            Assert.NotNull(lambda);

            // Two captured locals => at least two ldfld reads, and no boxing of the int captures.
            Assert.True(
                ILShapeInspector.CountOpcode(lambda!, OpCodes.Ldfld) >= 2,
                "The lambda must read both lifted captures via ldfld.");
            ILShapeInspector.AssertNoBoxing(lambda!);
            return 0;
        });
    }
}
