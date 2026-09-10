namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// USER-DEFINED OPERATORS DECLARED BY AN EXTERNAL TYPE, selected by ordinary CLR member resolution.
//
// This is the runtime twin of `ColumnarSourceOperatorResolver`: that owner reads the `op_*` a SOURCE
// declaration is emitting, this one reads the `op_*` a referenced assembly already carries. Nothing
// here names a type, an assembly or an operator surface -- `System.Numerics.Vector<T>`'s `+`, `&` and
// `~` are ordinary instances of the same lookup that serves `System.DateTime`'s `-`,
// `System.TimeSpan`'s `+` and any third-party numeric type, and the resolver cannot tell them apart.
//
// THE CANDIDATE SET IS C#'s (ECMA-334 §12.4.5). For each operand type, the first type in its own
// inheritance chain that declares ANY public static `op_` of the requested name supplies the whole
// candidate set for that operand; a further base class does not add to it. The two operands' sets are
// unioned, deduplicated by declaring type, and then ranked by the SAME argument-flow scorer every
// other call selection uses, with the better-conversion-target tie-break behind it -- so a user-defined
// operator can never disagree with an ordinary call about which conversion is preferred.
//
// TWO UNIVERSES, as everywhere else in the emitter. An operand whose type is fully runtime-closed
// reads its already-substituted operators directly. An operand that is BUILDER-BOUND (a runtime
// generic closed over an N#-declared type argument) cannot: its members are only reachable through
// the open definition, so candidates are read there, their signatures are substituted with the closed
// arguments, and the winner is rebound with `TypeBuilder.GetMethod`.
enum ColumnarRuntimeOperatorStatus {
    NotOperatorType,
    Rejected,
    Selected
}

class ColumnarRuntimeOperatorSelection {
    Status: ColumnarRuntimeOperatorStatus
    Method: MethodInfo?
    DeclaringType: Type
    ParameterTypes: Type[]
    ReturnType: Type

    HasCandidates: bool => Status != ColumnarRuntimeOperatorStatus.NotOperatorType
    IsSelected: bool => Status == ColumnarRuntimeOperatorStatus.Selected

    constructor(status: ColumnarRuntimeOperatorStatus, method: MethodInfo?, declaringType: Type, parameterTypes: Type[], returnType: Type) {
        if declaringType == null || parameterTypes == null || returnType == null {
            throw new InvalidOperationException("Runtime operator selection facts cannot be null.")
        }
        if status == ColumnarRuntimeOperatorStatus.Selected {
            if method == null {
                throw new InvalidOperationException("A selected runtime operator requires an exact method handle.")
            }
        } else if method != null || parameterTypes.Length != 0 {
            throw new InvalidOperationException("An unselected runtime operator cannot carry executable facts.")
        }

        Status = status
        Method = method
        DeclaringType = declaringType
        ParameterTypes = parameterTypes
        ReturnType = returnType
    }
}

class ColumnarRuntimeOperatorResolver {
    static func ResolveUnary(symbol: string, operandType: Type): ColumnarRuntimeOperatorSelection {
        ValidateInputs(symbol, operandType, operandType)
        methodName := ColumnarSourceOperatorResolver.UnaryMethodName(symbol)
        if methodName == null {
            return Unselected(ColumnarRuntimeOperatorStatus.NotOperatorType)
        }

        operandTypes := new Type[](1)
        operandTypes[0] = operandType
        candidates := new List<MethodInfo>()
        candidateParameters := new List<Type[]>()
        candidateReturnTypes := new List<Type>()
        AppendOperandCandidates(operandType, methodName, 1, candidates, candidateParameters, candidateReturnTypes)
        return Select(candidates, candidateParameters, candidateReturnTypes, operandTypes)
    }

    static func ResolveBinary(symbol: string, leftType: Type, rightType: Type): ColumnarRuntimeOperatorSelection {
        ValidateInputs(symbol, leftType, rightType)
        methodName := ColumnarSourceOperatorResolver.BinaryMethodName(symbol)
        if methodName == null {
            return Unselected(ColumnarRuntimeOperatorStatus.NotOperatorType)
        }

        operandTypes := new Type[](2)
        operandTypes[0] = leftType
        operandTypes[1] = rightType
        candidates := new List<MethodInfo>()
        candidateParameters := new List<Type[]>()
        candidateReturnTypes := new List<Type>()
        AppendOperandCandidates(leftType, methodName, 2, candidates, candidateParameters, candidateReturnTypes)
        AppendOperandCandidates(rightType, methodName, 2, candidates, candidateParameters, candidateReturnTypes)
        return Select(candidates, candidateParameters, candidateReturnTypes, operandTypes)
    }

