namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// THE WRITE TWIN OF THE MEMBER AND INDEX READS, AS CODE-PLAN ROWS.
//
// `receiver.Member = value` and `receiver[index] = value` are the same question the READ owners
// already answer — which member does this name select on this receiver, which `set_Item` does this
// index list select — asked once more with the value flowing the other way. This owner asks exactly
// those owners (`ColumnarInstanceMemberPlanner.TrySelect` for a member,
// `ColumnarOrdinaryRuntimeDirectCallResolver` for an indexer) and stores the value through the ONE
// target-typed value door, so a write behaves precisely like the call it is: a store into the field
// the read would have loaded, a `set_X` paired with the `get_X` the read selected, a `set_Item` taken
// from the same overload set, with the conversion a call argument at that type would take.
//
// What it refuses is what a store cannot mean. A VALUE-TYPE receiver reached as a value (a call
// result, a property read, an element of a `List<T>`) is a COPY, so writing through it would compile
// to a store nothing can observe; a read-only field and a property with no setter are refused for the
// same reason. Declining is the honest answer to all three.
class ColumnarStoreTargetPlanner {

    // The two target shapes this owner claims. An identifier target is a plain binding and belongs to
    // whoever owns that binding's storage; nothing else is an assignment target at all.
    static func ClaimsTarget(nodes: ColumnarNodeTable, node: int): bool {
        if nodes == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.MemberAccessExpression() {
            return nodes.ChildCount(node) == 1
        }
        return kind == ColumnarExpressionNodeKind.IndexAccessExpression() && nodes.ChildCount(node) == 2
    }

    // `<target> = <value>`. Rows are appended in source order — receiver, then index, then value —
    // which is both the evaluation order the language promises and the order the read path uses. A
    // decline rolls the plan back, so a caller never sees half a store.
    static func TryAppendStore(nodes: ColumnarNodeTable, source: string, targetNode: int, valueNode: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out declineReason: string): bool {
        declineReason = "the assignment target is not a member or an indexer"
        if nodes == null || source == null || bindings == null || plan == null || !ClaimsTarget(nodes, targetNode) {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        stored := false
        if nodes.Kind(targetNode) == ColumnarExpressionNodeKind.MemberAccessExpression() {
            stored = TryAppendMemberStore(nodes, source, targetNode, valueNode, bindings, plan, out declineReason)
        } else {
            stored = TryAppendIndexStore(nodes, source, targetNode, valueNode, bindings, plan, out declineReason)
        }
        if !stored {
            plan.Rollback(checkpoint)
        }
        return stored
    }

    // `<receiver>.<member> = <value>`. The member is selected by the READ owner, so a source field, an
    // inherited source field, a reflected field and a settable property all resolve exactly as they do
    // on the right-hand side; only the direction of the last row differs.
    static func TryAppendMemberStore(nodes: ColumnarNodeTable, source: string, targetNode: int, valueNode: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out declineReason: string): bool {
        declineReason = ""
        memberName := nodes.Text(source, targetNode)
        receiverNode := nodes.Child(targetNode, 0)
        receiverType := typeof(int)
        if !TryDiscoverType(nodes, source, receiverNode, bindings, out receiverType) {
            declineReason = "the assignment target's receiver could not be planned"
            return false
        }
        if !IsObservableWriteReceiver(receiverType) {
            declineReason = "a write through a '" + receiverType.Name + "' value would be lost; only a reference receiver can be assigned through"
            return false
        }

        selection := ColumnarInstanceMemberPlanner.EmptySelection()
        if !ColumnarInstanceMemberPlanner.TrySelect(receiverType, memberName, bindings, out selection) {
            declineReason = "'" + receiverType.Name + "' has no member named '" + memberName + "' to assign"
            return false
        }

        field := selection.Field
        setter: MethodInfo? = null
        if selection.Kind == ColumnarInstanceMemberKind.Field {
            if field == null || field.get_IsInitOnly() || field.get_IsLiteral() {
                declineReason = "'" + memberName + "' is read-only and cannot be assigned"
                return false
            }
        } else if selection.Kind == ColumnarInstanceMemberKind.Property {
            setter = SetterFor(selection)
            if setter == null {
                declineReason = "the property '" + memberName + "' has no setter"
                return false
            }
        } else {
            declineReason = "'" + memberName + "' is not an assignable member"
            return false
        }

        planned := typeof(int)
        if !TryAppendValue(nodes, source, receiverNode, bindings, plan, out planned) {
            declineReason = "the assignment target's receiver could not be planned"
            return false
        }
        if !TryAppendStoredValue(nodes, source, valueNode, bindings, plan, selection.ResultType, out declineReason) {
            return false
        }

        if selection.Kind == ColumnarInstanceMemberKind.Field {
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), plan.AddFieldWithSignature(field, selection.DeclaringType, selection.ResultType, false))
            return true
        }

