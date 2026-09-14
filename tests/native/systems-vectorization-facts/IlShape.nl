namespace NSharpLang.SystemsVectorizationFacts.Tests

import System
import System.Reflection
import System.Reflection.Emit


// THE INSTRUMENT THE FOUR VECTORIZATION FACT FILES MEASURE WITH: A REAL IL WALK OVER THE EMITTED KERNELS.
//
// The SIMD auto-vectorizer lives in `src/NSharpLang.Compiler/Columnar/ColumnarIlEmitter.cs` and lowers four
// loop shapes to calls into `src/NSharpLang.Runtime/SimdReductions.cs`:
//
//   TryEmitVectorizedReduction{While,For}        -> SumInt32 / SumUInt32 / SumInt64 / SumUInt64
//   TryEmitVectorizedRangeCount{While,For}       -> CountInRangeInt32
//   TryEmitVectorizedMinMax{While,For}           -> MinInt32 / MaxInt32 / MinMaxInt32 (fused)
//   TryEmitVectorizedCountTransitions{While,For} -> CountTransitionsInt32
//
// The four `TryEmit...While` entries are the FIRST four statements of the emitter's `case 26` (While), and
// the four `TryEmit...For` entries sit immediately after the for-initializer emission in the For case. They
// are unconditional: no systems-profile gate, no project.yml switch, no environment variable stands in front
// of them, which is why this project needs no `language.systems` profile and gets the vectorizer from an
// ordinary `backend: il` library build. `OptOutFacts.tests.nl` pins the absence of the opt-out separately.
//
// WHAT THIS FILE DOES. Given a kernel's holder type and method name, it takes the kernel's own `MethodInfo`,
// reads its IL bytes, DECODES the instruction stream, and resolves the metadata token of every `call` /
// `callvirt` against the defining module — so `SimdCalls` answers which `SimdReductions` helpers the emitted
// method actually calls, in call order, and `OpcodeCount` answers how many times a given opcode appears.
// That is the same question `tests/PerfEvidence/ILShapeInspector.cs` answered before commit a50cb4000
// deleted it, asked of the shipping product build rather than of an emit-only test entry.
//
// WHY A REAL DECODE AND NOT A BYTE SCAN. `call` is 0x28, but 0x28 also occurs inside operand bytes — as part
// of a token, a branch offset, or an `ldc.i4` operand. Scanning for the byte would report calls that do not
// exist and miss ones that do. The walk below reads each instruction's operand SIZE from its `OperandType`
// and steps by exactly that many bytes, so every byte it treats as an opcode is one. `IlShapeFacts.tests.nl`
// pins that on a method carrying a `switch` jump table and an eight-byte `ldc.i8` operand, the two encodings
// a naive stepper gets wrong.
//
// WHERE THE OPERAND SIZES COME FROM. The opcode -> `OperandType` map is REFLECTED out of the public static
// fields of `System.Reflection.Emit.OpCodes`, so it is the runtime's own table rather than a transcription
// that could drift. Only the `OperandType` -> byte-count step is written out here (`OperandSize`), and it is
// the fixed encoding of ECMA-335 SS III.1.2: none, one, two, four, eight, or the `switch` form's 4 + 4 * n.
//
// FOUR COLUMNAR DECLINES SHAPED THIS FILE, AND EACH WORKAROUND IS NARROW.
//   1 `System.Reflection.MethodBody` is not an admitted local or parameter type (NL103
//     emit.local.unsupported-type / emit.declaration.method-param), so `GetMethodBody` and
//     `GetILAsByteArray` are reached through `MethodInfo.Invoke` and their results kept in `object?` locals.
//   2 A cast from `object` to an ARRAY type declines, so the IL bytes are read one at a time through
//     `Array.GetValue(int)` rather than cast to `byte[]`.
//   3 Unboxing `object` to the `OpCode` struct declines, so `get_Value` and `get_OperandType` are invoked ON
//     the boxed value and their answers come back through `Convert.ToInt32`.
//   4 `Module.ResolveMethod` has no binding plan either, so it is invoked the same way; the two-argument
//     `GetMethod(name, Type[])` overload is required because the one-argument form throws on its overload
//     set. Boxing stores into an `object?[]` go through `SetArgument`, because the columnar backend declines
//     the same store written inline (emit.statement.block-child).
// The `must` operator carries the non-null narrowing these reflection results need.
class IlShape {

    // The `SimdReductions` helpers `holder.methodName` calls, comma-separated in CALL ORDER, or "" when it
    // calls none. Not de-duplicated: two calls to the same helper are two entries, so a contract can pin how
    // many scans a kernel makes as well as which.
    static func SimdCalls(holder: Type, methodName: string): string {
        return CallsInto(holder, methodName, "SimdReductions")
    }

    // The same, for any declaring type's simple name. "" means the method calls nothing declared on it.
    static func CallsInto(holder: Type, methodName: string, declaringTypeName: string): string {
        il := MethodIl(holder, methodName)
        operandKinds := OperandKindTable()
        moduleValue := holder.get_Module()
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
                called := ResolvedCallName(moduleValue, resolve, ReadInt32(il, position), declaringTypeName)
                if called != "" {
                    if names == "" {
                        names = called
                    } else {
                        names = names + "," + called
                    }
                }
            }

