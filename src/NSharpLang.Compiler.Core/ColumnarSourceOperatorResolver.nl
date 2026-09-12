namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Source operator selection is a semantic decision. The retained C# assembly owner may emit the
// selected MethodInfo, but it must not reconstruct operator names, source owners, overload
// identity, or exact dynamic type shapes.
enum ColumnarSourceOperatorStatus {
    NotSourceType,
    Rejected,
    Selected
}

class ColumnarSourceOperatorSelection {
    Status: ColumnarSourceOperatorStatus
    SourceDefinition: ColumnarStructDef?
    OperatorDefinition: ColumnarStaticMethodDef?
    Method: MethodInfo?
    DeclaringType: Type
    ParameterTypes: Type[]
    ReturnType: Type

    IsSourceType: bool => Status != ColumnarSourceOperatorStatus.NotSourceType
    IsSelected: bool => Status == ColumnarSourceOperatorStatus.Selected

    constructor(status: ColumnarSourceOperatorStatus, sourceDefinition: ColumnarStructDef?, operatorDefinition: ColumnarStaticMethodDef?, method: MethodInfo?, declaringType: Type, parameterTypes: Type[], returnType: Type) {
        if declaringType == null || parameterTypes == null || returnType == null {
            throw new InvalidOperationException("Source operator selection facts cannot be null.")
        }
        if status == ColumnarSourceOperatorStatus.Selected {
            if sourceDefinition == null || operatorDefinition == null || method == null {
                throw new InvalidOperationException("A selected source operator requires exact declaration facts.")
            }
        } else if sourceDefinition != null || operatorDefinition != null || method != null || parameterTypes.Length != 0 {
            throw new InvalidOperationException("An unselected source operator cannot carry executable facts.")
        }

        Status = status
        SourceDefinition = sourceDefinition
        OperatorDefinition = operatorDefinition
        Method = method
        DeclaringType = declaringType
        ParameterTypes = parameterTypes
        ReturnType = returnType
    }
}

// The owner's DECLARATION plus the exact type the operand named it through. For a non-generic owner
// those are the same handle; for `Tagged<int>` the declaration is the open Tagged definition and the exact
// type is the constructed instantiation, which is what the parameter substitution and the
// `TypeBuilder.GetMethod` rebinding both need.
class ColumnarSourceOperatorCandidate {
    Owner: ColumnarStructDef
    OwnerType: Type
    Closed: bool
    Definition: ColumnarStaticMethodDef

    constructor(owner: ColumnarStructDef, ownerType: Type, closed: bool, definition: ColumnarStaticMethodDef) {
        if ownerType == null {
            throw new InvalidOperationException("Source operator candidate owner type cannot be null.")
        }
        Owner = owner
        OwnerType = ownerType
        Closed = closed
        Definition = definition
    }
}

class ColumnarSourceOperatorResolver {
    static func ResolveUnary(symbol: string, operandType: Type, sourceDefinitions: IEnumerable<ColumnarStructDef>): ColumnarSourceOperatorSelection {
        ValidateInputs(symbol, operandType, operandType, sourceDefinitions)
        owner: ColumnarStructDef? = null
        ownerClosed := false
        if !TryFindExactOwner(operandType, sourceDefinitions, out owner, out ownerClosed) || owner == null {
            return Unselected(ColumnarSourceOperatorStatus.NotSourceType)
        }

        methodName := UnaryMethodName(symbol)
        if methodName == null {
            return Unselected(ColumnarSourceOperatorStatus.Rejected)
        }
        operandTypes := new Type[](1)
        operandTypes[0] = operandType
        candidates := new List<ColumnarSourceOperatorCandidate>()
        AppendExactCandidates(owner, operandType, ownerClosed, methodName, operandTypes, candidates)
        return Select(candidates, operandTypes)
    }

    static func ResolveBinary(symbol: string, leftType: Type, rightType: Type, sourceDefinitions: IEnumerable<ColumnarStructDef>): ColumnarSourceOperatorSelection {
        ValidateInputs(symbol, leftType, rightType, sourceDefinitions)
        leftOwner: ColumnarStructDef? = null
        rightOwner: ColumnarStructDef? = null
        leftClosed := false
        rightClosed := false
        hasLeftOwner := TryFindExactOwner(leftType, sourceDefinitions, out leftOwner, out leftClosed)
        hasRightOwner := TryFindExactOwner(rightType, sourceDefinitions, out rightOwner, out rightClosed)
        if !hasLeftOwner && !hasRightOwner {
            return Unselected(ColumnarSourceOperatorStatus.NotSourceType)
        }

        methodName := BinaryMethodName(symbol)
        if methodName == null {
            return Unselected(ColumnarSourceOperatorStatus.Rejected)
        }
        operandTypes := new Type[](2)
        operandTypes[0] = leftType
        operandTypes[1] = rightType
        candidates := new List<ColumnarSourceOperatorCandidate>()
        if leftOwner != null {
            AppendExactCandidates(leftOwner, leftType, leftClosed, methodName, operandTypes, candidates)
        }
        // One DECLARATION is one candidate set. Two operands that closed the same open type over
        // different arguments (`Tagged<int>` and `Tagged<string>`) still share that declaration, and
        // asking it twice would make its single operator look ambiguous; the substituted parameter
        // check below is what rejects the cross-instantiation pair, exactly as it rejects any other
        // operand type the declared operator does not take.
        if rightOwner != null && !ColumnarConstructionPlanner.SameObject(rightOwner, leftOwner) {
            AppendExactCandidates(rightOwner, rightType, rightClosed, methodName, operandTypes, candidates)
        }
        return Select(candidates, operandTypes)
    }

