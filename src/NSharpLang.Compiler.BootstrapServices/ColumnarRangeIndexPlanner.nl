namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit

// Callback-free owner for System.Index/System.Range construction and Index/Range reads over
// strings and SZ arrays. Every accepted child is represented by its own schema-v3 fragment;
// failure rolls the complete candidate back to an empty, NotOwned plan.
public class ColumnarRangeIndexPlanner {
    // Production-facing seam: the mechanical host passes only its existing live fact collections.
    // N# gates syntax/type shape before allocating bindings or resolving any reflection handle.
    public static func TryEmitFromFacts(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        parameterOrdinals: Dictionary<string, int>,
        parameterTypes: Dictionary<string, Type>,
        locals: Dictionary<string, LocalBuilder>,
        enums: Dictionary<string, ColumnarEnumDef>,
        liftedNames: IEnumerable<string>,
        boxedNames: IEnumerable<string>?,
        enclosingNames: IEnumerable<string>,
        siblingNames: IEnumerable<string>,
        visibleLocalFunctionNames: IEnumerable<string>,
        plan: ColumnarCodePlan,
        il: ILGenerator,
        out resultType: Type): bool {
        ValidateFacadeRootInputs(nodes, source, node, plan)
        resultType = typeof(int)
        if !FacadeRootMayBeOwned(nodes, source, node, parameterTypes, locals) {
            plan.PrepareV3()
            return false
        }

        bindings := BindFromRawFacts(
            parameterOrdinals,
            parameterTypes,
            locals,
            enums,
            liftedNames,
            boxedNames,
            enclosingNames,
            siblingNames,
            visibleLocalFunctionNames)
        handles := ColumnarRangeIndexHandles.Resolve()
        return TryEmit(nodes, source, node, bindings, handles, plan, il, out resultType)
    }

    public static func TryGetTypeFromFacts(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        parameterOrdinals: Dictionary<string, int>,
        parameterTypes: Dictionary<string, Type>,
        locals: Dictionary<string, LocalBuilder>,
        enums: Dictionary<string, ColumnarEnumDef>,
        liftedNames: IEnumerable<string>,
        boxedNames: IEnumerable<string>?,
        enclosingNames: IEnumerable<string>,
        siblingNames: IEnumerable<string>,
        visibleLocalFunctionNames: IEnumerable<string>,
        plan: ColumnarCodePlan,
        out resultType: Type): bool {
        ValidateFacadeRootInputs(nodes, source, node, plan)
        resultType = typeof(int)
        if !FacadeRootMayBeOwned(nodes, source, node, parameterTypes, locals) {
            plan.PrepareV3()
            return false
        }

        bindings := BindFromRawFacts(
            parameterOrdinals,
            parameterTypes,
            locals,
            enums,
            liftedNames,
            boxedNames,
            enclosingNames,
            siblingNames,
            visibleLocalFunctionNames)
        handles := ColumnarRangeIndexHandles.Resolve()
        return TryGetType(nodes, source, node, bindings, handles, plan, out resultType)
    }

    public static func TryEmit(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        il: ILGenerator,
        out resultType: Type): bool {
        if Plan(nodes, source, node, bindings, handles, plan)
            != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
        return true
    }

    public static func TryGetType(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        out resultType: Type): bool {
        if Plan(nodes, source, node, bindings, handles, plan)
            != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        resultType = RequiredResultType(plan)
        return true
    }

    public static func Plan(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        if nodes == null || source == null || bindings == null || handles == null || plan == null {
            throw new InvalidOperationException("Range/index planning inputs cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Range/index planning received an invalid root node index.")
        }

        plan.PrepareV3()
        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 || !IsRootCandidate(nodes, source, candidate) {
            return plan.Status
        }

        checkpoint := plan.CreateCheckpoint()
        resultType := typeof(int)
        if !TryPlanValue(nodes, source, candidate, bindings, handles, plan, -1, 0, out resultType)
            || !RootResultMatches(nodes, source, candidate, resultType) {
            plan.Rollback(checkpoint)
            return plan.Status
        }

        plan.CompleteV3(resultType)
        return plan.Status
    }

    static func ValidateFacadeRootInputs(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        plan: ColumnarCodePlan) {
        if nodes == null || source == null || plan == null {
            throw new InvalidOperationException("Range/index raw planning inputs cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Range/index raw planning received an invalid root node index.")
        }
    }