        setterParameters := new Type[](1)
        setterParameters[0] = selection.ResultType
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), plan.AddMethodWithSignature(setter, selection.DeclaringType, setterParameters, ColumnarTypeOfPlanner.RequiredVoidType(), false, setter.get_IsAbstract()))
        return true
    }

    // `<receiver>[<index>] = <value>`. An ARRAY stores through `stelem` with the element conversion an
    // assignment takes; every other receiver stores through the `set_Item` its own overload set
    // selects for the written index and value types — the same resolution `get_Item` takes on a read.
    static func TryAppendIndexStore(nodes: ColumnarNodeTable, source: string, targetNode: int, valueNode: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out declineReason: string): bool {
        declineReason = ""
        receiverNode := nodes.Child(targetNode, 0)
        indexNode := nodes.Child(targetNode, 1)
        receiverType := typeof(int)
        if !TryDiscoverType(nodes, source, receiverNode, bindings, out receiverType) {
            declineReason = "the indexed target's receiver could not be planned"
            return false
        }

        if ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(receiverType) {
            elementType: Type = receiverType.GetElementType()
            planned := typeof(int)
            if !TryAppendValue(nodes, source, receiverNode, bindings, plan, out planned) {
                declineReason = "the indexed target's receiver could not be planned"
                return false
            }
            indexType := typeof(int)
            if !TryAppendValue(nodes, source, indexNode, bindings, plan, out indexType) || indexType != typeof(int) {
                declineReason = "an array index must be an `int`"
                return false
            }
            if !TryAppendStoredValue(nodes, source, valueNode, bindings, plan, elementType, out declineReason) {
                return false
            }
            plan.AppendTypeInstruction(ColumnarCodePlanContract.Stelem(), plan.AddType(elementType))
            return true
        }

        if !IsObservableWriteReceiver(receiverType) {
            declineReason = "a write through a '" + receiverType.Name + "' value would be lost; only a reference receiver can be indexed into"
            return false
        }

        indexType := typeof(int)
        valueType := typeof(int)
        if !TryDiscoverType(nodes, source, indexNode, bindings, out indexType) || !TryDiscoverType(nodes, source, valueNode, bindings, out valueType) {
            declineReason = "the indexed target's index or value could not be planned"
            return false
        }

        argumentTypes := new Type[](2)
        argumentTypes[0] = indexType
        argumentTypes[1] = valueType
        selection := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(receiverType, "set_Item", argumentTypes, false)
        if !selection.IsSelected || selection.Method == null {
            declineReason = "'" + receiverType.Name + "' has no indexer that accepts a '" + indexType.Name + "' index and a '" + valueType.Name + "' value"
            return false
        }

        planned := typeof(int)
        if !TryAppendValue(nodes, source, receiverNode, bindings, plan, out planned) {
            declineReason = "the indexed target's receiver could not be planned"
            return false
        }
        if !TryAppendStoredValue(nodes, source, indexNode, bindings, plan, selection.ParameterTypes[0], out declineReason) {
            return false
        }
        if !TryAppendStoredValue(nodes, source, valueNode, bindings, plan, selection.ParameterTypes[1], out declineReason) {
            return false
        }
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), plan.AddMethod(selection.Method))
        return true
    }

    // A receiver a store can be OBSERVED through. A class instance is one; a struct reached as a value
    // is a copy, and so is a type parameter that might be instantiated with one.
    static func IsObservableWriteReceiver(receiverType: Type): bool {
        if receiverType == null {
            return false
        }
        return !receiverType.get_IsValueType() && !receiverType.get_IsByRef() && !receiverType.get_IsPointer() && !receiverType.get_IsGenericParameter() && !receiverType.get_IsArray()
    }

    // The `set_X` paired with the `get_X` the read owner selected, taken from the SAME declaring type
    // so an inherited property resolves against the declaration that actually has the accessor. A
    // still-being-emitted type cannot answer a reflection query at all, and a source declaration's
    // computed members are read-only anyway, so a builder-bound owner declines here.
    static func SetterFor(selection: ColumnarInstanceMemberSelection): MethodInfo? {
        getter := selection.Getter
        if getter == null || ColumnarRuntimeInstanceMemberResolver.IsSourceBuilderShape(selection.DeclaringType) {
            return null
        }

        name := getter.Name
        if !name.StartsWith("get_", StringComparison.Ordinal) {
            return null
        }

        parameters := new Type[](1)
        parameters[0] = selection.ResultType
        return selection.DeclaringType.GetMethod("set_" + name.Substring(4), BindingFlags.Public | BindingFlags.Instance, null, parameters, null)
    }

    // THE TYPE OF A VALUE, DISCOVERED BY PLANNING IT INTO A PLAN NOBODY EXECUTES. `set_Item` overload
    // selection needs the written index and value types before any row goes down, exactly as the read
    // path needs a receiver's type before it appends a receiver it cannot reach again.
    static func TryDiscoverType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out resultType: Type): bool {
        resultType = typeof(int)
        scratch := new ColumnarCodePlan()
        scratch.PrepareMethodBody()
        return TryAppendValue(nodes, source, node, bindings, scratch, out resultType) && !ColumnarCodePlanExecutor.IsVoidType(resultType)
    }

    static func TryAppendValue(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        return ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, node, bindings, ColumnarRangeIndexHandles.Resolve(), plan, 0 - 1, 0, out resultType)
    }

    // A value that must arrive at a known storage type: the ONE target-typed door, which plans a
    // target-typed form against that type and everything else through the ordinary cascade plus the
    // conversion a call argument at that type would take.
    static func TryAppendStoredValue(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, targetType: Type, out declineReason: string): bool {
        declineReason = ""
        checkpoint := plan.CreateCheckpoint()
        if ColumnarConstructionPlanner.TryAppendTargetTypedValue(nodes, source, node, bindings, ColumnarRangeIndexHandles.Resolve(), plan, 0 - 1, 0, targetType) {
            return true
        }

        plan.Rollback(checkpoint)
        declineReason = "the assigned value could not be stored as a '" + targetType.Name + "'"
        return false
    }
}
