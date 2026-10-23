namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection.Emit

func TypeTestAsPlan(source: string, parameterType: Type): ColumnarCodePlan {
    nodes: ColumnarNodeTable? = null
    root := -1
    if !ColumnarProgramInputBuilder.TryBuildExpressionNodeTable(source, out nodes, out root) || nodes == null || root < 0 {
        throw new InvalidOperationException("The type-test expression did not parse.")
    }
    tree := new ColumnarRangePlannerTestTree(nodes, source, root)
    ConstructionStampScope(tree, "")
    bindings := ColumnarRangePlannerEmptyBindings()
    bindings.ParameterOrdinals["value"] = 0
    bindings.ParameterTypes["value"] = parameterType
    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()
    rootFragment := plan.BeginFragment(-1, nodes.Kind(root), root)
    resultType := typeof(int)
    nestedOwnership := ColumnarDirectCallOwnership.NotOwned
    assert ColumnarTypeTestPlanner.TryAppendAs(nodes, source, root, bindings, ColumnarRangeIndexHandles.Resolve(), plan, rootFragment, 0, false, out resultType, out nestedOwnership)
    plan.CompleteFragment(rootFragment, resultType)
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    plan.CompleteMethodBody(resultType)
    ColumnarCodePlanExecutor.Validate(plan)
    return plan
}

func TypeTestRunAs(plan: ColumnarCodePlan, value: object?): object? {
    dynamicMethod := new DynamicMethod("TypeTestAs", typeof(string), [typeof(object)], typeof(ColumnarTypeTestPlanner), true)
    il := dynamicMethod.GetILGenerator()
    ColumnarCodePlanExecutor.Execute(plan, il)
    arguments := new object[](1)
    arguments[0] = value
    return dynamicMethod.Invoke(null, arguments)
}

test "as expression narrows a reference and returns null for a mismatch" {
    plan := TypeTestAsPlan("value as string", typeof(object))
    assert plan.ResultType == typeof(string)
    matched: object? = TypeTestRunAs(plan, "matched")
    assert matched != null
    assert matched.ToString() == "matched"
    mismatchPlan := TypeTestAsPlan("value as string", typeof(object))
    mismatch: object? = TypeTestRunAs(mismatchPlan, new object())
    assert mismatch == null
}