    static func BindFromRawFacts(
        parameterOrdinals: Dictionary<string, int>,
        parameterTypes: Dictionary<string, Type>,
        locals: Dictionary<string, LocalBuilder>,
        enums: Dictionary<string, ColumnarEnumDef>,
        liftedNames: IEnumerable<string>,
        boxedNames: IEnumerable<string>?,
        enclosingNames: IEnumerable<string>,
        siblingNames: IEnumerable<string>,
        visibleLocalFunctionNames: IEnumerable<string>): ColumnarFragmentBindings {
        normalizedBoxedNames: IEnumerable<string> = new string[](0)
        if boxedNames != null {
            normalizedBoxedNames = boxedNames
        }
        return new ColumnarFragmentBindings(
            parameterOrdinals,
            parameterTypes,
            locals,
            enums,
            liftedNames,
            normalizedBoxedNames,
            enclosingNames,
            siblingNames,
            visibleLocalFunctionNames)
    }

    static func FacadeRootMayBeOwned(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        parameterTypes: Dictionary<string, Type>,
        locals: Dictionary<string, LocalBuilder>): bool {
        node = UnwrapParentheses(nodes, node)
        if node < 0 || node >= nodes.Kinds.Length {
            return false
        }
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.RangeExpression() {
            return true
        }
        if kind == ColumnarExpressionNodeKind.UnaryExpression() {
            return nodes.ChildCount(node) == 1 && nodes.Text(source, node) == "^"
        }
        if kind != ColumnarExpressionNodeKind.IndexAccessExpression()
            || nodes.ChildCount(node) != 2 {
            return false
        }
        return FacadeSelectorMayProduceIndexOrRange(
            nodes,
            source,
            nodes.Child(node, 1),
            parameterTypes,
            locals,
            0)
    }

    static func FacadeSelectorMayProduceIndexOrRange(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        parameterTypes: Dictionary<string, Type>,
        locals: Dictionary<string, LocalBuilder>,
        depth: int): bool {
        if depth > 200 {
            return false
        }
        node = UnwrapParentheses(nodes, node)
        if node < 0 || node >= nodes.Kinds.Length {
            return false
        }
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.RangeExpression() {
            return true
        }
        if kind == ColumnarExpressionNodeKind.UnaryExpression() {
            return nodes.ChildCount(node) == 1 && nodes.Text(source, node) == "^"
        }
        if kind == ColumnarExpressionNodeKind.IdentifierExpression() {
            if nodes.ChildCount(node) != 0 {
                return false
            }
            name := nodes.Text(source, node)
            if locals != null && locals.ContainsKey(name) {
                local := locals[name]
                if local == null {
                    return true
                }
                localType := local.get_LocalType()
                return localType == typeof(Index) || localType == typeof(Range)
            }
            if parameterTypes != null && parameterTypes.ContainsKey(name) {
                parameterType := parameterTypes[name]
                return parameterType == null
                    || parameterType == typeof(Index)
                    || parameterType == typeof(Range)
            }
            return false
        }
        if kind == ColumnarExpressionNodeKind.TernaryExpression()
            && nodes.ChildCount(node) == 3 {
            return FacadeSelectorMayProduceIndexOrRange(
                    nodes, source, nodes.Child(node, 1), parameterTypes, locals, depth + 1)
                && FacadeSelectorMayProduceIndexOrRange(
                    nodes, source, nodes.Child(node, 2), parameterTypes, locals, depth + 1)
        }
        return false
    }

    static func IsRootCandidate(nodes: ColumnarNodeTable, source: string, node: int): bool {
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.RangeExpression()
            || kind == ColumnarExpressionNodeKind.IndexAccessExpression() {
            return true
        }
        return kind == ColumnarExpressionNodeKind.UnaryExpression()
            && nodes.ChildCount(node) == 1
            && nodes.Text(source, node) == "^"
    }

    static func RootResultMatches(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        resultType: Type): bool {
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.UnaryExpression()
            && nodes.Text(source, node) == "^" {
            return resultType == typeof(Index)
        }
        if kind == ColumnarExpressionNodeKind.RangeExpression() {
            return resultType == typeof(Range)
        }
        return kind == ColumnarExpressionNodeKind.IndexAccessExpression()
    }

