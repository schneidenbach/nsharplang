namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Callback-free owner for System.Index/System.Range construction and Index/Range reads over
// strings and SZ arrays. Every accepted child is represented by its own schema-v3 fragment;
// failure rolls the complete candidate back to an empty, NotOwned plan.
class ColumnarRangeIndexPlanner {

    // Production-facing seam: the mechanical host passes only its existing live fact collections.
    // N# gates syntax/type shape before allocating bindings or resolving any reflection handle.
    static func TryEmitFromFacts(nodes: ColumnarNodeTable, source: string, node: int, parameterOrdinals: Dictionary<string, int>, parameterTypes: Dictionary<string, Type>, locals: Dictionary<string, LocalBuilder>, enums: Dictionary<string, ColumnarEnumDef>, liftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>, boxedCaptures: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>?, currentInstance: ColumnarStructDef?, enclosingTypeDefinition: ColumnarStructDef?, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>, sourceUnionDefinitions: IEnumerable<ColumnarUnionDef>, tupleNames: Dictionary<string, string[]>, enclosingNames: IEnumerable<string>, siblingNames: IEnumerable<string>, visibleLocalFunctionNames: IEnumerable<string>, plan: ColumnarCodePlan, il: ILGenerator, out nsharpOwned: bool, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        typeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
        return TryEmitFromFacts(nodes, source, node, parameterOrdinals, parameterTypes, locals, enums, liftedLocals, boxedCaptures, currentInstance, enclosingTypeDefinition, sourceTypeDefinitions, sourceUnionDefinitions, tupleNames, enclosingNames, siblingNames, visibleLocalFunctionNames, typeParameters, new Dictionary<string, Type>(StringComparer.Ordinal), false, new Dictionary<string, ColumnarSiblingCallFacts>(StringComparer.Ordinal), plan, il, out nsharpOwned, out legacyWholeSubtreePlanning, out resultType)
    }

    static func TryEmitFromFacts(nodes: ColumnarNodeTable, source: string, node: int, parameterOrdinals: Dictionary<string, int>, parameterTypes: Dictionary<string, Type>, locals: Dictionary<string, LocalBuilder>, enums: Dictionary<string, ColumnarEnumDef>, liftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>, boxedCaptures: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>?, currentInstance: ColumnarStructDef?, enclosingTypeDefinition: ColumnarStructDef?, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>, sourceUnionDefinitions: IEnumerable<ColumnarUnionDef>, tupleNames: Dictionary<string, string[]>, enclosingNames: IEnumerable<string>, siblingNames: IEnumerable<string>, visibleLocalFunctionNames: IEnumerable<string>, typeParameters: Dictionary<string, Type>, exactSourceTypes: Dictionary<string, Type>, overflowCheckingEnabled: bool, siblingCallables: Dictionary<string, ColumnarSiblingCallFacts>, plan: ColumnarCodePlan, il: ILGenerator, out nsharpOwned: bool, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ValidateFacadeRootInputs(nodes, source, node, plan)
        nsharpOwned = false
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if !FacadeRootMayNeedFacts(nodes, source, node) {
            plan.PrepareV3()
            return false
        }

        bindings := ColumnarFragmentBindings.FromRawFacts(parameterOrdinals, parameterTypes, locals, enums, liftedLocals, boxedCaptures, currentInstance, sourceTypeDefinitions, sourceUnionDefinitions, tupleNames, enclosingNames, siblingNames, visibleLocalFunctionNames, typeParameters)
        bindings.ExactSourceTypes = exactSourceTypes
        bindings.OverflowCheckingEnabled = overflowCheckingEnabled
        if siblingCallables != null {
            bindings.SiblingCallables = siblingCallables
        }

        bindings.SetEnclosingTypeDefinition(enclosingTypeDefinition)
        if ColumnarConstructionPlanner.MayPlanRoot(nodes, node) {
            return ColumnarConstructionPlanner.TryEmit(
                nodes, source, node, bindings, plan, il,
                out nsharpOwned,
                out legacyWholeSubtreePlanning,
                out resultType)
        }
        if ColumnarDirectCallPlanner.MayPlanRoot(nodes, node) {
            return ColumnarDirectCallPlanner.TryEmit(nodes, source, node, bindings, plan, il, out nsharpOwned, out legacyWholeSubtreePlanning, out resultType)
        }
        if ColumnarPrimitiveBinaryPlanner.MayPlanRoot(nodes, source, node) {
            handles := ColumnarRangeIndexHandles.Resolve()
            return ColumnarPrimitiveBinaryPlanner.TryEmitRoot(nodes, source, node, bindings, handles, plan, il, out nsharpOwned, out legacyWholeSubtreePlanning, out resultType)
        }

        if ColumnarTypeOfPlanner.MayPlanRoot(nodes, node) {
            nsharpOwned = true
            return ColumnarTypeOfPlanner.TryEmit(nodes, source, node, bindings, plan, il, out resultType)
        }

        if ColumnarBoundIdentifierPlanner.MayPlanRoot(nodes, node) {
            nsharpOwned = ColumnarBoundIdentifierPlanner.ClaimsRoot(nodes, source, node, bindings)

            return ColumnarBoundIdentifierPlanner.TryEmit(nodes, source, node, bindings, plan, il, out resultType)
        }

        if ColumnarExternalStaticMemberPlanner.MayPlanRoot(nodes, node) {
            if ColumnarExternalStaticMemberPlanner.TryEmit(nodes, source, node, bindings, plan, il, out resultType) {
                return true
            }
        }

        if ColumnarInstanceMemberPlanner.MayPlanRoot(nodes, node) {
            nsharpOwned = ColumnarInstanceMemberPlanner.ClaimsRoot(nodes, source, node, bindings)

            if nsharpOwned {
                return ColumnarInstanceMemberPlanner.TryEmit(nodes, source, node, bindings, plan, il, out resultType)
            }
        }

        if !FacadeRootMayBeOwned(nodes, source, node, bindings) {
            plan.PrepareV3()
            return false
        }

        handles := ColumnarRangeIndexHandles.Resolve()
        return TryEmit(nodes, source, node, bindings, handles, plan, il, out resultType)
    }

