namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Diagnostics
import System.Globalization
import System.IO
import System.Reflection
import System.Reflection.Emit
import System.Text
import System.Text.Json
import YamlDotNet.Core
import YamlDotNet.Core.Events
import YamlDotNet.Serialization


// Direct schema-v3 owner for the admitted construction surface: exact source and runtime
// constructor calls (including closed generics and metadata defaults), sized SZ arrays, nonempty
// homogeneous array literals, and exact source/runtime/union object initializers. Contextual
// constructor syntax outside this admitted surface remains a whole-subtree boundary; malformed
// syntax in an owned family is terminal and can never be reinterpreted by another emitter route.
class ColumnarConstructionPlanner {
    static func MayPlanRoot(nodes: ColumnarNodeTable, node: int): bool {
        if nodes == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return false
        }

        kind := nodes.Kind(candidate)
        return kind == ColumnarExpressionNodeKind.NewExpression() || kind == ColumnarExpressionNodeKind.ObjectInitializerExpression() || kind == ColumnarExpressionNodeKind.ArrayLiteralExpression()
    }

    // DirectCall's syntax preflight may use this without walking NewExpression's type child as a
    // value. Exact type-shape and semantic rejection remain this planner's responsibility.
    static func IsAdmittedValueSyntax(nodes: ColumnarNodeTable, node: int, depth: int): bool {
        if nodes == null || depth > 200 {
            return false
        }

        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return false
        }

        kind := nodes.Kind(candidate)
        childStart := 0
        if kind == ColumnarExpressionNodeKind.ObjectInitializerExpression() {
            childCount := nodes.ChildCount(candidate)
            if childCount < 1 || childCount % 2 != 1 {
                return true
            }
            typeNode := nodes.Child(candidate, 0)
            if typeNode < 0 || typeNode >= nodes.Kinds.Length {
                return true
            }
            typeKind := nodes.Kind(typeNode)
            if typeKind == ColumnarExpressionNodeKind.NewExpression() {
                if !IsAdmittedValueSyntax(nodes, typeNode, depth + 1) {
                    return false
                }
            } else if typeKind != 0 && typeKind != 1 {
                return false
            }
            index := 1
            while index < childCount {
                nameNode := nodes.Child(candidate, index)
                valueNode := nodes.Child(candidate, index + 1)
                if nameNode < 0 || nameNode >= nodes.Kinds.Length || nodes.Kind(nameNode) != ColumnarExpressionNodeKind.IdentifierExpression() || !ColumnarDirectCallPlanner.IsAdmittedValueSyntax(nodes, valueNode, depth + 1) {
                    return false
                }
                index += 2
            }
            return true
        }
        if kind == ColumnarExpressionNodeKind.NewExpression() {
            if nodes.ChildCount(candidate) < 1 {
                return true
            }
            typeNode := nodes.Child(candidate, 0)
            if typeNode < 0 || typeNode >= nodes.Kinds.Length {
                return true
            }
            typeKind := nodes.Kind(typeNode)
            if typeKind != 0 && typeKind != 1 && typeKind != 2 {
                return false
            }
            childStart = 1
        } else if kind != ColumnarExpressionNodeKind.ArrayLiteralExpression() {
            return false
        }

        index := childStart
        while index < nodes.ChildCount(candidate) {
            child := nodes.Child(candidate, index)
            if ColumnarConstructionPlanner.MayPlanRoot(nodes, child) {
                if !IsAdmittedValueSyntax(nodes, child, depth + 1) {
                    return false
                }
            } else if !ColumnarDirectCallPlanner.IsAdmittedValueSyntax(nodes, child, depth + 1) {
                return false
            }
            index += 1
        }
        return true
    }

    // Source-aware construction admission is deliberately separate from DirectCall's public
    // shape-only preflight. It commits a primitive binary value only after a scratch schema-v3 plan
    // proves the exact operand surface the primitive-binary planner owns; every unproven binary
    // shape remains a whole-subtree exit.
    static func IsAdmittedConstructionValueSyntax(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, depth: int): bool {
        if nodes == null || source == null || bindings == null || handles == null || depth > 200 {
            return false
        }

        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return false
        }
        kind := nodes.Kind(candidate)
        childStart := 0
        if kind == ColumnarExpressionNodeKind.ObjectInitializerExpression() {
            childCount := nodes.ChildCount(candidate)
            if childCount < 1 || childCount % 2 != 1 {
                return true
            }
            typeNode := nodes.Child(candidate, 0)
            if typeNode < 0 || typeNode >= nodes.Kinds.Length {
                return true
            }
            typeKind := nodes.Kind(typeNode)
            if typeKind == ColumnarExpressionNodeKind.NewExpression() {
                if !IsAdmittedConstructionValueSyntax(nodes, source, typeNode, bindings, handles, depth + 1) {
                    return false
                }
            } else if typeKind != 0 && typeKind != 1 {
                return false
            }
            index := 1
            while index < childCount {
                nameNode := nodes.Child(candidate, index)
                valueNode := nodes.Child(candidate, index + 1)
                if nameNode < 0 || nameNode >= nodes.Kinds.Length || nodes.Kind(nameNode) != ColumnarExpressionNodeKind.IdentifierExpression() || !ValueSyntaxIsAdmitted(nodes, source, valueNode, bindings, handles, depth + 1) {
                    return false
                }
                index += 2
            }
            return true
        }
        if kind == ColumnarExpressionNodeKind.NewExpression() {
            if nodes.ChildCount(candidate) < 1 {
                return true
            }
            typeNode := nodes.Child(candidate, 0)
            if typeNode < 0 || typeNode >= nodes.Kinds.Length {
                return true
            }
            typeKind := nodes.Kind(typeNode)
            if typeKind != 0 && typeKind != 1 && typeKind != 2 {
                return false
            }
            childStart = 1
        } else if kind != ColumnarExpressionNodeKind.ArrayLiteralExpression() {
            return false
        }

        index := childStart
        while index < nodes.ChildCount(candidate) {
            if !ValueSyntaxIsAdmitted(nodes, source, nodes.Child(candidate, index), bindings, handles, depth + 1) {
                return false
            }
            index += 1
        }
        return true
    }

    static func TryEmit(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, il: ILGenerator, out nsharpOwned: bool, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership := ColumnarDirectCallOwnership.NotOwned
        status := Plan(nodes, source, node, bindings, plan, out ownership, out legacyWholeSubtreePlanning, out resultType)
        ValidateOwnershipBoundary(ownership, legacyWholeSubtreePlanning)
        nsharpOwned = ownership != ColumnarDirectCallOwnership.NotOwned
        if status != ColumnarFragmentPlanStatus.Planned {
            return false
        }

        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
        return true
    }

    static func TryGetType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out nsharpOwned: bool, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership := ColumnarDirectCallOwnership.NotOwned
        status := Plan(nodes, source, node, bindings, plan, out ownership, out legacyWholeSubtreePlanning, out resultType)
        ValidateOwnershipBoundary(ownership, legacyWholeSubtreePlanning)
        nsharpOwned = ownership != ColumnarDirectCallOwnership.NotOwned
        if status != ColumnarFragmentPlanStatus.Planned {
            return false
        }

        resultType = RequiredResultType(plan)
        return true
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): ColumnarFragmentPlanStatus {
        ValidateInputs(nodes, source, node, bindings, plan)
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        plan.PrepareV3()

        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 || !MayPlanRoot(nodes, candidate) {
            return plan.Status
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            fragment := plan.BeginFragment(-1, nodes.Kind(candidate), candidate)
            handles := ColumnarRangeIndexHandles.Resolve()
            if !TryAppend(nodes, source, candidate, bindings, handles, plan, fragment, 0, out ownership, out legacyWholeSubtreePlanning, out resultType) {
                plan.Rollback(checkpoint)
                ValidateOwnershipBoundary(ownership, legacyWholeSubtreePlanning)
                return plan.Status
            }

            plan.CompleteFragment(fragment, resultType)
            plan.CompleteV3(resultType)
            ownership = ColumnarDirectCallOwnership.Planned
            return plan.Status
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    // The caller has already opened the expression fragment. This operation appends only its
    // value rows and leaves fragment completion to the shared recursive planner.
    static func TryAppend(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if nodes == null || source == null || bindings == null || handles == null || plan == null || node < 0 || node >= nodes.Kinds.Length || depth > 200 {
            return false
        }
        if plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() || plan.Status != ColumnarFragmentPlanStatus.NotOwned || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Construction append requires an open schema-v3 plan.")
        }

        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return false
        }
        kind := nodes.Kind(candidate)
        if kind == ColumnarExpressionNodeKind.ObjectInitializerExpression() {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            if TryAppendObjectInitializer(nodes, source, candidate, bindings, handles, plan, fragment, depth, out ownership, out legacyWholeSubtreePlanning, out resultType) {
                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }
            return false
        }
        if kind == ColumnarExpressionNodeKind.ArrayLiteralExpression() {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            if TryAppendInferredArray(nodes, source, candidate, bindings, handles, plan, fragment, depth, out ownership, out legacyWholeSubtreePlanning, out resultType) {
                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }
            return false
        }
        if kind != ColumnarExpressionNodeKind.NewExpression() {
            return false
        }

        ownership = ColumnarDirectCallOwnership.OwnedRejected
        if nodes.ChildCount(candidate) < 1 {
            return false
        }
        typeNode := nodes.Child(candidate, 0)
        if typeNode < 0 || typeNode >= nodes.Kinds.Length {
            return false
        }

        typeKind := nodes.Kind(typeNode)
        if typeKind == 2 {
            if TryAppendSizedArray(nodes, source, candidate, typeNode, bindings, handles, plan, fragment, depth, out ownership, out legacyWholeSubtreePlanning, out resultType) {
                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }
            return false
        }
        if typeKind != 0 && typeKind != 1 {
            ownership = ColumnarDirectCallOwnership.NotOwned
            legacyWholeSubtreePlanning = true
            return false
        }
        if typeKind == 0 && nodes.ChildCount(typeNode) != 0 {
            return false
        }

        canonical := ""
        targetType := typeof(object)
        if !TryBuildTypeCanonical(nodes, source, typeNode, 0, out canonical) {
            return false
        }

        unionClaimed := false
        unionDefinition: ColumnarUnionDef? = null
        caseDefinition: ColumnarUnionCaseDef? = null
        unionType := typeof(object)
        caseType := typeof(object)
        typeArguments := new Type[](0)
        if TryResolveExplicitUnionCase(nodes, canonical, bindings, out unionClaimed, out unionDefinition, out caseDefinition, out unionType, out caseType, out typeArguments) && unionDefinition != null && caseDefinition != null {
            if !TryAppendUnionCasePositionalConstruction(nodes, source, candidate, bindings, handles, plan, fragment, depth, caseDefinition, unionType, caseType, typeArguments, out ownership, out legacyWholeSubtreePlanning) {
                return false
            }
            resultType = unionType
            ownership = ColumnarDirectCallOwnership.Planned
            return true
        }
        if unionClaimed {
            return false
        }
        if !TryResolveExactType(nodes, canonical, bindings, out targetType) {
            return false
        }

        // A live generic parameter still requires contextual construction facts that are outside
        // this root slice. A raw union base is semantically claimed but is never constructible;
        // only one of its declared cases may allocate a union value.
        if targetType.get_IsGenericParameter() {
            ownership = ColumnarDirectCallOwnership.NotOwned
            legacyWholeSubtreePlanning = true
            return false
        }
        if IsSourceUnionType(targetType, bindings) {
            return false
        }
        if targetType == typeof(JsonElement) {
            if nodes.ChildCount(candidate) != 1 {
                return false
            }
            AppendDefaultValueConstruction(plan, targetType)
            resultType = targetType
            ownership = ColumnarDirectCallOwnership.Planned
            return true
        }

        if targetType.get_IsGenericType() && !targetType.get_IsGenericTypeDefinition() {
            if TryAppendClosedGenericConstruction(nodes, source, candidate, bindings, handles, plan, fragment, depth, targetType, out ownership, out legacyWholeSubtreePlanning) {
                resultType = targetType
                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }
            return false
        }

        sourceDefinition: ColumnarStructDef? = null
        if TryFindSourceDefinition(targetType, bindings, out sourceDefinition) && sourceDefinition != null {
            if TryAppendSourceConstruction(nodes, source, candidate, bindings, handles, plan, fragment, depth, sourceDefinition, targetType, out ownership, out legacyWholeSubtreePlanning) {
                resultType = targetType
                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }
            return false
        }

        if TryAppendRuntimeConstruction(nodes, source, candidate, bindings, handles, plan, fragment, depth, targetType, out ownership, out legacyWholeSubtreePlanning) {
            resultType = targetType
            ownership = ColumnarDirectCallOwnership.Planned
            return true
        }
        return false
    }

    static func TryAppendSizedArray(nodes: ColumnarNodeTable, source: string, node: int, typeNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if nodes.ChildCount(node) != 2 || nodes.ChildCount(typeNode) != 1 {
            return false
        }

        elementNode := nodes.Child(typeNode, 0)
        elementSyntax := ClassifyExactSizedArrayElementSyntax(nodes, elementNode, 0)
        if elementSyntax == 0 {
            ownership = ColumnarDirectCallOwnership.NotOwned
            legacyWholeSubtreePlanning = true
            return false
        }
        if elementSyntax < 0 {
            return false
        }

        elementCanonical := ""
        elementType := typeof(object)
        if !TryBuildTypeCanonical(nodes, source, elementNode, 0, out elementCanonical) || !TryResolveExactType(nodes, elementCanonical, bindings, out elementType) || !IsSupportedArrayElement(elementType, bindings) {
            return false
        }

        lengthNode := nodes.Child(node, 1)
        if !ValueSyntaxIsAdmitted(nodes, source, lengthNode, bindings, handles, depth + 1) {
            ownership = ColumnarDirectCallOwnership.NotOwned
            legacyWholeSubtreePlanning = true
            return false
        }
        lengthType := typeof(int)
        nestedOwnership := ColumnarDirectCallOwnership.NotOwned
        if !ColumnarDirectCallPlanner.TryGetPlannableValueType(nodes, source, lengthNode, bindings, handles, depth + 1, true, out lengthType, out nestedOwnership) {
            if nestedOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                ownership = nestedOwnership
            }
            return false
        }
        if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(lengthType, typeof(int)) {
            return false
        }

        emittedLengthType := typeof(int)
        if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, lengthNode, bindings, handles, plan, fragment, depth + 1, out emittedLengthType, out nestedOwnership) || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(emittedLengthType, typeof(int)) {
            if nestedOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                ownership = nestedOwnership
            }
            return false
        }

        elementIndex := plan.AddType(elementType)
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Newarr(), elementIndex)
        resultType = elementType.MakeArrayType()
        return true
    }

    static func TryAppendInferredArray(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        elementCount := nodes.ChildCount(node)
        if elementCount == 0 {
            ownership = ColumnarDirectCallOwnership.NotOwned
            legacyWholeSubtreePlanning = true
            return false
        }

        elementType := typeof(object)
        index := 0
        while index < elementCount {
            elementNode := nodes.Child(node, index)
            candidate := UnwrapParentheses(nodes, elementNode)
            if candidate < 0 {
                return false
            }
            if nodes.Kind(candidate) == ColumnarExpressionNodeKind.NullLiteralExpression() {
                ownership = ColumnarDirectCallOwnership.NotOwned
                legacyWholeSubtreePlanning = true
                return false
            }
            if !ValueSyntaxIsAdmitted(nodes, source, elementNode, bindings, handles, depth + 1) {
                ownership = ColumnarDirectCallOwnership.NotOwned
                legacyWholeSubtreePlanning = true
                return false
            }

            currentType := typeof(int)
            nestedOwnership := ColumnarDirectCallOwnership.NotOwned
            if !ColumnarDirectCallPlanner.TryGetPlannableValueType(nodes, source, elementNode, bindings, handles, depth + 1, true, out currentType, out nestedOwnership) {
                if nestedOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                    ownership = nestedOwnership
                }
                return false
            }
            if index == 0 {
                if !IsSupportedArrayElement(currentType, bindings) {
                    return false
                }
                elementType = currentType
            } else if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(elementType, currentType) {
                return false
            }
            index += 1
        }

        countIndex := plan.AddInt32(elementCount)
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), countIndex)
        elementTypeIndex := plan.AddType(elementType)
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Newarr(), elementTypeIndex)

        index = 0
        while index < elementCount {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
            arrayIndex := plan.AddInt32(index)
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), arrayIndex)

            emittedType := typeof(int)
            nestedOwnership := ColumnarDirectCallOwnership.NotOwned
            if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, nodes.Child(node, index), bindings, handles, plan, fragment, depth + 1, out emittedType, out nestedOwnership) || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(emittedType, elementType) {
                if nestedOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                    ownership = nestedOwnership
                }
                return false
            }
            AppendArrayElementStore(plan, elementType)
            index += 1
        }

        resultType = elementType.MakeArrayType()
        return true
    }

    static func TryAppendObjectInitializer(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        childCount := nodes.ChildCount(node)
        if childCount < 1 || childCount % 2 != 1 {
            return false
        }
        if !IsAdmittedConstructionValueSyntax(nodes, source, node, bindings, handles, depth) {
            ownership = ColumnarDirectCallOwnership.NotOwned
            legacyWholeSubtreePlanning = true
            return false
        }

        typeRoot := nodes.Child(node, 0)
        rootKind := nodes.Kind(typeRoot)
        if rootKind == ColumnarExpressionNodeKind.NewExpression() {
            nestedOwnership := ColumnarDirectCallOwnership.NotOwned
            nestedLegacy := false
            constructedType := typeof(int)
            nestedFragment := plan.BeginFragment(fragment, rootKind, typeRoot)
            if !TryAppend(nodes, source, typeRoot, bindings, handles, plan, nestedFragment, depth + 1, out nestedOwnership, out nestedLegacy, out constructedType) {
                if nestedOwnership == ColumnarDirectCallOwnership.NotOwned {
                    ownership = nestedOwnership
                    legacyWholeSubtreePlanning = true
                }
                return false
            }
            plan.CompleteFragment(nestedFragment, constructedType)
            constructedDefinition: ColumnarStructDef? = null
            if !TryFindSourceDefinition(constructedType, bindings, out constructedDefinition) {
                TryFindClosedSourceDefinition(constructedType, bindings, out constructedDefinition)
            }
            if constructedDefinition == null && (constructedType is TypeBuilder || ContainsBuilderBoundType(constructedType)) {
                ownership = ColumnarDirectCallOwnership.NotOwned
                legacyWholeSubtreePlanning = true
                return false
            }
            if constructedDefinition != null && !constructedDefinition.IsReference {
                return false
            }
            if !TryAppendObjectMembers(nodes, source, node, bindings, handles, plan, fragment, depth, constructedType, constructedDefinition, out ownership, out legacyWholeSubtreePlanning) {
                return false
            }
            resultType = constructedType
            return true
        }
        if rootKind != 0 && rootKind != 1 {
            return false
        }

        canonical := ""
        if !TryBuildTypeCanonical(nodes, source, typeRoot, 0, out canonical) {
            return false
        }

        unionDefinition: ColumnarUnionDef? = null
        caseDefinition: ColumnarUnionCaseDef? = null
        unionType := typeof(object)
        caseType := typeof(object)
        typeArguments := new Type[](0)
        unionClaimed := false
        if TryResolveExplicitUnionCase(nodes, canonical, bindings, out unionClaimed, out unionDefinition, out caseDefinition, out unionType, out caseType, out typeArguments) && unionDefinition != null && caseDefinition != null {
            if !TryAppendUnionCaseObjectInitializer(nodes, source, node, bindings, handles, plan, fragment, depth, caseDefinition, unionType, caseType, typeArguments, out ownership, out legacyWholeSubtreePlanning) {
                return false
            }
            resultType = unionType
            return true
        }
        if unionClaimed {
            return false
        }

        targetType := typeof(object)
        if !TryResolveExactType(nodes, canonical, bindings, out targetType) {
            return false
        }

        definition: ColumnarStructDef? = null
        if !TryFindSourceDefinition(targetType, bindings, out definition) {
            TryFindClosedSourceDefinition(targetType, bindings, out definition)
        }
        if definition != null {
            if !TryAppendSourceObjectInitializerConstruction(nodes, source, node, bindings, handles, plan, fragment, depth, definition, targetType, out ownership, out legacyWholeSubtreePlanning) {
                return false
            }
            resultType = targetType
            return true
        }

        if !IsApprovedRuntimeObjectInitializerType(targetType) || !TryAppendRuntimeObjectInitializerConstruction(nodes, source, node, bindings, handles, plan, fragment, depth, targetType, out ownership, out legacyWholeSubtreePlanning) {
            return false
        }
        resultType = targetType
        return true
    }

    static func TryAppendSourceObjectInitializerConstruction(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, definition: ColumnarStructDef, targetType: Type, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        closed := targetType.get_IsGenericType() && !targetType.get_IsGenericTypeDefinition()

        if definition.IsReference {
            if definition.DefaultCtor == null {
                return false
            }
            constructor: ConstructorInfo = definition.DefaultCtor
            if closed {
                constructor = TypeBuilder.GetConstructor(targetType, definition.DefaultCtor)
            }
            constructorIndex := plan.AddConstructorWithSignature(constructor, targetType, new Type[](0))
            plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
            return TryAppendObjectMembers(nodes, source, node, bindings, handles, plan, fragment, depth, targetType, definition, out ownership, out legacyWholeSubtreePlanning)
        }

        localIndex := BeginDefaultValueConstruction(plan, targetType)
        if !TryAppendValueTypeObjectFields(nodes, source, node, bindings, handles, plan, fragment, depth, targetType, definition, localIndex, out ownership, out legacyWholeSubtreePlanning) {
            return false
        }
        CompleteDefaultValueConstruction(plan, localIndex)
        return true
    }

    static func BeginDefaultValueConstruction(plan: ColumnarCodePlan, targetType: Type): int {
        typeIndex := plan.AddType(targetType)
        localIndex := plan.DeclarePlanLocal(typeIndex)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), localIndex)
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Initobj(), typeIndex)
        return localIndex
    }

    static func CompleteDefaultValueConstruction(plan: ColumnarCodePlan, localIndex: int) {
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), localIndex)
    }

    static func AppendDefaultValueConstruction(plan: ColumnarCodePlan, targetType: Type) {
        localIndex := BeginDefaultValueConstruction(plan, targetType)
        CompleteDefaultValueConstruction(plan, localIndex)
    }

    static func TryAppendRuntimeObjectInitializerConstruction(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, targetType: Type, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        constructor := targetType.GetConstructor(new Type[](0))
        if constructor == null {
            return false
        }
        constructorIndex := plan.AddConstructorWithSignature(constructor, targetType, new Type[](0))
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
        return TryAppendObjectMembers(nodes, source, node, bindings, handles, plan, fragment, depth, targetType, null, out ownership, out legacyWholeSubtreePlanning)
    }

    static func TryAppendObjectMembers(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, targetType: Type, definition: ColumnarStructDef?, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        assigned := new HashSet<string>(StringComparer.Ordinal)
        index := 1
        while index < nodes.ChildCount(node) {
            nameNode := nodes.Child(node, index)
            valueNode := nodes.Child(node, index + 1)
            if nodes.Kind(nameNode) != ColumnarExpressionNodeKind.IdentifierExpression() {
                return false
            }
            memberName := nodes.Text(source, nameNode)
            if !assigned.Add(memberName) {
                return false
            }

            if definition != null {
                propertyOwner: ColumnarStructDef? = null
                property: ColumnarPropertyDef? = null
                if TryFindObjectInitializerProperty(definition, memberName, out propertyOwner, out property) && propertyOwner != null && property != null {
                    if property.Setter == null || property.SetterParameterCount != 1 {
                        return false
                    }
                    propertyOwnerType := typeof(object)
                    propertyOwnerArguments := new Type[](0)
                    if !TryResolveExactObjectMemberOwnerType(definition, targetType, propertyOwner, out propertyOwnerType, out propertyOwnerArguments) {
                        return false
                    }
                    propertyType := propertyOwnerArguments.Length > 0 ? SubstituteTypeArgument(property.PropertyType, propertyOwnerArguments) : property.PropertyType
                    setter: MethodInfo = property.Setter
                    declaringType: Type = propertyOwnerType
                    if !SameObject(propertyOwnerType, propertyOwner.Builder) {
                        setter = TypeBuilder.GetMethod(propertyOwnerType, property.Setter)
                    }
                    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
                    if !TryAppendObjectInitializerValue(nodes, source, valueNode, bindings, handles, plan, fragment, depth + 1, propertyType, out ownership, out legacyWholeSubtreePlanning) {
                        return false
                    }
                    parameterTypes := Types1(propertyType)
                    methodIndex := plan.AddMethodWithSignature(setter, declaringType, parameterTypes, RequiredVoidType(), false, setter.get_IsAbstract())
                    plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), methodIndex)
                    index += 2
                    continue
                }

                fieldOwner: ColumnarStructDef? = null
                field: FieldBuilder? = null
                if !TryFindObjectInitializerField(definition, memberName, out fieldOwner, out field) || fieldOwner == null || field == null {
                    return false
                }
                selectedField: FieldBuilder = field
                if selectedField.get_IsInitOnly() {
                    return false
                }
                fieldOwnerType := typeof(object)
                fieldOwnerArguments := new Type[](0)
                if !TryResolveExactObjectMemberOwnerType(definition, targetType, fieldOwner, out fieldOwnerType, out fieldOwnerArguments) {
                    return false
                }
                fieldType: Type = typeof(object)
                fieldType = selectedField.get_FieldType()
                if fieldOwnerArguments.Length > 0 {
                    fieldType = SubstituteTypeArgument(fieldType, fieldOwnerArguments)
                }
                fieldHandle: FieldInfo = selectedField
                declaringType: Type = fieldOwnerType
                if !SameObject(fieldOwnerType, fieldOwner.Builder) {
                    fieldHandle = TypeBuilder.GetField(fieldOwnerType, selectedField)
                }
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
                if !TryAppendObjectInitializerValue(nodes, source, valueNode, bindings, handles, plan, fragment, depth + 1, fieldType, out ownership, out legacyWholeSubtreePlanning) {
                    return false
                }
                fieldIndex := plan.AddFieldWithSignature(fieldHandle, declaringType, fieldType, false)
                plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), fieldIndex)
                index += 2
                continue
            }

            runtimeProperty := targetType.GetProperty(memberName)
            if runtimeProperty == null {
                return false
            }
            selectedProperty: PropertyInfo = runtimeProperty
            setterCandidate := selectedProperty.get_SetMethod()
            if setterCandidate == null || setterCandidate.get_IsStatic() || setterCandidate.GetParameters().Length != 1 {
                return false
            }
            setter: MethodInfo = setterCandidate
            setterDeclaringType := setter.get_DeclaringType()
            if setterDeclaringType == null {
                return false
            }
            propertyType := selectedProperty.get_PropertyType()
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
            if !TryAppendObjectInitializerValue(nodes, source, valueNode, bindings, handles, plan, fragment, depth + 1, propertyType, out ownership, out legacyWholeSubtreePlanning) {
                return false
            }
            parameterTypes := Types1(propertyType)
            methodIndex := plan.AddMethodWithSignature(setter, setterDeclaringType, parameterTypes, RequiredVoidType(), false, setter.get_IsAbstract())
            plan.AppendMethodInstruction(setter.get_IsVirtual() ? ColumnarCodePlanContract.Callvirt() : ColumnarCodePlanContract.Call(), methodIndex)
            index += 2
        }
        return true
    }

    static func TryAppendValueTypeObjectFields(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, targetType: Type, definition: ColumnarStructDef, localIndex: int, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        assigned := new HashSet<string>(StringComparer.Ordinal)
        index := 1
        while index < nodes.ChildCount(node) {
            nameNode := nodes.Child(node, index)
            valueNode := nodes.Child(node, index + 1)
            if nodes.Kind(nameNode) != ColumnarExpressionNodeKind.IdentifierExpression() {
                return false
            }
            memberName := nodes.Text(source, nameNode)
            fieldOwner: ColumnarStructDef? = null
            field: FieldBuilder? = null
            if !assigned.Add(memberName) || !TryFindObjectInitializerField(definition, memberName, out fieldOwner, out field) || fieldOwner == null || field == null {
                return false
            }
            selectedField: FieldBuilder = field
            if selectedField.get_IsInitOnly() {
                return false
            }
            fieldOwnerType := typeof(object)
            fieldOwnerArguments := new Type[](0)
            if !TryResolveExactObjectMemberOwnerType(definition, targetType, fieldOwner, out fieldOwnerType, out fieldOwnerArguments) {
                return false
            }
            fieldType: Type = typeof(object)
            fieldType = selectedField.get_FieldType()
            if fieldOwnerArguments.Length > 0 {
                fieldType = SubstituteTypeArgument(fieldType, fieldOwnerArguments)
            }
            fieldHandle: FieldInfo = selectedField
            declaringType: Type = fieldOwnerType
            if !SameObject(fieldOwnerType, fieldOwner.Builder) {
                fieldHandle = TypeBuilder.GetField(fieldOwnerType, selectedField)
            }
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), localIndex)
            if !TryAppendObjectInitializerValue(nodes, source, valueNode, bindings, handles, plan, fragment, depth + 1, fieldType, out ownership, out legacyWholeSubtreePlanning) {
                return false
            }
            fieldIndex := plan.AddFieldWithSignature(fieldHandle, declaringType, fieldType, false)
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), fieldIndex)
            index += 2
        }
        return true
    }

    static func TryAppendObjectInitializerValue(nodes: ColumnarNodeTable, source: string, valueNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, expectedType: Type, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        candidate := UnwrapParentheses(nodes, valueNode)
        if candidate < 0 {
            return false
        }
        if nodes.Kind(candidate) == ColumnarExpressionNodeKind.NullLiteralExpression() {
            return ColumnarNullableArgumentLowering.TryAppendNullArgument(plan, fragment, nodes.Kind(candidate), candidate, expectedType)
        }
        if TryAppendTargetTypedInitializerInteger(nodes, source, candidate, expectedType, plan, fragment) {
            return true
        }
        if !ValueSyntaxIsAdmitted(nodes, source, valueNode, bindings, handles, depth) {
            ownership = ColumnarDirectCallOwnership.NotOwned
            legacyWholeSubtreePlanning = true
            return false
        }

        actualType := typeof(int)
        nestedOwnership := ColumnarDirectCallOwnership.NotOwned
        if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, valueNode, bindings, handles, plan, fragment, depth, out actualType, out nestedOwnership) {
            if nestedOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                ownership = nestedOwnership
            }
            return false
        }
        if ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(actualType, expectedType) {
            return true
        }
        return ColumnarDirectCallPlanner.AppendArgumentConversion(plan, actualType, expectedType, bindings.SourceTypeDefinitions)
    }

    static func TryAppendTargetTypedInitializerInteger(nodes: ColumnarNodeTable, source: string, node: int, expectedType: Type, plan: ColumnarCodePlan, fragment: int): bool {
        literalNode := node
        negative := false
        if nodes.Kind(node) == ColumnarExpressionNodeKind.UnaryExpression() && nodes.ChildCount(node) == 1 && nodes.Text(source, node) == "-" {
            literalNode = nodes.Child(node, 0)
            negative = true
        }
        if nodes.Kind(literalNode) != ColumnarExpressionNodeKind.IntLiteralExpression() || nodes.ChildCount(literalNode) != 0 {
            return false
        }
        magnitude := 0
        if !ColumnarScalarLiteralPlanner.TryGetTargetTypedIntegerMagnitude(nodes.Text(source, literalNode), out magnitude) {
            return false
        }
        value := (long)magnitude
        if negative {
            value = -value
        }
        literalType := expectedType
        liftNullable := false
        nullableElement := typeof(int)
        if ColumnarNullableArgumentLowering.TryGetSupportedNullableElement(expectedType, out nullableElement) {
            literalType = nullableElement
            liftNullable = true
        }
        if !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(literalType, value, negative) {
            return false
        }
        valueFragment := plan.BeginFragment(fragment, nodes.Kind(node), node)
        if literalType == typeof(long) || literalType == typeof(ulong) {
            valueIndex := plan.AddInt64(value)
            plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), valueIndex)
        } else {
            valueIndex := plan.AddInt32((int)value)
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
        }
        plan.CompleteFragment(valueFragment, literalType)
        return !liftNullable || ColumnarNullableArgumentLowering.TryAppendValueLift(plan, literalType, expectedType)
    }

    static func TryFindObjectInitializerProperty(definition: ColumnarStructDef, memberName: string, out owner: ColumnarStructDef?, out property: ColumnarPropertyDef?): bool {
        owner = null
        property = null
        current: ColumnarStructDef? = definition
        while current != null {
            candidate := current
            if candidate.Properties.ContainsKey(memberName) {
                owner = candidate
                property = candidate.Properties[memberName]
                return true
            }
            current = candidate.BaseDef
        }
        return false
    }

    // Contextual object-initializer fallback still emits values the schema-v3 expression
    // planner does not own. It must consume this N#-owned declaration-to-CLR mapping rather
    // than rebuilding generic base substitution in the mechanical emitter.
    static func TryResolveExactObjectMemberOwnerType(definition: ColumnarStructDef, targetType: Type, owner: ColumnarStructDef, out ownerType: Type, out ownerArguments: Type[]): bool {
        ownerType = typeof(object)
        ownerArguments = new Type[](0)
        currentDefinition: ColumnarStructDef? = definition
        currentType := targetType
        while currentDefinition != null {
            candidate := currentDefinition
            if SameObject(candidate, owner) {
                ownerType = currentType
                if currentType.get_IsGenericType() && !currentType.get_IsGenericTypeDefinition() {
                    ownerArguments = currentType.GetGenericArguments()
                }
                return true
            }

            baseDefinition := candidate.BaseDef
            openBaseType := candidate.Builder.get_BaseType()
            if baseDefinition == null || openBaseType == null {
                return false
            }
            if currentType.get_IsGenericType() && !currentType.get_IsGenericTypeDefinition() {
                currentType = SubstituteTypeArgument(openBaseType, currentType.GetGenericArguments())
            } else {
                currentType = openBaseType
            }
            currentDefinition = baseDefinition
        }
        return false
    }

    static func TryFindObjectInitializerField(definition: ColumnarStructDef, memberName: string, out owner: ColumnarStructDef?, out field: FieldBuilder?): bool {
        owner = null
        field = null
        current: ColumnarStructDef? = definition
        while current != null {
            candidate := current
            if candidate.Fields.ContainsKey(memberName) {
                owner = candidate
                field = candidate.Fields[memberName]
                return true
            }
            current = candidate.BaseDef
        }
        return false
    }

    static func IsApprovedRuntimeObjectInitializerType(targetType: Type): bool {
        return targetType == typeof(JsonSerializerOptions) || targetType == typeof(ProcessStartInfo) || targetType == typeof(Process)
    }

    static func RequiredVoidType(): Type {
        result := Type.GetType("System.Void")
        if result == null {
            throw new InvalidOperationException("System.Void runtime type was not found.")
        }
        return result
    }

    static func TryResolveExplicitUnionCase(nodes: ColumnarNodeTable, canonical: string, bindings: ColumnarFragmentBindings, out claimed: bool, out unionDefinition: ColumnarUnionDef?, out caseDefinition: ColumnarUnionCaseDef?, out unionType: Type, out caseType: Type, out typeArguments: Type[]): bool {
        claimed = false
        unionDefinition = null
        caseDefinition = null
        unionType = typeof(object)
        caseType = typeof(object)
        typeArguments = new Type[](0)
        caseArguments := new Type[](0)
        head := canonical
        genericSuffix := ""
        genericOpen := canonical.IndexOf("<", StringComparison.Ordinal)
        if genericOpen > 0 && canonical.EndsWith(">", StringComparison.Ordinal) {
            head = canonical.Substring(0, genericOpen)
            genericSuffix = canonical.Substring(genericOpen)
        }
        separator := head.LastIndexOf(".", StringComparison.Ordinal)
        if separator <= 0 || separator + 1 >= head.Length {
            return false
        }
        ownerHead := head.Substring(0, separator)
        ownerCanonical := ownerHead + genericSuffix
        caseName := head.Substring(separator + 1)
        resolvedUnionType := typeof(object)
        ownerClaimed := false
        if !TryResolveExactType(nodes, ownerCanonical, bindings, out resolvedUnionType, out ownerClaimed) {
            // Wrong generic arity or an invalid explicit argument still belongs to the source
            // union named by the head. Resolve that head without its arguments solely to preserve
            // the semantic claim; it must not be reinterpreted as a runtime construction.
            openOwnerType := typeof(object)
            openOwnerClaimed := false
            openOwnerDefinition: ColumnarUnionDef? = null
            if genericSuffix.Length > 0 && TryResolveExactType(nodes, ownerHead, bindings, out openOwnerType, out openOwnerClaimed) && TryFindSourceUnionDefinition(openOwnerType, bindings, out openOwnerDefinition) {
                claimed = true
            }
            return false
        }

        openUnionType := resolvedUnionType
        if resolvedUnionType.get_IsGenericType() && !resolvedUnionType.get_IsGenericTypeDefinition() {
            openUnionType = resolvedUnionType.GetGenericTypeDefinition()
            caseArguments = resolvedUnionType.GetGenericArguments()
        }
        selectedUnion: ColumnarUnionDef? = null
        if !TryFindSourceUnionDefinition(openUnionType, bindings, out selectedUnion) || selectedUnion == null {
            return false
        }
        claimed = true

        selectedCase: ColumnarUnionCaseDef? = null
        suffix := "." + caseName
        for pair in selectedUnion.Cases {
            if pair.Value == null {
                return false
            }
            if pair.Key.EndsWith(suffix, StringComparison.Ordinal) {
                if selectedCase != null && !SameObject(selectedCase, pair.Value) {
                    return false
                }
                selectedCase = pair.Value
            }
        }
        if selectedCase == null {
            return false
        }
        if !SameObject(selectedCase.UnionBase, selectedUnion.Base) {
            return false
        }
        resolvedCaseType: Type = selectedCase.CaseType
        if caseArguments.Length > 0 {
            caseDefinitionType: Type = selectedCase.CaseType
            if !caseDefinitionType.get_IsGenericTypeDefinition() || caseDefinitionType.GetGenericArguments().Length != caseArguments.Length {
                return false
            }
            try {
                resolvedCaseType = caseDefinitionType.MakeGenericType(caseArguments)
            } catch {
                return false
            }
        } else if selectedCase.UnionBase.get_IsGenericTypeDefinition() {
            return false
        }
        unionDefinition = selectedUnion
        caseDefinition = selectedCase
        unionType = resolvedUnionType
        caseType = resolvedCaseType
        typeArguments = caseArguments
        return true
    }

    static func TryFindSourceUnionDefinition(targetType: Type, bindings: ColumnarFragmentBindings, out selected: ColumnarUnionDef?): bool {
        selected = null
        openTarget := targetType
        if targetType.get_IsGenericType() && !targetType.get_IsGenericTypeDefinition() {
            openTarget = targetType.GetGenericTypeDefinition()
        }
        for candidate in bindings.SourceUnionDefinitions {
            if candidate == null || candidate.Base == null {
                throw new InvalidOperationException("Construction union facts cannot contain null values.")
            }
            candidateType: Type = candidate.Base
            if ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(candidateType, openTarget) {
                if selected != null && !SameObject(selected, candidate) {
                    throw new InvalidOperationException("One construction union target cannot map to two definitions.")
                }
                selected = candidate
            }
        }
        return selected != null
    }

    static func TryAppendUnionCaseObjectInitializer(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, definition: ColumnarUnionCaseDef, unionType: Type, caseType: Type, typeArguments: Type[], out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        pairCount := (nodes.ChildCount(node) - 1) / 2
        assigned := new HashSet<string>(StringComparer.Ordinal)
        index := 1
        while index < nodes.ChildCount(node) {
            nameNode := nodes.Child(node, index)
            valueNode := nodes.Child(node, index + 1)
            if nodes.Kind(nameNode) != ColumnarExpressionNodeKind.IdentifierExpression() {
                return false
            }
            fieldName := nodes.Text(source, nameNode)
            fieldHandle: FieldInfo? = null
            fieldType := typeof(object)
            if !assigned.Add(fieldName) || !TryResolveUnionCaseField(definition, caseType, typeArguments, fieldName, out fieldHandle, out fieldType) || fieldHandle == null {
                return false
            }
            index += 2
        }

        referenceCase := false
        if !TryAppendUnionCaseCreation(plan, definition, unionType, caseType, typeArguments, pairCount, out referenceCase) {
            return false
        }
        if !referenceCase {
            return true
        }

        index = 1
        while index < nodes.ChildCount(node) {
            fieldName := nodes.Text(source, nodes.Child(node, index))
            fieldHandle: FieldInfo? = null
            fieldType := typeof(object)
            if !TryResolveUnionCaseField(definition, caseType, typeArguments, fieldName, out fieldHandle, out fieldType) || fieldHandle == null || !TryAppendUnionCaseFieldValue(nodes, source, nodes.Child(node, index + 1), bindings, handles, plan, fragment, depth, caseType, fieldHandle, fieldType, out ownership, out legacyWholeSubtreePlanning) {
                return false
            }
            index += 2
        }
        return true
    }

    static func TryAppendUnionCasePositionalConstruction(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, definition: ColumnarUnionCaseDef, unionType: Type, caseType: Type, typeArguments: Type[], out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        argumentCount := nodes.ChildCount(node) - 1
        if definition.FieldOrder == null || definition.FieldOrder.Length != argumentCount {
            return false
        }

        assigned := new HashSet<string>(StringComparer.Ordinal)
        index := 0
        while index < argumentCount {
            fieldName := definition.FieldOrder[index]
            fieldHandle: FieldInfo? = null
            fieldType := typeof(object)
            if fieldName == null || !assigned.Add(fieldName) || !TryResolveUnionCaseField(definition, caseType, typeArguments, fieldName, out fieldHandle, out fieldType) || fieldHandle == null {
                return false
            }
            index += 1
        }

        referenceCase := false
        if !TryAppendUnionCaseCreation(plan, definition, unionType, caseType, typeArguments, argumentCount, out referenceCase) {
            return false
        }
        if !referenceCase {
            return true
        }

        index = 0
        while index < argumentCount {
            fieldName := definition.FieldOrder[index]
            fieldHandle: FieldInfo? = null
            fieldType := typeof(object)
            if !TryResolveUnionCaseField(definition, caseType, typeArguments, fieldName, out fieldHandle, out fieldType) || fieldHandle == null || !TryAppendUnionCaseFieldValue(nodes, source, nodes.Child(node, index + 1), bindings, handles, plan, fragment, depth, caseType, fieldHandle, fieldType, out ownership, out legacyWholeSubtreePlanning) {
                return false
            }
            index += 1
        }
        return true
    }

    static func TryAppendUnionCaseCreation(plan: ColumnarCodePlan, definition: ColumnarUnionCaseDef, unionType: Type, caseType: Type, typeArguments: Type[], assignmentCount: int, out referenceCase: bool): bool {
        referenceCase = false
        if definition.IsValueStruct {
            if assignmentCount != 0 || typeArguments.Length != 0 || definition.ValueStructFactory == null || !SameObject(unionType, definition.UnionBase) {
                return false
            }
            methodIndex := plan.AddMethodWithSignature(definition.ValueStructFactory, unionType, new Type[](0), unionType, true, false)
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
            return true
        }

        if !ConstructorBuilderMatches(definition.Ctor, definition.CaseType) {
            return false
        }
        constructor: ConstructorInfo = definition.Ctor
        if typeArguments.Length > 0 {
            try {
                constructor = TypeBuilder.GetConstructor(caseType, definition.Ctor)
            } catch {
                return false
            }
        }
        constructorIndex := plan.AddConstructorWithSignature(constructor, caseType, new Type[](0))
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
        referenceCase = true
        return true
    }

    static func TryResolveUnionCaseField(definition: ColumnarUnionCaseDef, caseType: Type, typeArguments: Type[], fieldName: string, out fieldHandle: FieldInfo?, out fieldType: Type): bool {
        fieldHandle = null
        fieldType = typeof(object)
        openField: FieldBuilder? = null
        if definition.Fields == null || !definition.Fields.TryGetValue(fieldName, out openField) || openField == null || openField.get_IsStatic() || openField.get_IsInitOnly() || !SameObject(openField.get_DeclaringType(), definition.CaseType) {
            return false
        }
        fieldType = openField.get_FieldType()
        if typeArguments.Length > 0 {
            fieldType = SubstituteTypeArgument(fieldType, typeArguments)
            try {
                fieldHandle = TypeBuilder.GetField(caseType, openField)
            } catch {
                fieldHandle = null
                return false
            }
        } else {
            fieldHandle = openField
        }
        return true
    }

    static func TryAppendUnionCaseFieldValue(nodes: ColumnarNodeTable, source: string, valueNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, caseType: Type, fieldHandle: FieldInfo, fieldType: Type, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
        if !TryAppendObjectInitializerValue(nodes, source, valueNode, bindings, handles, plan, fragment, depth + 1, fieldType, out ownership, out legacyWholeSubtreePlanning) {
            return false
        }
        fieldIndex := plan.AddFieldWithSignature(fieldHandle, caseType, fieldType, false)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), fieldIndex)
        return true
    }

    static func TryAppendSourceConstruction(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, definition: ColumnarStructDef, targetType: Type, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        argumentCount := nodes.ChildCount(node) - 1
        if argumentCount == 0 && !definition.IsReference && definition.Constructors.Count == 0 {
            AppendDefaultValueConstruction(plan, targetType)
            return true
        }
        argumentTypes := new Type[](argumentCount)
        argumentFacts := ColumnarDirectCallArgumentFacts.Empty(argumentCount)
        argumentFacts.SourceTypeDefinitions = bindings.SourceTypeDefinitions
        if !TryGetConstructorArguments(nodes, source, node, bindings, handles, depth, argumentTypes, argumentFacts, out ownership, out legacyWholeSubtreePlanning) {
            return false
        }

        if argumentCount == 0 && definition.IsReference && definition.DefaultCtor != null {
            parameters := new Type[](0)
            if !ConstructorBuilderMatches(definition.DefaultCtor, targetType) {
                throw new InvalidOperationException("Source default-constructor facts do not identify their exact owner.")
            }
            constructorIndex := plan.AddConstructorWithSignature(definition.DefaultCtor, targetType, parameters)
            plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
            return true
        }

        selected: ColumnarConstructorDef? = null
        if !TrySelectSourceConstructor(nodes, definition, argumentTypes, argumentFacts, bindings, out selected) || selected == null {
            return false
        }

        suppliedParameters := PrefixTypes(selected.ParamTypes, argumentCount)
        if !ColumnarDirectCallPlanner.AppendArguments(nodes, source, node, bindings, handles, plan, fragment, depth + 1, true, argumentTypes, suppliedParameters, argumentFacts) {
            return false
        }

        defaultIndex := argumentCount
        while defaultIndex < selected.ParamTypes.Length {
            if !TryAppendConstructorDefault(nodes, plan, selected.ParamTypes[defaultIndex], selected.DefaultKinds[defaultIndex], selected.DefaultTexts[defaultIndex], bindings) {
                return false
            }
            defaultIndex += 1
        }

        constructorIndex := plan.AddConstructorWithSignature(selected.Builder, targetType, selected.ParamTypes)
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
        return true
    }

    static func TryAppendRuntimeConstruction(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, targetType: Type, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        argumentCount := nodes.ChildCount(node) - 1
        parameters := new Type[](0)
        constructor: ConstructorInfo? = null
        if !TrySelectRuntimeConstructor(targetType, argumentCount, out constructor, out parameters) || constructor == null {
            return false
        }

        argumentTypes := new Type[](argumentCount)
        argumentFacts := ColumnarDirectCallArgumentFacts.Empty(argumentCount)
        argumentFacts.SourceTypeDefinitions = bindings.SourceTypeDefinitions
        if !TryGetConstructorArguments(nodes, source, node, bindings, handles, depth, argumentTypes, argumentFacts, out ownership, out legacyWholeSubtreePlanning) {
            return false
        }
        if !ColumnarDirectCallPlanner.AppendArguments(nodes, source, node, bindings, handles, plan, fragment, depth + 1, true, argumentTypes, parameters, argumentFacts) {
            return false
        }

        constructorIndex := plan.AddConstructorWithSignature(constructor, targetType, parameters)
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
        return true
    }

    static func TryAppendClosedGenericConstruction(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, targetType: Type, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        if targetType == null || !targetType.get_IsGenericType() || targetType.get_IsGenericTypeDefinition() {
            return false
        }

        definition: ColumnarStructDef? = null
        if TryFindClosedSourceDefinition(targetType, bindings, out definition) && definition != null {
            return TryAppendClosedSourceConstruction(nodes, source, node, bindings, handles, plan, fragment, depth, definition, targetType, out ownership, out legacyWholeSubtreePlanning)
        }

        return TryAppendClosedRuntimeConstruction(nodes, source, node, bindings, handles, plan, fragment, depth, targetType, out ownership, out legacyWholeSubtreePlanning)
    }

    static func TryAppendClosedSourceConstruction(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, definition: ColumnarStructDef, targetType: Type, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        argumentCount := nodes.ChildCount(node) - 1
        if argumentCount == 0 && !definition.IsReference && definition.Constructors.Count == 0 {
            AppendDefaultValueConstruction(plan, targetType)
            return true
        }
        argumentTypes := new Type[](argumentCount)
        argumentFacts := ColumnarDirectCallArgumentFacts.Empty(argumentCount)
        argumentFacts.SourceTypeDefinitions = bindings.SourceTypeDefinitions
        if !TryGetConstructorArguments(nodes, source, node, bindings, handles, depth, argumentTypes, argumentFacts, out ownership, out legacyWholeSubtreePlanning) {
            return false
        }

        if argumentCount == 0 && definition.IsReference && definition.DefaultCtor != null {
            if !ConstructorBuilderMatches(definition.DefaultCtor, definition.Builder) {
                throw new InvalidOperationException("Closed source default-constructor facts do not identify their open owner.")
            }
            defaultConstructor := TypeBuilder.GetConstructor(targetType, definition.DefaultCtor)
            defaultConstructorIndex := plan.AddConstructorWithSignature(defaultConstructor, targetType, new Type[](0))
            plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), defaultConstructorIndex)
            return true
        }

        selected: ColumnarConstructorDef? = null
        selectedParameters := new Type[](0)
        closedArguments := targetType.GetGenericArguments()
        candidates := new List<ColumnarConstructorDef>()
        candidateParameters := new List<Type[]>()
        exactArityOnly := false
        for candidate in definition.Constructors {
            ValidateSourceConstructor(definition, candidate)
            if candidate.ParamTypes.Length < argumentCount {
                continue
            }
            parameters := SubstituteTypeArguments(candidate.ParamTypes, closedArguments)
            defaultsSupported := true
            defaultIndex := argumentCount
            while defaultIndex < parameters.Length {
                if !CanUseConstructorDefault(nodes, parameters[defaultIndex], candidate.DefaultKinds[defaultIndex], candidate.DefaultTexts[defaultIndex], bindings) {
                    defaultsSupported = false
                }
                defaultIndex += 1
            }
            if !defaultsSupported {
                continue
            }

            exactArity := parameters.Length == argumentCount
            if exactArity && !exactArityOnly {
                candidates.Clear()
                candidateParameters.Clear()
                exactArityOnly = true
            }
            if exactArityOnly && !exactArity {
                continue
            }
            candidates.Add(candidate)
            candidateParameters.Add(parameters)
        }
        if candidates.Count == 0 {
            return false
        }
        selectedIndex := BestSourceConstructorIndex(candidateParameters, argumentTypes, argumentFacts)
        if selectedIndex < 0 {
            return false
        }
        selected = candidates[selectedIndex]
        selectedParameters = candidateParameters[selectedIndex]

        suppliedParameters := PrefixTypes(selectedParameters, argumentCount)
        if !ColumnarDirectCallPlanner.AppendArguments(nodes, source, node, bindings, handles, plan, fragment, depth + 1, true, argumentTypes, suppliedParameters, argumentFacts) {
            return false
        }

        defaultIndex := argumentCount
        while defaultIndex < selectedParameters.Length {
            if !TryAppendConstructorDefault(nodes, plan, selectedParameters[defaultIndex], selected.DefaultKinds[defaultIndex], selected.DefaultTexts[defaultIndex], bindings) {
                return false
            }
            defaultIndex += 1
        }

        constructor := TypeBuilder.GetConstructor(targetType, selected.Builder)
        if constructor == null {
            return false
        }
        constructorIndex := plan.AddConstructorWithSignature(constructor, targetType, selectedParameters)
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
        return true
    }

    static func TryAppendClosedRuntimeConstruction(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, targetType: Type, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        argumentCount := nodes.ChildCount(node) - 1
        parameterTypes := new Type[](0)
        openConstructor: ConstructorInfo? = null
        openType := targetType.GetGenericTypeDefinition()

        if IsSupportedValueTupleType(targetType) {
            parameterTypes = targetType.GetGenericArguments()
            if parameterTypes.Length != argumentCount {
                return false
            }
            openConstructor = openType.GetConstructor(openType.GetGenericArguments())
        } else if IsConstructibleCollectionDefinition(openType) {
            if argumentCount == 0 {
                parameterTypes = new Type[](0)
                openConstructor = openType.GetConstructor(parameterTypes)
            } else if argumentCount == 1 {
                argumentTypes := new Type[](1)
                argumentFacts := ColumnarDirectCallArgumentFacts.Empty(1)
                argumentFacts.SourceTypeDefinitions = bindings.SourceTypeDefinitions
                if !TryGetConstructorArguments(nodes, source, node, bindings, handles, depth, argumentTypes, argumentFacts, out ownership, out legacyWholeSubtreePlanning) {
                    return false
                }

                capacityParameters := Types1(typeof(int))
                if ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(capacityParameters, argumentTypes, argumentFacts) >= 0 {
                    parameterTypes = capacityParameters
                    openConstructor = openType.GetConstructor(parameterTypes)
                } else if IsComparerCollectionDefinition(openType) {
                    openConstructor = FindOpenComparerConstructor(openType)
                    if openConstructor == null {
                        return false
                    }
                    openParameters := openConstructor.GetParameters()
                    comparerType := SubstituteTypeArgument(openParameters[0].get_ParameterType(), targetType.GetGenericArguments())
                    comparerParameters := Types1(comparerType)
                    if ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(comparerParameters, argumentTypes, argumentFacts) < 0 {
                        return false
                    }
                    parameterTypes = comparerParameters
                }
            }
        }
        if openConstructor == null {
            return false
        }

        argumentTypes := new Type[](argumentCount)
        argumentFacts := ColumnarDirectCallArgumentFacts.Empty(argumentCount)
        argumentFacts.SourceTypeDefinitions = bindings.SourceTypeDefinitions
        if !TryGetConstructorArguments(nodes, source, node, bindings, handles, depth, argumentTypes, argumentFacts, out ownership, out legacyWholeSubtreePlanning) {
            return false
        }
        if !ColumnarDirectCallPlanner.AppendArguments(nodes, source, node, bindings, handles, plan, fragment, depth + 1, true, argumentTypes, parameterTypes, argumentFacts) {
            return false
        }

        constructor := ResolveClosedRuntimeConstructor(targetType, openConstructor)
        if constructor == null {
            return false
        }
        constructorIndex := plan.AddConstructorWithSignature(constructor, targetType, parameterTypes)
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
        return true
    }

    static func TryFindClosedSourceDefinition(targetType: Type, bindings: ColumnarFragmentBindings, out selected: ColumnarStructDef?): bool {
        selected = null
        if targetType == null || !targetType.get_IsGenericType() || targetType.get_IsGenericTypeDefinition() {
            return false
        }
        openType := targetType.GetGenericTypeDefinition()
        for candidate in bindings.SourceTypeDefinitions {
            if candidate == null || candidate.Builder == null {
                throw new InvalidOperationException("Construction source-type facts cannot contain null values.")
            }
            candidateType: Type = candidate.Builder
            if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(candidateType, openType) {
                continue
            }
            if selected != null && !SameObject(selected, candidate) {
                throw new InvalidOperationException("One closed construction target cannot map to two source definitions.")
            }
            selected = candidate
        }
        return selected != null
    }

    static func SubstituteTypeArguments(parameterTypes: Type[], arguments: Type[]): Type[] {
        result := new Type[](parameterTypes.Length)
        index := 0
        while index < parameterTypes.Length {
            result[index] = SubstituteTypeArgument(parameterTypes[index], arguments)
            index += 1
        }
        return result
    }

    static func SubstituteTypeArgument(signatureType: Type, arguments: Type[]): Type {
        if signatureType.get_IsGenericParameter() && signatureType.get_DeclaringMethod() == null {
            position := signatureType.get_GenericParameterPosition()
            if position < 0 || position >= arguments.Length {
                throw new InvalidOperationException("Construction generic parameter position is invalid.")
            }
            return arguments[position]
        }
        if signatureType.get_IsByRef() {
            element := signatureType.GetElementType()
            if element == null {
                throw new InvalidOperationException("Construction by-reference signature has no element type.")
            }
            return SubstituteTypeArgument(element, arguments).MakeByRefType()
        }
        if signatureType.get_IsSZArray() {
            element := signatureType.GetElementType()
            if element == null {
                throw new InvalidOperationException("Construction array signature has no element type.")
            }
            return SubstituteTypeArgument(element, arguments).MakeArrayType()
        }
        if signatureType.get_IsGenericType() && !signatureType.get_IsGenericTypeDefinition() {
            definition := signatureType.GetGenericTypeDefinition()
            rawArguments := signatureType.GetGenericArguments()
            closedArguments := new Type[](rawArguments.Length)
            index := 0
            while index < rawArguments.Length {
                closedArguments[index] = SubstituteTypeArgument(rawArguments[index], arguments)
                index += 1
            }
            return definition.MakeGenericType(closedArguments)
        }
        return signatureType
    }

    static func IsConstructibleCollectionDefinition(definition: Type): bool {
        name := definition.FullName
        return name == "System.Collections.Generic.List`1" || name == "System.Collections.Generic.Dictionary`2" || name == "System.Collections.Generic.SortedDictionary`2" || name == "System.Collections.Generic.HashSet`1" || name == "System.Collections.Generic.Stack`1"
    }

    static func IsComparerCollectionDefinition(definition: Type): bool {
        name := definition.FullName
        return name == "System.Collections.Generic.Dictionary`2" || name == "System.Collections.Generic.HashSet`1"
    }

    static func IsSupportedValueTupleType(valueType: Type): bool {
        if valueType == null || !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() || ContainsBuilderBoundType(valueType) {
            return false
        }
        definition := valueType.GetGenericTypeDefinition()
        name := definition.FullName
        return name == "System.ValueTuple`2" || name == "System.ValueTuple`3" || name == "System.ValueTuple`4" || name == "System.ValueTuple`5" || name == "System.ValueTuple`6" || name == "System.ValueTuple`7"
    }

    static func FindOpenComparerConstructor(definition: Type): ConstructorInfo? {
        constructors := definition.GetConstructors()
        index := 0
        while index < constructors.Length {
            parameters := constructors[index].GetParameters()
            if parameters.Length == 1 {
                parameterType := parameters[0].get_ParameterType()
                if parameterType.get_IsGenericType() && !parameterType.get_IsGenericTypeDefinition() {
                    parameterDefinition := parameterType.GetGenericTypeDefinition()
                    if parameterDefinition.FullName == "System.Collections.Generic.IEqualityComparer`1" {
                        return constructors[index]
                    }
                }
            }
            index += 1
        }
        return null
    }

    static func ResolveClosedRuntimeConstructor(targetType: Type, openConstructor: ConstructorInfo): ConstructorInfo? {
        if ContainsBuilderBoundType(targetType) {
            return TypeBuilder.GetConstructor(targetType, openConstructor)
        }
        parameterTypes := openConstructor.GetParameters()
        closedArguments := targetType.GetGenericArguments()
        expected := new Type[](parameterTypes.Length)
        index := 0
        while index < parameterTypes.Length {
            expected[index] = SubstituteTypeArgument(parameterTypes[index].get_ParameterType(), closedArguments)
            index += 1
        }
        return targetType.GetConstructor(expected)
    }

    static func ContainsBuilderBoundType(valueType: Type): bool {
        if valueType is TypeBuilder || valueType.get_IsGenericParameter() {
            return true
        }
        if valueType.get_HasElementType() {
            element := valueType.GetElementType()
            return element != null && ContainsBuilderBoundType(element)
        }
        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }
        arguments := valueType.GetGenericArguments()
        index := 0
        while index < arguments.Length {
            if ContainsBuilderBoundType(arguments[index]) {
                return true
            }
            index += 1
        }
        return false
    }

    static func TryGetConstructorArguments(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        index := 1
        while index < nodes.ChildCount(node) {
            if !ValueSyntaxIsAdmitted(nodes, source, nodes.Child(node, index), bindings, handles, depth + 1) {
                ownership = ColumnarDirectCallOwnership.NotOwned
                legacyWholeSubtreePlanning = true
                return false
            }
            index += 1
        }

        nestedOwnership := ColumnarDirectCallOwnership.NotOwned
        if !ColumnarDirectCallPlanner.TryGetArgumentTypes(nodes, source, node, bindings, handles, depth, true, argumentTypes, argumentFacts, out nestedOwnership) {
            if nestedOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                ownership = nestedOwnership
            }
            return false
        }
        return true
    }

    static func TrySelectSourceConstructor(nodes: ColumnarNodeTable, definition: ColumnarStructDef, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, bindings: ColumnarFragmentBindings, out selected: ColumnarConstructorDef?): bool {
        selected = null
        candidates := new List<ColumnarConstructorDef>()
        for candidate in definition.Constructors {
            ValidateSourceConstructor(definition, candidate)
            if candidate.ParamTypes.Length < argumentTypes.Length {
                continue
            }
            defaultsSupported := true
            defaultIndex := argumentTypes.Length
            while defaultIndex < candidate.ParamTypes.Length {
                if !CanUseConstructorDefault(nodes, candidate.ParamTypes[defaultIndex], candidate.DefaultKinds[defaultIndex], candidate.DefaultTexts[defaultIndex], bindings) {
                    defaultsSupported = false
                }
                defaultIndex += 1
            }
            if defaultsSupported {
                AddDistinctConstructor(candidates, candidate)
            }
        }
        if candidates.Count == 0 {
            return false
        }

        exact := new List<ColumnarConstructorDef>()
        for candidate in candidates {
            if candidate.ParamTypes.Length == argumentTypes.Length {
                exact.Add(candidate)
            }
        }
        if exact.Count > 0 {
            candidates = exact
        }
        candidateParameters := new List<Type[]>()
        for candidate in candidates {
            candidateParameters.Add(candidate.ParamTypes)
        }
        selectedIndex := BestSourceConstructorIndex(candidateParameters, argumentTypes, argumentFacts)
        if selectedIndex < 0 {
            return false
        }
        selected = candidates[selectedIndex]
        return true
    }

    // Conversion quality, not declaration order, owns source-constructor overload selection.
    // The direct-call score is larger for a more specific conversion (identity is the maximum),
    // so a unique highest score wins and only an equal-best set is ambiguous.
    static func BestSourceConstructorIndex(candidateParameters: List<Type[]>, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): int {
        bestIndex := -1
        bestScore := -1
        bestCount := 0
        candidateIndex := 0
        while candidateIndex < candidateParameters.Count {
            expected := PrefixTypes(candidateParameters[candidateIndex], argumentTypes.Length)
            score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(expected, argumentTypes, argumentFacts)
            if score > bestScore {
                bestIndex = candidateIndex
                bestScore = score
                bestCount = 1
            } else if score >= 0 && score == bestScore {
                bestCount += 1
            }
            candidateIndex += 1
        }
        if bestCount != 1 {
            return -1
        }
        return bestIndex
    }

    static func AddDistinctConstructor(values: List<ColumnarConstructorDef>, candidate: ColumnarConstructorDef) {
        for existing in values {
            if SameObject(existing.Builder, candidate.Builder) {
                return
            }
        }
        values.Add(candidate)
    }

    static func ValidateSourceConstructor(owner: ColumnarStructDef, candidate: ColumnarConstructorDef) {
        if owner == null || candidate == null || candidate.Builder == null || candidate.ParamTypes == null || candidate.DefaultKinds == null || candidate.DefaultTexts == null || candidate.DefaultKinds.Length != candidate.ParamTypes.Length || candidate.DefaultTexts.Length != candidate.ParamTypes.Length {
            throw new InvalidOperationException("Source constructor facts must be complete and positional.")
        }
        ownerType: Type = owner.Builder
        if !ConstructorBuilderMatches(candidate.Builder, ownerType) {
            throw new InvalidOperationException("Source constructor facts do not identify their exact owner.")
        }
        index := 0
        while index < candidate.ParamTypes.Length {
            if candidate.ParamTypes[index] == null || candidate.DefaultTexts[index] == null {
                throw new InvalidOperationException("Source constructor signature facts cannot contain null values.")
            }
            index += 1
        }
    }

    static func ConstructorBuilderMatches(constructor: ConstructorInfo, ownerType: Type): bool {
        if constructor == null || ownerType == null {
            return false
        }
        declaringType := constructor.get_DeclaringType()
        return declaringType != null && ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(declaringType, ownerType)
    }

    static func PrefixTypes(values: Type[], count: int): Type[] {
        if values == null || count < 0 || count > values.Length {
            throw new InvalidOperationException("Constructor parameter prefix is invalid.")
        }
        result := new Type[](count)
        index := 0
        while index < count {
            result[index] = values[index]
            index += 1
        }
        return result
    }

    static func TrySelectRuntimeConstructor(targetType: Type, argumentCount: int, out constructor: ConstructorInfo?, out parameterTypes: Type[]): bool {
        constructor = null
        parameterTypes = new Type[](0)
        selectedParameterTypes := new Type[](0)

        if targetType == typeof(string) {
            if argumentCount == 2 {
                selectedParameterTypes = Types2(typeof(char), typeof(int))
            } else if argumentCount == 3 {
                selectedParameterTypes = Types3(typeof(char).MakeArrayType(), typeof(int), typeof(int))
            } else {
                return false
            }
        } else if targetType == typeof(StringBuilder) {
            if argumentCount == 0 {
                selectedParameterTypes = new Type[](0)
            } else if argumentCount == 1 {
                selectedParameterTypes = Types1(typeof(int))
            } else {
                return false
            }
        } else if targetType == typeof(Version) {
            if argumentCount != 4 {
                return false
            }
            selectedParameterTypes = Types4(typeof(int), typeof(int), typeof(int), typeof(int))
        } else if targetType == typeof(object) || targetType == typeof(ProcessStartInfo) || targetType == typeof(Process) || targetType == typeof(JsonSerializerOptions) || targetType == typeof(DeserializerBuilder) || targetType == typeof(MappingStart) || targetType == typeof(MappingEnd) {
            if argumentCount != 0 {
                return false
            }
            selectedParameterTypes = new Type[](0)
        } else if targetType == typeof(StreamReader) {
            if argumentCount != 1 {
                return false
            }
            selectedParameterTypes = Types1(typeof(Stream))
        } else if targetType == typeof(Scalar) {
            if argumentCount != 1 {
                return false
            }
            selectedParameterTypes = Types1(typeof(string))
        } else if IsApprovedExceptionType(targetType) {
            if argumentCount == 0 {
                selectedParameterTypes = new Type[](0)
            } else if argumentCount == 1 {
                selectedParameterTypes = Types1(typeof(string))
            } else if argumentCount == 2 {
                selectedParameterTypes = Types2(typeof(string), typeof(string))
            } else {
                return false
            }
        } else {
            return false
        }

        parameterTypes = selectedParameterTypes
        resolvedConstructor := targetType.GetConstructor(selectedParameterTypes)
        if resolvedConstructor == null {
            parameterTypes = new Type[](0)
            return false
        }
        if resolvedConstructor.get_DeclaringType() != targetType {
            throw new InvalidOperationException("Construction runtime catalog resolved a constructor on the wrong owner.")
        }
        parameters := resolvedConstructor.GetParameters()
        if parameters.Length != selectedParameterTypes.Length {
            constructor = null
            return false
        }
        index := 0
        while index < parameters.Length {
            if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(parameters[index].get_ParameterType(), selectedParameterTypes[index]) {
                constructor = null
                return false
            }
            index += 1
        }
        constructor = resolvedConstructor
        return true
    }

    static func IsApprovedExceptionType(targetType: Type): bool {
        return targetType == typeof(Exception) || targetType == typeof(InvalidOperationException) || targetType == typeof(ArgumentException) || targetType == typeof(ArgumentNullException) || targetType == typeof(ArgumentOutOfRangeException) || targetType == typeof(FormatException) || targetType == typeof(NotSupportedException) || targetType == typeof(NotImplementedException) || targetType == typeof(TimeoutException) || targetType == typeof(DivideByZeroException) || targetType == typeof(ArithmeticException) || targetType == typeof(OverflowException) || targetType == typeof(NullReferenceException) || targetType == typeof(IndexOutOfRangeException) || targetType == typeof(InvalidCastException) || targetType == typeof(FileNotFoundException) || targetType == typeof(YamlException)
    }

    static func Types1(first: Type): Type[] {
        result := new Type[](1)
        result[0] = first
        return result
    }

    static func Types2(first: Type, second: Type): Type[] {
        result := new Type[](2)
        result[0] = first
        result[1] = second
        return result
    }

    static func Types3(first: Type, second: Type, third: Type): Type[] {
        result := new Type[](3)
        result[0] = first
        result[1] = second
        result[2] = third
        return result
    }

    static func Types4(first: Type, second: Type, third: Type, fourth: Type): Type[] {
        result := new Type[](4)
        result[0] = first
        result[1] = second
        result[2] = third
        result[3] = fourth
        return result
    }

    static func CanUseConstructorDefault(nodes: ColumnarNodeTable, expectedType: Type, defaultKind: int, defaultText: string, bindings: ColumnarFragmentBindings): bool {
        if defaultKind == 46 {
            return !expectedType.get_IsValueType()
        }
        if defaultKind == 44 || defaultKind == 45 {
            return expectedType == typeof(bool)
        }
        if defaultKind == 1 {
            value := 0
            return expectedType == typeof(int) && Int32.TryParse(defaultText, out value)
        }
        if defaultKind == 4 {
            return expectedType == typeof(string)
        }
        if defaultKind != 1000 {
            return false
        }

        stringValue := ""
        intValue := 0
        return TryResolveStringEnumDefault(nodes, expectedType, defaultText, bindings, out stringValue) || TryResolveNumericEnumDefault(nodes, expectedType, defaultText, bindings, out intValue)
    }

    static func TryAppendConstructorDefault(nodes: ColumnarNodeTable, plan: ColumnarCodePlan, expectedType: Type, defaultKind: int, defaultText: string, bindings: ColumnarFragmentBindings): bool {
        if !CanUseConstructorDefault(nodes, expectedType, defaultKind, defaultText, bindings) {
            return false
        }
        if defaultKind == 46 {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
            return true
        }
        if defaultKind == 44 {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
            return true
        }
        if defaultKind == 45 {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
            return true
        }
        if defaultKind == 1 {
            intValue := 0
            if !Int32.TryParse(defaultText, out intValue) {
                return false
            }
            valueIndex := plan.AddInt32(intValue)
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
            return true
        }
        if defaultKind == 4 {
            valueIndex := plan.AddString(StringLiteralDecoder.Decode(defaultText))
            plan.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), valueIndex)
            return true
        }

        stringValue := ""
        if TryResolveStringEnumDefault(nodes, expectedType, defaultText, bindings, out stringValue) {
            valueIndex := plan.AddString(stringValue)
            plan.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), valueIndex)
            return true
        }
        intValue := 0
        if TryResolveNumericEnumDefault(nodes, expectedType, defaultText, bindings, out intValue) {
            valueIndex := plan.AddInt32(intValue)
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
            return true
        }
        return false
    }

    static func TryResolveStringEnumDefault(nodes: ColumnarNodeTable, expectedType: Type, defaultText: string, bindings: ColumnarFragmentBindings, out value: string): bool {
        value = ""
        ownerName := ""
        memberName := ""
        if !TrySplitDefaultMember(defaultText, out ownerName, out memberName) {
            return false
        }

        exactClaimed := false
        if TryResolveDeclaredStringEnumMember(expectedType, ownerName, memberName, bindings, out value, out exactClaimed) {
            return true
        }
        if exactClaimed {
            return false
        }

        ownerType := typeof(object)
        resolvedByScope := false
        if !TryResolveConstructorDefaultOwner(nodes, expectedType, ownerName, bindings, out ownerType, out resolvedByScope) {
            return false
        }
        if resolvedByScope {
            return TryResolveBoundStringEnumMember(nodes, ownerName, ownerType, memberName, bindings, out value)
        }
        if !bindings.Enums.ContainsKey(ownerName) {
            return false
        }
        definition := bindings.Enums[ownerName]
        constants := definition.StringConstants
        if constants == null || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(definition.EnumType, expectedType) || !constants.ContainsKey(memberName) {
            return false
        }
        value = constants[memberName]
        return true
    }

    static func TryResolveNumericEnumDefault(nodes: ColumnarNodeTable, expectedType: Type, defaultText: string, bindings: ColumnarFragmentBindings, out value: int): bool {
        value = 0
        ownerName := ""
        memberName := ""
        if !TrySplitDefaultMember(defaultText, out ownerName, out memberName) {
            return false
        }

        exactClaimed := false
        if TryResolveDeclaredNumericEnumMember(expectedType, ownerName, memberName, bindings, out value, out exactClaimed) {
            return true
        }
        if exactClaimed {
            return false
        }
        if expectedType.FullName == ownerName {
            return TryResolveRuntimeEnumMember(expectedType, memberName, out value)
        }

        ownerType := typeof(object)
        resolvedByScope := false
        if !TryResolveConstructorDefaultOwner(nodes, expectedType, ownerName, bindings, out ownerType, out resolvedByScope) {
            return false
        }
        if resolvedByScope {
            if TryResolveBoundNumericEnumMember(nodes, ownerName, ownerType, memberName, bindings, out value) {
                return true
            }
            return TryResolveRuntimeEnumMember(ownerType, memberName, out value)
        }

        if bindings.Enums.ContainsKey(ownerName) {
            definition := bindings.Enums[ownerName]
            if ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(definition.EnumType, expectedType) && definition.Constants.ContainsKey(memberName) {
                value = definition.Constants[memberName]
                return true
            }
        }

        if expectedType.Name != ownerName && expectedType.FullName != ownerName {
            return false
        }
        return TryResolveRuntimeEnumMember(expectedType, memberName, out value)
    }

    static func TryResolveConstructorDefaultOwner(nodes: ColumnarNodeTable, expectedType: Type, ownerName: string, bindings: ColumnarFragmentBindings, out ownerType: Type, out resolvedByScope: bool): bool {
        ownerType = expectedType
        resolvedByScope = false
        scope := nodes.BindingScope
        if scope == null {
            return true
        }

        claimed := false
        resolvedType := typeof(object)
        if scope.TryResolveExactExplicitType(ownerName, bindings, out resolvedType, out claimed) {
            resolvedByScope = true
            ownerType = resolvedType
            return ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(resolvedType, expectedType)
        }
        if claimed {
            resolvedByScope = true
            return false
        }
        return true
    }

    static func TryResolveDeclaredStringEnumMember(expectedType: Type, ownerName: string, memberName: string, bindings: ColumnarFragmentBindings, out value: string, out claimed: bool): bool {
        value = ""
        claimed = false
        selected: ColumnarEnumDef? = null
        for pair in bindings.Enums {
            definition := pair.Value
            if definition.DeclaredTypeName != ownerName {
                continue
            }
            claimed = true
            constants := definition.StringConstants
            if constants == null || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(definition.EnumType, expectedType) || !constants.ContainsKey(memberName) {
                return false
            }
            if selected != null && !SameObject(selected, definition) {
                return false
            }
            selected = definition
        }
        if selected == null || selected.StringConstants == null {
            return false
        }
        value = selected.StringConstants[memberName]
        return true
    }

    static func TryResolveDeclaredNumericEnumMember(expectedType: Type, ownerName: string, memberName: string, bindings: ColumnarFragmentBindings, out value: int, out claimed: bool): bool {
        value = 0
        claimed = false
        selected: ColumnarEnumDef? = null
        for pair in bindings.Enums {
            definition := pair.Value
            if definition.DeclaredTypeName != ownerName {
                continue
            }
            claimed = true
            if definition.IsStringBacked || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(definition.EnumType, expectedType) || !definition.Constants.ContainsKey(memberName) {
                return false
            }
            if selected != null && !SameObject(selected, definition) {
                return false
            }
            selected = definition
        }
        if selected == null {
            return false
        }
        value = selected.Constants[memberName]
        return true
    }

    static func TryResolveBoundStringEnumMember(nodes: ColumnarNodeTable, ownerName: string, ownerType: Type, memberName: string, bindings: ColumnarFragmentBindings, out value: string): bool {
        value = ""
        selected: ColumnarEnumDef? = null
        for pair in bindings.Enums {
            definition := pair.Value
            constants := definition.StringConstants
            if constants == null || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(definition.EnumType, ownerType) || !ExactScopeSelectsEnumDefinition(nodes, ownerName, definition, bindings) || !constants.ContainsKey(memberName) {
                continue
            }
            if selected != null && !SameObject(selected, definition) {
                return false
            }
            selected = definition
        }
        if selected == null || selected.StringConstants == null {
            return false
        }
        value = selected.StringConstants[memberName]
        return true
    }

    static func TryResolveBoundNumericEnumMember(nodes: ColumnarNodeTable, ownerName: string, ownerType: Type, memberName: string, bindings: ColumnarFragmentBindings, out value: int): bool {
        value = 0
        selected: ColumnarEnumDef? = null
        for pair in bindings.Enums {
            definition := pair.Value
            if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(definition.EnumType, ownerType) || !ExactScopeSelectsEnumDefinition(nodes, ownerName, definition, bindings) || !definition.Constants.ContainsKey(memberName) {
                continue
            }
            if selected != null && !SameObject(selected, definition) {
                return false
            }
            selected = definition
        }
        if selected == null {
            return false
        }
        value = selected.Constants[memberName]
        return true
    }

    static func ExactScopeSelectsEnumDefinition(nodes: ColumnarNodeTable, ownerName: string, definition: ColumnarEnumDef, bindings: ColumnarFragmentBindings): bool {
        scope := nodes.BindingScope
        if scope == null {
            return true
        }
        if definition.DeclaredTypeName == null || definition.DeclaredTypeName.Length == 0 {
            return false
        }
        candidateBindings := bindings.CreateSingleEnumTypeResolutionBindings(definition)
        candidateType := typeof(object)
        claimed := false
        if !scope.TryResolveExactExplicitType(ownerName, candidateBindings, out candidateType, out claimed) || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(candidateType, definition.EnumType) {
            return false
        }

        emptyBindings := bindings.CreateEmptySourceTypeResolutionBindings()
        typeWithoutCandidate := typeof(object)
        claimedWithoutCandidate := false
        return !scope.TryResolveExactExplicitType(ownerName, emptyBindings, out typeWithoutCandidate, out claimedWithoutCandidate) || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(typeWithoutCandidate, candidateType)
    }

    static func TryResolveRuntimeEnumMember(enumType: Type, memberName: string, out value: int): bool {
        value = 0
        if enumType is TypeBuilder || enumType.GetType().FullName == "System.Reflection.Emit.EnumBuilder" || !enumType.get_IsEnum() || Enum.GetUnderlyingType(enumType).FullName != "System.Int32" || !Enum.IsDefined(enumType, memberName) {
            return false
        }
        value = Convert.ToInt32(Enum.Parse(enumType, memberName), CultureInfo.InvariantCulture)
        return true
    }

    static func TrySplitDefaultMember(text: string, out ownerName: string, out memberName: string): bool {
        ownerName = ""
        memberName = ""
        if text == null {
            return false
        }
        separator := text.LastIndexOf(".", StringComparison.Ordinal)
        if separator <= 0 || separator + 1 >= text.Length {
            return false
        }
        ownerName = text.Substring(0, separator)
        memberName = text.Substring(separator + 1)
        return ownerName.Length > 0 && memberName.Length > 0
    }

    static func AppendArrayElementStore(plan: ColumnarCodePlan, elementType: Type) {
        if elementType == typeof(bool) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemI1())
        } else if elementType == typeof(char) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemI2())
        } else if elementType == typeof(int) || elementType == typeof(uint) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemI4())
        } else if elementType == typeof(long) || elementType == typeof(ulong) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemI8())
        } else if elementType == typeof(float) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemR4())
        } else if elementType == typeof(double) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemR8())
        } else if !elementType.get_IsValueType() && !elementType.get_IsGenericParameter() {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.StelemRef())
        } else {
            typeIndex := plan.AddType(elementType)
            plan.AppendTypeInstruction(ColumnarCodePlanContract.Stelem(), typeIndex)
        }
    }

    static func IsSupportedArrayElement(elementType: Type, bindings: ColumnarFragmentBindings): bool {
        if elementType == null || elementType.FullName == "System.Void" || elementType.get_IsByRef() || elementType.get_IsPointer() {
            return false
        }
        return ColumnarTypeOfPlanner.IsSupportedElementType(elementType, bindings)
    }

    static func TryResolveExactType(nodes: ColumnarNodeTable, canonical: string, bindings: ColumnarFragmentBindings, out resultType: Type): bool {
        claimed := false
        return TryResolveExactType(nodes, canonical, bindings, out resultType, out claimed)
    }

    static func TryResolveExactType(nodes: ColumnarNodeTable, canonical: string, bindings: ColumnarFragmentBindings, out resultType: Type, out claimed: bool): bool {
        resultType = typeof(object)
        claimed = false
        if VisibleTypeParameterHandleIsMissing(nodes, canonical, bindings) {
            claimed = true
            return false
        }
        scope := nodes.BindingScope
        return scope != null && scope.TryResolveExactExplicitTypeInContext(nodes.EnclosingTypeName, canonical, bindings, out resultType, out claimed)
    }

    // The immutable node context records the lexical type-parameter names even when a corrupt
    // mechanical caller omits their live handles. Such a spelling is blocked; exact scope must
    // never reinterpret it as a source or runtime type with the same name.
    static func VisibleTypeParameterHandleIsMissing(nodes: ColumnarNodeTable, canonical: string, bindings: ColumnarFragmentBindings): bool {
        baseName := canonical
        while baseName.EndsWith("[]", StringComparison.Ordinal) {
            baseName = baseName.Substring(0, baseName.Length - 2)
        }
        genericOpen := baseName.IndexOf("<", StringComparison.Ordinal)
        if genericOpen > 0 && baseName.EndsWith(">", StringComparison.Ordinal) {
            if VisibleTypeParameterRootIsInvalid(nodes, baseName.Substring(0, genericOpen), bindings, false) {
                return true
            }
            arguments := ColumnarTypeCanonicalizer.SplitTopLevelCommas(baseName.Substring(genericOpen + 1, baseName.Length - genericOpen - 2))
            for argument in arguments {
                if VisibleTypeParameterHandleIsMissing(nodes, argument, bindings) {
                    return true
                }
            }
            return false
        }
        return VisibleTypeParameterRootIsInvalid(nodes, baseName, bindings, true)
    }

    static func VisibleTypeParameterRootIsInvalid(nodes: ColumnarNodeTable, canonical: string, bindings: ColumnarFragmentBindings, allowExactParameter: bool): bool {
        index := 0
        while index < nodes.VisibleTypeParameterNames.Length {
            name := nodes.VisibleTypeParameterNames[index]
            if canonical == name {
                if !allowExactParameter {
                    return true
                }
                parameterType := typeof(object)
                return !bindings.TryGetTypeParameter(name, out parameterType)
            }
            if canonical.StartsWith(name + ".", StringComparison.Ordinal) {
                return true
            }
            index += 1
        }
        return false
    }

    static func TryFindSourceDefinition(targetType: Type, bindings: ColumnarFragmentBindings, out selected: ColumnarStructDef?): bool {
        selected = null
        for candidate in bindings.SourceTypeDefinitions {
            if candidate == null || candidate.Builder == null {
                throw new InvalidOperationException("Construction source-type facts cannot contain null values.")
            }
            candidateType: Type = candidate.Builder
            if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(candidateType, targetType) {
                continue
            }
            if selected != null && !SameObject(selected, candidate) {
                throw new InvalidOperationException("One exact construction target cannot map to two source definitions.")
            }
            selected = candidate
        }
        return selected != null
    }

    static func IsSourceUnionType(targetType: Type, bindings: ColumnarFragmentBindings): bool {
        selected: ColumnarUnionDef? = null
        for candidate in bindings.SourceUnionDefinitions {
            if candidate == null || candidate.Base == null {
                throw new InvalidOperationException("Construction source-union facts cannot contain null values.")
            }
            candidateType: Type = candidate.Base
            if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(candidateType, targetType) {
                continue
            }
            if selected != null && !SameObject(selected, candidate) {
                throw new InvalidOperationException("One exact construction target cannot map to two source unions.")
            }
            selected = candidate
        }
        return selected != null
    }

    static func SameObject(first: object, second: object): bool {
        return Object.ReferenceEquals(first, second)
    }

    static func ValueSyntaxIsAdmitted(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, depth: int): bool {
        candidate := UnwrapParentheses(nodes, node)
        if candidate >= 0 && nodes.Kind(candidate) == ColumnarExpressionNodeKind.NullLiteralExpression() && nodes.ChildCount(candidate) == 0 {
            return true
        }
        syntaxAdmitted := false
        if ColumnarPrimitiveBinaryPlanner.IsAdmittedSyntax(nodes, source, node, depth) {
            syntaxAdmitted = true
        } else if MayPlanRoot(nodes, node) {
            syntaxAdmitted = IsAdmittedConstructionValueSyntax(nodes, source, node, bindings, handles, depth)
        } else {
            syntaxAdmitted = ColumnarDirectCallPlanner.IsAdmittedValueSyntax(nodes, node, depth)
        }
        if !syntaxAdmitted {
            return false
        }

        scratch := new ColumnarCodePlan()
        scratch.PrepareV3()
        resultType := typeof(int)
        if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, node, bindings, handles, scratch, -1, depth, out resultType) || resultType.FullName == "System.Void" {
            return false
        }
        scratch.CompleteV3(resultType)
        ColumnarCodePlanExecutor.Validate(scratch)
        return true
    }

    // Sized arrays in this slice deliberately admit only an exact simple element spelling, with
    // any number of surrounding array suffixes. Other type families still belong to the legacy
    // whole-subtree planner because they may require target context or richer type
    // binding. A malformed node in the admitted simple/repeated-array family remains terminal.
    //  1: admitted exact syntax, 0: excluded well-formed family, -1: malformed admitted family.
    static func ClassifyExactSizedArrayElementSyntax(nodes: ColumnarNodeTable, node: int, depth: int): int {
        if nodes == null || depth > 200 || node < 0 || node >= nodes.Kinds.Length {
            return -1
        }

        kind := nodes.Kind(node)
        if kind == 0 {
            return nodes.ChildCount(node) == 0 ? 1 : -1
        }
        if kind == 2 {
            if nodes.ChildCount(node) != 1 {
                return -1
            }
            return ClassifyExactSizedArrayElementSyntax(nodes, nodes.Child(node, 0), depth + 1)
        }
        return 0
    }

    static func TryBuildTypeCanonical(nodes: ColumnarNodeTable, source: string, node: int, depth: int, out canonical: string): bool {
        canonical = ""
        if depth > 200 || node < 0 || node >= nodes.Kinds.Length {
            return false
        }
        kind := nodes.Kind(node)
        if kind == 0 {
            if nodes.ChildCount(node) != 0 {
                return false
            }
            canonical = nodes.Text(source, node)
            return canonical.Length > 0
        }
        if kind == 1 {
            childCount := nodes.ChildCount(node)
            name := nodes.Text(source, node)
            if childCount == 0 || name.Length == 0 {
                return false
            }
            builder := new StringBuilder()
            builder.Append(name)
            builder.Append("<")
            index := 0
            while index < childCount {
                if index > 0 {
                    builder.Append(",")
                }
                argument := ""
                if !TryBuildTypeCanonical(nodes, source, nodes.Child(node, index), depth + 1, out argument) {
                    return false
                }
                builder.Append(argument)
                index += 1
            }
            builder.Append(">")
            canonical = builder.ToString()
            return true
        }
        if kind == 2 || kind == 3 {
            if nodes.ChildCount(node) != 1 {
                return false
            }
            element := ""
            if !TryBuildTypeCanonical(nodes, source, nodes.Child(node, 0), depth + 1, out element) {
                return false
            }
            canonical = element + (kind == 2 ? "[]" : "?")
            return true
        }
        if kind == 4 {
            childCount := nodes.ChildCount(node)
            if childCount != 2 {
                return false
            }
            builder := new StringBuilder()
            index := 0
            while index < childCount {
                if index > 0 {
                    builder.Append("|")
                }
                arm := ""
                if !TryBuildTypeCanonical(nodes, source, nodes.Child(node, index), depth + 1, out arm) {
                    return false
                }
                builder.Append(arm)
                index += 1
            }
            canonical = builder.ToString()
            return true
        }
        if kind == 6 {
            childCount := nodes.ChildCount(node)
            if childCount < 2 || childCount > 7 {
                return false
            }
            builder := new StringBuilder()
            builder.Append("ValueTuple<")
            index := 0
            while index < childCount {
                if index > 0 {
                    builder.Append(",")
                }
                element := ""
                if !TryBuildTypeCanonical(nodes, source, nodes.Child(node, index), depth + 1, out element) {
                    return false
                }
                builder.Append(element)
                index += 1
            }
            builder.Append(">")
            canonical = builder.ToString()
            return true
        }
        if kind == 7 && nodes.ChildCount(node) == 1 {
            return TryBuildTypeCanonical(nodes, source, nodes.Child(node, 0), depth + 1, out canonical)
        }
        return false
    }

    static func ValidateOwnershipBoundary(ownership: ColumnarDirectCallOwnership, legacyWholeSubtreePlanning: bool) {
        if legacyWholeSubtreePlanning && ownership != ColumnarDirectCallOwnership.NotOwned {
            throw new InvalidOperationException("Legacy whole-subtree construction planning requires NotOwned.")
        }
    }

    static func UnwrapParentheses(nodes: ColumnarNodeTable, node: int): int {
        depth := 0
        while node >= 0 && node < nodes.Kinds.Length && nodes.Kind(node) == ColumnarExpressionNodeKind.ParenthesizedExpression() {
            if depth > 200 || nodes.ChildCount(node) != 1 {
                return -1
            }
            node = nodes.Child(node, 0)
            depth += 1
        }
        return node
    }

    static func ValidateInputs(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan) {
        if nodes == null || source == null || bindings == null || plan == null || bindings.SourceTypeDefinitions == null || bindings.SourceUnionDefinitions == null || bindings.Enums == null {
            throw new InvalidOperationException("Construction planning inputs and binding facts cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Construction planning received an invalid root node index.")
        }
    }

    static func RequiredResultType(plan: ColumnarCodePlan): Type {
        resultType := plan.ResultType
        if resultType == null {
            throw new InvalidOperationException("Planned construction expression has no result type.")
        }
        return resultType
    }
}
