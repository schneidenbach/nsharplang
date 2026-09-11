namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler


// Callback-free owner for prefix operators whose operand is an exact scalar literal. The unary
// and operand nodes keep distinct schema-v3 fragments, so recursive range/index plans preserve
// the same source ownership and validation boundary as standalone unary roots.
class ColumnarUnaryLiteralPlanner {
    static func TryEmit(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, il: ILGenerator, out resultType: Type): bool {
        if Plan(nodes, source, node, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
        return true
    }

    static func TryGetType(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, out resultType: Type): bool {
        if Plan(nodes, source, node, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        resultType = RequiredResultType(plan)
        return true
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        ValidateRootInputs(nodes, source, node, plan)
        plan.PrepareV3()
        resultType := typeof(int)
        if !TryAppendRoot(nodes, source, node, plan, out resultType) {
            return plan.Status
        }

        plan.CompleteV3(resultType)
        return plan.Status
    }

    // THE ROOT-APPEND SEQUENCE, OWNED ONCE (015-B6). A unary literal root is a checkpoint, a root
    // fragment, the append, and the fragment's completion — the same four steps whether the plan is a
    // standalone schema-v3 expression (`Plan` wraps this between `PrepareV3` and `CompleteV3`) or an
    // open schema-v4 METHOD BODY (`ColumnarMethodBodyPlanner`'s expression door calls it directly).
    // Both callers therefore produce the SAME row sequence, which is the whole of producing the same
    // bytes: the emitter's `EmitExpressionCore` reaches this owner's `TryEmit` ahead of every other
    // route, so a body the door claims here cannot diverge from the body the host would have emitted.
    // A decline rolls the plan back to the caller's exact state and opens no fragment.
    static func TryAppendRoot(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        if nodes == null || source == null || plan == null || node < 0 || node >= nodes.Kinds.Length || nodes.Kind(node) != ColumnarExpressionNodeKind.UnaryExpression() {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        fragment := plan.BeginFragment(-1, ColumnarExpressionNodeKind.UnaryExpression(), node)
        if !TryAppendUnaryLiteral(nodes, source, node, plan, fragment, out resultType) {
            plan.Rollback(checkpoint)
            return false
        }

        plan.CompleteFragment(fragment, resultType)
        return true
    }

    // Append one admitted unary literal to an already-open parent fragment. A decline rolls back
    // the nested operand fragment and every pool row it introduced.
    static func TryAppendUnaryLiteral(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, parentFragment: int, out resultType: Type): bool {
        ValidateAppendInputs(nodes, source, node, plan, parentFragment)
        resultType = typeof(int)
        if nodes.Kind(node) != ColumnarExpressionNodeKind.UnaryExpression() || nodes.ChildCount(node) != 1 {
            return false
        }

        operatorText := ""
        if !TryGetNodeText(nodes, source, node, out operatorText) || (operatorText != "-" && operatorText != "~" && operatorText != "!") {
            return false
        }

        operand := nodes.Child(node, 0)
        if operand < 0 || operand >= nodes.Kinds.Length {
            return false
        }
        operandKind := nodes.Kind(operand)
        if operatorText == "!" {
            if operandKind != ColumnarExpressionNodeKind.BoolLiteralExpression() {
                return false
            }
        } else if operandKind != ColumnarExpressionNodeKind.IntLiteralExpression() && (operatorText != "-" || operandKind != ColumnarExpressionNodeKind.FloatLiteralExpression()) {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        operandFragment := plan.BeginFragment(parentFragment, operandKind, operand)
        operandType := typeof(int)
        planned := false
        if operatorText == "!" {
            planned = TryAppendBoolean(nodes, source, operand, plan)
            operandType = typeof(bool)
        } else if operatorText == "-" {
            planned = TryAppendMinimumMagnitude(nodes, source, operand, plan, out operandType)
            if !planned {
                planned = ColumnarScalarLiteralPlanner.TryAppendLiteral(nodes, source, operand, plan, out operandType) && (operandType == typeof(int) || operandType == typeof(long) || operandType == typeof(float) || operandType == typeof(double) || operandType == typeof(decimal))
            }
        } else {
            planned = ColumnarScalarLiteralPlanner.TryAppendLiteral(nodes, source, operand, plan, out operandType) && (operandType == typeof(int) || operandType == typeof(long) || operandType == typeof(ulong))
        }

        if !planned {
            plan.Rollback(checkpoint)
            return false
        }

        plan.CompleteFragment(operandFragment, operandType)
        resultType = operandType
        if operatorText == "-" {
            // Decimal is not an IL primitive: neg is invalid over its value, so negation calls
            // the System.Decimal op_UnaryNegation static, exactly like the legacy unary arm.
            if operandType == typeof(decimal) {
                parameterTypes := new Type[](1)
                parameterTypes[0] = typeof(decimal)
                methodIndex := plan.AddMethodWithSignature(RequiredDecimalNegation(parameterTypes), typeof(decimal), parameterTypes, typeof(decimal), true, false)
                plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
            } else {
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Neg())
            }
        } else if operatorText == "~" {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Not())
        } else {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
            resultType = typeof(bool)
        }
        return true
    }

    static func TryAppendBoolean(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan): bool {
        text := ""
        if nodes.ChildCount(node) != 0 || !TryGetNodeText(nodes, source, node, out text) {
            return false
        }
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

    static func TryAppendMinimumMagnitude(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        text := ""
        if nodes.Kind(node) != ColumnarExpressionNodeKind.IntLiteralExpression() || nodes.ChildCount(node) != 0 || !TryGetNodeText(nodes, source, node, out text) {
            return false
        }
        suffix := NumericLiteralFacts.GetIntegerSuffix(text)
        magnitude := 0UL
        if suffix.HasUnsigned || suffix.HasLong || !NumericLiteralFacts.TryParseUnsignedIntegerMagnitude(text, out magnitude) || magnitude != 2147483648UL {
            return false
        }

        valueIndex := plan.AddInt32(-2147483648)
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
        return true
    }

    static func RequiredDecimalNegation(parameterTypes: Type[]): MethodInfo {
        method := typeof(decimal).GetMethod("op_UnaryNegation", parameterTypes)
        if method == null || method.get_DeclaringType() != typeof(decimal) || !method.get_IsStatic() || method.get_IsGenericMethod() || method.get_ReturnType() != typeof(decimal) {
            throw new InvalidOperationException("Required CLR method Decimal.op_UnaryNegation(Decimal) was not found exactly.")
        }
        parameters := method.GetParameters()
        if parameters.Length != 1 || parameters[0].get_ParameterType() != typeof(decimal) {
            throw new InvalidOperationException("Decimal.op_UnaryNegation(Decimal) has an unexpected runtime signature.")
        }
        return method
    }

    static func TryGetNodeText(nodes: ColumnarNodeTable, source: string, node: int, out text: string): bool {
        text = ""
        start := nodes.ValueStart(node)
        length := nodes.ValueLengths[node]
        if start < 0 || length <= 0 || length > source.Length || start > source.Length - length {
            return false
        }
        text = source.Substring(start, length)
        return true
    }

    static func ValidateRootInputs(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan) {
        if nodes == null || source == null || plan == null {
            throw new InvalidOperationException("Unary-literal planning inputs cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Unary-literal planning received an invalid node index.")
        }
    }

    static func ValidateAppendInputs(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, parentFragment: int) {
        ValidateRootInputs(nodes, source, node, plan)
        // 015-B6: a schema-v4 METHOD BODY is admitted alongside v3. This gate threw — a hard crash out
        // of the compiler, not a decline — on every method-body plan, and ALL NINE owners that carried
        // it were widened in ONE move because the value surface routes by operand kind: admitting a
        // subset would mean pre-scanning operands to predict which owner they reach, which is a second
        // copy of the dispatcher's own decision.
        // It opens a NESTED operand fragment and recurses into the scalar literal owner, which B3
        // widened.
        if (plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() && plan.SchemaVersion != ColumnarCodePlanContract.MethodBodySchemaVersion()) || plan.Status != ColumnarFragmentPlanStatus.NotOwned || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Unary literals can only append to an open schema-v3 or method-body plan.")
        }
        if parentFragment < 0 || parentFragment >= plan.FragmentCount || plan.FragmentCompleted == null || plan.FragmentCompleted.Length <= parentFragment || plan.FragmentCompleted[parentFragment] {
            throw new InvalidOperationException("Unary literals require an open parent expression fragment.")
        }
    }

    static func RequiredResultType(plan: ColumnarCodePlan): Type {
        resultType := plan.ResultType
        if resultType == null {
            throw new InvalidOperationException("Planned unary literal has no result type.")
        }
        return resultType
    }
}