    // One operand's contribution: the first type in its inheritance chain that declares any candidate
    // of this name and arity supplies them all. A type that declares none contributes nothing, which is
    // not a failure -- the other operand may still supply the whole set.
    static func AppendOperandCandidates(operandType: Type, methodName: string, arity: int, candidates: List<MethodInfo>, candidateParameters: List<Type[]>, candidateReturnTypes: List<Type>) {
        current := OperatorLookupStart(operandType)
        while current != null {
            before := candidates.Count
            AppendDeclaredCandidates(current, methodName, arity, candidates, candidateParameters, candidateReturnTypes)
            if candidates.Count != before {
                return
            }

            // A value type's operator set is its own; only a class hierarchy is walked.
            if current.get_IsValueType() {
                return
            }
            current = BaseTypeOrNull(current)
        }
    }

    // The type whose declarations are read for the operand. A pointer, by-ref or open generic operand
    // has no operator surface at all.
    static func OperatorLookupStart(operandType: Type): Type? {
        if operandType == null || operandType.get_IsByRef() || operandType.get_IsPointer() || operandType.get_IsGenericParameter() || operandType.get_IsGenericTypeDefinition() || operandType.get_IsArray() {
            return null
        }
        return operandType
    }

    static func BaseTypeOrNull(current: Type): Type? {
        try {
            return current.get_BaseType()
        } catch ex: NotSupportedException {
            return null
        } catch ex: NotImplementedException {
            return null
        }
    }

    static func AppendDeclaredCandidates(lookupType: Type, methodName: string, arity: int, candidates: List<MethodInfo>, candidateParameters: List<Type[]>, candidateReturnTypes: List<Type>) {
        closedArguments := new Type[](0)
        candidateOwner := lookupType
        if ColumnarRuntimeInstanceMemberResolver.ContainsBuilderBoundType(lookupType) {
            if !lookupType.get_IsGenericType() || lookupType.get_IsGenericTypeDefinition() {
                return
            }
            definition := lookupType.GetGenericTypeDefinition()
            // A source-headed instantiation is the source operator resolver's business.
            if definition is TypeBuilder {
                return
            }
            candidateOwner = definition
            closedArguments = lookupType.GetGenericArguments()
        }

        declared := DeclaredMethodsOrEmpty(candidateOwner)
        index := 0
        while index < declared.Length {
            candidate := declared[index]
            if IsCallableOperator(candidate, candidateOwner, methodName, arity) {
                parameterTypes := SubstitutedParameterTypes(candidate, closedArguments)
                returnType := SubstitutedType(candidate.get_ReturnType(), closedArguments)
                if parameterTypes != null && !HasUnsupportedOperatorSignature(parameterTypes, returnType) {
                    bound := BindOperator(candidate, lookupType, closedArguments)
                    if bound != null && !ContainsSameOperator(candidates, bound) {
                        candidates.Add(bound)
                        candidateParameters.Add(parameterTypes)
                        candidateReturnTypes.Add(returnType)
                    }
                }
            }

            index = index + 1
        }
    }