    static func TryGetTypeFromFacts(nodes: ColumnarNodeTable, source: string, node: int, parameterOrdinals: Dictionary<string, int>, parameterTypes: Dictionary<string, Type>, locals: Dictionary<string, LocalBuilder>, enums: Dictionary<string, ColumnarEnumDef>, liftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>, boxedCaptures: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>?, currentInstance: ColumnarStructDef?, enclosingTypeDefinition: ColumnarStructDef?, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>, sourceUnionDefinitions: IEnumerable<ColumnarUnionDef>, tupleNames: Dictionary<string, string[]>, enclosingNames: IEnumerable<string>, siblingNames: IEnumerable<string>, visibleLocalFunctionNames: IEnumerable<string>, plan: ColumnarCodePlan, out nsharpOwned: bool, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        typeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
        return TryGetTypeFromFacts(nodes, source, node, parameterOrdinals, parameterTypes, locals, enums, liftedLocals, boxedCaptures, currentInstance, enclosingTypeDefinition, sourceTypeDefinitions, sourceUnionDefinitions, tupleNames, enclosingNames, siblingNames, visibleLocalFunctionNames, typeParameters, new Dictionary<string, Type>(StringComparer.Ordinal), false, new Dictionary<string, ColumnarSiblingCallFacts>(StringComparer.Ordinal), plan, out nsharpOwned, out legacyWholeSubtreePlanning, out resultType)
    }