    static func TryPlanValue(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        parentFragment: int,
        depth: int,
        out resultType: Type): bool {
        resultType = typeof(int)
        if depth > 200 {
            return false
        }

        node = UnwrapParentheses(nodes, node)
        if node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        kind := nodes.Kind(node)
        fragment := plan.BeginFragment(parentFragment, kind, node)
        planned := false

        if kind == ColumnarExpressionNodeKind.IntLiteralExpression()
            || kind == ColumnarExpressionNodeKind.CharLiteralExpression()
            || kind == ColumnarExpressionNodeKind.StringLiteralExpression() {
            planned = ColumnarScalarLiteralPlanner.TryAppendLiteral(
                nodes, source, node, plan, out resultType)
        } else if kind == ColumnarExpressionNodeKind.NameOfExpression() {
            planned = ColumnarNameOfPlanner.TryAppendNameOf(
                nodes, source, node, plan, out resultType)
        } else if kind == ColumnarExpressionNodeKind.BoolLiteralExpression() {
            planned = TryPlanBooleanLiteral(nodes, source, node, plan, out resultType)
        } else if kind == ColumnarExpressionNodeKind.IdentifierExpression() {
            planned = TryPlanIdentifier(nodes, source, node, bindings, plan, out resultType)
        } else if kind == ColumnarExpressionNodeKind.MemberAccessExpression() {
            planned = TryPlanEnumMember(nodes, source, node, bindings, plan, out resultType)
        } else if kind == ColumnarExpressionNodeKind.UnaryExpression() {
            planned = ColumnarUnaryLiteralPlanner.TryAppendUnaryLiteral(
                nodes, source, node, plan, fragment, out resultType)
            if !planned {
                planned = TryPlanFromEnd(
                    nodes, source, node, bindings, handles,
                    plan, fragment, depth, out resultType)
            }
        } else if kind == ColumnarExpressionNodeKind.RangeExpression() {
            planned = TryPlanRange(
                nodes, source, node, bindings, handles, plan, fragment, depth, out resultType)
        } else if kind == ColumnarExpressionNodeKind.TernaryExpression() {
            planned = TryPlanTernary(
                nodes, source, node, bindings, handles, plan, fragment, depth, out resultType)
        } else if kind == ColumnarExpressionNodeKind.IndexAccessExpression() {
            planned = TryPlanIndexAccess(
                nodes,
                source,
                node,
                bindings,
                handles,
                plan,
                fragment,
                depth,
                parentFragment >= 0,
                out resultType)
        }

        if !planned {
            plan.Rollback(checkpoint)
            return false
        }

        plan.CompleteFragment(fragment, resultType)
        return true
    }

    static func TryPlanBooleanLiteral(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        plan: ColumnarCodePlan,
        out resultType: Type): bool {
        resultType = typeof(bool)
        if nodes.ChildCount(node) != 0 {
            return false
        }
        text := nodes.Text(source, node)
        if text == "true" {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
            return true
        }
        if text == "false" {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
            return true
        }
        return false
    }

    static func TryPlanIdentifier(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        plan: ColumnarCodePlan,
        out resultType: Type): bool {
        resultType = typeof(int)
        if nodes.ChildCount(node) != 0 {
            return false
        }
        name := nodes.Text(source, node)
        if name.Length == 0
            || ColumnarExpressionSyntaxFacts.IsExplicitThisIdentifier(nodes, source, node)
            || bindings.IsBlocked(name) {
            return false
        }

        hasLocal := bindings.Locals.ContainsKey(name)
        hasOrdinal := bindings.ParameterOrdinals.ContainsKey(name)
        hasParameterType := bindings.ParameterTypes.ContainsKey(name)
        if hasLocal && (hasOrdinal || hasParameterType) {
            throw new InvalidOperationException(
                "Range/index binding facts contain overlapping local and parameter names.")
        }

        if hasLocal {
            local := bindings.Locals[name]
            if local == null {
                throw new InvalidOperationException("Range/index local binding cannot be null.")
            }
            localType := local.get_LocalType()
            if localType == null || localType.get_IsByRef() {
                return false
            }
            localIndex := plan.AddAmbientLocal(local)
            plan.AppendAmbientLocalInstruction(ColumnarCodePlanContract.Ldloc(), localIndex)
            resultType = localType
            return true
        }

        if hasOrdinal != hasParameterType {
            throw new InvalidOperationException(
                "Range/index parameter ordinals and types must contain identical names.")
        }
        if hasOrdinal {
            ordinal := bindings.ParameterOrdinals[name]
            parameterType := bindings.ParameterTypes[name]
            if parameterType == null || parameterType.get_IsByRef() {
                return false
            }
            typeIndex := plan.AddType(parameterType)
            argumentIndex := plan.AddArgument(ordinal, typeIndex)
            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
            resultType = parameterType
            return true
        }

        return false
    }

