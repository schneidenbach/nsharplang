namespace NSharpLang.NativeComparison

import System
import System.Reflection
import System.Reflection.Emit


// THE SELF-INSPECTION INSTRUMENT: WHICH `SimdReductions` HELPER EACH KERNEL ACTUALLY CALLS.
//
// `Kernels.nl` claims that four of its six loops are rewritten by the systems vectorizer into calls
// into `NSharpLang.Runtime.SimdReductions`. That claim decides what the comparison against Rust and C
// means, so it is READ BACK OUT OF THE EMITTED IL at run time rather than asserted in a comment: this
// file walks each kernel's own method body and reports the helpers it calls.
//
// WHY A REAL IL WALK AND NOT A BYTE SCAN. `call` is 0x28, but 0x28 also occurs inside operand bytes —
// a `ldc.i4 0x28` operand, a branch offset, a token. Scanning for the byte would report calls that do
// not exist and miss ones that do. The walk below decodes each instruction, reads its operand SIZE
// from `OperandType`, and steps by it, so every byte it treats as an opcode is one.
//
// WHERE THE OPERAND SIZES COME FROM. The opcode -> `OperandType` map is REFLECTED from the public
// static fields of `System.Reflection.Emit.OpCodes`, so it is the runtime's own table rather than a
// transcription. Only the `OperandType` -> byte-count step is written out here (`OperandSize`), and it
// is the fixed encoding of ECMA-335 §III.1.2: no operand, one, two, four, eight, or the `switch`
// form's `4 + 4 * n`.
//
// FOUR COLUMNAR DECLINES SHAPED THIS FILE, AND EACH WORKAROUND IS NARROW.
//   1 `MethodBody` is not an admitted local type and `MethodBody.GetILAsByteArray` has no binding
//     plan, so both are reached through `MethodInfo.Invoke` and kept in `object` locals.
//   2 `Module.ResolveMethod` likewise has no plan row, so it is invoked the same way; the two-argument
//     `GetMethod(name, Type[])` overload picks the one-argument `ResolveMethod` unambiguously, which
//     the one-argument `GetMethod(name)` could not (it throws on the overload set).
//   3 A cast from `object` to an ARRAY type declines (`emit.local.initializer`), so the IL bytes are
//     read one at a time through `Array.GetValue(int)` instead of being cast to `byte[]`.
//   4 Unboxing `object` to the `OpCode` struct declines, so `get_Value` and `get_OperandType` are
//     invoked ON the boxed value and their answers come back through `Convert.ToInt32`.
// The instrument runs only under `--il-shape`; none of this reflection is on any timed path.
class IlShape {

    // The helpers one kernel calls, comma-separated in first-call order, or `none`.
    [boundary]
    static func SimdHelpersFor(kernelName: string): string {
        kernel := must typeof(Kernels).GetMethod(kernelName)
        il := KernelIl(kernel)
        operandKinds := OperandKindTable()
        moduleValue := typeof(Kernels).get_Module()
        resolve := must typeof(Module).GetMethod("ResolveMethod", Int32Types())

        names := ""
        position := 0
        while position < il.Length {
            opcode := il[position]
            position = position + 1
            isCall := false
            kind := -1
            if opcode == 254 {
                kind = operandKinds[256 + il[position]]
                position = position + 1
            } else {
                kind = operandKinds[opcode]
                isCall = opcode == 40 || opcode == 111
            }

            if kind < 0 {
                return "undecodable-opcode"
            }

            if isCall {
                called := ResolvedSimdHelper(moduleValue, resolve, ReadInt32(il, position))
                if called != "" && !AlreadyNamed(names, called) {
                    if names == "" {
                        names = called
                    } else {
                        names = names + "," + called
                    }
                }
            }

            position = position + OperandSize(kind, il, position)
        }

        if names == "" {
            return "none"
        }

        return names
    }