    static func TryGetTypeFromFacts(nodes: ColumnarNodeTable, source: string, node: int, parameterOrdinals: Dictionary<string, int>, parameterTypes: Dictionary<string, Type>, locals: Dictionary<string, LocalBuilder>, enums: Dictionary<string, ColumnarEnumDef>, liftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>, boxedCaptures: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>?, currentInstance: ColumnarStructDef?, enclosingTypeDefinition: ColumnarStructDef?, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>, sourceUnionDefinitions: IEnumerable<ColumnarUnionDef>, tupleNames: Dictionary<string, string[]>, enclosingNames: IEnumerable<string>, siblingNames: IEnumerable<string>, visibleLocalFunctionNames: IEnumerable<string>, typeParameters: Dictionary<string, Type>, exactSourceTypes: Dictionary<string, Type>, overflowCheckingEnabled: bool, siblingCallables: Dictionary<string, ColumnarSiblingCallFacts>, plan: ColumnarCodePlan, out nsharpOwned: bool, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ValidateFacadeRootInputs(nodes, source, node, plan)
        nsharpOwned = false
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if !FacadeRootMayNeedFacts(nodes, source, node) {
            plan.PrepareV3()
            return false
        }

        bindings := ColumnarFragmentBindings.FromRawFacts(parameterOrdinals, parameterTypes, locals, enums, liftedLocals, boxedCaptures, currentInstance, sourceTypeDefinitions, sourceUnionDefinitions, tupleNames, enclosingNames, siblingNames, visibleLocalFunctionNames, typeParameters)
        bindings.ExactSourceTypes = exactSourceTypes
        bindings.OverflowCheckingEnabled = overflowCheckingEnabled
        if siblingCallables != null {
            bindings.SiblingCallables = siblingCallables
        }

        bindings.SetEnclosingTypeDefinition(enclosingTypeDefinition)
        if ColumnarConstructionPlanner.MayPlanRoot(nodes, node) {
            return ColumnarConstructionPlanner.TryGetType(
                nodes, source, node, bindings, plan,
                out nsharpOwned,
                out legacyWholeSubtreePlanning,
                out resultType)
        }
        if ColumnarDirectCallPlanner.MayPlanRoot(nodes, node) {
            return ColumnarDirectCallPlanner.TryGetType(nodes, source, node, bindings, plan, out nsharpOwned, out legacyWholeSubtreePlanning, out resultType)
        }
        if ColumnarPrimitiveBinaryPlanner.MayPlanRoot(nodes, source, node) {
            handles := ColumnarRangeIndexHandles.Resolve()
            return ColumnarPrimitiveBinaryPlanner.TryGetTypeRoot(nodes, source, node, bindings, handles, plan, out nsharpOwned, out legacyWholeSubtreePlanning, out resultType)
        }

        if ColumnarTypeOfPlanner.MayPlanRoot(nodes, node) {
            nsharpOwned = true
            return ColumnarTypeOfPlanner.TryGetType(nodes, source, node, bindings, plan, out resultType)
        }

        if ColumnarBoundIdentifierPlanner.MayPlanRoot(nodes, node) {
            nsharpOwned = ColumnarBoundIdentifierPlanner.ClaimsRoot(nodes, source, node, bindings)

            return ColumnarBoundIdentifierPlanner.TryGetType(nodes, source, node, bindings, plan, out resultType)
        }

        if ColumnarExternalStaticMemberPlanner.MayPlanRoot(nodes, node) {
            if ColumnarExternalStaticMemberPlanner.TryGetType(nodes, source, node, bindings, plan, out resultType) {
                return true
            }
        }

        if ColumnarInstanceMemberPlanner.MayPlanRoot(nodes, node) {
            nsharpOwned = ColumnarInstanceMemberPlanner.ClaimsRoot(nodes, source, node, bindings)

            if nsharpOwned {
                return ColumnarInstanceMemberPlanner.TryGetType(nodes, source, node, bindings, plan, out resultType)
            }
        }

        if !FacadeRootMayBeOwned(nodes, source, node, bindings) {
            plan.PrepareV3()
            return false
        }

        handles := ColumnarRangeIndexHandles.Resolve()
        return TryGetType(nodes, source, node, bindings, handles, plan, out resultType)
    }

