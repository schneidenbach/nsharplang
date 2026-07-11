namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// Target-typed null and Nullable<T> construction are argument-lowering concerns, not overload
// selection side effects. This helper keeps those rules pure until a selected parameter type is
// known, then appends one callback-free schema-v3 sequence to the caller's open fragment.
class ColumnarNullableArgumentLowering {
    static func CanAdoptNull(targetType: Type): bool {
        ValidateType(targetType, "targetType")
        element := typeof(int)
        return (!targetType.get_IsValueType() && !targetType.get_IsGenericParameter()) || TryGetSupportedNullableElement(targetType, out element)
    }

    static func CanLiftValue(actualType: Type, targetType: Type): bool {
        ValidateType(actualType, "actualType")
        ValidateType(targetType, "targetType")

        element := typeof(int)
        if !TryGetSupportedNullableElement(targetType, out element) {
            return false
        }

        if ExactTypeShapeMatches(actualType, targetType) || ExactTypeShapeMatches(actualType, element) {
            return true
        }

        return CanAppendNumericConversion(actualType, element)
    }

    static func TryGetSupportedNullableElement(targetType: Type, out elementType: Type): bool {
        ValidateType(targetType, "targetType")
        elementType = typeof(int)
        nullableDefinition := RequiredNullableDefinition()
        if !targetType.get_IsGenericType() || targetType.get_IsGenericTypeDefinition() || targetType.GetGenericTypeDefinition() != nullableDefinition {
            return false
        }

        arguments := targetType.GetGenericArguments()
        if arguments.Length != 1 || !IsLiftableNullableElement(arguments[0]) {
            return false
        }

        elementType = arguments[0]
        return true
    }

