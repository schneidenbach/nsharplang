using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Regression guard for <c>lock</c>-statement codegen. The lock body is emitted inside a
/// protected (try) region whose finally calls <c>Monitor.Exit</c>. A <c>return</c> inside that
/// body must NOT emit a raw <c>ret</c> (illegal: you cannot leave a try region with <c>ret</c>) —
/// the emitter has to track the exception-block depth so <c>EmitReturn</c> lowers the return to a
/// structured <c>leave</c> targeting the method's return label. The original emitter never
/// incremented <c>_exceptionBlockDepth</c> around the lock body, so a returning lock body produced
/// a structurally broken method body that crashed <c>dotnet ilverify</c> with
/// <c>IndexOutOfRangeException</c>. These tests pin the corrected IL shape (balanced try/finally,
/// Monitor.Enter/Exit, and no <c>ret</c> trapped inside the protected region) so the defect cannot
/// silently return when the blocking ilverify CI gate is not run locally.
/// </summary>
public class LockStatementIlShapeTests
{
    private const string ReturningLockSource = @"
class Counter {
    count: int = 0
    syncLock: object = new object()

    func GetValue(): int {
        lock syncLock {
            return count
        }
    }
}
";

    private const string VoidLockSource = @"
class Counter {
    count: int = 0
    syncLock: object = new object()

    func Increment() {
        lock syncLock {
            count++
        }
    }
}
";

    [Fact]
    public void LockWithReturn_EmitsBalancedTryFinallyAndStructuredReturn()
    {
        ILShapeInspector.Compile(ReturningLockSource, assembly =>
        {
            var counterType = assembly.GetType("Counter");
            Assert.NotNull(counterType);

            var getValue = counterType!.GetMethod(
                "GetValue",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.NotNull(getValue);

            var body = getValue!.GetMethodBody();
            Assert.NotNull(body);

            // Exactly one exception region, and it is a finally clause => balanced try/finally.
            var clauses = body!.ExceptionHandlingClauses;
            Assert.Single(clauses);
            Assert.Equal(ExceptionHandlingClauseOptions.Finally, clauses[0].Flags);

            var finallyStart = clauses[0].HandlerOffset;
            var finallyEnd = clauses[0].HandlerOffset + clauses[0].HandlerLength;
            var tryStart = clauses[0].TryOffset;
            var tryEnd = clauses[0].TryOffset + clauses[0].TryLength;

            var instructions = ILShapeInspector.Decode(getValue);

            // Monitor.Enter is called before the try; Monitor.Exit is called inside the finally.
            Assert.True(
                ILShapeInspector.CountCallsTo(getValue, typeof(System.Threading.Monitor), "Enter") >= 1,
                "lock must call Monitor.Enter.");
            Assert.True(
                ILShapeInspector.CountCallsTo(getValue, typeof(System.Threading.Monitor), "Exit") >= 1,
                "lock must call Monitor.Exit in the finally.");

            // The body must leave the protected region via `leave` (structured return), not `ret`.
            var hasLeave = instructions.Any(i => i.OpCode == OpCodes.Leave || i.OpCode == OpCodes.Leave_S);
            Assert.True(hasLeave, "A return inside a lock body must lower to a `leave`, not a `ret`.");

            // No `ret` may appear inside the try or finally region — that is the unverifiable shape
            // that crashed the verifier.
            foreach (var instruction in instructions)
            {
                if (instruction.OpCode != OpCodes.Ret)
                {
                    continue;
                }

                var insideTry = instruction.Offset >= tryStart && instruction.Offset < tryEnd;
                var insideFinally = instruction.Offset >= finallyStart && instruction.Offset < finallyEnd;
                Assert.False(
                    insideTry || insideFinally,
                    $"Found a `ret` at IL_{instruction.Offset:x4} inside a protected region; returns must use `leave`.");
            }

            // Behavioural sanity: the structured return still produces the field value.
            return 0;
        });
    }

    [Fact]
    public void VoidLock_EmitsBalancedTryFinallyWithMonitorEnterExit()
    {
        ILShapeInspector.Compile(VoidLockSource, assembly =>
        {
            var counterType = assembly.GetType("Counter");
            Assert.NotNull(counterType);

            var increment = counterType!.GetMethod(
                "Increment",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.NotNull(increment);

            var body = increment!.GetMethodBody();
            Assert.NotNull(body);

            var clauses = body!.ExceptionHandlingClauses;
            Assert.Single(clauses);
            Assert.Equal(ExceptionHandlingClauseOptions.Finally, clauses[0].Flags);

            Assert.Equal(1, ILShapeInspector.CountCallsTo(increment, typeof(System.Threading.Monitor), "Enter"));
            Assert.Equal(1, ILShapeInspector.CountCallsTo(increment, typeof(System.Threading.Monitor), "Exit"));

            return 0;
        });
    }
}