    static func TryEmit(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, il: ILGenerator, out resultType: Type): bool {
        if Plan(nodes, source, node, bindings, handles, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
        return true
    }

    static func TryGetType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, out resultType: Type): bool {
        if Plan(nodes, source, node, bindings, handles, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        resultType = RequiredResultType(plan)
        return true
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
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
        try {
            resultType := typeof(int)
            if !TryAppendPlannableValue(nodes, source, candidate, bindings, handles, plan, -1, 0, out resultType) || !RootResultMatches(nodes, source, candidate, resultType) {
                plan.Rollback(checkpoint)
                return plan.Status
            }

            plan.CompleteV3(resultType)
            return plan.Status
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    static func ValidateFacadeRootInputs(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan) {
        if nodes == null || source == null || plan == null {
            throw new InvalidOperationException("Range/index raw planning inputs cannot be null.")
        }

        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Range/index raw planning received an invalid root node index.")
        }
    }

    static func FacadeRootMayNeedFacts(nodes: ColumnarNodeTable, source: string, node: int): bool {
        node = UnwrapParentheses(nodes, node)
        if node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.NewExpression()
            || kind == ColumnarExpressionNodeKind.ObjectInitializerExpression()
            || kind == ColumnarExpressionNodeKind.ArrayLiteralExpression() {
            return true
        }
        if kind == ColumnarExpressionNodeKind.CallExpression() {
            return true
        }

        if kind == ColumnarExpressionNodeKind.RangeExpression() {
            return true
        }

        if kind == ColumnarExpressionNodeKind.UnaryExpression() {
            return nodes.ChildCount(node) == 1 && nodes.Text(source, node) == "^"
        }

        if kind == ColumnarExpressionNodeKind.MemberAccessExpression() {
            return true
        }

        if kind == ColumnarExpressionNodeKind.TypeOfExpression() {
            return true
        }

        if kind == ColumnarExpressionNodeKind.IdentifierExpression() {
            return true
        }

        if kind == ColumnarExpressionNodeKind.BinaryExpression() {
            return ColumnarPrimitiveBinaryPlanner.MayPlanRoot(nodes, source, node)
        }

        if kind != ColumnarExpressionNodeKind.IndexAccessExpression() || nodes.ChildCount(node) != 2 {
            return false
        }

        return FacadeSelectorMayNeedFacts(nodes, source, nodes.Child(node, 1), 0)
    }

    static func FacadeSelectorMayNeedFacts(nodes: ColumnarNodeTable, source: string, node: int, depth: int): bool {
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
            return nodes.ChildCount(node) == 0
        }

        if kind == ColumnarExpressionNodeKind.MemberAccessExpression() {
            return nodes.ChildCount(node) == 1
        }

        if kind == ColumnarExpressionNodeKind.TernaryExpression() && nodes.ChildCount(node) == 3 {
            return FacadeSelectorMayNeedFacts(nodes, source, nodes.Child(node, 1), depth + 1) && FacadeSelectorMayNeedFacts(nodes, source, nodes.Child(node, 2), depth + 1)
        }

        return false
    }

    static func FacadeRootMayBeOwned(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings): bool {
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

        if kind != ColumnarExpressionNodeKind.IndexAccessExpression() || nodes.ChildCount(node) != 2 {
            return false
        }

        return FacadeSelectorMayProduceIndexOrRange(nodes, source, nodes.Child(node, 1), bindings, 0)
    }

    static func FacadeSelectorMayProduceIndexOrRange(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, depth: int): bool {
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
            resultType := typeof(int)
            return ColumnarBoundIdentifierPlanner.TryGetBoundType(nodes, source, node, bindings, out resultType) && (resultType == typeof(Index) || resultType == typeof(Range))
        }

        if kind == ColumnarExpressionNodeKind.MemberAccessExpression() && nodes.ChildCount(node) == 1 {
            memberPlan := new ColumnarCodePlan()
            memberType := typeof(int)
            return ColumnarInstanceMemberPlanner.ClaimsRoot(nodes, source, node, bindings) && ColumnarInstanceMemberPlanner.TryGetType(nodes, source, node, bindings, memberPlan, out memberType) && (memberType == typeof(Index) || memberType == typeof(Range))
        }

        if kind == ColumnarExpressionNodeKind.TernaryExpression() && nodes.ChildCount(node) == 3 {
            return FacadeSelectorMayProduceIndexOrRange(nodes, source, nodes.Child(node, 1), bindings, depth + 1) && FacadeSelectorMayProduceIndexOrRange(nodes, source, nodes.Child(node, 2), bindings, depth + 1)
        }

        return false
    }

    static func IsRootCandidate(nodes: ColumnarNodeTable, source: string, node: int): bool {
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.RangeExpression() || kind == ColumnarExpressionNodeKind.IndexAccessExpression() {
            return true
        }

        return kind == ColumnarExpressionNodeKind.UnaryExpression() && nodes.ChildCount(node) == 1 && nodes.Text(source, node) == "^"
    }

    static func RootResultMatches(nodes: ColumnarNodeTable, source: string, node: int, resultType: Type): bool {
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.UnaryExpression() && nodes.Text(source, node) == "^" {
            return resultType == typeof(Index)
        }

        if kind == ColumnarExpressionNodeKind.RangeExpression() {
            return resultType == typeof(Range)
        }

        return kind == ColumnarExpressionNodeKind.IndexAccessExpression()
    }

    static func TryAppendPlannableValue(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int, depth: int, out resultType: Type): bool {
        nestedOwnership := ColumnarDirectCallOwnership.NotOwned
        return TryAppendPlannableValue(nodes, source, node, bindings, handles, plan, parentFragment, depth, out resultType, out nestedOwnership)
    }

    static func TryAppendPlannableValue(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int, depth: int, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        return TryAppendPlannableValueCore(
            nodes, source, node, bindings, handles, plan,
            parentFragment, depth, false,
            out resultType, out nestedOwnership)
    }

    static func TryAppendConstructionValue(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int, depth: int, out resultType: Type): bool {
        nestedOwnership := ColumnarDirectCallOwnership.NotOwned
        return TryAppendConstructionValue(
            nodes, source, node, bindings, handles, plan,
            parentFragment, depth,
            out resultType, out nestedOwnership)
    }

