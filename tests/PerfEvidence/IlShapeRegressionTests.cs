using System.Linq;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// IL-shape REGRESSION GATE for the performance patterns landed in PR #160.
///
/// Unlike <see cref="ILShapeBaselineTests"/> (which documents the <em>current</em> shape so the
/// refactor can measure progress), these tests are a <strong>ratchet</strong>: each one pins the
/// optimized shape of a hot path so a later change cannot silently regress it. They are
/// deterministic (no wall-clock, no benchmarking) and run as part of the normal
/// <c>dotnet test tests/Tests.csproj</c> suite, so CI enforces them on every change.
///
/// Each test mirrors one benchmark in the <c>benchmarks/</c> BenchmarkDotNet corpus
/// (<c>NSharpLang.Benchmarks</c>). The benchmark measures wall-clock N#-vs-C# numbers manually;
/// the test here freezes the IL shape the benchmark depends on. When you add a new optimized
/// pattern, add a matched benchmark AND a regression assertion here — see
/// <c>docs/design/performance-compiler-refactor.md</c> ("Benchmark Corpus And IL-Shape Gate").
///
/// The pinned invariants, one per optimized pattern:
///   1. foreach over <c>T[]</c>      → no enumerator allocation (newobj == 0) and no dispatch.
///   2. foreach over <c>Span&lt;T&gt;</c>  → no enumerator allocation (newobj == 0).
///   3. value-struct union           → construction/consumption does not box (box == 0).
///   4. constrained generic dispatch → <c>constrained.</c> + <c>callvirt</c>, never <c>box</c>.
///   5. static (non-capturing) lambda → delegate constructed at most once (delegate-ctor &lt;= 1).
///   6. result/err error tuple       → the success path synthesizes no <c>throw</c>/<c>rethrow</c>.
/// </summary>
public class IlShapeRegressionTests
{
    // ============================================================
    // Pattern 1: foreach over T[] — allocation-free index loop.
    // ============================================================

    /// <summary>
    /// Pinned by benchmark <c>ForeachArrayBenchmarks</c>. A <c>foreach</c> over a single-dimension
    /// array must lower to an <c>ldlen</c> + index loop: no enumerator object is allocated
    /// (<c>newobj == 0</c>) and the loop performs no <c>call</c>/<c>callvirt</c> dispatch.
    /// </summary>
    [Fact]
    public void Gate_ForeachOverArray_AllocatesNoEnumerator_AndDispatchesNothing()
    {
        const string source = """
func sumArray(numbers: int[]): int {
    sum := 0
    foreach num in numbers {
        sum = sum + num
    }
    return sum
}
""";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "sumArray");

            // The ratchet: zero enumerator allocation, zero dispatch in the hot loop.
            ILShapeInspector.AssertCallCount(method, OpCodes.Newobj, 0);
            ILShapeInspector.AssertCallCount(method, OpCodes.Callvirt, 0);
            ILShapeInspector.AssertCallCount(method, OpCodes.Call, 0);

