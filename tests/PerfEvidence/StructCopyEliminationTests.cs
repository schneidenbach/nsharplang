using System;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// IL-shape and behavioral regression tests for struct-copy elimination
/// (Performance/StructCopyAnalysis.cs). A large readonly struct passed by value forces a
/// full struct copy at every call site; lowering the parameter to pass-by-<c>in</c> drops the
/// copy while preserving behavior and C# interop.
///
/// These tests assert the <em>shape</em> (parameter is byref / no per-call copy) and the
/// <em>behavior</em> (results match) so a regression in either dimension is caught.
/// </summary>
public class StructCopyEliminationTests
{
    // A "large" readonly struct: four doubles (4 words) comfortably exceeds the small-struct
    // threshold, and a record struct emits InitOnly backing fields, so it is provably readonly.
    private const string LargeReadonlyStructSource = @"
record struct Big(a: double, b: double, c: double, d: double) {
    func Sum(): double => a + b + c + d
}

func total(value: Big): double {
    return value.a + value.b + value.c + value.d
}

func sumViaMethod(value: Big): double {
    return value.Sum()
}

func run(): double {
    big := new Big(1.0, 2.0, 3.0, 4.0)
    return total(big) + sumViaMethod(big)
}
";

    [Fact]
    public void StructCopy_LargeReadonlyStructParameter_IsLoweredToIn()
    {
        ILShapeInspector.Compile(LargeReadonlyStructSource, assembly =>
        {
            var total = ILShapeInspector.GetProgramMethod(assembly, "total");
            var parameter = total.GetParameters().Single();

            Assert.True(
                parameter.ParameterType.IsByRef,
                "Expected the large readonly struct parameter of 'total' to be lowered to a byref (in) parameter.");

            // `in` carries the [In] flag and the IsReadOnly attribute, so C# sees `in`, not `ref`.
            Assert.True(parameter.IsIn, "Expected the lowered parameter to carry the [In] flag.");
            Assert.Contains(
                parameter.GetRequiredCustomModifiers(),
                modifier => modifier.FullName == "System.Runtime.InteropServices.InAttribute");

            return 0;
        });
    }

    [Fact]
    public void StructCopy_LoweredParameter_DropsPerCallCopy_AndLoadsReceiverByAddress()
    {
        ILShapeInspector.Compile(LargeReadonlyStructSource, assembly =>
        {
            // A by-`in` parameter is read through its address: the body never copies the whole
            // struct (no ldobj/stobj/cpobj of the struct), it dereferences fields directly.
            var total = ILShapeInspector.GetProgramMethod(assembly, "total");
            Assert.Equal(0, ILShapeInspector.CountOpcode(total, OpCodes.Ldobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(total, OpCodes.Cpobj));
            Assert.Equal(0, ILShapeInspector.CountOpcode(total, OpCodes.Stobj));

            // The struct instance-method receiver is loaded by address (ldarg of the byref),
            // not copied, and dispatched with a non-virtual call on the value type.
            var sumViaMethod = ILShapeInspector.GetProgramMethod(assembly, "sumViaMethod");
            Assert.Equal(0, ILShapeInspector.CountOpcode(sumViaMethod, OpCodes.Ldobj));
            ILShapeInspector.AssertCallCount(sumViaMethod, OpCodes.Callvirt, 0);

            // Nothing regressed: no boxing and no extra allocations were introduced.
            ILShapeInspector.AssertNoBoxing(total);
            ILShapeInspector.AssertNoBoxing(sumViaMethod);
            Assert.Equal(0, ILShapeInspector.CountNewObj(total));
            Assert.Equal(0, ILShapeInspector.CountNewObj(sumViaMethod));

            return 0;
        });
    }

    [Fact]
    public void StructCopy_LoweredCall_ProducesCorrectResult()
    {
        // Behavioral parity: the lowered ABI must compute the same value as a by-value call.
        ILShapeInspector.Compile(LargeReadonlyStructSource, assembly =>
        {
            var run = ILShapeInspector.GetProgramMethod(assembly, "run");
            var result = run.Invoke(null, Array.Empty<object>());

            // total(big) = 10, sumViaMethod(big) = 10 → 20.
            Assert.Equal(20.0, Assert.IsType<double>(result));
            return 0;
        });
    }

    [Fact]
    public void StructCopy_SmallStruct_KeepsByValueAbi()
    {
        // A small readonly struct (two ints = 2 words, at the threshold) stays by value: the
        // indirection would not pay off and we must not surprise the common small-struct case.
        const string source = @"
record struct Small(x: int, y: int) {
}

func add(value: Small): int {
    return value.x + value.y
}
";

        ILShapeInspector.Compile(source, assembly =>
        {
            var add = ILShapeInspector.GetProgramMethod(assembly, "add");
            Assert.False(
                add.GetParameters().Single().ParameterType.IsByRef,
                "A small struct parameter should keep its by-value ABI.");
            return 0;
        });
    }

    [Fact]
    public void StructCopy_PrimitiveParameter_KeepsByValueAbi()
    {
        const string source = @"
func twice(value: int): int {
    return value + value
}
";

        ILShapeInspector.Compile(source, assembly =>
        {
            var twice = ILShapeInspector.GetProgramMethod(assembly, "twice");
            Assert.False(
                twice.GetParameters().Single().ParameterType.IsByRef,
                "A primitive parameter should never be lowered to in.");
            return 0;
        });
    }

    [Fact]
    public void StructCopy_FunctionWithClosure_KeepsByValueAbi()
    {
        // Escape gate: a parameter that could be captured by a closure must stay by value so the
        // readonly reference can never outlive the call frame.
        const string source = @"
import System

func choose(value: Big): Func<double> {
    return () => value.a + value.b + value.c + value.d
}

record struct Big(a: double, b: double, c: double, d: double) {
}
";

        ILShapeInspector.Compile(source, assembly =>
        {
            var choose = ILShapeInspector.GetProgramMethod(assembly, "choose");
            Assert.False(
                choose.GetParameters().Single().ParameterType.IsByRef,
                "A parameter usable by a closure must keep its by-value ABI (escape safety).");
            return 0;
        });
    }
}
