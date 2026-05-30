using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Regression guard for writing <c>initonly</c> (readonly) instance fields from a constructor.
///
/// ECMA-335 only permits a <c>stfld</c> to an <c>initonly</c> field when the receiver on the stack
/// is the constructor's own <c>this</c> — in practice a direct <c>ldarg.0</c>. The emitter used to
/// lower an explicit <c>this.field = value</c> member-access assignment by caching the receiver into
/// a local (<c>ldarg.0; stloc; ldloc; ...; stfld</c>) so it could reload the member afterwards as the
/// assignment-expression result. That local round-trip defeats ILVerify's <c>this</c>-identity check
/// and produced:
///   [InitOnly] Cannot change initonly field outside its .ctor.
/// which crashed verification for BankAccount (PropertiesAndNestedTypes) and IssueService
/// (IssueTracker). The fix emits the receiver directly and preserves the assigned value via a
/// <c>dup</c>, keeping the write verifiable. This test pins that IL shape so the defect cannot return
/// when the (separate) blocking ilverify CI gate is not run locally.
/// </summary>
public class InitOnlyFieldWriteIlShapeTests
{
    // `accountNumber` is readonly (=> initonly) and is written via an explicit `this.`-qualified
    // assignment inside the constructor — the exact pattern that previously emitted unverifiable IL.
    private const string Source = @"
class BankAccount {
    readonly accountNumber: string
    balance: double

    AccountNumber: string {
        get {
            return accountNumber
        }
    }

    constructor(accountNumber: string, initialBalance: double) {
        this.accountNumber = accountNumber
        balance = initialBalance
    }
}
";