    static func TryAppendConstructionValue(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int, depth: int, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        return TryAppendPlannableValueCore(
            nodes, source, node, bindings, handles, plan,
            parentFragment, depth, true,
            out resultType, out nestedOwnership)
    }

    static func TryAppendPlannableValueCore(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int, depth: int, allowPrimitiveBinary: bool, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = typeof(int)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
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

        if kind == ColumnarExpressionNodeKind.IntLiteralExpression() || kind == ColumnarExpressionNodeKind.FloatLiteralExpression() || kind == ColumnarExpressionNodeKind.CharLiteralExpression() || kind == ColumnarExpressionNodeKind.StringLiteralExpression() {
            planned = ColumnarScalarLiteralPlanner.TryAppendLiteral(nodes, source, node, plan, out resultType)
        } else if kind == ColumnarExpressionNodeKind.NameOfExpression() {
            planned = ColumnarNameOfPlanner.TryAppendNameOf(nodes, source, node, plan, out resultType)
        } else if kind == ColumnarExpressionNodeKind.TypeOfExpression() {
            planned = ColumnarTypeOfPlanner.TryAppendTypeOf(nodes, source, node, bindings, plan, out resultType)
        } else if kind == ColumnarExpressionNodeKind.BoolLiteralExpression() {
            planned = TryPlanBooleanLiteral(nodes, source, node, plan, out resultType)
        } else if kind == ColumnarExpressionNodeKind.IdentifierExpression() {
            planned = ColumnarBoundIdentifierPlanner.TryAppend(nodes, source, node, bindings, plan, out resultType)
        } else if kind == ColumnarExpressionNodeKind.MemberAccessExpression() {
            planned = TryPlanEnumMember(nodes, source, node, bindings, plan, out resultType)
            if !planned {
                planned = ColumnarExternalStaticMemberPlanner.TryAppendStaticMember(nodes, source, node, bindings, plan, out resultType)
            }

            if !planned {
                planned = ColumnarInstanceMemberPlanner.TryAppend(nodes, source, node, bindings, plan, fragment, out resultType)
            }
        } else if kind == ColumnarExpressionNodeKind.CallExpression() {
            ownership := ColumnarDirectCallOwnership.NotOwned
            _legacyWholeSubtreePlanning := false
            planned = ColumnarDirectCallPlanner.TryAppendCall(nodes, source, node, bindings, handles, plan, fragment, depth, out ownership, out _legacyWholeSubtreePlanning, out resultType)

            if !planned && ownership == ColumnarDirectCallOwnership.OwnedRejected {
                nestedOwnership = ColumnarDirectCallOwnership.OwnedRejected
            }
        } else if allowPrimitiveBinary
            && kind == ColumnarExpressionNodeKind.BinaryExpression() {
            planned = ColumnarPrimitiveBinaryPlanner.TryAppend(
                nodes, source, node, bindings, handles, plan,
                fragment, depth,
                out resultType,
                out nestedOwnership)
        } else if kind == ColumnarExpressionNodeKind.NewExpression()
            || kind == ColumnarExpressionNodeKind.ObjectInitializerExpression()
            || kind == ColumnarExpressionNodeKind.ArrayLiteralExpression() {
            ownership := ColumnarDirectCallOwnership.NotOwned
            _legacyWholeSubtreePlanning := false
            planned = ColumnarConstructionPlanner.TryAppend(
                nodes, source, node, bindings, handles, plan,
                fragment, depth,
                out ownership,
                out _legacyWholeSubtreePlanning,
                out resultType)
            if !planned
                && ownership == ColumnarDirectCallOwnership.OwnedRejected {
                nestedOwnership = ColumnarDirectCallOwnership.OwnedRejected
            }
        } else if kind == ColumnarExpressionNodeKind.UnaryExpression() {
            planned = ColumnarUnaryLiteralPlanner.TryAppendUnaryLiteral(nodes, source, node, plan, fragment, out resultType)

            if !planned {
                planned = TryPlanFromEnd(nodes, source, node, bindings, handles, plan, fragment, depth, out resultType, out nestedOwnership)
            }
        } else if kind == ColumnarExpressionNodeKind.CastExpression() {
            planned = TryPlanNumericCast(nodes, source, node, bindings, handles, plan, fragment, depth, out resultType, out nestedOwnership)
        } else if kind == ColumnarExpressionNodeKind.RangeExpression() {
            planned = TryPlanRange(nodes, source, node, bindings, handles, plan, fragment, depth, out resultType, out nestedOwnership)
        } else if kind == ColumnarExpressionNodeKind.TernaryExpression() {
            planned = TryPlanTernary(nodes, source, node, bindings, handles, plan, fragment, depth, out resultType, out nestedOwnership)
        } else if kind == ColumnarExpressionNodeKind.IndexAccessExpression() {
            planned = TryPlanIndexAccess(nodes, source, node, bindings, handles, plan, fragment, depth, parentFragment >= 0, out resultType, out nestedOwnership)
        }

        if !planned {
            plan.Rollback(checkpoint)
            return false
        }

        plan.CompleteFragment(fragment, resultType)
        return true
    }

