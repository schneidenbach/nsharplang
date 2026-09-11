namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection


// The analyzer admits user-defined implicit conversion compatibility only from members declared
// on the actual source type. The legacy emitter additionally probes the target type, but that path
// cannot be reached by an analyzer-accepted program. This resolver deliberately owns the smaller
// intersection: one exact, public, static, non-generic op_Implicit whose sole parameter is the
// actual source type and whose return is the exact target type.
enum ColumnarSourceImplicitConversionStatus {
    NotSourceType,
    NoConversion,
    Ambiguous,
    Selected
}

class ColumnarSourceImplicitConversionSelection {
    Status: ColumnarSourceImplicitConversionStatus
    SourceDefinition: ColumnarStructDef?
    OperatorDefinition: ColumnarStaticMethodDef?
    SourceType: Type
    TargetType: Type
    DeclaringType: Type
    Method: MethodInfo?
    ParameterTypes: Type[]

    IsSelected: bool => Status == ColumnarSourceImplicitConversionStatus.Selected
    IsAmbiguous: bool => Status == ColumnarSourceImplicitConversionStatus.Ambiguous

    constructor(status: ColumnarSourceImplicitConversionStatus, sourceDefinition: ColumnarStructDef?, operatorDefinition: ColumnarStaticMethodDef?, sourceType: Type, targetType: Type, declaringType: Type, method: MethodInfo?, parameterTypes: Type[]) {
        if sourceType == null || targetType == null || declaringType == null || parameterTypes == null {
            throw new InvalidOperationException("Source implicit-conversion selection facts cannot be null.")
        }

        if status == ColumnarSourceImplicitConversionStatus.Selected {
            if sourceDefinition == null || operatorDefinition == null || method == null || parameterTypes.Length != 1 {
                throw new InvalidOperationException("A selected source implicit conversion requires one exact operator signature.")
            }
        } else if operatorDefinition != null || method != null || parameterTypes.Length != 0 {
            throw new InvalidOperationException("An unselected source implicit conversion cannot carry executable facts.")
        }

        Status = status
        SourceDefinition = sourceDefinition
        OperatorDefinition = operatorDefinition
        SourceType = sourceType
        TargetType = targetType
        DeclaringType = declaringType
        Method = method
        ParameterTypes = parameterTypes
    }
}

class ColumnarSourceImplicitConversionResolver {

    // This is the analyzer's ordinary assignability tier: below exact (8) and implicit numeric
    // (6), and tied with reference/boxing compatibility (4).
    static func CompatibilityScore(): int {
        return 4
    }

    static func ResolveExact(sourceType: Type, targetType: Type, sourceDefinitions: IEnumerable<ColumnarStructDef>): ColumnarSourceImplicitConversionSelection {
        ValidateInputs(sourceType, targetType, sourceDefinitions)

        sourceDefinition: ColumnarStructDef? = null
        for candidate in sourceDefinitions {
            if candidate == null || candidate.Builder == null {
                throw new InvalidOperationException("Source implicit-conversion type definitions cannot be null.")
            }

            candidateType: Type = candidate.Builder
            if candidateType == sourceType {
                if sourceDefinition != null && sourceDefinition != candidate {
                    throw new InvalidOperationException("One exact implicit-conversion source type cannot map to two definitions.")
                }

                sourceDefinition = candidate
            }
        }

        if sourceDefinition == null {
            return Unselected(ColumnarSourceImplicitConversionStatus.NotSourceType, null, sourceType, targetType)
        }

        ValidateSourceDefinition(sourceDefinition, sourceType)

        overloads := new List<ColumnarStaticMethodDef>()
        if !sourceDefinition.StaticMethods.TryGetValue("op_Implicit", out overloads) {
            return Unselected(ColumnarSourceImplicitConversionStatus.NoConversion, sourceDefinition, sourceType, targetType)
        }

        if overloads == null {
            throw new InvalidOperationException("Source implicit-conversion overload facts cannot be null.")
        }

        selected: ColumnarStaticMethodDef? = null
        selectedMethods := new List<MethodInfo>()
        index := 0
        while index < overloads.Count {
            candidate := overloads[index]
            ValidateOperatorFact(sourceDefinition, candidate)
            if IsExactCallableOperator(candidate, sourceType, targetType) {
                candidateMethod: MethodInfo = candidate.Builder
                seenMethod := false
                methodIndex := 0
                while methodIndex < selectedMethods.Count {
                    if Object.ReferenceEquals(selectedMethods[methodIndex], candidateMethod) {
                        seenMethod = true
                    }

                    methodIndex += 1
                }

                if !seenMethod {
                    selectedMethods.Add(candidateMethod)
                    if selected == null {
                        selected = candidate
                    }
                }
            }

            index += 1
        }

        if selectedMethods.Count == 0 || selected == null {
            return Unselected(ColumnarSourceImplicitConversionStatus.NoConversion, sourceDefinition, sourceType, targetType)
        }

        if selectedMethods.Count != 1 {
            return Unselected(ColumnarSourceImplicitConversionStatus.Ambiguous, sourceDefinition, sourceType, targetType)
        }

        parameters := new Type[](1)
        parameters[0] = sourceType
        method: MethodInfo = selected.Builder
        declaringType: Type = sourceDefinition.Builder
        return new ColumnarSourceImplicitConversionSelection(ColumnarSourceImplicitConversionStatus.Selected, sourceDefinition, selected, sourceType, targetType, declaringType, method, parameters)
    }