    [Fact]
    public void ReadonlyFieldIsEmittedInitOnly()
    {
        ILShapeInspector.Compile(Source, assembly =>
        {
            var type = assembly.GetType("BankAccount");
            Assert.NotNull(type);

            var field = type!.GetField("accountNumber", BindingFlags.NonPublic | BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(field);
            Assert.True(field!.IsInitOnly, "A `readonly` field must be emitted as initonly.");
            return 0;
        });
    }

    [Fact]
    public void InitOnlyFieldWrite_LoadsThisDirectly_NotViaLocal()
    {
        ILShapeInspector.Compile(Source, assembly =>
        {
            var type = assembly.GetType("BankAccount")!;
            var ctor = type.GetConstructor(new[] { typeof(string), typeof(double) });
            Assert.NotNull(ctor);

            var module = ctor!.Module;
            var instructions = ILShapeInspector.Decode(ctor).ToList();

            // Find the stfld targeting the initonly field.
            var initOnlyStoreIndex = -1;
            for (var i = 0; i < instructions.Count; i++)
            {
                var instruction = instructions[i];
                if (instruction.OpCode != OpCodes.Stfld || instruction.MetadataToken is not { } token)
                {
                    continue;
                }

                var target = module.ResolveField(token);
                if (target is { IsInitOnly: true } && target.Name == "accountNumber")
                {
                    initOnlyStoreIndex = i;
                    break;
                }
            }

            Assert.True(initOnlyStoreIndex >= 0, "Expected a stfld writing the initonly `accountNumber` field.");

            // ECMA-335 only permits an initonly stfld when the receiver is the constructor's own
            // `this`, which the verifier proves only for a direct ldarg.0 — never for a receiver
            // round-tripped through a local. The regression was exactly that round-trip: the receiver
            // was cached as `ldarg.0; stloc; ldloc; <value>; stfld`. Reconstruct the receiver slot via
            // a minimal stack walk over the prefix and assert the instruction that produced it is
            // ldarg.0 (and specifically not an ldloc).
            var receiverProducer = FindReceiverProducer(instructions, initOnlyStoreIndex);
            Assert.NotNull(receiverProducer);

            var receiverOp = receiverProducer!.Value.OpCode;
            Assert.False(
                receiverOp == OpCodes.Ldloc || receiverOp == OpCodes.Ldloc_S
                    || receiverOp == OpCodes.Ldloc_0 || receiverOp == OpCodes.Ldloc_1
                    || receiverOp == OpCodes.Ldloc_2 || receiverOp == OpCodes.Ldloc_3,
                "initonly field write must not load its receiver from a local (defeats ILVerify's this-identity check).");
            Assert.True(
                receiverOp == OpCodes.Ldarg_0,
                $"initonly field write must load `this` directly via ldarg.0, but receiver was produced by {receiverOp.Name}.");
            return 0;
        });
    }

    /// <summary>
    /// Forward-simulates the operand stack over <paramref name="instructions"/> up to (and including)
    /// the consumption at <paramref name="storeIndex"/> (a <c>stfld</c>), returning the instruction
    /// that produced the receiver slot — i.e. the slot beneath the value the <c>stfld</c> stores.
    /// </summary>
    private static ILInstruction? FindReceiverProducer(System.Collections.Generic.IReadOnlyList<ILInstruction> instructions, int storeIndex)
    {
        // A stack of the instruction index that produced each live stack slot.
        var producers = new System.Collections.Generic.List<int>();
        for (var i = 0; i < storeIndex; i++)
        {
            var (pops, pushes) = StackEffect(instructions[i].OpCode);
            for (var p = 0; p < pops && producers.Count > 0; p++)
            {
                producers.RemoveAt(producers.Count - 1);
            }

            for (var p = 0; p < pushes; p++)
            {
                producers.Add(i);
            }
        }

        // For `stfld` the stack is [..., receiver, value]; receiver is the second-from-top slot.
        if (producers.Count < 2)
        {
            return null;
        }

        return instructions[producers[producers.Count - 2]];
    }

    /// <summary>
    /// Returns the (pops, pushes) stack effect for the small set of opcodes the constructor under test
    /// can emit. Throwing on anything unexpected keeps the test honest: a new emission shape forces an
    /// explicit decision rather than a silently wrong stack model.
    /// </summary>
    private static (int Pops, int Pushes) StackEffect(OpCode opCode)
    {
        if (opCode == OpCodes.Ldarg_0 || opCode == OpCodes.Ldarg_1 || opCode == OpCodes.Ldarg_2
            || opCode == OpCodes.Ldarg_3 || opCode == OpCodes.Ldarg || opCode == OpCodes.Ldarg_S
            || opCode == OpCodes.Ldloc || opCode == OpCodes.Ldloc_S
            || opCode == OpCodes.Ldloc_0 || opCode == OpCodes.Ldloc_1
            || opCode == OpCodes.Ldloc_2 || opCode == OpCodes.Ldloc_3
            || opCode == OpCodes.Ldc_I4 || opCode == OpCodes.Ldc_I4_S || opCode == OpCodes.Ldc_I4_0
            || opCode == OpCodes.Ldc_R8 || opCode == OpCodes.Ldnull || opCode == OpCodes.Ldstr)
        {
            return (0, 1);
        }

        if (opCode == OpCodes.Stloc || opCode == OpCodes.Stloc_S
            || opCode == OpCodes.Stloc_0 || opCode == OpCodes.Stloc_1
            || opCode == OpCodes.Stloc_2 || opCode == OpCodes.Stloc_3
            || opCode == OpCodes.Pop)
        {
            return (1, 0);
        }

        if (opCode == OpCodes.Dup)
        {
            return (1, 2);
        }

        if (opCode == OpCodes.Ldfld)
        {
            return (1, 1);
        }

        if (opCode == OpCodes.Stfld)
        {
            return (2, 0);
        }

        if (opCode == OpCodes.Call)
        {
            // The only `call` reachable before the field stores in this fixture is the base
            // System.Object::.ctor() chain: pops `this`, pushes nothing.
            return (1, 0);
        }

        throw new Xunit.Sdk.XunitException($"Unexpected opcode {opCode.Name} in initonly-ctor stack model; extend StackEffect.");
    }
}