    static func TryPlanBooleanLiteral(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, out resultType: Type): bool {
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

    static func TryPlanEnumMember(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        if nodes.ChildCount(node) != 1 {
            return false
        }

        qualifiedOwner := ""
        rootName := ""
        if !TryGetQualifiedName(nodes, source, nodes.Child(node, 0), 0, out qualifiedOwner, out rootName) || bindings.IsValueBinding(rootName) || bindings.IsCallable(rootName) || !bindings.Enums.ContainsKey(qualifiedOwner) {
            return false
        }

        enumDefinition := bindings.Enums[qualifiedOwner]
        memberName := nodes.Text(source, node)
        if enumDefinition == null || enumDefinition.IsStringBacked || !enumDefinition.Constants.ContainsKey(memberName) {
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

    // Explicit numeric cast `(<builtin>) operand` — the Conv-opcode slice of the legacy case-16
    // table. Children are [typeRoot, operand]; the type root must be a Simple type reference whose
    // name is one of the eleven castable numeric builtins (decimal stays legacy-owned: it converts
    // through System.Decimal operator statics, not conv opcodes, exactly like enum, user-defined,
    // reference, and interface casts). The opcode is TARGET-driven and mirrors the legacy emitter
    // exactly, including its i4-slot no-ops: an int/uint target over an i4-slot source emits no
    // instruction, so that shape is claimable only for int/char literal operands, whose known
    // literal value the fragment boundary can refine; an exact-typed i4-slot source declines.
    static func TryPlanNumericCast(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = typeof(int)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        if nodes.ChildCount(node) != 2 {
            return false
        }

        typeNode := nodes.Child(node, 0)
        // Type-reference nodes use the type-kernel encoding: 0 = SimpleTypeReference. Generic,
        // array, nullable, and every other type form stays with the legacy cast owner.
        if typeNode < 0 || typeNode >= nodes.Kinds.Length || nodes.Kind(typeNode) != 0 {
            return false
        }

        targetType := typeof(int)
        if !TryResolveNumericCastTarget(nodes.Text(source, typeNode), out targetType) {
            return false
        }

        operandNode := UnwrapParentheses(nodes, nodes.Child(node, 1))
        if operandNode < 0 || operandNode >= nodes.Kinds.Length {
            return false
        }

        // The i4-slot no-op branch: an int/uint target over an int or char literal emits only the
        // literal itself. Plan the literal directly into this open cast fragment so its known
        // Int32 value survives to the fragment boundary, which refines it to the declared target.
        if (targetType == typeof(int) || targetType == typeof(uint))
            && IsI4LiteralOperand(nodes, source, operandNode) {
            operandType := typeof(int)
            if !ColumnarScalarLiteralPlanner.TryAppendLiteral(nodes, source, operandNode, plan, out operandType) {
                return false
            }
            if operandType != typeof(int) && operandType != typeof(char) {
                return false
            }
            resultType = targetType
            return true
        }

        operandType := typeof(int)
        if !TryAppendPlannableValue(nodes, source, operandNode, bindings, handles, plan, fragment, depth + 1, out operandType, out nestedOwnership) {
            return false
        }

        if !ColumnarNumericFacts.IsCastableScalar(operandType) || operandType == typeof(decimal) {
            return false
        }

        // An identity cast emits nothing, which would seal this cast fragment over exactly its
        // operand child fragment's rows — a shape the plan schema forbids. Identity casts over
        // literal operands ride the direct-literal path above; every other identity stays with
        // the legacy owner.
        if operandType == targetType {
            return false
        }

        // The legacy target-driven opcode table. A non-identity ushort target shares conv.u2 with
        // char but the validation stack models conv.u2 as char, so that form stays legacy-owned.
        if targetType == typeof(double) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvR8())
        } else if targetType == typeof(float) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvR4())
        } else if targetType == typeof(long) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI8())
        } else if targetType == typeof(ulong) {
            // N# unchecked: int sign-extends, uint zero-extends — exactly the legacy selection.
            if operandType == typeof(uint) {
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvU8())
            } else {
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI8())
            }
        } else if targetType == typeof(char) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvU2())
        } else if targetType == typeof(byte) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvU1())
        } else if targetType == typeof(sbyte) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI1())
        } else if targetType == typeof(short) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI2())
        } else if (targetType == typeof(int) || targetType == typeof(uint))
            && (operandType == typeof(long) || operandType == typeof(ulong)
                || operandType == typeof(double) || operandType == typeof(float)) {
            if targetType == typeof(uint) {
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvU4())
            } else {
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
            }
        } else {
            // int/uint targets over exact i4-slot sources are the legacy no-op branch (no opcode,
            // reinterpreted slot); without a known literal the fragment boundary cannot prove the
            // reinterpretation, so the whole cast stays legacy-owned.
            return false
        }

        resultType = targetType
        return true
    }

    // The eleven builtin numeric cast targets the Conv-opcode table serves. decimal is excluded
    // by scope ruling; bool, string, object, and every non-numeric builtin never reach this arm.
    static func TryResolveNumericCastTarget(name: string, out targetType: Type): bool {
        targetType = typeof(int)
        if name == "int" { targetType = typeof(int) }
        else if name == "long" { targetType = typeof(long) }
        else if name == "uint" { targetType = typeof(uint) }
        else if name == "ulong" { targetType = typeof(ulong) }
        else if name == "short" { targetType = typeof(short) }
        else if name == "ushort" { targetType = typeof(ushort) }
        else if name == "byte" { targetType = typeof(byte) }
        else if name == "sbyte" { targetType = typeof(sbyte) }
        else if name == "char" { targetType = typeof(char) }
        else if name == "float" { targetType = typeof(float) }
        else if name == "double" { targetType = typeof(double) }
        else { return false }
        return true
    }

    // An operand whose literal lowering is a single known Int32 stack value: a char literal, or an
    // int literal with no suffix (an l/u/m suffix selects the Int64, UInt64, or Decimal lowering).
    static func IsI4LiteralOperand(nodes: ColumnarNodeTable, source: string, node: int): bool {
        kind := nodes.Kind(node)
        if nodes.ChildCount(node) != 0 {
            return false
        }
        if kind == ColumnarExpressionNodeKind.CharLiteralExpression() {
            return true
        }
        if kind != ColumnarExpressionNodeKind.IntLiteralExpression() {
            return false
        }
        text := nodes.Text(source, node)
        if text.Length == 0 {
            return false
        }
        last := text[text.Length - 1]
        return last != 'l' && last != 'L' && last != 'u' && last != 'U'
            && last != 'm' && last != 'M'
    }

    static func TryPlanFromEnd(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = typeof(Index)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        if nodes.ChildCount(node) != 1 || nodes.Text(source, node) != "^" {
            return false
        }

        operandType := typeof(int)
        if !TryAppendPlannableValue(nodes, source, nodes.Child(node, 0), bindings, handles, plan, fragment, depth + 1, out operandType, out nestedOwnership) || !ConvertIndexOperand(plan, operandType) {
            return false
        }

        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
        constructorIndex := plan.AddConstructor(handles.IndexConstructor)
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
        return true
    }

    static func TryPlanRange(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = typeof(Range)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        startNode := -1
        endNode := -1
        if !TryGetRangeEndpoints(nodes, node, out startNode, out endNode) {
            return false
        }

        if startNode < 0 {
            EmitDefaultIndex(plan, handles, false)
        } else if !TryPlanIndexValue(nodes, source, startNode, bindings, handles, plan, fragment, depth + 1, out nestedOwnership) {
            return false
        }

        if endNode < 0 {
            EmitDefaultIndex(plan, handles, true)
        } else if !TryPlanIndexValue(nodes, source, endNode, bindings, handles, plan, fragment, depth + 1, out nestedOwnership) {
            return false
        }

        constructorIndex := plan.AddConstructor(handles.RangeConstructor)
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
        return true
    }

    static func TryPlanIndexValue(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int, depth: int, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        valueType := typeof(int)
        if !TryAppendPlannableValue(nodes, source, node, bindings, handles, plan, parentFragment, depth, out valueType, out nestedOwnership) {
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

        if !ColumnarNumericFacts.IsIntPromotable(operandType) && (!operandType.get_IsEnum() || operandType.GetEnumUnderlyingType() != typeof(int)) {
            return false
        }

        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
        return true
    }

    static func EmitDefaultIndex(plan: ColumnarCodePlan, handles: ColumnarRangeIndexHandles, fromEnd: bool) {
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
        if fromEnd {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
        } else {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
        }

        constructorIndex := plan.AddConstructor(handles.IndexConstructor)
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
    }

    static func TryPlanTernary(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = typeof(int)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        if nodes.ChildCount(node) != 3 {
            return false
        }

        conditionType := typeof(bool)
        if !TryAppendPlannableValue(nodes, source, nodes.Child(node, 0), bindings, handles, plan, fragment, depth + 1, out conditionType, out nestedOwnership) || conditionType != typeof(bool) {
            return false
        }

        falseLabel := plan.DefineLabel()
        endLabel := plan.DefineLabel()
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), falseLabel)

        whenTrueType := typeof(int)
        if !TryAppendPlannableValue(nodes, source, nodes.Child(node, 1), bindings, handles, plan, fragment, depth + 1, out whenTrueType, out nestedOwnership) {
            return false
        }

        plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), endLabel)
        plan.AppendMarkLabel(falseLabel)

        whenFalseType := typeof(int)
        if !TryAppendPlannableValue(nodes, source, nodes.Child(node, 2), bindings, handles, plan, fragment, depth + 1, out whenFalseType, out nestedOwnership) || whenTrueType != whenFalseType {
            return false
        }

        plan.AppendMarkLabel(endLabel)
        resultType = whenTrueType
        return true
    }

    static func TryPlanIndexAccess(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, allowOrdinaryIntIndex: bool, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = typeof(int)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        if nodes.ChildCount(node) != 2 {
            return false
        }

        indexedType := typeof(int)
        if !TryAppendPlannableValue(nodes, source, nodes.Child(node, 0), bindings, handles, plan, fragment, depth + 1, out indexedType, out nestedOwnership) {
            return false
        }

        isString := indexedType == typeof(string)
        if !isString && !indexedType.get_IsSZArray() {
            return false
        }

        accessType := typeof(int)
        if !TryAppendPlannableValue(nodes, source, nodes.Child(node, 1), bindings, handles, plan, fragment, depth + 1, out accessType, out nestedOwnership) {
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

    static func PlanStringOrdinaryIndex(plan: ColumnarCodePlan, handles: ColumnarRangeIndexHandles, out resultType: Type): bool {
        charsGetter := plan.AddMethod(handles.StringCharsGetter)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), charsGetter)
        resultType = typeof(char)
        return true
    }

    static func PlanArrayOrdinaryIndex(plan: ColumnarCodePlan, arrayType: Type, out resultType: Type): bool {
        elementType := arrayType.GetElementType()
        if elementType == null {
            resultType = typeof(int)
            return false
        }

        AppendArrayElementLoad(plan, elementType)
        resultType = elementType
        return true
    }

    static func PlanStringIndex(plan: ColumnarCodePlan, handles: ColumnarRangeIndexHandles, out resultType: Type): bool {
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

    static func PlanStringRange(plan: ColumnarCodePlan, handles: ColumnarRangeIndexHandles, out resultType: Type): bool {
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

    static func PlanArrayIndex(plan: ColumnarCodePlan, handles: ColumnarRangeIndexHandles, arrayType: Type, out resultType: Type): bool {
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

    static func PlanArrayRange(plan: ColumnarCodePlan, handles: ColumnarRangeIndexHandles, arrayType: Type, out resultType: Type): bool {
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

    static func TryGetRangeEndpoints(nodes: ColumnarNodeTable, node: int, out startNode: int, out endNode: int): bool {
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
            return startNode >= 0 && startNode < nodes.Kinds.Length && endNode >= 0 && endNode < nodes.Kinds.Length
        }

        return false
    }

    static func TryGetQualifiedName(nodes: ColumnarNodeTable, source: string, node: int, depth: int, out qualifiedName: string, out rootName: string): bool {
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

        if kind != ColumnarExpressionNodeKind.MemberAccessExpression() || nodes.ChildCount(node) != 1 {
            return false
        }

        prefix := ""
        if !TryGetQualifiedName(nodes, source, nodes.Child(node, 0), depth + 1, out prefix, out rootName) {
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
        while node >= 0 && node < nodes.Kinds.Length && nodes.Kind(node) == ColumnarExpressionNodeKind.ParenthesizedExpression() {
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