    static func DeclaredMethodsOrEmpty(lookupType: Type): MethodInfo[] {
        try {
            methods := lookupType.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.DeclaredOnly)
            if methods == null {
                return new MethodInfo[](0)
            }
            return methods
        } catch ex: NotSupportedException {
            return new MethodInfo[](0)
        } catch ex: NotImplementedException {
            return new MethodInfo[](0)
        }
    }

    static func IsCallableOperator(candidate: MethodInfo, candidateOwner: Type, methodName: string, arity: int): bool {
        if candidate == null || !candidate.get_IsPublic() || !candidate.get_IsStatic() || !candidate.get_IsSpecialName() {
            return false
        }
        if candidate.get_Name() != methodName || candidate.get_IsGenericMethod() || candidate.get_IsGenericMethodDefinition() {
            return false
        }
        if ColumnarSourceOperatorResolver.IsVarArgs(candidate) {
            return false
        }
        declaringType := candidate.get_DeclaringType()
        if declaringType == null || !ColumnarConstructionPlanner.SameObject(declaringType, candidateOwner) {
            return false
        }
        parameters := candidate.GetParameters()
        if parameters == null || parameters.Length != arity {
            return false
        }
        index := 0
        while index < parameters.Length {
            parameter := parameters[index]
            if parameter == null || ColumnarExtensionMethodResolver.IsParamsParameter(parameter) || parameter.get_ParameterType() == null {
                return false
            }
            index = index + 1
        }
        return true
    }

    static func SubstitutedParameterTypes(candidate: MethodInfo, closedArguments: Type[]): Type[]? {
        parameters := candidate.GetParameters()
        result := new Type[](parameters.Length)
        index := 0
        while index < parameters.Length {
            parameterType := parameters[index].get_ParameterType()
            if parameterType == null {
                return null
            }
            result[index] = SubstitutedType(parameterType, closedArguments)
            index = index + 1
        }
        return result
    }

    static func SubstitutedType(signatureType: Type, closedArguments: Type[]): Type {
        if closedArguments.Length == 0 {
            return signatureType
        }
        return ColumnarConstructionPlanner.SubstituteTypeArgument(signatureType, closedArguments)
    }

    static func HasUnsupportedOperatorSignature(parameterTypes: Type[], returnType: Type): bool {
        if returnType == null || returnType.FullName == "System.Void" || returnType.get_IsByRef() || returnType.get_IsPointer() {
            return true
        }
        index := 0
        while index < parameterTypes.Length {
            parameterType := parameterTypes[index]
            if parameterType == null || parameterType.get_IsPointer() || ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedSignatureType(parameterType) {
                return true
            }
            index = index + 1
        }
        return false
    }

    // The handle the emitter will actually call: the declaration itself for a runtime-closed owner, or
    // its rebinding onto the builder-bound instantiation.
    static func BindOperator(candidate: MethodInfo, lookupType: Type, closedArguments: Type[]): MethodInfo? {
        if closedArguments.Length == 0 {
            return candidate
        }
        return TypeBuilder.GetMethod(lookupType, candidate)
    }

    static func ContainsSameOperator(candidates: List<MethodInfo>, candidate: MethodInfo): bool {
        for existing in candidates {
            if ColumnarConstructionPlanner.SameObject(existing, candidate) {
                return true
            }
        }
        return false
    }

    static func Select(candidates: List<MethodInfo>, candidateParameters: List<Type[]>, candidateReturnTypes: List<Type>, operandTypes: Type[]): ColumnarRuntimeOperatorSelection {
        if candidates.Count == 0 {
            return Unselected(ColumnarRuntimeOperatorStatus.NotOperatorType)
        }

        facts := ColumnarDirectCallArgumentFacts.Empty(operandTypes.Length)
        selectedIndex := ColumnarConstructionPlanner.BestSourceConstructorIndex(candidateParameters, operandTypes, facts)
        if selectedIndex < 0 {
            return Unselected(ColumnarRuntimeOperatorStatus.Rejected)
        }

        selected := candidates[selectedIndex]
        declaringType := selected.get_DeclaringType()
        if declaringType == null {
            return Unselected(ColumnarRuntimeOperatorStatus.Rejected)
        }

        return new ColumnarRuntimeOperatorSelection(
            ColumnarRuntimeOperatorStatus.Selected,
            selected,
            declaringType,
            candidateParameters[selectedIndex],
            candidateReturnTypes[selectedIndex]
        )
    }

    // THE PREDEFINED SURFACE KEEPS ITS OPERATORS. C# only reaches a user-defined operator when the
    // operand types are not both served by a predefined one, and the CLR agrees: the integral, floating
    // and boolean primitives declare their `op_*` as EXPLICIT interface implementations (private), so a
    // public lookup finds nothing for them anyway. Naming the surface here keeps `1 + 2` on `add`
    // whatever a future runtime chooses to make public, and keeps `string` equality and concatenation on
    // the emitter's own arms. `decimal`, `DateTime`, `TimeSpan`, `Vector<T>` and every other type whose
    // arithmetic IS its `op_*` are deliberately NOT on this list.
    static func IsIlPrimitiveOperandType(operandType: Type): bool {
        if operandType == null {
            return false
        }
        // Asked through the guarded owner: a raw `get_IsEnum` routes through `IsSubclassOf`, and an
        // operand that is a constructed EMITTED generic (`Tagged<int>` mid-emit, a
        // `TypeBuilderInstantiation`) answers that with NotSupportedException rather than `false`.
        if ColumnarTypeOfPlanner.IsEnumType(operandType) {
            return true
        }
        return ColumnarNumericFacts.IsIntPromotable(operandType) || operandType == typeof(long) || operandType == typeof(ulong) || operandType == typeof(uint) || operandType == typeof(double) || operandType == typeof(float) || operandType == typeof(bool) || operandType == typeof(string)
    }

    static func ValidateInputs(symbol: string, leftType: Type, rightType: Type) {
        if symbol == null || leftType == null || rightType == null {
            throw new InvalidOperationException("Runtime operator resolution inputs cannot be null.")
        }
    }

    static func Unselected(status: ColumnarRuntimeOperatorStatus): ColumnarRuntimeOperatorSelection {
        if status == ColumnarRuntimeOperatorStatus.Selected {
            throw new InvalidOperationException("A selected runtime operator requires declaration facts.")
        }
        return new ColumnarRuntimeOperatorSelection(status, null, typeof(object), new Type[](0), typeof(object))
    }
}