    static func Select(candidates: List<ColumnarSourceOperatorCandidate>, operandTypes: Type[]): ColumnarSourceOperatorSelection {
        if candidates.Count != 1 {
            return Unselected(ColumnarSourceOperatorStatus.Rejected)
        }

        candidate := candidates[0]
        definition := candidate.Definition
        parameterTypes := SubstitutedParameterTypes(definition, candidate.OwnerType, candidate.Closed, operandTypes.Length)
        method: MethodInfo = definition.Builder
        declaringType: Type = candidate.Owner.Builder
        returnType := definition.ReturnType
        if candidate.Closed {
            rebound := TypeBuilder.GetMethod(candidate.OwnerType, definition.Builder)
            if rebound == null {
                throw new InvalidOperationException("TypeBuilder.GetMethod returned no exact closed source operator.")
            }
            method = rebound
            declaringType = candidate.OwnerType
            returnType = ColumnarSourceDirectCallResolver.SubstituteTypeArguments(definition.ReturnType, candidate.OwnerType.GetGenericArguments())
        }
        return new ColumnarSourceOperatorSelection(ColumnarSourceOperatorStatus.Selected, candidate.Owner, definition, method, declaringType, parameterTypes, returnType)
    }

    static func AppendExactCandidates(owner: ColumnarStructDef, ownerType: Type, closed: bool, methodName: string, operandTypes: Type[], candidates: List<ColumnarSourceOperatorCandidate>) {
        overloads := new List<ColumnarStaticMethodDef>()
        if !owner.StaticMethods.TryGetValue(methodName, out overloads) {
            return
        }
        if overloads == null {
            throw new InvalidOperationException("Source operator overload facts cannot be null.")
        }

        for candidate in overloads {
            ValidateOperatorFact(owner, methodName, candidate)
            if !IsExactCallableOperator(candidate, ownerType, closed, operandTypes) {
                continue
            }

            duplicate := false
            index := 0
            while index < candidates.Count {
                if ColumnarConstructionPlanner.SameObject(candidates[index].Definition, candidate) {
                    duplicate = true
                    break
                }
                index += 1
            }
            if !duplicate {
                candidates.Add(new ColumnarSourceOperatorCandidate(owner, ownerType, closed, candidate))
            }
        }
    }

    // A declared operator parameter reached through a CONSTRUCTED owner is the declared type with the
    // owner's type arguments substituted in: `operator ==(left: Tagged<T>, right: Tagged<T>)` on
    // `Tagged<int>` takes two `Tagged<int>`. An open owner substitutes nothing.
    static func SubstitutedParameterTypes(definition: ColumnarStaticMethodDef, ownerType: Type, closed: bool, count: int): Type[] {
        parameterTypes := new Type[](count)
        arguments := closed ? ownerType.GetGenericArguments() : new Type[](0)
        index := 0
        while index < count {
            parameterTypes[index] = closed ? ColumnarSourceDirectCallResolver.SubstituteTypeArguments(definition.ParamTypes[index], arguments) : definition.ParamTypes[index]
            index += 1
        }
        return parameterTypes
    }

    static func IsExactCallableOperator(definition: ColumnarStaticMethodDef, ownerType: Type, closed: bool, operandTypes: Type[]): bool {
        method: MethodInfo = definition.Builder
        if !method.get_IsPublic() {
            return false
        }
        if !method.get_IsStatic() {
            return false
        }
        if !method.get_IsSpecialName() {
            return false
        }
        if method.get_IsAbstract() {
            return false
        }
        if method.get_IsGenericMethod() {
            return false
        }
        if IsVarArgs(method) {
            return false
        }
        if definition.ParamTypes.Length != operandTypes.Length {
            return false
        }
        if definition.ParamModifierKinds.Length != operandTypes.Length {
            return false
        }
        if definition.ReturnType.get_IsByRef() {
            return false
        }
        if definition.ReturnType.FullName == "System.Void" {
            return false
        }

        parameterTypes := SubstitutedParameterTypes(definition, ownerType, closed, operandTypes.Length)
        index := 0
        while index < operandTypes.Length {
            if definition.ParamModifierKinds[index] != 0 {
                return false
            }
            if parameterTypes[index].get_IsByRef() {
                return false
            }
            if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(parameterTypes[index], operandTypes[index]) {
                return false
            }
            index += 1
        }
        return true
    }

