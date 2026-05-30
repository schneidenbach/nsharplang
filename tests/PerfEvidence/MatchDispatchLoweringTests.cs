using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// IL-shape and behavioural regression tests for match/switch dispatch lowering (Unit 10):
/// dense int/enum matches lower to a range-biased <see cref="OpCodes.Switch"/> jump table,
/// many-arm string matches lower to hash-bucketed dispatch (one <see cref="OpCodes.Switch"/>
/// over the hash, then string-equality verification), the scrutinee is evaluated exactly once,
/// and sparse/guarded matches preserve the linear semantics. All emitted IL must stay verifiable
/// and GC-safe (proven separately by ILVerify in the end-to-end gate).
/// </summary>
public class MatchDispatchLoweringTests
{
    private static int CountSwitch(MethodInfo method) =>
        ILShapeInspector.CountOpcode(method, OpCodes.Switch);

    private static object? Invoke(Assembly assembly, string methodName, params object[] args)
    {
        var method = ILShapeInspector.GetProgramMethod(assembly, methodName);
        return method.Invoke(null, args);
    }

    [Fact]
    public void DenseIntMatch_LowersToJumpTable_AndMatchesBehaviour()
    {
        const string source = @"
func classify(x: int): int {
    return match x {
        0 => 100,
        1 => 101,
        2 => 102,
        3 => 103,
        4 => 104,
        _ => -1
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "classify");
            Assert.Equal(1, CountSwitch(method));

            Assert.Equal(100, Invoke(assembly, "classify", 0));
            Assert.Equal(102, Invoke(assembly, "classify", 2));
            Assert.Equal(104, Invoke(assembly, "classify", 4));
            Assert.Equal(-1, Invoke(assembly, "classify", 9));
            Assert.Equal(-1, Invoke(assembly, "classify", -1));
            return 0;
        });
    }

    [Fact]
    public void DenseIntMatch_WithNonZeroBias_LowersToJumpTable()
    {
        // Keys are dense but biased away from zero; the range-bias subtract should keep the table compact.
        const string source = @"
func score(x: int): int {
    return match x {
        10 => 1,
        11 => 2,
        12 => 3,
        13 => 4,
        _ => 0
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "score");
            Assert.Equal(1, CountSwitch(method));

            Assert.Equal(1, Invoke(assembly, "score", 10));
            Assert.Equal(4, Invoke(assembly, "score", 13));
            Assert.Equal(0, Invoke(assembly, "score", 9));
            Assert.Equal(0, Invoke(assembly, "score", 14));
            return 0;
        });
    }

    [Fact]
    public void EnumMatch_LowersToJumpTable_AndComparesInsteadOfBinding()
    {
        // Regression: enum-member patterns must COMPARE the discriminant, not bind it. Before the
        // fix, every arm was misread as a variable binding so the match always returned the first arm.
        const string source = @"
enum Color {
    Red = 0,
    Green = 1,
    Blue = 2,
    Cyan = 3,
    Magenta = 4
}

func classify(c: Color): int {
    return match c {
        Color.Red => 10,
        Color.Green => 20,
        Color.Blue => 30,
        Color.Cyan => 40,
        Color.Magenta => 50,
        _ => 0
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "classify");
            Assert.Equal(1, CountSwitch(method));

            var colorType = assembly.GetType("Color")!;
            var values = System.Enum.GetValues(colorType).Cast<object>().ToArray();
            Assert.Equal(10, Invoke(assembly, "classify", values[0])); // Red
            Assert.Equal(20, Invoke(assembly, "classify", values[1])); // Green
            Assert.Equal(30, Invoke(assembly, "classify", values[2])); // Blue
            Assert.Equal(40, Invoke(assembly, "classify", values[3])); // Cyan
            Assert.Equal(50, Invoke(assembly, "classify", values[4])); // Magenta
            return 0;
        });
    }

    [Fact]
    public void StringMatch_ManyArms_LowersToHashDispatch_AndMatchesBehaviour()
    {
        const string source = @"
func lookup(s: string): int {
    return match s {
        ""alpha"" => 1,
        ""beta"" => 2,
        ""gamma"" => 3,
        ""delta"" => 4,
        ""epsilon"" => 5,
        _ => 0
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "lookup");
            // Hash dispatch emits exactly one switch (over the hash buckets).
            Assert.Equal(1, CountSwitch(method));

            Assert.Equal(1, Invoke(assembly, "lookup", "alpha"));
            Assert.Equal(2, Invoke(assembly, "lookup", "beta"));
            Assert.Equal(3, Invoke(assembly, "lookup", "gamma"));
            Assert.Equal(4, Invoke(assembly, "lookup", "delta"));
            Assert.Equal(5, Invoke(assembly, "lookup", "epsilon"));
            Assert.Equal(0, Invoke(assembly, "lookup", "zeta"));
            return 0;
        });
    }

    [Fact]
    public void StringMatch_NullScrutinee_FallsToDefault()
    {
        const string source = @"
func lookup(s: string): int {
    return match s {
        ""a"" => 1,
        ""b"" => 2,
        ""c"" => 3,
        ""d"" => 4,
        _ => -9
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "lookup");
            Assert.Equal(1, CountSwitch(method));
            Assert.Equal(-9, method.Invoke(null, new object?[] { null }));
            return 0;
        });
    }

    [Fact]
    public void DenseIntMatch_ScrutineeEvaluatedExactlyOnce()
    {
        // The scrutinee call `next()` has a side effect; it must be invoked exactly once and the
        // dispatch must run off the spilled local. We prove single-evaluation by counting the
        // calls to `next` in the lowered IL: exactly one call site, plus the table dispatch.
        const string source = @"
func next(): int {
    return 2
}

func choose(): int {
    return match next() {
        0 => 10,
        1 => 11,
        2 => 12,
        3 => 13,
        _ => -1
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "choose");
            Assert.Equal(1, CountSwitch(method));

            // Exactly one call to `next` (the scrutinee is spilled to a local, not re-evaluated per arm).
            var module = method.Module;
            var nextCalls = ILShapeInspector.Decode(method)
                .Count(instruction =>
                    instruction.OpCode == OpCodes.Call
                    && instruction.MetadataToken is { } token
                    && SafeResolveName(module, token) == "next");
            Assert.Equal(1, nextCalls);

            Assert.Equal(12, Invoke(assembly, "choose"));
            return 0;
        });
    }

    [Fact]
    public void SparseIntMatch_StaysLinear_NoJumpTable()
    {
        // Keys span 0..50000 with only three arms; far too sparse for a jump table. The linear
        // chain must be preserved and behaviour unchanged.
        const string source = @"
func sparse(x: int): int {
    return match x {
        1 => 10,
        1000 => 20,
        50000 => 30,
        _ => 0
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "sparse");
            Assert.Equal(0, CountSwitch(method));

            Assert.Equal(10, Invoke(assembly, "sparse", 1));
            Assert.Equal(20, Invoke(assembly, "sparse", 1000));
            Assert.Equal(30, Invoke(assembly, "sparse", 50000));
            Assert.Equal(0, Invoke(assembly, "sparse", 7));
            return 0;
        });
    }

    [Fact]
    public void GuardedMatch_StaysLinear_AndRespectsGuardOrdering()
    {
        // A guarded arm cannot participate in a jump table (the guard may fail and must fall
        // through to later arms). The whole match keeps the linear path.
        const string source = @"
func guarded(x: int): int {
    return match x {
        n when n > 100 => 1,
        5 => 2,
        10 => 3,
        15 => 4,
        20 => 5,
        _ => 0
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "guarded");
            Assert.Equal(0, CountSwitch(method));

            Assert.Equal(1, Invoke(assembly, "guarded", 200)); // guard wins
            Assert.Equal(2, Invoke(assembly, "guarded", 5));
            Assert.Equal(5, Invoke(assembly, "guarded", 20));
            Assert.Equal(0, Invoke(assembly, "guarded", 7));
            return 0;
        });
    }

    [Fact]
    public void FewArmStringMatch_StaysLinear()
    {
        // Below the hash-dispatch threshold (4 distinct keys), a short string match stays a linear
        // compare chain.
        const string source = @"
func two(s: string): int {
    return match s {
        ""x"" => 1,
        ""y"" => 2,
        _ => 0
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "two");
            Assert.Equal(0, CountSwitch(method));

            Assert.Equal(1, Invoke(assembly, "two", "x"));
            Assert.Equal(2, Invoke(assembly, "two", "y"));
            Assert.Equal(0, Invoke(assembly, "two", "z"));
            return 0;
        });
    }

    [Fact]
    public void DenseIntMatch_VariableBindingCatchAll_BindsScrutinee()
    {
        // The catch-all is a variable binding (not `_`); the default path must bind the scrutinee
        // before evaluating the catch-all body.
        const string source = @"
func describe(x: int): int {
    return match x {
        0 => 1000,
        1 => 1001,
        2 => 1002,
        3 => 1003,
        other => other * 2
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "describe");
            Assert.Equal(1, CountSwitch(method));

            Assert.Equal(1000, Invoke(assembly, "describe", 0));
            Assert.Equal(1003, Invoke(assembly, "describe", 3));
            Assert.Equal(50, Invoke(assembly, "describe", 25)); // binding: 25 * 2
            return 0;
        });
    }

    [Fact]
    public void DenseSwitchStatement_LowersToJumpTable_AndMatchesBehaviour()
    {
        const string source = @"
func bucket(x: int): int {
    result := -1
    switch x {
        case 0 => result = 90
        case 1 => result = 91
        case 2 => result = 92
        case 3 => result = 93
        default => result = 0
    }
    return result
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "bucket");
            Assert.Equal(1, CountSwitch(method));

            Assert.Equal(90, Invoke(assembly, "bucket", 0));
            Assert.Equal(93, Invoke(assembly, "bucket", 3));
            Assert.Equal(0, Invoke(assembly, "bucket", 8));
            return 0;
        });
    }

    private static string? SafeResolveName(Module module, int token)
    {
        try
        {
            return module.ResolveMethod(token)?.Name;
        }
        catch (System.Exception)
        {
            return null;
        }
    }
}
