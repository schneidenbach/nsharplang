namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// Narrow schema-v3 owner for addition used as a composed construction value. The planner admits
// only `+` with two recursively plannable operands, then closes the retained primitive families
// or one exact source-declared operator selected by N#. Every other binary family remains
// available to its existing whole-subtree owner.
public class ColumnarPrimitiveBinaryPlanner {
    public static func Plan(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        ValidateRootInputs(nodes, source, node, bindings, handles, plan)
        plan.PrepareV3()
        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0
            || !IsAdmittedSyntax(nodes, source, candidate, 0) {
            return plan.Status
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            fragment := plan.BeginFragment(
                -1, ColumnarExpressionNodeKind.BinaryExpression(), candidate)
            resultType := typeof(int)
            nestedOwnership := ColumnarDirectCallOwnership.NotOwned
            if !TryAppend(
                    nodes, source, candidate, bindings, handles, plan,
                    fragment, 0, out resultType, out nestedOwnership) {
                plan.Rollback(checkpoint)
                return plan.Status
            }

            plan.CompleteFragment(fragment, resultType)
            plan.CompleteV3(resultType)
            return plan.Status
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    public static func IsAdmittedSyntax(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        depth: int): bool {
        if nodes == null || source == null || depth > 200 {
            return false
        }

        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0
            || nodes.Kind(candidate)
                != ColumnarExpressionNodeKind.BinaryExpression()
            || nodes.ChildCount(candidate) != 2
            || !HasExactOperatorText(nodes, source, candidate, "+") {
            return false
        }

        return IsAdmittedOperandSyntax(
                nodes, source, nodes.Child(candidate, 0), depth + 1)
            && IsAdmittedOperandSyntax(
                nodes, source, nodes.Child(candidate, 1), depth + 1)
    }

    // Append to an already-open binary fragment. A decline is atomic and does not claim other
    // binary operators, mixed primitive pairs, or unselected source-operator families.
    public static func TryAppend(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        parentFragment: int,
        depth: int,
        out resultType: Type,
        out nestedOwnership: ColumnarDirectCallOwnership): bool {
        ValidateAppendInputs(
            nodes, source, node, bindings, handles, plan, parentFragment)
        resultType = typeof(int)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0
            || !IsAdmittedSyntax(nodes, source, candidate, depth) {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            leftType := typeof(int)
            leftOwnership := ColumnarDirectCallOwnership.NotOwned
            if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(
                    nodes, source, nodes.Child(candidate, 0),
                    bindings, handles, plan, parentFragment, depth + 1,
                    out leftType, out leftOwnership) {
                if leftOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                    nestedOwnership = leftOwnership
                }
                plan.Rollback(checkpoint)
                return false
            }

            rightType := typeof(int)
            rightOwnership := ColumnarDirectCallOwnership.NotOwned
            if !ColumnarRangeIndexPlanner.TryAppendConstructionValue(
                    nodes, source, nodes.Child(candidate, 1),
                    bindings, handles, plan, parentFragment, depth + 1,
                    out rightType, out rightOwnership) {
                if rightOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                    nestedOwnership = rightOwnership
                }
                plan.Rollback(checkpoint)
                return false
            }

            // The CLR evaluates char and the small integral types in an Int32 stack slot. N#
            // follows the same binary numeric promotion: every pair in this family produces int,
            // including mixed pairs such as byte + short.
            if ColumnarNumericFacts.IsIntPromotable(leftType)
                && ColumnarNumericFacts.IsIntPromotable(rightType) {
                plan.AppendInstructionWithoutOperand(
                    ColumnarCodePlanContract.Add())
                resultType = typeof(int)
                return true
            }
            if leftType == rightType
                && (leftType == typeof(long)
                    || leftType == typeof(uint)
                    || leftType == typeof(ulong)
                    || leftType == typeof(float)
                    || leftType == typeof(double)) {
                plan.AppendInstructionWithoutOperand(
                    ColumnarCodePlanContract.Add())
                resultType = leftType
                return true
            }
            if leftType == typeof(decimal) && rightType == typeof(decimal) {
                parameterTypes := new Type[](2)
                parameterTypes[0] = typeof(decimal)
                parameterTypes[1] = typeof(decimal)
                method := RequiredDecimalAddition(parameterTypes)
                methodIndex := plan.AddMethodWithSignature(
                    method,
                    typeof(decimal),
                    parameterTypes,
                    typeof(decimal),
                    true,
                    false)
                plan.AppendMethodInstruction(
                    ColumnarCodePlanContract.Call(), methodIndex)
                resultType = typeof(decimal)
                return true
            }
            if leftType == typeof(string) && rightType == typeof(string) {
                methodIndex := plan.AddMethod(RequiredStringConcat())
                plan.AppendMethodInstruction(
                    ColumnarCodePlanContract.Call(), methodIndex)
                resultType = typeof(string)
                return true
            }

            sourceSelection := ColumnarSourceOperatorResolver.ResolveBinary(
                "+", leftType, rightType, bindings.SourceTypeDefinitions)
            if sourceSelection.IsSourceType {
                if !sourceSelection.IsSelected {
                    plan.Rollback(checkpoint)
                    return false
                }
                method := sourceSelection.Method
                if method == null {
                    throw new InvalidOperationException(
                        "A selected source addition operator has no exact method handle.")
                }
                methodIndex := plan.AddMethodWithSignature(
                    method,
                    sourceSelection.DeclaringType,
                    sourceSelection.ParameterTypes,
                    sourceSelection.ReturnType,
                    true,
                    false)
                plan.AppendMethodInstruction(
                    ColumnarCodePlanContract.Call(), methodIndex)
                resultType = sourceSelection.ReturnType
                return true
            }

            plan.Rollback(checkpoint)
            return false
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    static func IsAdmittedOperandSyntax(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        depth: int): bool {
        if depth > 200 {
            return false
        }
        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return false
        }
        if nodes.Kind(candidate)
                == ColumnarExpressionNodeKind.BinaryExpression() {
            return IsAdmittedSyntax(nodes, source, candidate, depth)
        }
        if ColumnarConstructionPlanner.MayPlanRoot(nodes, candidate) {
            return ColumnarConstructionPlanner.IsAdmittedValueSyntax(
                nodes, candidate, depth)
        }
        return ColumnarDirectCallPlanner.IsAdmittedValueSyntax(
            nodes, candidate, depth)
    }

    static func RequiredStringConcat(): MethodInfo {
        parameterTypes := new Type[](2)
        parameterTypes[0] = typeof(string)
        parameterTypes[1] = typeof(string)
        method := typeof(string).GetMethod("Concat", parameterTypes)
        if method == null
            || method.get_DeclaringType() != typeof(string)
            || !method.get_IsStatic()
            || method.get_ReturnType() != typeof(string) {
            throw new InvalidOperationException(
                "Required CLR method String.Concat(String,String) was not found exactly.")
        }
        parameters := method.GetParameters()
        if parameters.Length != 2
            || parameters[0].get_ParameterType() != typeof(string)
            || parameters[1].get_ParameterType() != typeof(string) {
            throw new InvalidOperationException(
                "String.Concat(String,String) has an unexpected runtime signature.")
        }
        return method
    }

    static func RequiredDecimalAddition(
        parameterTypes: Type[]): MethodInfo {
        method := typeof(decimal).GetMethod("op_Addition", parameterTypes)
        if method == null
            || method.get_DeclaringType() != typeof(decimal)
            || !method.get_IsStatic()
            || method.get_IsGenericMethod()
            || method.get_ReturnType() != typeof(decimal) {
            throw new InvalidOperationException(
                "Required CLR method Decimal.op_Addition(Decimal,Decimal) was not found exactly.")
        }
        parameters := method.GetParameters()
        if parameters.Length != 2
            || parameters[0].get_ParameterType() != typeof(decimal)
            || parameters[1].get_ParameterType() != typeof(decimal) {
            throw new InvalidOperationException(
                "Decimal.op_Addition(Decimal,Decimal) has an unexpected runtime signature.")
        }
        return method
    }

    static func HasExactOperatorText(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        expected: string): bool {
        start := nodes.ValueStart(node)
        length := nodes.ValueLengths[node]
        return start >= 0
            && length == expected.Length
            && length <= source.Length
            && start <= source.Length - length
            && source.Substring(start, length) == expected
    }

    static func UnwrapParentheses(
        nodes: ColumnarNodeTable,
        node: int): int {
        depth := 0
        current := node
        while current >= 0
            && current < nodes.Kinds.Length
            && nodes.Kind(current)
                == ColumnarExpressionNodeKind.ParenthesizedExpression() {
            if nodes.ChildCount(current) != 1 || depth > 200 {
                return -1
            }
            current = nodes.Child(current, 0)
            depth += 1
        }
        if current < 0 || current >= nodes.Kinds.Length {
            return -1
        }
        return current
    }

    static func ValidateRootInputs(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan) {
        if nodes == null || source == null || bindings == null
            || handles == null || plan == null {
            throw new InvalidOperationException(
                "Primitive binary planning inputs cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException(
                "Primitive binary planning received an invalid node index.")
        }
    }

    static func ValidateAppendInputs(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        parentFragment: int) {
        ValidateRootInputs(nodes, source, node, bindings, handles, plan)
        if plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion()
            || plan.Status != ColumnarFragmentPlanStatus.NotOwned
            || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException(
                "Primitive binary expressions can only append to an open schema-v3 plan.")
        }
        if parentFragment < 0 || parentFragment >= plan.FragmentCount
            || plan.FragmentCompleted == null
            || plan.FragmentCompleted.Length <= parentFragment
            || plan.FragmentCompleted[parentFragment] {
            throw new InvalidOperationException(
                "Primitive binary expressions require an open parent expression fragment.")
        }
    }
}
