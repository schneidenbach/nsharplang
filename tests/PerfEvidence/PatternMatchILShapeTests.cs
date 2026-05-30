using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// ADDITIVE IL-validity coverage for type-test pattern matching (<c>match obj { Type x => ... }</c>).
///
/// Type patterns lower to an <c>isinst</c> + <c>dup</c> + <c>brtrue</c> probe per arm, with a
/// <c>pop</c> on the no-match path and a <c>castclass</c> (or use of the duplicated reference) on the
/// bind path. The <c>dup</c>/<c>pop</c> bracketing around each <c>isinst</c> is the verifiability-
/// critical shape: an unbalanced stack here (a missing <c>pop</c> on the fall-through, or a stray
/// <c>dup</c>) is exactly the class of bug the IL gate exists to catch. The existing
/// <see cref="MatchDispatchLoweringTests"/> covers int/enum/string <em>value</em> dispatch but pins
/// no structural invariant for <em>type</em> patterns; these do.
/// </summary>
public class PatternMatchILShapeTests
{
    private static IReadOnlyList<ILInstruction> Decode(Assembly assembly, string method) =>
        ILShapeInspector.Decode(ILShapeInspector.GetProgramMethod(assembly, method));

    /// <summary>
    /// Verifies the local <c>dup</c>/<c>pop</c> bracketing of each <c>isinst</c> probe: every
    /// <c>isinst</c> is immediately followed by a <c>dup</c> (to keep the tested reference for binding
    /// while branching on the type-test result). This is the per-arm shape the lowering emits and the
    /// invariant a stack-imbalance regression would break.
    /// </summary>
    private static void AssertEachIsinstIsFollowedByDup(IReadOnlyList<ILInstruction> instructions)
    {
        for (var i = 0; i < instructions.Count; i++)
        {
            if (instructions[i].OpCode != OpCodes.Isinst)
            {
                continue;
            }

            Assert.True(
                i + 1 < instructions.Count && instructions[i + 1].OpCode == OpCodes.Dup,
                $"Each isinst type-test must be bracketed by a dup at offset IL_{instructions[i].Offset:x4}.");
        }
    }

    [Fact]
    public void TypePatternMatch_EmitsBalancedIsinstDupPop_AndNoBoxing()
    {
        const string source = @"
func describe(obj: object): string {
    return match obj {
        string s => s,
        int => ""int"",
        _ => ""other""
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var instructions = Decode(assembly, "describe");

            // Two type-test arms => two isinst probes.
            var isinst = ILShapeInspector.CountOpcode(instructions, OpCodes.Isinst);
            Assert.Equal(2, isinst);

            // Each isinst is bracketed by a dup; the no-match fall-through pops the duplicate.
            AssertEachIsinstIsFollowedByDup(instructions);
            Assert.True(
                ILShapeInspector.CountOpcode(instructions, OpCodes.Dup) >= isinst,
                "Each isinst probe must duplicate the scrutinee reference.");
            Assert.True(
                ILShapeInspector.CountOpcode(instructions, OpCodes.Pop) >= isinst,
                "Each isinst no-match path must pop the duplicated reference to keep the stack balanced.");

            // A reference type test must never box the scrutinee.
            ILShapeInspector.AssertNoBoxing(ILShapeInspector.GetProgramMethod(assembly, "describe"));
            return 0;
        });
    }

    [Fact]
    public void TypePatternMatch_BindsAndExecutesCorrectly()
    {
        // Behavioural proof the isinst/castclass binding resolves and runs (token validity at runtime).
        const string source = @"
func describe(obj: object): string {
    return match obj {
        string s => s,
        int => ""int"",
        _ => ""other""
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var describe = ILShapeInspector.GetProgramMethod(assembly, "describe");
            Assert.Equal("hello", describe.Invoke(null, new object[] { "hello" }));
            Assert.Equal("int", describe.Invoke(null, new object[] { 7 }));
            Assert.Equal("other", describe.Invoke(null, new object[] { new object() }));
            return 0;
        });
    }

    [Fact]
    public void NestedTypePatternMatch_KeepsStackBalanced_PerScrutinee()
    {
        // Two independent match expressions (outer arms each contain a nested match). Each match's
        // isinst probes must be individually dup/pop-balanced; nesting must not leak stack between
        // the inner and outer dispatch.
        const string source = @"
func classify(a: object, b: object): string {
    return match a {
        string => match b {
            string => ""both strings"",
            _ => ""a string""
        },
        _ => ""a other""
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var instructions = Decode(assembly, "classify");

            AssertEachIsinstIsFollowedByDup(instructions);

            var isinst = ILShapeInspector.CountOpcode(instructions, OpCodes.Isinst);
            Assert.True(isinst >= 2, "Expected at least one isinst per type-test arm across both matches.");
            Assert.True(
                ILShapeInspector.CountOpcode(instructions, OpCodes.Pop) >= isinst,
                "Every nested isinst no-match path must pop to stay balanced.");

            var classify = ILShapeInspector.GetProgramMethod(assembly, "classify");
            Assert.Equal("both strings", classify.Invoke(null, new object[] { "x", "y" }));
            Assert.Equal("a string", classify.Invoke(null, new object[] { "x", 1 }));
            Assert.Equal("a other", classify.Invoke(null, new object[] { 1, 1 }));
            return 0;
        });
    }

    [Fact]
    public void TypePatternWithGuard_EvaluatesScrutineeOnce_AndStaysBalanced()
    {
        // A guarded type pattern must test the type once, bind, then evaluate the guard; the guard
        // failure must fall through to the next arm without leaving the scrutinee on the stack.
        const string source = @"
func check(obj: object): string {
    return match obj {
        string s when s.Length > 3 => ""long"",
        string s => ""short"",
        _ => ""not string""
    }
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var instructions = Decode(assembly, "check");
            AssertEachIsinstIsFollowedByDup(instructions);

            var check = ILShapeInspector.GetProgramMethod(assembly, "check");
            Assert.Equal("long", check.Invoke(null, new object[] { "abcde" }));
            Assert.Equal("short", check.Invoke(null, new object[] { "ab" }));
            Assert.Equal("not string", check.Invoke(null, new object[] { 42 }));
            return 0;
        });
    }
}
