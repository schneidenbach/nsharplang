using System;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Unit 12 regression tests: arithmetic overflow semantics and bounds-check-elision-friendly
/// loop shapes.
///
/// Two invariants are pinned here, both of which are required to keep runtime-hot code fast
/// while staying GC-safe and verifiable (see <c>docs/design/performance-compiler-refactor.md</c>):
///
/// 1. <b>Unchecked default for hot-loop / induction arithmetic.</b> N#'s language-level default
///    overflow semantics are <em>unchecked</em> (wraparound), matching C#'s default — see
///    <c>docs/DESIGN.md</c> and <c>examples/11-advanced-features/CheckedUnchecked</c>. The
///    compiler-introduced index induction (<c>i++</c>) in the foreach fast paths must therefore
///    emit plain <c>add</c> (never <c>add.ovf</c>) regardless of any surrounding <c>checked</c>
///    region, and user arithmetic outside an explicit <c>checked</c> region must also use the
///    non-<c>.ovf</c> opcodes.
///
/// 2. <b>Explicit <c>checked</c> is honored exactly.</b> An expression inside <c>checked(...)</c>
///    must still emit the <c>*.ovf</c> opcode and throw <see cref="OverflowException"/> at runtime.
///
/// 3. <b>Bounds-check-elision-friendly loop shape.</b> The array foreach fast path must emit the
///    canonical RyuJIT range-check-elimination idiom: index initialised to 0, the loop test
///    comparing the index against the array's own length (a fresh <c>ldlen</c>), and indexing the
///    same array with <c>ldelem*</c>. This is the shape RyuJIT proves <c>0 &lt;= i &lt; arr.Length</c>
///    for and elides the per-element bounds check.
/// </summary>
public class ArithmeticAndLoopShapeTests
{
    private static readonly OpCode[] OverflowOpcodes =
    {
        OpCodes.Add_Ovf, OpCodes.Add_Ovf_Un,
        OpCodes.Sub_Ovf, OpCodes.Sub_Ovf_Un,
        OpCodes.Mul_Ovf, OpCodes.Mul_Ovf_Un,
        OpCodes.Conv_Ovf_I, OpCodes.Conv_Ovf_I_Un,
        OpCodes.Conv_Ovf_I1, OpCodes.Conv_Ovf_I1_Un,
        OpCodes.Conv_Ovf_I2, OpCodes.Conv_Ovf_I2_Un,
        OpCodes.Conv_Ovf_I4, OpCodes.Conv_Ovf_I4_Un,
        OpCodes.Conv_Ovf_I8, OpCodes.Conv_Ovf_I8_Un,
        OpCodes.Conv_Ovf_U, OpCodes.Conv_Ovf_U_Un,
        OpCodes.Conv_Ovf_U1, OpCodes.Conv_Ovf_U1_Un,
        OpCodes.Conv_Ovf_U2, OpCodes.Conv_Ovf_U2_Un,
        OpCodes.Conv_Ovf_U4, OpCodes.Conv_Ovf_U4_Un,
        OpCodes.Conv_Ovf_U8, OpCodes.Conv_Ovf_U8_Un,
    };

    private static int CountOverflowOpcodes(System.Collections.Generic.IReadOnlyList<ILInstruction> il) =>
        il.Count(instruction => OverflowOpcodes.Contains(instruction.OpCode));

    /// <summary>
    /// Returns the index of the first position in <paramref name="il"/> at which the contiguous
    /// opcode <paramref name="pattern"/> appears, or -1 if it never does. Used to pin that
    /// instructions appear adjacently in the required order, not merely somewhere in the method.
    /// </summary>
    private static int IndexOfSequence(
        System.Collections.Generic.IReadOnlyList<ILInstruction> il,
        params OpCode[] pattern)
    {
        for (var start = 0; start + pattern.Length <= il.Count; start++)
        {
            var matched = true;
            for (var offset = 0; offset < pattern.Length; offset++)
            {
                if (il[start + offset].OpCode != pattern[offset])
                {
                    matched = false;
                    break;
                }
            }

            if (matched)
            {
                return start;
            }
        }

        return -1;
    }

    private static void AssertContainsSequence(
        System.Collections.Generic.IReadOnlyList<ILInstruction> il,
        string description,
        params OpCode[] pattern)
    {
        Assert.True(
            IndexOfSequence(il, pattern) >= 0,
            $"Expected contiguous IL sequence [{string.Join(", ", pattern.Select(p => p.Name))}] ({description}).");
    }