    static func ValidateOperatorFact(owner: ColumnarStructDef, methodName: string, definition: ColumnarStaticMethodDef) {
        if owner == null || owner.Builder == null || owner.StaticMethods == null || definition == null || definition.Builder == null || definition.ParamTypes == null || definition.ParamModifierKinds == null || definition.ReturnType == null {
            throw new InvalidOperationException("Source operator declaration facts cannot be null.")
        }

        parameterIndex := 0
        while parameterIndex < definition.ParamTypes.Length {
            if definition.ParamTypes[parameterIndex] == null {
                throw new InvalidOperationException("Source operator parameter facts cannot contain null values.")
            }
            parameterIndex += 1
        }
        modifierIndex := 0
        while modifierIndex < definition.ParamModifierKinds.Length {
            modifier := definition.ParamModifierKinds[modifierIndex]
            if modifier < 0 || modifier > 4 {
                throw new InvalidOperationException("Source operator modifier facts are invalid.")
            }
            modifierIndex += 1
        }

        method: MethodInfo = definition.Builder
        ownerType: Type = owner.Builder
        if !method.get_IsStatic() || method.get_Name() != methodName || !ColumnarConstructionPlanner.SameObject(method.get_DeclaringType(), ownerType) || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(method.get_ReturnType(), definition.ReturnType) {
            throw new InvalidOperationException("Source operator facts do not identify an exact static declaration.")
        }
    }

    // An operand is an operator owner when it is a source type: the OPEN `TypeBuilder` itself, or a
    // CONSTRUCTED instantiation of one, whose declaration is the open definition it closes over.
    static func TryFindExactOwner(operandType: Type, sourceDefinitions: IEnumerable<ColumnarStructDef>, out owner: ColumnarStructDef?, out closed: bool): bool {
        owner = null
        closed = false
        if operandType == null {
            return false
        }

        declarationType := operandType
        isClosed := ColumnarTypeOfPlanner.IsClosedSourceGeneric(operandType)
        if isClosed {
            declarationType = operandType.GetGenericTypeDefinition()
        } else if !(operandType is TypeBuilder) {
            return false
        }

        for candidate in sourceDefinitions {
            if candidate == null || candidate.Builder == null {
                throw new InvalidOperationException("Source operator type definitions cannot be null.")
            }
            if !ColumnarConstructionPlanner.SameObject(candidate.Builder, declarationType) {
                continue
            }
            if owner != null && !ColumnarConstructionPlanner.SameObject(owner, candidate) {
                throw new InvalidOperationException("One exact operator operand type cannot map to two definitions.")
            }
            owner = candidate
        }
        closed = owner != null && isClosed
        return owner != null
    }

    static func UnaryMethodName(symbol: string): string? {
        if symbol == "+" {
            return "op_UnaryPlus"
        }
        if symbol == "-" {
            return "op_UnaryNegation"
        }
        if symbol == "!" {
            return "op_LogicalNot"
        }
        if symbol == "~" {
            return "op_OnesComplement"
        }
        return null
    }

    static func BinaryMethodName(symbol: string): string? {
        if symbol == "+" {
            return "op_Addition"
        }
        if symbol == "-" {
            return "op_Subtraction"
        }
        if symbol == "*" {
            return "op_Multiply"
        }
        if symbol == "/" {
            return "op_Division"
        }
        if symbol == "%" {
            return "op_Modulus"
        }
        if symbol == "==" {
            return "op_Equality"
        }
        if symbol == "!=" {
            return "op_Inequality"
        }
        if symbol == "<" {
            return "op_LessThan"
        }
        if symbol == "<=" {
            return "op_LessThanOrEqual"
        }
        if symbol == ">" {
            return "op_GreaterThan"
        }
        if symbol == ">=" {
            return "op_GreaterThanOrEqual"
        }
        if symbol == "&" {
            return "op_BitwiseAnd"
        }
        if symbol == "|" {
            return "op_BitwiseOr"
        }
        if symbol == "^" {
            return "op_ExclusiveOr"
        }
        if symbol == "<<" {
            return "op_LeftShift"
        }
        if symbol == ">>" {
            return "op_RightShift"
        }
        return null
    }

    static func IsVarArgs(method: MethodInfo): bool {
        callingConvention := (int)method.get_CallingConvention()
        return (callingConvention & ColumnarCodePlanReflectionContract.VarArgsCallingConventionFlag()) != 0
    }

    static func ValidateInputs(symbol: string, leftType: Type, rightType: Type, sourceDefinitions: IEnumerable<ColumnarStructDef>) {
        if symbol == null || leftType == null || rightType == null || sourceDefinitions == null {
            throw new InvalidOperationException("Source operator resolution inputs cannot be null.")
        }
    }

    static func Unselected(status: ColumnarSourceOperatorStatus): ColumnarSourceOperatorSelection {
        if status == ColumnarSourceOperatorStatus.Selected {
            throw new InvalidOperationException("A selected source operator requires declaration facts.")
        }
        return new ColumnarSourceOperatorSelection(status, null, null, null, typeof(object), new Type[](0), typeof(object))
    }
}
