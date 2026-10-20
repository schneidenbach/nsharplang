namespace NSharpLang.Compiler.Columnar

import System


// The value-producing `as` expression used by schema-v4 method bodies. A failed reference test
// leaves null; a successful reference test leaves the narrowed reference; a Nullable<T> target
// unwraps the `isinst` result with `unbox.any`, which produces the empty nullable on a miss.
class ColumnarTypeTestPlanner {
    static func TryAppendAs(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, allowPrimitiveBinary: bool, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = typeof(int)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        if nodes == null || source == null || bindings == null || handles == null || plan == null || !plan.IsMethodBodySchema() || depth > 200 || node < 0 || node >= nodes.Kinds.Length || nodes.Kind(node) != ColumnarExpressionNodeKind.AsExpression || nodes.ChildCount(node) != 2 {
            return false
        }

        canonical := ""
        targetNode := nodes.Child(node, 1)
        if !ColumnarTypeOfPlanner.TryBuildTypeCanonical(nodes, source, targetNode, 0, out canonical) {
            return false
        }
        targetType := typeof(object)
        if !ColumnarConstructionPlanner.TryResolveExactType(nodes, canonical, bindings, out targetType) || !IsSupportedAsTarget(targetType) {
            return false
        }

        valueType := typeof(int)
        if !ColumnarRangeIndexPlanner.TryAppendPlannableValueCore(nodes, source, nodes.Child(node, 0), bindings, handles, plan, fragment, depth + 1, allowPrimitiveBinary, out valueType, out nestedOwnership) {
            return false
        }
        if RequiresBoxBeforeReferenceTest(valueType, bindings) {
            boxTypeIndex := plan.AddType(valueType)
            plan.AppendTypeInstruction(ColumnarCodePlanContract.Box(), boxTypeIndex)
        }
        targetTypeIndex := plan.AddType(targetType)
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Isinst(), targetTypeIndex)
        if ColumnarTypeOfPlanner.IsSupportedNullable(targetType) {
            plan.AppendTypeInstruction(ColumnarCodePlanContract.UnboxAny(), targetTypeIndex)
        }
        resultType = targetType
        return true
    }

    static func IsSupportedAsTarget(targetType: Type): bool {
        if targetType == null || targetType.IsByRef || targetType.IsPointer || targetType.IsGenericParameter || targetType.IsGenericTypeDefinition || targetType.FullName == "System.Void" {
            return false
        }
        if ColumnarTypeOfPlanner.IsSupportedNullable(targetType) {
            return ColumnarTypeOfPlanner.IsSupportedType(targetType.GetGenericArguments()[0])
        }
        return !targetType.IsValueType
    }

    static func RequiresBoxBeforeReferenceTest(valueType: Type, bindings: ColumnarFragmentBindings): bool {
        if valueType == null {
            return false
        }
        sourceType := valueType
        if valueType.IsGenericType && !valueType.IsGenericTypeDefinition {
            try {
                sourceType = valueType.GetGenericTypeDefinition()
            } catch ex: NotSupportedException {
            } catch ex: NotImplementedException {
            }
        }
        for sourceDefinition in bindings.SourceTypeDefinitions {
            if Object.ReferenceEquals(sourceDefinition.Builder, sourceType) {
                return !sourceDefinition.IsReference
            }
        }
        return valueType.IsValueType || valueType.IsGenericParameter || RuntimeTypeShapeFacts.IsEnumType(valueType)
    }
}
