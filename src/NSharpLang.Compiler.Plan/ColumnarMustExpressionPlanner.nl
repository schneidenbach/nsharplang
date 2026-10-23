namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// Emits the null assertion in `must value`. State-machine bodies use the ordinary expression
// cascade for the operand, then keep the assertion and its exact failure message in the same plan.
class ColumnarMustExpressionPlanner {
    static func TryAppend(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, fragment: int, depth: int, allowPrimitiveBinary: bool, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = typeof(int)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        if nodes == null || source == null || bindings == null || handles == null || plan == null || !plan.IsMethodBodySchema() || depth > 200 || node < 0 || node >= nodes.Kinds.Length || nodes.Kind(node) != ColumnarExpressionNodeKind.MustExpression || nodes.ChildCount(node) != 1 {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        operandType := typeof(int)
        if !ColumnarRangeIndexPlanner.TryAppendPlannableValueCore(nodes, source, nodes.Child(node, 0), bindings, handles, plan, fragment, depth + 1, allowPrimitiveBinary, out operandType, out nestedOwnership) || operandType == null {
            plan.Rollback(checkpoint)
            return false
        }

        if ColumnarTypeOfPlanner.IsSupportedNullable(operandType) {
            nullableArguments := operandType.GetGenericArguments()
            if nullableArguments.Length != 1 {
                plan.Rollback(checkpoint)
                return false
            }
            nullableDefinition := operandType.GetGenericTypeDefinition()
            hasValueProperty := nullableDefinition.GetProperty("HasValue", BindingFlags.Public | BindingFlags.Instance)
            valueProperty := nullableDefinition.GetProperty("Value", BindingFlags.Public | BindingFlags.Instance)
            hasValueDefinition := hasValueProperty == null ? null : hasValueProperty.GetGetMethod()
            valueDefinition := valueProperty == null ? null : valueProperty.GetGetMethod()
            if hasValueDefinition == null || valueDefinition == null {
                plan.Rollback(checkpoint)
                return false
            }
            hasValueGetter := ColumnarClosedGenericMemberResolver.ResolveMethod(operandType, hasValueDefinition)
            valueGetter := ColumnarClosedGenericMemberResolver.ResolveMethod(operandType, valueDefinition)
            failureConstructor := typeof(InvalidOperationException).GetConstructor([typeof(string)])
            if hasValueGetter == null || valueGetter == null || failureConstructor == null {
                plan.Rollback(checkpoint)
                return false
            }
            local := plan.DeclarePlanLocal(plan.AddType(bindings.StructuralTypeReferences.SelectRuntimeType(operandType), bindings.StructuralTypeReferences))
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), local)
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), local)
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethod(hasValueGetter))
            present := plan.DefineLabel()
            plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), present)
            plan.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), plan.AddString("must unwrap failed: value was null"))
            plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), plan.AddConstructor(failureConstructor))
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Throw())
            plan.AppendMarkLabel(present)
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), local)
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethod(valueGetter))
            resultType = nullableArguments[0]
            return true
        }

        if operandType.IsGenericParameter {
            valueTypeIndex := plan.AddType(bindings.StructuralTypeReferences.SelectRuntimeType(operandType), bindings.StructuralTypeReferences)
            failureConstructor := typeof(InvalidOperationException).GetConstructor([typeof(string)])
            if failureConstructor == null {
                plan.Rollback(checkpoint)
                return false
            }
            plan.AppendTypeInstruction(ColumnarCodePlanContract.Box(), valueTypeIndex)
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
            present := plan.DefineLabel()
            plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), present)
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
            plan.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), plan.AddString("must unwrap failed: value was null"))
            plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), plan.AddConstructor(failureConstructor))
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Throw())
            plan.AppendMarkLabel(present)
            plan.AppendTypeInstruction(ColumnarCodePlanContract.UnboxAny(), valueTypeIndex)
            resultType = operandType
            return true
        }

        if !operandType.IsValueType {
            failureConstructor := typeof(InvalidOperationException).GetConstructor([typeof(string)])
            if failureConstructor == null {
                plan.Rollback(checkpoint)
                return false
            }
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
            present := plan.DefineLabel()
            plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), present)
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
            plan.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), plan.AddString("must unwrap failed: value was null"))
            plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), plan.AddConstructor(failureConstructor))
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Throw())
            plan.AppendMarkLabel(present)
        }
        resultType = operandType
        return true
    }
}
