namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// Prefix numeric negation over a planned method-body value. Literal operands stay with the
// byte-pinned unary-literal owner; this seam lets async state-machine bodies negate a value produced
// by a call, a hoisted local, or an await without adding a second expression path.
class ColumnarUnaryOperatorPlanner {
    static func TryAppend(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int, depth: int, allowPrimitiveBinary: bool, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = typeof(int)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        if nodes == null || source == null || bindings == null || handles == null || plan == null || !plan.IsMethodBodySchema() || depth > 200 || node < 0 || node >= nodes.Kinds.Length || nodes.Kind(node) != ColumnarExpressionNodeKind.UnaryExpression || nodes.ChildCount(node) != 1 {
            return false
        }

        operatorText := ""
        if !ColumnarPlannerSupport.TryGetNodeText(nodes, source, node, out operatorText) || operatorText != "-" {
            return false
        }
        operand := ColumnarPlannerSupport.UnwrapParenthesesInRange(nodes, nodes.Child(node, 0))
        if operand < 0 || nodes.Kind(operand) == ColumnarExpressionNodeKind.IntLiteralExpression || nodes.Kind(operand) == ColumnarExpressionNodeKind.FloatLiteralExpression {
            return false
        }

        operandType := typeof(int)
        if !ColumnarDirectCallPlanner.TryGetPlannableValueType(nodes, source, operand, bindings, handles, depth + 1, allowPrimitiveBinary, true, out operandType, out nestedOwnership) || !IsSupportedNegationType(operandType) {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        actualType := typeof(int)
        if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, operand, bindings, handles, plan, parentFragment, depth + 1, out actualType, out nestedOwnership) || !RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(actualType, operandType) {
            plan.Rollback(checkpoint)
            return false
        }

        if actualType == typeof(decimal) {
            parameterTypes := new Type[](1)
            parameterTypes[0] = typeof(decimal)
            method := typeof(decimal).GetMethod("op_UnaryNegation", parameterTypes)
            if method == null || method.DeclaringType != typeof(decimal) || !method.IsStatic || method.ReturnType != typeof(decimal) {
                plan.Rollback(checkpoint)
                return false
            }
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethodWithSignature(method, typeof(decimal), parameterTypes, typeof(decimal), true, false))
        } else {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Neg())
        }

        resultType = actualType
        return true
    }

    static func IsSupportedNegationType(valueType: Type): bool {
        return valueType == typeof(int) || valueType == typeof(long) || valueType == typeof(float) || valueType == typeof(double) || valueType == typeof(decimal)
    }
}
