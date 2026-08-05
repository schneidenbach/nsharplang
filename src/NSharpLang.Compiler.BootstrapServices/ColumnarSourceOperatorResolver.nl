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

class ColumnarSourceOperatorCandidate {
    Owner: ColumnarStructDef
    Definition: ColumnarStaticMethodDef

    constructor(owner: ColumnarStructDef, definition: ColumnarStaticMethodDef) {
        Owner = owner
        Definition = definition
    }
}

class ColumnarSourceOperatorResolver {
    static func ResolveUnary(symbol: string, operandType: Type, sourceDefinitions: IEnumerable<ColumnarStructDef>): ColumnarSourceOperatorSelection {
        ValidateInputs(symbol, operandType, operandType, sourceDefinitions)
        owner: ColumnarStructDef? = null
        if !TryFindExactOwner(operandType, sourceDefinitions, out owner) || owner == null {
            return Unselected(ColumnarSourceOperatorStatus.NotSourceType)
        }

        methodName := UnaryMethodName(symbol)
        if methodName == null {
            return Unselected(ColumnarSourceOperatorStatus.Rejected)
        }
        operandTypes := new Type[](1)
        operandTypes[0] = operandType
        candidates := new List<ColumnarSourceOperatorCandidate>()
        AppendExactCandidates(owner, methodName, operandTypes, candidates)
        return Select(candidates, operandTypes)
    }

    static func ResolveBinary(symbol: string, leftType: Type, rightType: Type, sourceDefinitions: IEnumerable<ColumnarStructDef>): ColumnarSourceOperatorSelection {
        ValidateInputs(symbol, leftType, rightType, sourceDefinitions)
        leftOwner: ColumnarStructDef? = null
        rightOwner: ColumnarStructDef? = null
        hasLeftOwner := TryFindExactOwner(leftType, sourceDefinitions, out leftOwner)
        hasRightOwner := TryFindExactOwner(rightType, sourceDefinitions, out rightOwner)
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
            AppendExactCandidates(leftOwner, methodName, operandTypes, candidates)
        }
        if rightOwner != null && !ColumnarConstructionPlanner.SameObject(rightOwner, leftOwner) {
            AppendExactCandidates(rightOwner, methodName, operandTypes, candidates)
        }
        return Select(candidates, operandTypes)
    }

    static func Select(candidates: List<ColumnarSourceOperatorCandidate>, operandTypes: Type[]): ColumnarSourceOperatorSelection {
        if candidates.Count != 1 {
            return Unselected(ColumnarSourceOperatorStatus.Rejected)
        }

        candidate := candidates[0]
        definition := candidate.Definition
        parameterTypes := new Type[](operandTypes.Length)
        index := 0
        while index < operandTypes.Length {
            parameterTypes[index] = definition.ParamTypes[index]
            index += 1
        }
        method: MethodInfo = definition.Builder
        declaringType: Type = candidate.Owner.Builder
        return new ColumnarSourceOperatorSelection(ColumnarSourceOperatorStatus.Selected, candidate.Owner, definition, method, declaringType, parameterTypes, definition.ReturnType)
    }

    static func AppendExactCandidates(owner: ColumnarStructDef, methodName: string, operandTypes: Type[], candidates: List<ColumnarSourceOperatorCandidate>) {
        overloads := new List<ColumnarStaticMethodDef>()
        if !owner.StaticMethods.TryGetValue(methodName, out overloads) {
            return
        }
        if overloads == null {
            throw new InvalidOperationException("Source operator overload facts cannot be null.")
        }

        for candidate in overloads {
            ValidateOperatorFact(owner, methodName, candidate)
            if !IsExactCallableOperator(candidate, operandTypes) {
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
                candidates.Add(new ColumnarSourceOperatorCandidate(owner, candidate))
            }
        }
    }

    static func IsExactCallableOperator(definition: ColumnarStaticMethodDef, operandTypes: Type[]): bool {
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

        index := 0
        while index < operandTypes.Length {
            if definition.ParamModifierKinds[index] != 0 {
                return false
            }
            if definition.ParamTypes[index].get_IsByRef() {
                return false
            }
            if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(definition.ParamTypes[index], operandTypes[index]) {
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

    static func TryFindExactOwner(operandType: Type, sourceDefinitions: IEnumerable<ColumnarStructDef>, out owner: ColumnarStructDef?): bool {
        owner = null
        if !(operandType is TypeBuilder) {
            return false
        }
        for candidate in sourceDefinitions {
            if candidate == null || candidate.Builder == null {
                throw new InvalidOperationException("Source operator type definitions cannot be null.")
            }
            if !ColumnarConstructionPlanner.SameObject(candidate.Builder, operandType) {
                continue
            }
            if owner != null && !ColumnarConstructionPlanner.SameObject(owner, candidate) {
                throw new InvalidOperationException("One exact operator operand type cannot map to two definitions.")
            }
            owner = candidate
        }
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