            // Positive proof it is the index-loop fast path, not just an empty body.
            Assert.Equal(1, ILShapeInspector.CountOpcode(method, OpCodes.Ldlen));
            return 0;
        });
    }

    // ============================================================
    // Pattern 2: foreach over Span<T> / ReadOnlySpan<T>.
    // ============================================================

    /// <summary>
    /// Pinned by benchmark <c>ForeachSpanBenchmarks</c>. A <c>foreach</c> over a span uses a
    /// <c>Length</c> + indexer loop and must not allocate an enumerator (<c>newobj == 0</c>).
    /// The span is obtained allocation-free through a <c>params ReadOnlySpan&lt;int&gt;</c> parameter.
    /// </summary>
    [Fact]
    public void Gate_ForeachOverSpan_AllocatesNoEnumerator()
    {
        const string source = """
import System

func sumSpan(numbers: ReadOnlySpan<int>): int {
    sum := 0
    foreach num in numbers {
        sum = sum + num
    }
    return sum
}
""";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "sumSpan");

            // The ratchet: iterating a span allocates nothing.
            ILShapeInspector.AssertCallCount(method, OpCodes.Newobj, 0);
            return 0;
        });
    }

    // ============================================================
    // Pattern 3: value-struct union — no boxing.
    // ============================================================

    /// <summary>
    /// Pinned by benchmark <c>ValueUnionBenchmarks</c>. A small, closed, payload-free union lowers
    /// to a value struct, and constructing/matching it must not box (<c>box == 0</c>).
    /// </summary>
    [Fact]
    public void Gate_ValueStructUnion_DoesNotBox()
    {
        const string source = """
union Signal {
    Stop
    Go
}

func classify(go: bool): int {
    s := new Signal.Stop
    if go {
        s = new Signal.Go
    }
    return match s {
        Signal.Stop => 0,
        Signal.Go => 1
    }
}
""";

        ILShapeInspector.Compile(source, assembly =>
        {
            // The union must actually be a value type (otherwise "no boxing" is vacuous).
            var unionType = assembly.GetType("Signal");
            Assert.NotNull(unionType);
            Assert.True(unionType!.IsValueType, "Payload-free union must lower to a value struct.");

            // The ratchet: constructing and matching the value-struct union never boxes the
            // tag (a struct stays a struct across construction + match dispatch).
            var classify = ILShapeInspector.GetProgramMethod(assembly, "classify");
            ILShapeInspector.AssertNoBoxing(classify);
            return 0;
        });
    }

    // ============================================================
    // Pattern 4: constrained generic dispatch — constrained. + callvirt, no box.
    // ============================================================

    /// <summary>
    /// Pinned by benchmark <c>ConstrainedDispatchBenchmarks</c>. Dispatching an interface method on
    /// a generic value-type receiver must use the <c>constrained.</c> prefix + <c>callvirt</c> and
    /// must never box the receiver (<c>box == 0</c>).
    /// </summary>
    [Fact]
    public void Gate_ConstrainedGenericDispatch_UsesConstrainedCallvirt_AndDoesNotBox()
    {
        const string source = """
interface IShape {
    func Area(): int
}

struct Square : IShape {
    side: int

    func Area(): int {
        return side * side
    }
}

func areaOf<T>(shape: T): int where T : IShape {
    return shape.Area()
}

func main(): int {
    sq := new Square { side: 6 }
    return areaOf(sq)
}
""";

        ILShapeInspector.Compile(source, assembly =>
        {
            var areaOf = ILShapeInspector.GetProgramMethod(assembly, "areaOf");
            var names = ILShapeInspector.Decode(areaOf).Select(instruction => instruction.OpCode.Name).ToArray();

            // The ratchet: constrained virtual dispatch with no boxing of the value-type receiver.
            Assert.Contains("constrained.", names);
            Assert.Contains("callvirt", names);
            ILShapeInspector.AssertNoBoxing(areaOf);
            return 0;
        });
    }

    // ============================================================
    // Pattern 5: static (non-capturing) lambda — delegate allocated at most once.
    // ============================================================

    /// <summary>
    /// Pinned by benchmark <c>StaticLambdaBenchmarks</c>. A non-capturing lambda materialized as a
    /// delegate inside a loop must be cached in a static field so the delegate is constructed at
    /// most once (delegate-ctor &lt;= 1), matching Roslyn's <c>&lt;&gt;9__N</c> caching idiom.
    /// </summary>
    [Fact]
    public void Gate_StaticLambdaInLoop_ConstructsDelegateAtMostOnce()
    {
        const string source = """
import System
import System.Collections.Generic

func main(): int {
    handlers := new List<Func<int, int>>()
    for i := 0; i < 3; i = i + 1 {
        handler: Func<int, int> = (x) => x + 1
        handlers.Add(handler)
    }
    return handlers[0](41)
}
""";

        ILShapeInspector.Compile(source, assembly =>
        {
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");
            var delegateCtors = ILShapeInspector.CountDelegateConstructions(main);

            // The ratchet: at most one delegate allocation despite looping three times.
            Assert.True(
                delegateCtors <= 1,
                $"Expected the non-capturing lambda to construct at most one delegate but found {delegateCtors}.");
            return 0;
        });
    }

    // ============================================================
    // Pattern 6: result/err error tuple — no throw on the success path.
    // ============================================================

    /// <summary>
    /// Pinned by benchmark <c>ErrorTupleBenchmarks</c>. The Go-style <c>(result, err) := call()</c>
    /// sugar must not use exceptions as success control flow: the success-path caller synthesizes
    /// no <c>throw</c>/<c>rethrow</c> opcode.
    /// </summary>
    [Fact]
    public void Gate_ErrorTupleSuccessPath_SynthesizesNoThrow()
    {
        const string source = """
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
""";

        ILShapeInspector.Compile(source, assembly =>
        {
            var runSuccess = ILShapeInspector.GetProgramMethod(assembly, "RunSuccess");

            // The ratchet: the happy path never throws or rethrows.
            ILShapeInspector.AssertCallCount(runSuccess, OpCodes.Throw, 0);
            ILShapeInspector.AssertCallCount(runSuccess, OpCodes.Rethrow, 0);
            return 0;
        });
    }
}