    // A single ranking API keeps call selection from assigning a different score to the same
    // conversion later at the emit site. Built-in flows remain authoritative; only an otherwise
    // incompatible pair probes the exact source operator.
    static func TryClassifyArgument(expectedType: Type, actualType: Type, sourceDefinitions: IEnumerable<ColumnarStructDef>, out score: int, out conversion: ColumnarSourceImplicitConversionSelection): bool {
        ValidateInputs(actualType, expectedType, sourceDefinitions)

        flow := ColumnarDirectCallArgumentFlow.None
        if ColumnarSourceDirectCallResolver.TryClassifyArgumentFlow(expectedType, actualType, out flow) {
            score = BuiltInFlowScore(flow)
            conversion = Unselected(ColumnarSourceImplicitConversionStatus.NoConversion, null, actualType, expectedType)

            return true
        }

        conversion = ResolveExact(actualType, expectedType, sourceDefinitions)
        if conversion.IsSelected {
            score = CompatibilityScore()
            return true
        }

        score = -1
        return false
    }

    // The argument value is already on the stack. Persist the exact MethodBuilder signature and
    // append only the conversion Call. The caller remains responsible for the subsequent target
    // call and for sealing/validating the complete plan.
    static func TryAppendCall(plan: ColumnarCodePlan, selection: ColumnarSourceImplicitConversionSelection): bool {
        if plan == null || selection == null {
            throw new InvalidOperationException("Source implicit-conversion append inputs cannot be null.")
        }

        if !selection.IsSelected {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            ValidateSelected(selection)
            method := selection.Method
            if method == null {
                throw new InvalidOperationException("A selected source implicit conversion has no method handle.")
            }

            methodIndex := plan.AddMethodWithSignature(method, selection.DeclaringType, selection.ParameterTypes, selection.TargetType, true, false)

            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
            return true
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    static func BuiltInFlowScore(flow: ColumnarDirectCallArgumentFlow): int {
        if flow == ColumnarDirectCallArgumentFlow.Identity {
            return 8
        }

        if flow == ColumnarDirectCallArgumentFlow.ImplicitNumeric {
            return 6
        }

        if flow == ColumnarDirectCallArgumentFlow.Reference || flow == ColumnarDirectCallArgumentFlow.Boxing {
            return 4
        }

        throw new InvalidOperationException("A classified direct-call argument flow must have a score.")
    }

    static func ValidateSelected(selection: ColumnarSourceImplicitConversionSelection) {
        sourceDefinition := selection.SourceDefinition
        operatorDefinition := selection.OperatorDefinition
        method := selection.Method
        if sourceDefinition == null || operatorDefinition == null || method == null {
            throw new InvalidOperationException("Selected source implicit-conversion facts are no longer exact.")
        }

        if selection.ParameterTypes.Length != 1 {
            throw new InvalidOperationException("Selected source implicit-conversion facts are no longer exact.")
        }

        if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(selection.ParameterTypes[0], selection.SourceType) {
            throw new InvalidOperationException("Selected source implicit-conversion facts are no longer exact.")
        }

        currentDeclaringType: Type = sourceDefinition.Builder
        if selection.DeclaringType != currentDeclaringType {
            throw new InvalidOperationException("Selected source implicit-conversion facts are no longer exact.")
        }

        currentMethod: MethodInfo = operatorDefinition.Builder
        if !Object.ReferenceEquals(method, currentMethod) {
            throw new InvalidOperationException("Selected source implicit-conversion facts are no longer exact.")
        }

        ValidateSourceDefinition(sourceDefinition, selection.SourceType)
        ValidateOperatorFact(sourceDefinition, operatorDefinition)
        if !IsExactCallableOperator(operatorDefinition, selection.SourceType, selection.TargetType) {
            throw new InvalidOperationException("Selected source implicit-conversion facts are no longer callable.")
        }
    }

    static func ValidateSourceDefinition(definition: ColumnarStructDef, sourceType: Type) {
        if definition.StaticMethods == null {
            throw new InvalidOperationException("Source implicit-conversion lookup requires the exact source definition.")
        }

        definitionType: Type = definition.Builder
        if definitionType != sourceType {
            throw new InvalidOperationException("Source implicit-conversion lookup requires the exact source definition.")
        }

        if sourceType.get_IsValueType() == definition.IsReference {
            throw new InvalidOperationException("Source implicit-conversion reference facts do not match the source type.")
        }
    }

    static func ValidateOperatorFact(owner: ColumnarStructDef, definition: ColumnarStaticMethodDef) {
        if definition == null || definition.Builder == null || definition.ParamTypes == null || definition.ParamModifierKinds == null || definition.ReturnType == null {
            throw new InvalidOperationException("Source implicit-conversion definition facts cannot be null.")
        }

        if definition.ParamModifierKinds.Length != 0 && definition.ParamModifierKinds.Length != definition.ParamTypes.Length {
            throw new InvalidOperationException("Source implicit-conversion modifier facts must match the parameter count.")
        }

        index := 0
        while index < definition.ParamTypes.Length {
            if definition.ParamTypes[index] == null {
                throw new InvalidOperationException("Source implicit-conversion parameter types cannot be null.")
            }

            if definition.ParamModifierKinds.Length != 0 {
                modifier := definition.ParamModifierKinds[index]
                if modifier < 0 || modifier > 4 {
                    throw new InvalidOperationException("Source implicit-conversion modifier facts are invalid.")
                }
            }

            index += 1
        }

        method: MethodInfo = definition.Builder
        ownerType: Type = owner.Builder
        if !method.get_IsStatic() || method.get_Name() != "op_Implicit" || method.get_DeclaringType() != ownerType || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(method.get_ReturnType(), definition.ReturnType) {
            throw new InvalidOperationException("Source implicit-conversion facts do not identify an exact static declaration.")
        }
    }

    // MethodBuilder cannot expose GetParameters until its owner is baked. The exact source
    // parameter facts are persisted into ColumnarCodePlan, whose executor revalidates the
    // inspectable signature when the reflection boundary permits it.

    static func IsExactCallableOperator(definition: ColumnarStaticMethodDef, sourceType: Type, targetType: Type): bool {
        method: MethodInfo = definition.Builder
        if sourceType.get_IsInterface() || sourceType.get_IsGenericTypeDefinition() || !method.get_IsPublic() || method.get_IsAbstract() || method.get_IsGenericMethod() || IsVarArgs(method) || definition.ParamTypes.Length != 1 || HasParameterModifiers(definition.ParamModifierKinds) || definition.ParamTypes[0].get_IsByRef() || definition.ReturnType.get_IsByRef() || definition.ParamTypes[0].get_IsGenericTypeDefinition() || definition.ReturnType.get_IsGenericTypeDefinition() || definition.ReturnType.FullName == "System.Void" {
            return false
        }

        return ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(definition.ParamTypes[0], sourceType) && ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(definition.ReturnType, targetType)
    }

    static func HasParameterModifiers(modifierKinds: int[]): bool {
        index := 0
        while index < modifierKinds.Length {
            if modifierKinds[index] != 0 {
                return true
            }

            index += 1
        }

        return false
    }

    static func IsVarArgs(method: MethodInfo): bool {
        callingConvention := (int)method.get_CallingConvention()
        return (callingConvention & ColumnarCodePlanReflectionContract.VarArgsCallingConventionFlag()) != 0
    }

    static func ValidateInputs(sourceType: Type, targetType: Type, sourceDefinitions: IEnumerable<ColumnarStructDef>) {
        if sourceType == null || targetType == null || sourceDefinitions == null {
            throw new InvalidOperationException("Source implicit-conversion lookup inputs cannot be null.")
        }
    }

    static func Unselected(status: ColumnarSourceImplicitConversionStatus, sourceDefinition: ColumnarStructDef?, sourceType: Type, targetType: Type): ColumnarSourceImplicitConversionSelection {
        declaringType: Type = typeof(object)
        if sourceDefinition != null {
            declaringType = sourceDefinition.Builder
        }

        return new ColumnarSourceImplicitConversionSelection(status, sourceDefinition, null, sourceType, targetType, declaringType, null, new Type[](0))
    }
}