    // Emits either ldnull for a reference target or the exact default(T?) sequence
    // ldloca/initobj/ldloc. The helper owns the argument fragment so its semantic result type
    // refines the verifier's raw null category before a call consumes it.
    static func TryAppendNullArgument(plan: ColumnarCodePlan, parentFragment: int, fragmentKind: int, sourceNode: int, targetType: Type): bool {
        ValidatePlan(plan)
        ValidateType(targetType, "targetType")
        if fragmentKind < 0 || sourceNode < 0 {
            throw new ArgumentOutOfRangeException("fragmentKind")
        }

        if !CanAdoptNull(targetType) {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            fragment := plan.BeginFragment(parentFragment, fragmentKind, sourceNode)
            nullableElement := typeof(int)
            if TryGetSupportedNullableElement(targetType, out nullableElement) {
                targetTypeIndex := plan.AddType(targetType)
                defaultLocal := plan.DeclarePlanLocal(targetTypeIndex)
                plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), defaultLocal)

                plan.AppendTypeInstruction(ColumnarCodePlanContract.Initobj(), targetTypeIndex)

                plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), defaultLocal)
            } else {
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
            }

            plan.CompleteFragment(fragment, targetType)
            return true
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    // The caller has already appended one value of actualType. Identity T? passes through;
    // T and the admitted implicit numeric T -> U flows construct Nullable<U>(U).
    static func TryAppendValueLift(plan: ColumnarCodePlan, actualType: Type, targetType: Type): bool {
        ValidatePlan(plan)
        ValidateType(actualType, "actualType")
        ValidateType(targetType, "targetType")

        element := typeof(int)
        if !TryGetSupportedNullableElement(targetType, out element) {
            return false
        }

        if ExactTypeShapeMatches(actualType, targetType) {
            return true
        }

        conversionMethod: MethodInfo? = null
        conversionSource := actualType
        requiresConversion := !ExactTypeShapeMatches(actualType, element)
        if requiresConversion && !TryGetNumericConversion(actualType, element, out conversionSource, out conversionMethod) {
            return false
        }

        constructorParameters := new Type[](1)
        constructorParameters[0] = element
        constructorInfo := targetType.GetConstructor(constructorParameters)
        if constructorInfo == null {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            if requiresConversion {
                AppendNumericConversion(plan, actualType, element, conversionSource, conversionMethod)
            }

            constructorIndex := plan.AddConstructorWithSignature(constructorInfo, targetType, constructorParameters)

            plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)

            return true
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    static func CanAppendNumericConversion(actualType: Type, targetType: Type): bool {
        conversionSource := actualType
        conversionMethod: MethodInfo? = null
        return TryGetNumericConversion(actualType, targetType, out conversionSource, out conversionMethod)
    }

    static func TryGetNumericConversion(actualType: Type, targetType: Type, out conversionSource: Type, out conversionMethod: MethodInfo?): bool {
        conversionSource = actualType
        conversionMethod = null

        if targetType == typeof(int) {
            return ColumnarNumericFacts.IsIntPromotable(actualType) && actualType != typeof(int)
        }

        if targetType == typeof(long) {
            return ColumnarNumericFacts.IsIntPromotable(actualType)
        }

        if targetType == typeof(float) {
            return ColumnarNumericFacts.IsIntPromotable(actualType) || actualType == typeof(long)
        }

        if targetType == typeof(double) {
            return ColumnarNumericFacts.IsIntPromotable(actualType) || actualType == typeof(long) || actualType == typeof(float)
        }

        if targetType != typeof(decimal) || (!ColumnarNumericFacts.IsIntPromotable(actualType) && actualType != typeof(long)) {
            return false
        }

        if actualType == typeof(byte) || actualType == typeof(sbyte) || actualType == typeof(short) || actualType == typeof(ushort) || actualType == typeof(char) {
            conversionSource = typeof(int)
        }

        parameters := new Type[](1)
        parameters[0] = conversionSource
        candidate := typeof(decimal).GetMethod("op_Implicit", parameters)
        if candidate == null || !candidate.get_IsStatic() || candidate.get_IsGenericMethod() || candidate.get_ReturnType() != typeof(decimal) {
            return false
        }

        conversionMethod = candidate
        return true
    }

    static func AppendNumericConversion(plan: ColumnarCodePlan, actualType: Type, targetType: Type, conversionSource: Type, conversionMethod: MethodInfo?) {
        if targetType == typeof(int) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
            return
        }

        if targetType == typeof(long) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI8())
            return
        }

        if targetType == typeof(float) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvR4())
            return
        }

        if targetType == typeof(double) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvR8())
            return
        }

        if conversionSource != actualType {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
        }

        if conversionMethod == null {
            throw new InvalidOperationException("A nullable decimal conversion requires its exact runtime method.")
        }

        parameters := new Type[](1)
        parameters[0] = conversionSource
        methodIndex := plan.AddMethodWithSignature(conversionMethod, typeof(decimal), parameters, typeof(decimal), true, false)

        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
    }

    static func IsLiftableNullableElement(valueType: Type): bool {
        return valueType == typeof(int) || valueType == typeof(long) || valueType == typeof(ulong) || valueType == typeof(uint) || valueType == typeof(short) || valueType == typeof(ushort) || valueType == typeof(byte) || valueType == typeof(sbyte) || valueType == typeof(bool) || valueType == typeof(char) || valueType == typeof(double) || valueType == typeof(float) || valueType == typeof(decimal) || valueType == typeof(TimeSpan) || ColumnarRuntimeInstanceMemberResolver.IsSupportedValueTupleReceiver(valueType)
    }

    static func ExactTypeShapeMatches(left: Type, right: Type): bool {
        if left == right {
            return true
        }

        if left.get_IsSZArray() || right.get_IsSZArray() {
            if !left.get_IsSZArray() || !right.get_IsSZArray() {
                return false
            }

            leftElement := left.GetElementType()
            rightElement := right.GetElementType()
            return leftElement != null && rightElement != null && ExactTypeShapeMatches(leftElement, rightElement)
        }

        if !left.get_IsGenericType() || !right.get_IsGenericType() || left.get_IsGenericTypeDefinition() || right.get_IsGenericTypeDefinition() || left.GetGenericTypeDefinition() != right.GetGenericTypeDefinition() {
            return false
        }

        leftArguments := left.GetGenericArguments()
        rightArguments := right.GetGenericArguments()
        if leftArguments.Length != rightArguments.Length {
            return false
        }

        i := 0
        while i < leftArguments.Length {
            if !ExactTypeShapeMatches(leftArguments[i], rightArguments[i]) {
                return false
            }

            i += 1
        }

        return true
    }

    static func RequiredNullableDefinition(): Type {
        result := Type.GetType("System.Nullable`1")
        if result == null {
            throw new InvalidOperationException("System.Nullable<T> runtime type was not found.")
        }

        return result
    }

    static func ValidatePlan(plan: ColumnarCodePlan) {
        if plan == null {
            throw new ArgumentNullException("plan")
        }

        if plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() || plan.Status != ColumnarFragmentPlanStatus.NotOwned || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Nullable argument lowering requires a building schema-v3 plan.")
        }
    }

    static func ValidateType(valueType: Type, name: string) {
        if valueType == null {
            throw new ArgumentNullException(name)
        }
    }
}