    static func TryPlanEnumMember(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        plan: ColumnarCodePlan,
        out resultType: Type): bool {
        resultType = typeof(int)
        if nodes.ChildCount(node) != 1 {
            return false
        }

        qualifiedOwner := ""
        rootName := ""
        if !TryGetQualifiedName(
            nodes, source, nodes.Child(node, 0), 0, out qualifiedOwner, out rootName)
            || bindings.IsValueBinding(rootName)
            || bindings.IsCallable(rootName)
            || !bindings.Enums.ContainsKey(qualifiedOwner) {
            return false
        }

        enumDefinition := bindings.Enums[qualifiedOwner]
        memberName := nodes.Text(source, node)
        if enumDefinition == null || enumDefinition.IsStringBacked
            || !enumDefinition.Constants.ContainsKey(memberName) {
            return false
        }

        enumType := enumDefinition.EnumType
        if enumType == null {
            throw new InvalidOperationException("Range/index enum binding type cannot be null.")
        }
        valueIndex := plan.AddInt32(enumDefinition.Constants[memberName])
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
        resultType = enumType
        return true
    }

    static func TryPlanFromEnd(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        fragment: int,
        depth: int,
        out resultType: Type): bool {
        resultType = typeof(Index)
        if nodes.ChildCount(node) != 1 || nodes.Text(source, node) != "^" {
            return false
        }

        operandType := typeof(int)
        if !TryPlanValue(
            nodes, source, nodes.Child(node, 0), bindings, handles,
            plan, fragment, depth + 1, out operandType)
            || !ConvertIndexOperand(plan, operandType) {
            return false
        }

        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
        constructorIndex := plan.AddConstructor(handles.IndexConstructor)
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
        return true
    }

    static func TryPlanRange(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        fragment: int,
        depth: int,
        out resultType: Type): bool {
        resultType = typeof(Range)
        startNode := -1
        endNode := -1
        if !TryGetRangeEndpoints(nodes, node, out startNode, out endNode) {
            return false
        }

        if startNode < 0 {
            EmitDefaultIndex(plan, handles, false)
        } else if !TryPlanIndexValue(
            nodes, source, startNode, bindings, handles,
            plan, fragment, depth + 1) {
            return false
        }

        if endNode < 0 {
            EmitDefaultIndex(plan, handles, true)
        } else if !TryPlanIndexValue(
            nodes, source, endNode, bindings, handles,
            plan, fragment, depth + 1) {
            return false
        }

        constructorIndex := plan.AddConstructor(handles.RangeConstructor)
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
        return true
    }

    static func TryPlanIndexValue(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        parentFragment: int,
        depth: int): bool {
        valueType := typeof(int)
        if !TryPlanValue(
            nodes, source, node, bindings, handles,
            plan, parentFragment, depth, out valueType) {
            return false
        }
        if valueType == typeof(Index) {
            return true
        }
        if !ConvertIndexOperand(plan, valueType) {
            return false
        }
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
        constructorIndex := plan.AddConstructor(handles.IndexConstructor)
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
        return true
    }

    static func ConvertIndexOperand(plan: ColumnarCodePlan, operandType: Type): bool {
        if operandType == typeof(int) {
            return true
        }
        if !ColumnarNumericFacts.IsIntPromotable(operandType)
            && (!operandType.get_IsEnum()
                || operandType.GetEnumUnderlyingType() != typeof(int)) {
            return false
        }
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
        return true
    }

    static func EmitDefaultIndex(
        plan: ColumnarCodePlan,
        handles: ColumnarRangeIndexHandles,
        fromEnd: bool) {
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
        if fromEnd {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
        } else {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
        }
        constructorIndex := plan.AddConstructor(handles.IndexConstructor)
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
    }