    [boundary]
    static func KernelIl(kernel: MethodInfo): int[] {
        // The kernel's IL, one byte per `int`. `Array.GetValue` is the only reader available here: see
        // decline 3 in the header.
        receiver: object? = kernel
        body := must InvokeNoArguments(typeof(MethodBase), "GetMethodBody", receiver)
        bytes := must InvokeNoArguments(body.GetType(), "GetILAsByteArray", body)
        arrayType := bytes.GetType()
        getLength := must arrayType.GetMethod("get_Length", NoTypes())
        length := Convert.ToInt32(must getLength.Invoke(bytes, NoArguments()))
        getValue := must arrayType.GetMethod("GetValue", Int32Types())
        indexArguments := new object?[](1)
        il := new int[](length)
        for i := 0; i < length; i++ {
            SetArgument(indexArguments, 0, i)
            il[i] = Convert.ToInt32(must getValue.Invoke(bytes, indexArguments))
        }

        return il
    }

    [boundary]
    static func OperandKindTable(): int[] {
        // Slot `b` holds the `OperandType` of the one-byte opcode `b`; slot `256 + b` holds the
        // `OperandType` of the two-byte opcode `0xFE b`. `-1` means the runtime defines no such opcode.
        table := new int[](512)
        for i := 0; i < 512; i++ {
            table[i] = -1
        }

        opCodeType := typeof(OpCode)
        getValue := must opCodeType.GetMethod("get_Value", NoTypes())
        getOperandType := must opCodeType.GetMethod("get_OperandType", NoTypes())
        fields := typeof(OpCodes).GetFields()
        for i := 0; i < fields.Length; i++ {
            boxed := fields[i].GetValue(null)
            if boxed != null {
                // `OpCode.Value` is a `short`, so a two-byte opcode such as `0xFE01` arrives negative;
                // masking to 16 bits recovers the encoded form.
                signed := Convert.ToInt32(must getValue.Invoke(boxed, NoArguments()))
                value := signed & 65535
                kind := Convert.ToInt32(must getOperandType.Invoke(boxed, NoArguments()))
                if value >= 65024 {
                    table[256 + (value & 255)] = kind
                } else if value <= 255 {
                    table[value] = kind
                }
            }
        }

        return table
    }

    // ECMA-335 §III.1.2 operand widths, by `System.Reflection.Emit.OperandType`.
    static func OperandSize(kind: int, il: int[], position: int): int {
        if kind == 5 {
            return 0
        }

        if kind == 15 || kind == 16 || kind == 18 {
            return 1
        }

        if kind == 14 {
            return 2
        }

        if kind == 3 || kind == 7 {
            return 8
        }

        if kind == 11 {
            // `switch` carries a jump-table length and then that many four-byte targets.
            return 4 + (4 * ReadInt32(il, position))
        }

        return 4
    }

    static func ReadInt32(il: int[], position: int): int {
        return il[position] | (il[position + 1] << 8) | (il[position + 2] << 16) | (il[position + 3] << 24)
    }

    [boundary]
    static func ResolvedSimdHelper(moduleValue: Module, resolve: MethodInfo, token: int): string {
        // Answers the `SimdReductions` method a call token names, or "" when the token names anything
        // else — a call into the BCL, or a constructor rather than a method.
        arguments := new object?[](1)
        SetArgument(arguments, 0, token)
        receiver: object? = moduleValue
        resolved := resolve.Invoke(receiver, arguments) as MethodInfo
        if resolved == null {
            return ""
        }

        declaring := resolved.get_DeclaringType()
        if declaring == null || declaring.Name != "SimdReductions" {
            return ""
        }

        return resolved.get_Name()
    }

    [boundary]
    static func AlreadyNamed(names: string, candidate: string): bool {
        // Anchored on both sides so that a name cannot match inside a longer one.
        return ("," + names + ",").Contains("," + candidate + ",")
    }

    [boundary]
    static func InvokeNoArguments(owner: Type, name: string, receiver: object?): object? {
        method := must owner.GetMethod(name, NoTypes())
        return method.Invoke(receiver, NoArguments())
    }

    [boundary]
    static func NoTypes(): Type[] {
        return new Type[](0)
    }

    [boundary]
    static func Int32Types(): Type[] {
        types := new Type[](1)
        types[0] = typeof(int)
        return types
    }

    [boundary]
    static func NoArguments(): object?[] {
        return new object?[](0)
    }

    // A boxing store into an `object?[]`, kept as its own function because the columnar backend
    // declines the same store written inline (`emit.statement.block-child`).
    static func SetArgument(target: object?[], index: int, value: object?) {
        target[index] = value
    }
}