    [Fact]
    public void ArithmeticUncheckedHotLoop_HasNoOverflowOpcodes()
    {
        const string source = @"
func sumArray(nums: int[]): int {
    total := 0
    for n in nums {
        total = total + n
    }
    return total
}";

        var il = ILShapeInspector.DecodeProgramMethod(source, "sumArray");

        // The unchecked default means neither the user addition nor the compiler-introduced
        // index induction may emit any *.ovf opcode anywhere in the method.
        Assert.Equal(0, CountOverflowOpcodes(il));

        // Plain add appears for both the user-level `total + n` and the `i++` induction, and the
        // induction specifically is a monotonic plain +1 (ldc.i4.1 ; add) — never add.ovf.
        Assert.True(
            ILShapeInspector.CountOpcode(il, OpCodes.Add) >= 2,
            "Expected at least two plain 'add' opcodes (user add + index induction).");
        AssertContainsSequence(
            il,
            "monotonic +1 index induction with plain add",
            OpCodes.Ldc_I4_1, OpCodes.Add);
    }

    [Fact]
    public void ArithmeticForeachArray_MatchesBoundsCheckElisionIdiom()
    {
        const string source = @"
func sumArray(nums: int[]): int {
    total := 0
    for n in nums {
        total = total + n
    }
    return total
}";

        var il = ILShapeInspector.DecodeProgramMethod(source, "sumArray");

        // RyuJIT's range-check-elimination idiom for T[] requires a specific contiguous shape, not
        // merely the presence of the opcodes. Pin the three contiguous fragments in order:
        //
        //   1. The loop test reads the array length *at the test* via ldlen (re-read each iteration,
        //      deliberately not cached in a local — caching defeats array BCE) and branches on the
        //      index-vs-length comparison:  ... ldlen ; conv.i4 ; bge end
        //   2. The element load happens immediately before storing into the loop variable:
        //      ... ldelem.i4 ; stloc
        //   3. The induction is a monotonic +1:  ldc.i4.1 ; add
        //
        // The ldlen→conv.i4→bge fragment also proves the length is NOT cached in a local (a cached
        // form would compare against an ldloc, with the single ldlen sitting in the pre-loop setup).
        AssertContainsSequence(
            il,
            "loop test reads array length fresh and branches (not a cached-length compare)",
            OpCodes.Ldlen, OpCodes.Conv_I4, OpCodes.Bge);
        AssertContainsSequence(
            il,
            "element loaded via ldelem.i4 then stored into the loop variable",
            OpCodes.Ldelem_I4, OpCodes.Stloc_S);
        AssertContainsSequence(
            il,
            "monotonic +1 index induction",
            OpCodes.Ldc_I4_1, OpCodes.Add);

        // There must be exactly one ldlen: the per-iteration loop test. More than one would imply a
        // different (non-canonical) shape; zero would mean the length came from somewhere else.
        Assert.Equal(1, ILShapeInspector.CountOpcode(il, OpCodes.Ldlen));

        // The whole method, including the index induction, must be free of *.ovf.
        Assert.Equal(0, CountOverflowOpcodes(il));
    }

    [Fact]
    public void ArithmeticCheckedExpression_EmitsOverflowOpcode()
    {
        const string source = @"
func checkedAdd(x: int, y: int): int {
    return checked(x + y)
}";

        var il = ILShapeInspector.DecodeProgramMethod(source, "checkedAdd");

        // An explicit checked region must still emit add.ovf — and ONLY add.ovf. Asserting the total
        // overflow-opcode count is 1 (not just add.ovf >= 1) rules out a regression that leaks any
        // extra *.ovf (sub.ovf, mul.ovf, conv.ovf.*, …) into the emitted method.
        Assert.Equal(1, ILShapeInspector.CountOpcode(il, OpCodes.Add_Ovf));
        Assert.Equal(1, CountOverflowOpcodes(il));
        Assert.Equal(0, ILShapeInspector.CountOpcode(il, OpCodes.Add));
    }

    [Fact]
    public void ArithmeticSubtractAndMultiply_DefaultUnchecked_UsePlainOpcodes()
    {
        // The unchecked default applies to sub and mul exactly as it does to add: plain sub/mul,
        // never sub.ovf/mul.ovf. Without this, a regression that only touched subtraction or
        // multiplication emission would slip past the add-only tests above.
        const string source = @"
func subMul(x: int, y: int): int {
    return x - y * x
}";

        var il = ILShapeInspector.DecodeProgramMethod(source, "subMul");

        Assert.Equal(1, ILShapeInspector.CountOpcode(il, OpCodes.Sub));
        Assert.Equal(1, ILShapeInspector.CountOpcode(il, OpCodes.Mul));
        Assert.Equal(0, CountOverflowOpcodes(il));
    }

