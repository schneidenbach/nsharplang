using System;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Unit 16 (performance refactor): proves that the N# Go-style <c>(result, err) := call()</c>
/// error-tuple sugar lowers to ordinary value carriers + a single capture clause, and that
/// the SUCCESS path never throws or unwinds an exception.
///
/// N# semantics (see docs/guide/language-tour.md "Tuple Error Capture"): the <c>err</c>
/// variable captures any exception the initializer throws. The error source is therefore a
/// CLR exception, so a catch clause is intrinsic to the contract. What the performance
/// strategy (docs/design/performance-compiler-refactor.md, "Error Handling And Exceptions")
/// forbids is paying the cost of a *thrown* exception on the happy path. These tests verify:
///   1. The success path executes without throwing (no unwind cost).
///   2. The lowering synthesizes no extra <c>throw</c>/<c>rethrow</c> on the success branch.
///   3. The only exception-handling clause present is the single catch required to bind
///      <c>err</c> — i.e. the sugar does not multiply EH regions, add filters/finally, or
///      use exceptions as the normal success control-flow mechanism.
/// </summary>
public partial class ILCompilerTests
{
    private const string ErrorTupleProgram = """
import System

func Divide(a: int, b: int): int {
    if b == 0 {
        throw new Exception("Cannot divide by zero")
    }
    return a / b
}

func RunSuccess(): int {
    result, err := Divide(10, 2)
    if err != null {
        return -1
    }
    return result
}

func RunFailure(): int {
    result, err := Divide(10, 0)
    if err != null {
        return -1
    }
    return result
}
""";

    [Fact]
    public void ErrorTuple_SuccessPath_DoesNotThrow_AndReturnsResult()
    {
        // Success path: invoking the (result, err) caller must return the value with no
        // exception escaping. If the happy path used exceptions as control flow we would
        // observe a thrown/unwound exception here.
        var result = CompileAndInvoke(ErrorTupleProgram, "RunSuccess");
        Assert.Equal(5, Assert.IsType<int>(result));
    }

    [Fact]
    public void ErrorTuple_FailurePath_CapturesExceptionAsValue()
    {
        // Failure path: the thrown exception is captured into err (a value), the caller
        // returns normally (-1) instead of propagating the exception.
        var result = CompileAndInvoke(ErrorTupleProgram, "RunFailure");
        Assert.Equal(-1, Assert.IsType<int>(result));
    }

    [Fact]
    public void ErrorTuple_SuccessPath_SynthesizesNoThrowOpcode()
    {
        // The lowering must not synthesize a `throw`/`rethrow` on the success branch. The
        // only `throw` in the whole program is the user-written one inside Divide; the
        // caller methods that use the sugar must contain none.
        CompileAndInspect(ErrorTupleProgram, assembly =>
        {
            var program = assembly.GetType("Program");
            Assert.NotNull(program);

            foreach (var methodName in new[] { "RunSuccess", "RunFailure" })
            {
                var method = program!.GetMethod(methodName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
                Assert.NotNull(method);

                var opcodes = GetMethodOpCodes(method!);
                Assert.DoesNotContain(OpCodes.Throw, opcodes);
                Assert.DoesNotContain(OpCodes.Rethrow, opcodes);
            }

            return true;
        });
    }

    [Fact]
    public void ErrorTuple_Lowering_UsesExactlyOneCaptureClause_NoFilters()
    {
        // The sugar binds err from a caught exception. That requires exactly one catch
        // clause (a value carrier populated from the unwind), and no exception filters or
        // fault/finally regions. This proves the sugar does not multiply EH machinery or
        // route the success path through exception control flow.
        CompileAndInspect(ErrorTupleProgram, assembly =>
        {
            var program = assembly.GetType("Program");
            Assert.NotNull(program);

            var method = program!.GetMethod("RunSuccess", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(method);

            var clauses = method!.GetMethodBody()!.ExceptionHandlingClauses;

            // Exactly one clause: the catch that captures the exception into `err`.
            var clause = Assert.Single(clauses);
            Assert.Equal(ExceptionHandlingClauseOptions.Clause, clause.Flags);
            Assert.Equal(typeof(Exception), clause.CatchType);

            // No filter/finally/fault machinery.
            Assert.DoesNotContain(clauses, c => c.Flags.HasFlag(ExceptionHandlingClauseOptions.Filter));
            Assert.DoesNotContain(clauses, c => c.Flags.HasFlag(ExceptionHandlingClauseOptions.Finally));
            Assert.DoesNotContain(clauses, c => c.Flags.HasFlag(ExceptionHandlingClauseOptions.Fault));

            return true;
        });
    }

    [Fact]
    public void ErrorTuple_NonThrowingInitializer_NeverEntersCatch()
    {
        // A purely successful run (initializer never throws) must complete by the normal
        // fall-through path. We assert behavior across many iterations to prove the success
        // path does not depend on exception unwinding to produce its value.
        var source = """
import System

func SafeDivide(a: int, b: int): int {
    return a / b
}

func Sum(n: int): int {
    total := 0
    for i := 1; i <= n; i = i + 1 {
        value, err := SafeDivide(i, 1)
        if err == null {
            total = total + value
        }
    }
    return total
}
""";

        var result = CompileAndInvoke(source, "Sum", 100);
        Assert.Equal(5050, Assert.IsType<int>(result));
    }
}
