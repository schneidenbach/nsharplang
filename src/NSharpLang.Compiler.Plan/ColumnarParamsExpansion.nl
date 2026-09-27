namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit


// A `params` TAIL IS A CALL-SITE SHAPE, NOT A CALLEE FEATURE, and this owner is the whole of it.
//
// `void LogDebug(this ILogger logger, string? message, params object?[] args)` declares THREE
// parameters and is called with ONE argument. The callee sees no difference between that call and
// `LogDebug(logger, message, new object[0])`: C# packs the trailing arguments into a fresh array at
// the CALL SITE and hands the array over as the last ordinary argument. Nothing about the method
// body, its metadata or its dispatch changes, which is why one owner can answer for every door —
// an external extension method, an external constructor, or any other selection that reaches here.
//
// THE NORMAL FORM COMES FIRST AND IS NOT THIS OWNER'S. When a call supplies exactly one argument
// for the params slot and that argument already IS an array of the declared type
// (`LogDebug(message, values)` over an `object[] values`), C# passes it straight through without
// allocating, and so does every resolver here: the candidate scores at its declared arity through
// the ordinary path and never reaches the expanded tier. The expanded tier is asked only when no
// candidate bound in normal form, which is exactly C#'s "applicable in its normal form beats
// applicable in its expanded form" (ECMA-334 §12.6.4.2) written as an ordering of tiers.
class ColumnarParamsExpansion {

    // THE ELEMENT TYPE OF A `params` TAIL, or null when the signature has none. Three facts must all
    // hold: the last parameter carries `[ParamArray]`, its type is a single-dimension zero-based
    // array, and its element type is something a call site can write a value of. A by-ref or pointer
    // element has no such value, and an array of arrays is an ordinary element — `params string[][]`
    // packs `string[]` values and is admitted like any other.
    static func ElementTypeOrNull(parameters: ParameterInfo[], parameterTypes: Type[]): Type? {
        if parameters == null || parameterTypes == null || parameters.Length != parameterTypes.Length || parameters.Length == 0 {
            return null
        }

        last := parameters.Length - 1
        if parameters[last] == null || !ColumnarExtensionMethodResolver.IsParamsParameter(parameters[last]) {
            return null
        }

        arrayType := parameterTypes[last]
        if arrayType == null || !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(arrayType) {
            return null
        }

        elementType := arrayType.GetElementType()
        if elementType == null || elementType.IsByRef || elementType.IsPointer || elementType.ContainsGenericParameters {
            return null
        }

        return elementType
    }

    // How many of the supplied arguments land in the declared FIXED slots. `argumentSlotOffset` is
    // where the arguments start in the declared list: 1 for an extension method, whose slot 0 is the
    // receiver, and 0 for a constructor or an ordinary static call. A negative answer means the call
    // supplied fewer arguments than the signature has fixed parameters, which no expansion can fix.
    static func FixedArgumentCount(parameterTypes: Type[], argumentSlotOffset: int): int {
        return parameterTypes.Length - 1 - argumentSlotOffset
    }

    // THE PER-ARGUMENT PARAMETER TYPES OF THE EXPANDED CALL, which is the one thing every caller
    // needs and the only shape the shared argument scorer understands: a list exactly as long as the
    // supplied arguments, carrying each fixed parameter's own type and then the element type once per
    // packed argument. Scoring the expanded form is then the SAME question as scoring any other call,
    // asked of the same owner, so an expanded candidate and an ordinary one can never disagree about
    // what converts.
    static func ExpandedParameterTypesOrNull(parameters: ParameterInfo[], parameterTypes: Type[], argumentSlotOffset: int, argumentCount: int): Type[]? {
        if argumentSlotOffset < 0 || argumentCount < 0 {
            return null
        }

        elementType := ElementTypeOrNull(parameters, parameterTypes)
        if elementType == null {
            return null
        }

        fixedCount := FixedArgumentCount(parameterTypes, argumentSlotOffset)
        if fixedCount < 0 || argumentCount < fixedCount {
            return null
        }

        expanded := new Type[](argumentCount)
        index := 0
        while index < argumentCount {
            if index < fixedCount {
                expanded[index] = parameterTypes[argumentSlotOffset + index]
            } else {
                expanded[index] = elementType
            }

            index = index + 1
        }

        return expanded
    }

    // THE ARRAY, WRITTEN INTO A PLAN. `newarr` leaves the fresh array on the stack and each element
    // is stored through a `dup` of it, so the array is still there for the call after the last
    // `stelem` — the same sequence a C# compiler writes, and the reason no temporary local is needed.
    // `stelem` carries the element TYPE rather than one of the specialised `stelem.*` opcodes: it is
    // exact for a reference element and for a value one alike, which is what a `params T[]` over an
    // instantiation's own argument needs.
    static func AppendArrayHeader(plan: ColumnarCodePlan, elementTypeIndex: int, elementCount: int) {
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), plan.AddInt32(elementCount))
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Newarr(), elementTypeIndex)
    }

    static func AppendElementPrologue(plan: ColumnarCodePlan, elementIndex: int) {
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), plan.AddInt32(elementIndex))
    }

    static func AppendElementEpilogue(plan: ColumnarCodePlan, elementTypeIndex: int) {
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Stelem(), elementTypeIndex)
    }

    // The same three writes, straight into an `ILGenerator` for the call sites that build no plan.
    // One rule, two writers — exactly as the optional-default fill is spelled.
    static func EmitArrayHeader(il: ILGenerator, elementType: Type, elementCount: int) {
        il.Emit(OpCodes.Ldc_I4, elementCount)
        il.Emit(OpCodes.Newarr, elementType)
    }

    static func EmitElementPrologue(il: ILGenerator, elementIndex: int) {
        il.Emit(OpCodes.Dup)
        il.Emit(OpCodes.Ldc_I4, elementIndex)
    }

    static func EmitElementEpilogue(il: ILGenerator, elementType: Type) {
        il.Emit(OpCodes.Stelem, elementType)
    }
}