    [Fact]
    public void ArithmeticSubtractAndMultiply_Checked_UseOverflowOpcodes()
    {
        // The mirror of the default case: an explicit checked(...) must emit sub.ovf and mul.ovf
        // (and nothing but those two overflow opcodes), proving checked is honored for sub/mul,
        // not just add.
        const string source = @"
func subMulChecked(x: int, y: int): int {
    return checked(x - y * x)
}";

        var il = ILShapeInspector.DecodeProgramMethod(source, "subMulChecked");

        Assert.Equal(1, ILShapeInspector.CountOpcode(il, OpCodes.Sub_Ovf));
        Assert.Equal(1, ILShapeInspector.CountOpcode(il, OpCodes.Mul_Ovf));
        Assert.Equal(2, CountOverflowOpcodes(il));
        Assert.Equal(0, ILShapeInspector.CountOpcode(il, OpCodes.Sub));
        Assert.Equal(0, ILShapeInspector.CountOpcode(il, OpCodes.Mul));
    }

    [Fact]
    public void ArithmeticUncheckedExpression_DefaultUsesPlainAdd()
    {
        const string source = @"
func plainAdd(x: int, y: int): int {
    return x + y
}";

        var il = ILShapeInspector.DecodeProgramMethod(source, "plainAdd");

        // The language default is unchecked: plain add, no *.ovf.
        Assert.Equal(1, ILShapeInspector.CountOpcode(il, OpCodes.Add));
        Assert.Equal(0, CountOverflowOpcodes(il));
    }

    [Fact]
    public void ArithmeticCheckedExpressionInLoopBody_DoesNotLeakIntoInduction()
    {
        // N#'s `checked` is *expression-scoped* (`checked(expr)`); there is no `checked { block }`
        // statement form (see Parser.cs — checked/unchecked require an immediate '('). A `for` loop
        // therefore can never be syntactically enclosed by a checked context. This test pins the
        // tightest thing the language can express: a checked(...) expression inside the loop body
        // must emit overflow opcodes for ITS arithmetic ONLY, and must not leak overflow checking
        // into the compiler-generated index induction or the BCE loop shape around it.
        const string source = @"
func sumChecked(nums: int[]): int {
    total := 0
    for n in nums {
        total = checked(total + n)
    }
    return total
}";

        var il = ILShapeInspector.DecodeProgramMethod(source, "sumChecked");

        // The whole method emits exactly one overflow opcode — the user's checked add — and that
        // opcode is add.ovf. Asserting the total count (not just add.ovf >= 1) catches a regression
        // that leaks any *.ovf (add.ovf.un, sub.ovf, conv.ovf.*, …) into the generated loop code.
        Assert.Equal(1, CountOverflowOpcodes(il));
        Assert.Equal(1, ILShapeInspector.CountOpcode(il, OpCodes.Add_Ovf));

        // The induction stays a monotonic plain +1 and the BCE loop shape is intact: exactly one
        // ldlen (the per-iteration test), the fresh-length branch, and the +1 induction.
        AssertContainsSequence(
            il,
            "loop test still reads the array length fresh under a checked-expression body",
            OpCodes.Ldlen, OpCodes.Conv_I4, OpCodes.Bge);
        AssertContainsSequence(
            il,
            "index induction stays plain +1 under a checked-expression body",
            OpCodes.Ldc_I4_1, OpCodes.Add);
        Assert.Equal(1, ILShapeInspector.CountOpcode(il, OpCodes.Ldlen));
    }

    [Fact]
    public void ArithmeticCheckedOverflow_ThrowsAtRuntime()
    {
        const string source = @"
func overflow(): int {
    return checked(2147483647 + 1)
}";

        var thrown = ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "overflow");
            try
            {
                method.Invoke(null, null);
                return false;
            }
            catch (TargetInvocationException ex) when (ex.InnerException is OverflowException)
            {
                return true;
            }
        });

        Assert.True(thrown, "Expected checked(int.MaxValue + 1) to throw OverflowException at runtime.");
    }

    [Fact]
    public void ArithmeticUncheckedOverflow_WrapsAtRuntime()
    {
        const string source = @"
func wrap(): int {
    return 2147483647 + 1
}";

        var result = ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "wrap");
            return method.Invoke(null, null);
        });

        // Default unchecked semantics: int.MaxValue + 1 wraps to int.MinValue, matching C# unchecked.
        Assert.Equal(int.MinValue, result);
    }

    [Fact]
    public void ArithmeticForeachArray_ProducesCorrectSum()
    {
        const string source = @"
func sumArray(nums: int[]): int {
    total := 0
    for n in nums {
        total = total + n
    }
    return total
}";

        var result = ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "sumArray");
            return method.Invoke(null, new object[] { new[] { 1, 2, 3, 4, 5 } });
        });

        Assert.Equal(15, result);
    }
}