            position = position + OperandSize(kind, il, position)
        }

        return names
    }

    // How many `call` and `callvirt` instructions resolve to a real method — the deleted `CountCall`.
    static func CallCount(holder: Type, methodName: string): int {
        il := MethodIl(holder, methodName)
        operandKinds := OperandKindTable()
        count := 0
        position := 0
        while position < il.Length {
            opcode := il[position]
            position = position + 1
            kind := -1
            if opcode == 254 {
                kind = operandKinds[256 + il[position]]
                position = position + 1
            } else {
                kind = operandKinds[opcode]
                if opcode == 40 || opcode == 111 {
                    count = count + 1
                }
            }

            if kind < 0 {
                return -1
            }

            position = position + OperandSize(kind, il, position)
        }

        return count
    }

    // How many times a one-byte opcode appears as an INSTRUCTION — the deleted `CountOpcode`. Returns -1 if
    // the stream did not decode, so a miscount can never be read as an absence.
    static func OpcodeCount(holder: Type, methodName: string, opcode: int): int {
        il := MethodIl(holder, methodName)
        operandKinds := OperandKindTable()
        count := 0
        position := 0
        while position < il.Length {
            current := il[position]
            position = position + 1
            kind := -1
            if current == 254 {
                kind = operandKinds[256 + il[position]]
                position = position + 1
            } else {
                kind = operandKinds[current]
                if current == opcode {
                    count = count + 1
                }
            }

            if kind < 0 {
                return -1
            }

            position = position + OperandSize(kind, il, position)
        }

        return count
    }

    // Whether the decode consumed the body EXACTLY and ended on `ret` (0x2A). This is the walk's own
    // soundness check: a stepper that mis-sized any operand would run off the end of the stream, land inside
    // an operand, or stop somewhere other than the method's final instruction. Every kernel this project
    // measures is asserted to satisfy it, so no contract rests on a desynchronised decode.
    static func DecodesToRet(holder: Type, methodName: string): bool {
        il := MethodIl(holder, methodName)
        operandKinds := OperandKindTable()
        last := -1
        position := 0
        while position < il.Length {
            current := il[position]
            position = position + 1
            kind := -1
            if current == 254 {
                if position >= il.Length {
                    return false
                }

                kind = operandKinds[256 + il[position]]
                position = position + 1
            } else {
                kind = operandKinds[current]
            }

            if kind < 0 {
                return false
            }

            position = position + OperandSize(kind, il, position)
            last = current
        }

        return position == il.Length && last == 42
    }

    // The IL of `holder.methodName`, one byte per `int`.
    static func MethodIl(holder: Type, methodName: string): int[] {
        method := must holder.GetMethod(methodName)
        receiver: object? = method
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

    // Slot `b` holds the `OperandType` of the one-byte opcode `b`; slot `256 + b` holds the `OperandType` of
    // the two-byte opcode `0xFE b`. `-1` means the runtime defines no such opcode.
    static func OperandKindTable(): int[] {
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
                // `OpCode.Value` is a `short`, so a two-byte opcode such as 0xFE01 arrives negative; masking
                // to 16 bits recovers the encoded form.
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

    // ECMA-335 SS III.1.2 operand widths, by `System.Reflection.Emit.OperandType`.
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

    // The simple name of the method a call token names, when it is declared on `declaringTypeName`; "" for a
    // call anywhere else, and for a token that names a constructor rather than a method.
    static func ResolvedCallName(moduleValue: Module, resolve: MethodInfo, token: int, declaringTypeName: string): string {
        arguments := new object?[](1)
        SetArgument(arguments, 0, token)
        receiver: object? = moduleValue
        resolved := resolve.Invoke(receiver, arguments) as MethodInfo
        if resolved == null {
            return ""
        }

        declaring := resolved.get_DeclaringType()
        if declaring == null || declaring.Name != declaringTypeName {
            return ""
        }

        return resolved.get_Name()
    }

    static func InvokeNoArguments(owner: Type, name: string, receiver: object?): object? {
        method := must owner.GetMethod(name, NoTypes())
        return method.Invoke(receiver, NoArguments())
    }

    static func NoTypes(): Type[] {
        return new Type[](0)
    }

    static func Int32Types(): Type[] {
        types := new Type[](1)
        types[0] = typeof(int)
        return types
    }

    static func NoArguments(): object?[] {
        return new object?[](0)
    }

    // A boxing store into an `object?[]`, kept as its own function because the columnar backend declines the
    // same store written inline (emit.statement.block-child).
    static func SetArgument(target: object?[], index: int, value: object?) {
        target[index] = value
    }
}

// The opcode and `OperandType` numbers the contracts assert on, named so that no assertion carries a bare
// magic number. The element-load opcodes are the ones a scalar loop keeps and a vectorized loop does not:
// the deleted tests read exactly these (`CountOpcode(method, OpCodes.Ldelem_I4)` and friends) to say that
// the scalar element-load loop had been folded into the helper call.
class IlEncoding {
    static func LdcI8(): int {
        return 33
    }

    static func LdelemI4(): int {
        return 148
    }

    static func LdelemU4(): int {
        return 149
    }

    static func LdelemI8(): int {
        return 150
    }

    static func LdelemR4(): int {
        return 152
    }

    static func LdelemR8(): int {
        return 153
    }

    static func InlineNone(): int {
        return 5
    }

    static func InlineBrTarget(): int {
        return 0
    }

    static func InlineVar(): int {
        return 14
    }

    static func ShortInlineI(): int {
        return 15
    }

    static func InlineI8(): int {
        return 7
    }

    static func InlineSwitch(): int {
        return 11
    }
}
