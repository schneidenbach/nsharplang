namespace NSharpLang.Compiler.Columnar

import System


// THE CONVERSION A CAST PERFORMS, AS CODE-PLAN ROWS.
//
// An ANNOTATED loop variable (`for m: Match in matches`) converts each element the way `(T)element`
// would, and the set of explicit conversions is the set of implicit ones plus four more
// (ECMA-334 §10.3). `ForeachElementConversionFacts` owns the QUESTION — whether a conversion exists
// at all, which is what NL330 reports — and this owner emits the rows for the ones that do, so a
// program the analyzer accepted is the program the machine runs:
//
//   * IDENTITY costs nothing.
//   * A REFERENCE WIDENING costs nothing — a derived reference already IS its base on the stack.
//   * A BOXING conversion (`int` read as `object`) is `box`.
//   * An UNBOXING conversion (`object` read as `int`) and a conversion to a TYPE PARAMETER are
//     `unbox.any`, which unwraps a boxed value and behaves exactly as `castclass` for a reference
//     instantiation — the only opcode that is correct for both, and why C# emits it there.
//   * A REFERENCE DOWNCAST is `castclass`, which raises `InvalidCastException` on an element that is
//     not what the annotation claimed. That is the behaviour the author asked for by writing it.
//   * A NUMERIC conversion is the `conv.*` its TARGET selects, unchecked, exactly as the cast owner
//     the ordinary expression path uses selects it.
//
// Anything else declines rather than guessing an opcode. This is the plan-row counterpart of
// `ColumnarIlEmitter`'s `TryEmitCastConversion`; that arm is the one this owner replaces as the
// remaining ILGenerator body paths move onto code plans.
class ColumnarCastConversionPlanner {

    // Whether a conversion from `sourceType` to `targetType` has rows this owner can append. Asked
    // before a receiver goes on the stack, so a decline never leaves a half-converted value.
    static func CanAppendCast(sourceType: Type, targetType: Type): bool {
        if sourceType == null || targetType == null || targetType.get_IsByRef() || targetType.get_IsPointer() || targetType.get_IsGenericTypeDefinition() {
            return false
        }
        if sourceType == targetType {
            return true
        }
        if targetType.get_IsGenericParameter() {
            return !sourceType.get_IsValueType()
        }
        if sourceType.get_IsGenericParameter() {
            return targetType == typeof(object)
        }
        if targetType.get_IsValueType() {
            if IsNumeric(sourceType) && IsNumeric(targetType) {
                return true
            }
            // An UNBOXING conversion is the reverse of a boxing one, so the source has to be a type
            // the boxed target actually IS — `object`, `ValueType`, or an interface it implements.
            // A `string` source is not, and refusing it here is what keeps `unbox.any` from being
            // emitted for a pair no conversion exists between.
            return !sourceType.get_IsValueType() && sourceType.IsAssignableFrom(targetType)
        }
        if sourceType.get_IsValueType() {
            // A value read at a reference type is a box; only `object` and an interface the value
            // implements can hold one, and the interface case is the boxing conversion too.
            return targetType == typeof(object) || targetType.get_IsInterface()
        }
        return true
    }

    // The rows themselves. `CanAppendCast` is the same decision, so a caller that asked first never
    // sees `false` here.
    static func TryAppendCast(plan: ColumnarCodePlan, sourceType: Type, targetType: Type, structuralTypeReferences: ColumnarStructuralTypeReferenceTable?): bool {
        if plan == null || !CanAppendCast(sourceType, targetType) {
            return false
        }
        if sourceType == targetType {
            return true
        }

        if targetType.get_IsGenericParameter() || (targetType.get_IsValueType() && !sourceType.get_IsValueType()) {
            plan.AppendTypeInstruction(ColumnarCodePlanContract.UnboxAny(), AddType(plan, targetType, structuralTypeReferences))
            return true
        }
        if sourceType.get_IsValueType() && !targetType.get_IsValueType() {
            plan.AppendTypeInstruction(ColumnarCodePlanContract.Box(), AddType(plan, sourceType, structuralTypeReferences))
            return true
        }
        if sourceType.get_IsValueType() && targetType.get_IsValueType() {
            return TryAppendNumericCast(plan, sourceType, targetType)
        }
        if targetType.IsAssignableFrom(sourceType) {
            // A widening reference conversion: the value on the stack already has the target type.
            return true
        }
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Castclass(), AddType(plan, targetType, structuralTypeReferences))
        return true
    }

    // The unchecked `conv.*` a numeric TARGET selects — the same target-driven table the ordinary
    // cast owner uses, so `(byte)n` truncates identically inside a generator and outside one.
    static func TryAppendNumericCast(plan: ColumnarCodePlan, sourceType: Type, targetType: Type): bool {
        if !IsNumeric(sourceType) || !IsNumeric(targetType) {
            return false
        }
        source := UnderlyingNumeric(sourceType)
        target := UnderlyingNumeric(targetType)
        if target == typeof(double) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvR8())
        } else if target == typeof(float) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvR4())
        } else if target == typeof(long) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI8())
        } else if target == typeof(ulong) {
            // N# is unchecked: an `int` sign-extends and a `uint` zero-extends.
            if source == typeof(uint) {
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvU8())
            } else {
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI8())
            }
        } else if target == typeof(char) || target == typeof(ushort) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvU2())
        } else if target == typeof(byte) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvU1())
        } else if target == typeof(sbyte) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI1())
        } else if target == typeof(short) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI2())
        } else if target == typeof(uint) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvU4())
        } else if target == typeof(int) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
        } else {
            return false
        }
        return true
    }

    // A built-in numeric type, or an enum over one: the enum conversions ARE the numeric conversions
    // over the underlying type, which is why they share this arm rather than getting their own.
    static func IsNumeric(candidate: Type): bool {
        return ColumnarNumericFacts.IsCastableScalar(UnderlyingNumeric(candidate)) && UnderlyingNumeric(candidate) != typeof(decimal)
    }

    static func UnderlyingNumeric(candidate: Type): Type {
        if candidate != null && candidate.get_IsEnum() {
            return candidate.GetEnumUnderlyingType()
        }
        return candidate
    }

    // A type operand, taken through the structural reference table when one is supplied so a machine's
    // own still-being-emitted handles resolve the way every other row's do.
    static func AddType(plan: ColumnarCodePlan, value: Type, structuralTypeReferences: ColumnarStructuralTypeReferenceTable?): int {
        if structuralTypeReferences == null {
            return plan.AddType(value)
        }
        return plan.AddType(structuralTypeReferences.SelectRuntimeType(value), structuralTypeReferences)
    }
}