    static func TryPlanTernary(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        fragment: int,
        depth: int,
        out resultType: Type): bool {
        resultType = typeof(int)
        if nodes.ChildCount(node) != 3 {
            return false
        }

        conditionType := typeof(bool)
        if !TryPlanValue(
            nodes, source, nodes.Child(node, 0), bindings, handles,
            plan, fragment, depth + 1, out conditionType)
            || conditionType != typeof(bool) {
            return false
        }

        falseLabel := plan.DefineLabel()
        endLabel := plan.DefineLabel()
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), falseLabel)

        whenTrueType := typeof(int)
        if !TryPlanValue(
            nodes, source, nodes.Child(node, 1), bindings, handles,
            plan, fragment, depth + 1, out whenTrueType) {
            return false
        }
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), endLabel)
        plan.AppendMarkLabel(falseLabel)

        whenFalseType := typeof(int)
        if !TryPlanValue(
            nodes, source, nodes.Child(node, 2), bindings, handles,
            plan, fragment, depth + 1, out whenFalseType)
            || whenTrueType != whenFalseType {
            return false
        }
        plan.AppendMarkLabel(endLabel)
        resultType = whenTrueType
        return true
    }

    static func TryPlanIndexAccess(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        fragment: int,
        depth: int,
        allowOrdinaryIntIndex: bool,
        out resultType: Type): bool {
        resultType = typeof(int)
        if nodes.ChildCount(node) != 2 {
            return false
        }

        indexedType := typeof(int)
        if !TryPlanValue(
            nodes, source, nodes.Child(node, 0), bindings, handles,
            plan, fragment, depth + 1, out indexedType) {
            return false
        }
        isString := indexedType == typeof(string)
        if !isString && !indexedType.get_IsSZArray() {
            return false
        }

        accessType := typeof(int)
        if !TryPlanValue(
            nodes, source, nodes.Child(node, 1), bindings, handles,
            plan, fragment, depth + 1, out accessType) {
            return false
        }
        if accessType == typeof(int) {
            if !allowOrdinaryIntIndex {
                return false
            }
            if isString {
                return PlanStringOrdinaryIndex(plan, handles, out resultType)
            }
            return PlanArrayOrdinaryIndex(plan, indexedType, out resultType)
        }
        if accessType != typeof(Index) && accessType != typeof(Range) {
            return false
        }

        if isString {
            if accessType == typeof(Index) {
                return PlanStringIndex(plan, handles, out resultType)
            }
            return PlanStringRange(plan, handles, out resultType)
        }
        if accessType == typeof(Index) {
            return PlanArrayIndex(plan, handles, indexedType, out resultType)
        }
        return PlanArrayRange(plan, handles, indexedType, out resultType)
    }

    static func PlanStringOrdinaryIndex(
        plan: ColumnarCodePlan,
        handles: ColumnarRangeIndexHandles,
        out resultType: Type): bool {
        charsGetter := plan.AddMethod(handles.StringCharsGetter)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), charsGetter)
        resultType = typeof(char)
        return true
    }

    static func PlanArrayOrdinaryIndex(
        plan: ColumnarCodePlan,
        arrayType: Type,
        out resultType: Type): bool {
        elementType := arrayType.GetElementType()
        if elementType == null {
            resultType = typeof(int)
            return false
        }
        AppendArrayElementLoad(plan, elementType)
        resultType = elementType
        return true
    }

    static func PlanStringIndex(
        plan: ColumnarCodePlan,
        handles: ColumnarRangeIndexHandles,
        out resultType: Type): bool {
        indexLocal := DeclarePlanLocal(plan, typeof(Index))
        stringLocal := DeclarePlanLocal(plan, typeof(string))
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), indexLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), stringLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), stringLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), indexLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), stringLocal)
        lengthGetter := plan.AddMethod(handles.StringLengthGetter)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), lengthGetter)
        getOffset := plan.AddMethod(handles.IndexGetOffset)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), getOffset)
        charsGetter := plan.AddMethod(handles.StringCharsGetter)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), charsGetter)
        resultType = typeof(char)
        return true
    }

    static func PlanStringRange(
        plan: ColumnarCodePlan,
        handles: ColumnarRangeIndexHandles,
        out resultType: Type): bool {
        tupleType := typeof(ValueTuple<int, int>)
        rangeLocal := DeclarePlanLocal(plan, typeof(Range))
        stringLocal := DeclarePlanLocal(plan, typeof(string))
        offsetsLocal := DeclarePlanLocal(plan, tupleType)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), rangeLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), stringLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), rangeLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), stringLocal)
        lengthGetter := plan.AddMethod(handles.StringLengthGetter)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), lengthGetter)
        offsetsMethod := plan.AddMethod(handles.RangeGetOffsetAndLength)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), offsetsMethod)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), offsetsLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), stringLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), offsetsLocal)
        item1 := plan.AddField(handles.TupleItem1)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), item1)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), offsetsLocal)
        item2 := plan.AddField(handles.TupleItem2)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), item2)
        substring := plan.AddMethod(handles.StringSubstring)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), substring)
        resultType = typeof(string)
        return true
    }

    static func PlanArrayIndex(
        plan: ColumnarCodePlan,
        handles: ColumnarRangeIndexHandles,
        arrayType: Type,
        out resultType: Type): bool {
        elementType := arrayType.GetElementType()
        if elementType == null {
            resultType = typeof(int)
            return false
        }

        indexLocal := DeclarePlanLocal(plan, typeof(Index))
        arrayLocal := DeclarePlanLocal(plan, arrayType)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), indexLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), arrayLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), arrayLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), indexLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), arrayLocal)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldlen())
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
        getOffset := plan.AddMethod(handles.IndexGetOffset)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), getOffset)
        AppendArrayElementLoad(plan, elementType)
        resultType = elementType
        return true
    }

    static func PlanArrayRange(
        plan: ColumnarCodePlan,
        handles: ColumnarRangeIndexHandles,
        arrayType: Type,
        out resultType: Type): bool {
        elementType := arrayType.GetElementType()
        if elementType == null {
            resultType = typeof(int)
            return false
        }
        method := handles.CloseGetSubArray(elementType)
        methodIndex := plan.AddMethod(method)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
        resultType = arrayType
        return true
    }

    static func AppendArrayElementLoad(plan: ColumnarCodePlan, elementType: Type) {
        if elementType == typeof(bool) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemU1())
        } else if elementType == typeof(char) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemU2())
        } else if elementType == typeof(int) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemI4())
        } else if elementType == typeof(uint) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemU4())
        } else if elementType == typeof(long) || elementType == typeof(ulong) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemI8())
        } else if elementType == typeof(float) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemR4())
        } else if elementType == typeof(double) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemR8())
        } else if !elementType.get_IsValueType() && !elementType.get_IsGenericParameter() {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemRef())
        } else {
            typeIndex := plan.AddType(elementType)
            plan.AppendTypeInstruction(ColumnarCodePlanContract.Ldelem(), typeIndex)
        }
    }

    static func DeclarePlanLocal(plan: ColumnarCodePlan, localType: Type): int {
        typeIndex := plan.AddType(localType)
        return plan.DeclarePlanLocal(typeIndex)
    }

    static func TryGetRangeEndpoints(
        nodes: ColumnarNodeTable,
        node: int,
        out startNode: int,
        out endNode: int): bool {
        startNode = -1
        endNode = -1
        childCount := nodes.ChildCount(node)
        if childCount == 0 {
            return true
        }
        if childCount == 1 {
            onlyChild := nodes.Child(node, 0)
            if onlyChild < 0 || onlyChild >= nodes.Kinds.Length {
                return false
            }
            if nodes.SpanStart(onlyChild) < nodes.ValueStart(node) {
                startNode = onlyChild
            } else {
                endNode = onlyChild
            }
            return true
        }
        if childCount == 2 {
            startNode = nodes.Child(node, 0)
            endNode = nodes.Child(node, 1)
            return startNode >= 0 && startNode < nodes.Kinds.Length
                && endNode >= 0 && endNode < nodes.Kinds.Length
        }
        return false
    }

    static func TryGetQualifiedName(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        depth: int,
        out qualifiedName: string,
        out rootName: string): bool {
        qualifiedName = ""
        rootName = ""
        if depth > 200 || node < 0 || node >= nodes.Kinds.Length {
            return false
        }
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.IdentifierExpression() {
            if nodes.ChildCount(node) != 0 {
                return false
            }
            rootName = nodes.Text(source, node)
            qualifiedName = rootName
            return rootName.Length > 0
        }
        if kind != ColumnarExpressionNodeKind.MemberAccessExpression()
            || nodes.ChildCount(node) != 1 {
            return false
        }

        prefix := ""
        if !TryGetQualifiedName(
            nodes, source, nodes.Child(node, 0), depth + 1, out prefix, out rootName) {
            return false
        }
        member := nodes.Text(source, node)
        if member.Length == 0 {
            return false
        }
        qualifiedName = prefix + "." + member
        return true
    }

    static func UnwrapParentheses(nodes: ColumnarNodeTable, node: int): int {
        depth := 0
        while node >= 0 && node < nodes.Kinds.Length
            && nodes.Kind(node) == ColumnarExpressionNodeKind.ParenthesizedExpression() {
            if depth > 200 || nodes.ChildCount(node) != 1 {
                return -1
            }
            node = nodes.Child(node, 0)
            depth = depth + 1
        }
        return node
    }

    static func RequiredResultType(plan: ColumnarCodePlan): Type {
        resultType := plan.ResultType
        if resultType == null {
            throw new InvalidOperationException("Planned range/index expression has no result type.")
        }
        return resultType
    }
}
