namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection.Emit

func StructuralPoolRequiredEntry(
    plan: ColumnarCodePlan,
    index: int
): ColumnarStructuralTypePoolEntry {
    entry := plan.TypeStructuralReferences[index]
    if entry == null {
        throw new InvalidOperationException(
            "Expected a structural type-pool entry."
        )
    }
    return entry
}

func StructuralPoolRequiredIntProperty(target: object, name: string): int {
    property := target.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException(
            "Expected reflected integer property: " + name
        )
    }
    value := property.GetValue(target)
    if value == null {
        throw new InvalidOperationException(
            "Expected a value for reflected property: " + name
        )
    }
    return Convert.ToInt32(value)
}

func StructuralPoolRejectedExecutionLeavesIlUntouched(
    plan: ColumnarCodePlan,
    name: string
): string {
    method := BoundDynamicMethod(name, typeof(int), new Type[](0))
    il := method.GetILGenerator()
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Execute(plan, il)
    }
    assert StructuralPoolRequiredIntProperty(il, "ILOffset") == 0

    // Validation also runs before local materialization. A first local declared after the rejection
    // must therefore retain index zero.
    untouchedLocal := il.DeclareLocal(typeof(int))
    assert StructuralPoolRequiredIntProperty(untouchedLocal, "LocalIndex") == 0

    // A pool mismatch is validated before the executor emits even the first instruction. The same
    // ILGenerator therefore remains a valid empty body and can still return this independent value.
    il.Emit(OpCodes.Ldc_I4_7)
    il.Emit(OpCodes.Ret)
    return BoundInvokeText(method, new object[](0))
}

test "structural type-pool rows append duplicates and clear stale companions on reuse" {
    table := new ColumnarStructuralTypeReferenceTable()
    selected := table.SelectRuntimeType(typeof(string))
    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()

    first := plan.AddType(selected, table)
    second := plan.AddType(selected, table)
    assert first == 0
    assert second == 1
    assert plan.TypeCount == 2
    assert plan.Types[first] == typeof(string)
    assert plan.Types[second] == typeof(string)
    assert plan.TypeUsesStructuralReference[first]
    assert plan.TypeUsesStructuralReference[second]
    assert ColumnarConstructionPlanner.SameObject(
        StructuralPoolRequiredEntry(plan, first).Selected.Key,
        StructuralPoolRequiredEntry(plan, second).Selected.Key
    )

    checkpoint := plan.CreateCheckpoint()
    discarded := plan.AddType(selected, table)
    assert discarded == 2
    assert plan.TypeUsesStructuralReference[discarded]
    plan.Rollback(checkpoint)
    reused := plan.AddType(typeof(int))
    assert reused == discarded
    assert plan.Types[reused] == typeof(int)
    assert !plan.TypeUsesStructuralReference[reused]
    assert plan.TypeStructuralReferences[reused] == null
    assert plan.ValidatedTypeAt(reused) == typeof(int)

    // Reset retains backing arrays and capacity, so a legacy append must overwrite the old keyed
    // cells at index zero as well as resetting the logical count.
    plan.Reset()
    plan.PrepareMethodBody()
    resetReuse := plan.AddType(typeof(string))
    assert resetReuse == 0
    assert !plan.TypeUsesStructuralReference[resetReuse]
    assert plan.TypeStructuralReferences[resetReuse] == null
    assert plan.ValidatedTypeAt(resetReuse) == typeof(string)
}

test "structural type-pool capacity growth keeps all companion columns aligned" {
    table := new ColumnarStructuralTypeReferenceTable()
    selected := table.SelectRuntimeType(typeof(int))
    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()

    // Model independently damaged capacities. The first append must align them; the fifth must then
    // cross the shared capacity while retaining mixed keyed and legacy rows in every companion.
    plan.Types = new Type[](1)
    plan.TypeStructuralReferences = new ColumnarStructuralTypePoolEntry?[](3)
    plan.TypeUsesStructuralReference = new bool[](2)
    first := plan.AddType(selected, table)
    second := plan.AddType(typeof(string))
    stringSelected := table.SelectRuntimeType(typeof(string))
    third := plan.AddType(stringSelected, table)
    fourth := plan.AddType(typeof(bool))
    fifth := plan.AddType(selected, table)

    assert first == 0
    assert second == 1
    assert third == 2
    assert fourth == 3
    assert fifth == 4
    assert plan.Types.Length == 8
    assert plan.TypeStructuralReferences.Length == 8
    assert plan.TypeUsesStructuralReference.Length == 8
    assert plan.Types[0] == typeof(int)
    assert plan.TypeUsesStructuralReference[0]
    assert StructuralPoolRequiredEntry(plan, 0).MatchesRuntime(typeof(int))
    assert plan.Types[1] == typeof(string)
    assert !plan.TypeUsesStructuralReference[1]
    assert plan.TypeStructuralReferences[1] == null
    assert plan.Types[2] == typeof(string)
    assert plan.TypeUsesStructuralReference[2]
    assert StructuralPoolRequiredEntry(plan, 2).MatchesRuntime(typeof(string))
    assert plan.Types[3] == typeof(bool)
    assert !plan.TypeUsesStructuralReference[3]
    assert plan.TypeStructuralReferences[3] == null
    assert plan.Types[4] == typeof(int)
    assert plan.TypeUsesStructuralReference[4]
    assert StructuralPoolRequiredEntry(plan, 4).MatchesRuntime(typeof(int))
}

test "schema v3 and v4 reject malformed structural pairs before mutating IL" {
    bindings := ColumnarRangePlannerEmptyBindings()
    v3 := TypeOfPlan(TypeOfSimpleTree("string"), bindings)
    originalEntry := StructuralPoolRequiredEntry(v3, 0)
    foreignTable := new ColumnarStructuralTypeReferenceTable()
    v3.TypeStructuralReferences[0] = new ColumnarStructuralTypePoolEntry(
        foreignTable,
        originalEntry.Selected
    )
    assert StructuralPoolRejectedExecutionLeavesIlUntouched(
        v3,
        "StructuralPoolInvalidV3"
    ) == "7"

    v4Table := new ColumnarStructuralTypeReferenceTable()
    v4Selected := v4Table.SelectRuntimeType(typeof(string))
    v4 := new ColumnarCodePlan()
    v4.PrepareMethodBody()
    localIndex := v4.DeclarePlanLocal(v4.AddType(typeof(int)))
    assert localIndex == 0
    v4.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
    v4.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), localIndex)
    typeIndex := v4.AddType(v4Selected, v4Table)
    v4.AppendTypeInstruction(ColumnarCodePlanContract.Ldtoken(), typeIndex)
    v4.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
    v4.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    v4.CompleteMethodBody(ExecutorVoidType())
    v4.Types[typeIndex] = typeof(int)
    assert StructuralPoolRejectedExecutionLeavesIlUntouched(
        v4,
        "StructuralPoolInvalidV4"
    ) == "7"
}
