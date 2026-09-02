namespace NSharpLang.SystemsVectorizationFacts.Tests


// THE INSTRUMENT, PINNED BEFORE ANYTHING IS MEASURED WITH IT.
//
// `IlShape` decodes an emitted method's IL and resolves its call tokens. Three properties have to hold
// before its answers mean anything, and each has a block below.
//
//   1 THE STEPPER IS SYNCHRONISED. `IlShape.DecodesToRet` re-walks a body and reports whether the decode
//     consumed it exactly and ended on `ret`. A stepper that mis-sized any operand would land inside an
//     operand, hit an undefined opcode, or stop short. It is asserted here on a method carrying an
//     EIGHT-BYTE `ldc.i8` operand — the widest inline operand a byte-stepper gets wrong — and, in the four
//     fact files, on one kernel of every accepted and rejected shape.
//
//   2 THE `switch` ARM IS CORRECT EVEN THOUGH NO N# METHOD CAN CARRY ONE. `switch` is the only variable-
//     length operand in ECMA-335 (a four-byte count then that many four-byte targets), and it is the other
//     encoding a naive stepper gets wrong. It cannot be exercised live: `grep -rn "OpCodes.Switch" src/`
//     is EMPTY, so the columnar backend emits no `switch` instruction anywhere, and an N# `match` over int
//     literals compiles to a comparison chain (measured: zero 0x45 opcodes in a six-arm match). So the arm
//     is pinned directly, on a hand-built jump table, rather than left unasserted.
//
//   3 IT READS THE RIGHT ANSWER OFF REAL KERNELS. A canonical counted reduction reports exactly one
//     `SumInt32` call and no element loads; the same loop with `a[i] * 2` reports no helper, one call of no
//     kind at all, and a surviving `ldelem.i4`. Those two are the whole discrimination the four fact files
//     rest on, so they are asserted against live emitted code and not only against the decoder.
//
// Maps: ILShapeInspector.cs — the deleted instrument this file replaces. It had no test methods of its own;
// its `Decode`, `CountOpcode` and `CountCall` entry points are what `IlShape` re-provides.

class InstrumentKernels {
    // Accepted by TryMatchWhileReduction: `i < n`, `acc = acc + a[i]`, `i = i + 1`.
    static func Canonical(a: int[], n: int): int {
        acc := 0
        i := 0
        while i < n {
            acc = acc + a[i]
            i = i + 1
        }
        return acc
    }

    // Rejected by TryMatchReductionUpdate: `a[i] * 2` is not a plain element read.
    static func Scaled(a: int[], n: int): int {
        acc := 0
        i := 0
        while i < n {
            acc = acc + a[i] * 2
            i = i + 1
        }
        return acc
    }

    // Carries two eight-byte `ldc.i8` operands and a six-arm `match`, so the decode has to step over the
    // widest inline operand twice and through the comparison chain the match lowers to.
    static func WideLiterals(x: int): long {
        step := match x {
            0 => 10,
            1 => 20,
            2 => 30,
            3 => 40,
            4 => 50,
            _ => 60
        }
        scaled: long = 0
        scaled = (long)step * 1000000007
        return scaled
    }
}

// A synthetic `switch` operand: a four-byte little-endian count of 3, then three four-byte targets.
func JumpTableOfThree(): int[] {
    table := new int[](20)
    table[0] = 3
    return table
}

func JumpTableOfNone(): int[] {
    return new int[](4)
}

test "the decode consumes a body carrying eight-byte operands exactly and stops on ret" {
    assert IlShape.DecodesToRet(typeof(InstrumentKernels), "WideLiterals")
    assert IlShape.OpcodeCount(typeof(InstrumentKernels), "WideLiterals", IlEncoding.LdcI8()) == 2
    assert IlShape.DecodesToRet(typeof(InstrumentKernels), "Canonical")
    assert IlShape.DecodesToRet(typeof(InstrumentKernels), "Scaled")
}

test "the switch operand is sized as a count followed by that many four-byte targets" {
    assert IlShape.OperandSize(IlEncoding.InlineSwitch(), JumpTableOfThree(), 0) == 16
    assert IlShape.OperandSize(IlEncoding.InlineSwitch(), JumpTableOfNone(), 0) == 4
    // The fixed widths, for contrast: no operand, one byte, two, four, eight.
    assert IlShape.OperandSize(IlEncoding.InlineNone(), JumpTableOfNone(), 0) == 0
    assert IlShape.OperandSize(IlEncoding.ShortInlineI(), JumpTableOfNone(), 0) == 1
    assert IlShape.OperandSize(IlEncoding.InlineVar(), JumpTableOfNone(), 0) == 2
    assert IlShape.OperandSize(IlEncoding.InlineBrTarget(), JumpTableOfNone(), 0) == 4
    assert IlShape.OperandSize(IlEncoding.InlineI8(), JumpTableOfNone(), 0) == 8
}

test "a vectorized kernel reports exactly one helper call and no surviving element load" {
    assert IlShape.SimdCalls(typeof(InstrumentKernels), "Canonical") == "SumInt32"
    assert IlShape.CallCount(typeof(InstrumentKernels), "Canonical") == 1
    assert IlShape.OpcodeCount(typeof(InstrumentKernels), "Canonical", IlEncoding.LdelemI4()) == 0
}

test "a kernel the matcher rejects reports no helper, no call at all, and a surviving element load" {
    assert IlShape.SimdCalls(typeof(InstrumentKernels), "Scaled") == ""
    assert IlShape.CallCount(typeof(InstrumentKernels), "Scaled") == 0
    assert IlShape.OpcodeCount(typeof(InstrumentKernels), "Scaled", IlEncoding.LdelemI4()) == 1
}

test "the call filter is anchored on the declaring type rather than on the method name" {
    // Asking for the same call under a type name that does not declare it must answer nothing, so a helper
    // name can never be reported from some other type that happens to define one.
    assert IlShape.CallsInto(typeof(InstrumentKernels), "Canonical", "SimdReductions") == "SumInt32"
    assert IlShape.CallsInto(typeof(InstrumentKernels), "Canonical", "SimdReductionsExtra") == ""
    assert IlShape.CallsInto(typeof(InstrumentKernels), "Canonical", "Math") == ""
}
