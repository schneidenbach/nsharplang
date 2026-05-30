using System;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using System.Threading.Tasks;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// ADDITIVE IL-validity regression coverage for async-method lowering.
///
/// N# lowers an <c>async</c> method to run <em>synchronously</em>, wrapping the body in a
/// <c>try/catch(Exception)</c> fault guard so a thrown exception becomes a <em>faulted</em>
/// <see cref="Task"/> (C# parity), and routing every return through the structured-return path
/// (<c>leave</c> out of the protected region into a single <c>ret</c>). See
/// <c>src/NSharpLang.Compiler/ILCompiler/ILCompiler.Async.cs</c>.
///
/// This shape is verifiability-sensitive: a bare <c>ret</c> inside the protected region, an
/// unbalanced <c>leave</c>, or a missing exception handler would all produce unverifiable IL that
/// ilverify rejects. No dedicated in-process IL-shape test pinned this before; these freeze the
/// structural invariants so a future state-machine rewrite (or a regression in the fault guard)
/// cannot silently emit invalid IL. End-to-end verifiability is enforced separately by
/// <c>scripts/ilverify.sh</c>.
/// </summary>
public class AsyncLoweringILShapeTests
{
    private const string Imports = @"
import System.Threading.Tasks
import NSharpLang.Tests
";

    private static int CountExceptionHandlers(MethodInfo method) =>
        method.GetMethodBody()?.ExceptionHandlingClauses.Count ?? 0;

    private static bool EndsWithSingleRet(MethodInfo method)
    {
        var instructions = ILShapeInspector.Decode(method);
        if (instructions.Count == 0)
        {
            return false;
        }

        // Exactly one ret, and it is the final instruction. Async bodies must funnel every return
        // through the structured-return path, so the only ret is the post-leave epilogue.
        var retCount = ILShapeInspector.CountOpcode(instructions, OpCodes.Ret);
        return retCount == 1 && instructions[^1].OpCode == OpCodes.Ret;
    }

    [Fact]
    public void AsyncTaskOfInt_WrapsBodyInFaultGuard_AndReturnsViaStructuredLeave()
    {
        // A value-returning async method must: run inside a try/catch fault guard (>= 1 EH clause),
        // funnel its return through a leave to a single trailing ret, and never box the int result.
        var source = Imports + @"
async func GetValue(): Task<int> {
    return await ILCompilerAsyncHelpers.GetValueAsync(42)
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "GetValue");

            Assert.True(
                CountExceptionHandlers(method) >= 1,
                "Async body must be wrapped in a try/catch fault guard (>= 1 exception-handling clause).");

            Assert.True(
                ILShapeInspector.CountOpcode(method, OpCodes.Leave) >= 1,
                "Async returns must route through the structured-return path (leave out of the protected region).");

            Assert.True(
                EndsWithSingleRet(method),
                "Async body must funnel to a single trailing ret; a bare ret inside the try is unverifiable.");

            // The int result must flow into Task<int> through the typed FromResult path, never boxed.
            ILShapeInspector.AssertNoBoxing(method);
            return 0;
        });
    }

    [Fact]
    public async Task AsyncTaskOfInt_ExecutesToCompletedResult()
    {
        // Behavioural proof the verifiable shape actually runs and the token resolves at runtime.
        var source = Imports + @"
async func GetValue(): Task<int> {
    return await ILCompilerAsyncHelpers.GetValueAsync(7)
}

async func main(): Task<int> {
    return await GetValue()
}";

        var result = await ILShapeInspector.Compile(source, assembly =>
        {
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");
            var task = (Task<int>)main.Invoke(null, null)!;
            return task;
        });

        Assert.Equal(7, result);
    }

    [Fact]
    public void AsyncTask_NoResult_StillWrapsFaultGuard_AndLeaves()
    {
        // A non-generic Task async method has no result value but must still guard + structured-return.
        var source = Imports + @"
async func DoWork(): Task {
    await ILCompilerAsyncHelpers.GetValueAsync(0)
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "DoWork");

            Assert.True(
                CountExceptionHandlers(method) >= 1,
                "Async Task body must be wrapped in a fault guard.");
            Assert.True(
                ILShapeInspector.CountOpcode(method, OpCodes.Leave) >= 1,
                "Async Task body must leave the protected region rather than fall through.");
            Assert.True(EndsWithSingleRet(method), "Async Task body must funnel to a single trailing ret.");
            ILShapeInspector.AssertNoBoxing(method);
            return 0;
        });
    }

    [Fact]
    public void AsyncValueTaskOfInt_WrapsFaultGuard_AndDoesNotBox()
    {
        // ValueTask<int> goes through a struct builder/result path; it must still be guarded and must
        // not box the int (the failure mode would be routing the result through an object sink).
        var source = Imports + @"
async func GetValue(): ValueTask<int> {
    await ILCompilerAsyncHelpers.GetValueAsync(0)
    return 5
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "GetValue");

            Assert.True(
                CountExceptionHandlers(method) >= 1,
                "Async ValueTask<int> body must be wrapped in a fault guard.");
            Assert.True(EndsWithSingleRet(method), "Async ValueTask<int> body must funnel to a single trailing ret.");
            ILShapeInspector.AssertNoBoxing(method);
            return 0;
        });
    }

    [Fact]
    public async Task AsyncThrow_BecomesFaultedTask_NotSynchronousThrow()
    {
        // The fault guard's contract: an exception in the body becomes a FAULTED task, observed only
        // when awaited — invoking the method must NOT throw synchronously. This is the behaviour the
        // try/catch + structured-return IL shape exists to guarantee.
        var source = Imports + @"
import System

async func Boom(): Task<int> {
    throw new InvalidOperationException(""boom"")
}";

        var (task, threwSynchronously) = ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "Boom");
            try
            {
                var t = (Task<int>)method.Invoke(null, null)!;
                return (t, false);
            }
            catch (TargetInvocationException)
            {
                return ((Task<int>?)null, true);
            }
        });

        Assert.False(threwSynchronously, "Async method must capture the exception into a faulted task, not throw synchronously.");
        Assert.NotNull(task);
        await Assert.ThrowsAsync<InvalidOperationException>(async () => await task!);
    }
}
