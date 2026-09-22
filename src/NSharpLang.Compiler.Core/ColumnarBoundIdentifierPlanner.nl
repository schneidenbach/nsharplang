namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit


// The storage tiers a bare identifier can name. `Local` and `PlanLocal` are the same source-level
// thing and two different handles: `Local` is an AMBIENT `LocalBuilder` the emitter already created,
// while `PlanLocal` (015-B6) is a slot the PLAN declared and the executor materialises at replay,
// which is the only tier a method-body plan can create for itself.
enum ColumnarBoundIdentifierKind {
    None,
    BoxedCapture,
    CapturedInstanceField,
    CapturedInstanceProperty,
    LiftedLocal,
    Local,
    PlanLocal,
    Parameter,
    ByRefParameter,
    CurrentField,
    CurrentProperty,
    BaseField,
    BaseProperty
}

class ColumnarBoundIdentifierSelection {
    Kind: ColumnarBoundIdentifierKind
    ResultType: Type
    Ordinal: int
    // The plan's own local-pool index for a `PlanLocal` selection, and -1 for every other kind.
    // It is deliberately NOT folded into `Ordinal`: that field is an ARGUMENT ordinal, and one
    // integer meaning two different addressing spaces is how a wrong slot becomes a silent read.
    PlanLocalIndex: int
    Local: LocalBuilder?
    FirstField: FieldInfo?
    ValueField: FieldInfo?
    Getter: MethodInfo?
    DeclaringType: Type?
    CurrentInstanceType: Type?
    CurrentInstanceIsAddress: bool
    // THE RECEIVER HOPS A CAPTURED-INSTANCE SELECTION TAKES FROM ARGUMENT ZERO, in order. One field
    // for a lambda whose display captured the enclosing instance directly; one per level for a lambda
    // nested inside another capturing lambda, where each display holds the display of the scope that
    // made it. Empty for every other kind, whose receiver is argument zero itself.
    ReceiverFields: FieldInfo[]

    constructor(kind: ColumnarBoundIdentifierKind, resultType: Type, ordinal: int, planLocalIndex: int, local: LocalBuilder?, firstField: FieldInfo?, valueField: FieldInfo?, getter: MethodInfo?, declaringType: Type?, currentInstanceType: Type?, currentInstanceIsAddress: bool, receiverFields: FieldInfo[]? = null) {
        Kind = kind
        ResultType = resultType
        Ordinal = ordinal
        PlanLocalIndex = planLocalIndex
        Local = local
        FirstField = firstField
        ValueField = valueField
        Getter = getter
        DeclaringType = declaringType
        CurrentInstanceType = currentInstanceType
        CurrentInstanceIsAddress = currentInstanceIsAddress
        ReceiverFields = receiverFields ?? new FieldInfo[](0)
    }
}

// Sole code-plan owner for lexical identifier-value reads. Exact live maps preserve definite
// binding; N# validates their relationships, chooses the storage tier, and emits every load row.
class ColumnarBoundIdentifierPlanner {
    static func MayPlanRoot(nodes: ColumnarNodeTable, node: int): bool {
        if nodes == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, node)
        return candidate >= 0 && (nodes.Kind(candidate) == ColumnarExpressionNodeKind.IdentifierExpression() || nodes.Kind(candidate) == ColumnarExpressionNodeKind.BaseMemberExpression())
    }

    static func ClaimsRoot(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings): bool {
        if nodes == null || source == null || bindings == null {
            return false
        }

        candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, node)
        if candidate < 0 || candidate >= nodes.Kinds.Length || nodes.ChildCount(candidate) != 0 {
            return false
        }

        // A `base.Member` read names no lexical binding at all: the only thing it can be is a member
        // of the base, so this owner claims it outright and reports its own decline if the base has
        // no such member.
        if nodes.Kind(candidate) == ColumnarExpressionNodeKind.BaseMemberExpression() {
            return true
        }

        if nodes.Kind(candidate) != ColumnarExpressionNodeKind.IdentifierExpression() {
            return false
        }

        if ColumnarExpressionSyntaxFacts.IsExplicitThisIdentifier(nodes, source, candidate) {
            return true
        }

        name := nodes.Text(source, candidate)
        if name.Length == 0 {
            return false
        }

        if bindings.BoxedCaptures.ContainsKey(name) || bindings.CapturedInstanceFields.ContainsKey(name) || bindings.LiftedLocals.ContainsKey(name) || bindings.Locals.ContainsKey(name) || bindings.PlanLocals.ContainsKey(name) || bindings.IsBlocked(name) {
            return true
        }

        hasOrdinal := bindings.ParameterOrdinals.ContainsKey(name)
        hasParameterType := bindings.ParameterTypes.ContainsKey(name)
        if hasOrdinal != hasParameterType {
            return true
        }

        if hasOrdinal {
            parameterType := bindings.ParameterTypes[name]
            if parameterType == null || !parameterType.get_IsByRef() {
                return true
            }
            // A byref parameter claims exactly when its element rides the typed-ldind deref
            // table; every other element (structs, enums, nullables, generic parameters) stays
            // with the legacy Ldobj deref owner as a whole-subtree exit.
            elementType := parameterType.GetElementType()
            indirectOpcode := ColumnarCodePlanContract.NoOpCode()
            return elementType != null && TryGetByRefElementOpcode(elementType, out indirectOpcode)
        }

        selection := EmptySelection()
        return TryResolveCurrentInstance(name, bindings, out selection) || TryResolveCapturedEnclosingInstance(name, bindings, out selection)
    }

    static func TryEmit(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, il: ILGenerator, out resultType: Type): bool {
        if Plan(nodes, source, node, bindings, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = ColumnarPlannerSupport.RequiredResultType(plan, "bound-identifier expression")
        return true
    }

    static func TryGetType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        if Plan(nodes, source, node, bindings, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        resultType = ColumnarPlannerSupport.RequiredResultType(plan, "bound-identifier expression")
        return true
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        ValidateInputs(nodes, source, node, bindings, plan)
        plan.PrepareV3()
        candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, node)
        if candidate < 0 || (nodes.Kind(candidate) != ColumnarExpressionNodeKind.IdentifierExpression() && nodes.Kind(candidate) != ColumnarExpressionNodeKind.BaseMemberExpression()) {
            return plan.Status
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            resultType := typeof(int)
            fragment := plan.BeginFragment(-1, nodes.Kind(candidate), candidate)

            if !TryAppend(nodes, source, candidate, bindings, plan, out resultType) {
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

    static func TryAppend(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        if nodes == null || source == null || bindings == null || plan == null || node < 0 || node >= nodes.Kinds.Length || (nodes.Kind(node) != ColumnarExpressionNodeKind.IdentifierExpression() && nodes.Kind(node) != ColumnarExpressionNodeKind.BaseMemberExpression()) {
            return false
        }

        // A schema-v4 METHOD BODY is admitted alongside v3, and without the open-fragment ceremony v3
        // carries: v4 is a documented superset with a FLAT operation stream and no fragments at all.
        // This is the SAME widening `ColumnarScalarLiteralPlanner.ValidateAppendInputs` took, in the
        // second owner that hit the same wall, and it is what lets an ordinary method body reach the
        // ONE owner of lexical identifier reads instead of growing a second copy of the decision.
        // FIVE of the eight arms are reachable from a method body — `ColumnarMethodBodyPlanner`
        // resolves first and filters — and each of the five arrived with its own byte-level corpus
        // diff: Parameter (015-B4), ByRefParameter/CurrentField/CurrentProperty (015-B5), PlanLocal
        // (015-B6). `Local` is not among them and cannot be: it names a `LocalBuilder` the driver has
        // no `ILGenerator` with which to create.
        if (plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() && plan.SchemaVersion != ColumnarCodePlanContract.MethodBodySchemaVersion()) || plan.Status != ColumnarFragmentPlanStatus.NotOwned || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Bound-identifier append requires an open schema-v3 or method-body plan.")
        }

        selection := EmptySelection()
        if !TryResolve(nodes, source, node, bindings, out selection) {
            return false
        }

        if selection.Kind == ColumnarBoundIdentifierKind.BoxedCapture {
            currentInstanceType := RequiredType(selection.CurrentInstanceType, "Boxed-capture selection has no current-instance type.")

            argumentIndex := GetOrAddArgument(plan, 0, currentInstanceType, false)

            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
            boxField := RequiredField(selection.FirstField, "Boxed-capture selection has no box field.")
            firstFieldIndex := plan.AddField(boxField)

            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), firstFieldIndex)
            valueFieldIndex := plan.AddFieldWithSignature(
                RequiredField(selection.ValueField, "Boxed-capture selection has no value field."),
                boxField.get_FieldType(),
                selection.ResultType,
                false
            )

            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), valueFieldIndex)
        } else if selection.Kind == ColumnarBoundIdentifierKind.CapturedInstanceField {
            // THE CAPTURED-RECEIVER READ. From argument zero, one `ldfld` per display in the chain —
            // the display's own field holding the scope that made it — and then the member's own
            // `ldfld` on the instance the last hop produced. With one hop that is the boxed-capture
            // shape with a member field in place of `StrongBox<T>.Value`; with more, it is the same
            // shape walked to whatever depth the source nested its lambdas. Every hop is a reference
            // load, so the member read needs no address and no `constrained` prefix.
            AppendCapturedReceiver(plan, selection, "Captured-instance-field")
            memberFieldIndex := plan.AddField(RequiredField(selection.ValueField, "Captured-instance-field selection has no member field."))

            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), memberFieldIndex)
        } else if selection.Kind == ColumnarBoundIdentifierKind.CapturedInstanceProperty {
            // THE SAME RECEIVER WALK, ENDING IN A PROPERTY GETTER. The enclosing instance a display
            // captured is a reference, so the accessor dispatches virtually exactly as it would on a
            // written receiver of that type — there is no address and no `constrained` prefix.
            AppendCapturedReceiver(plan, selection, "Captured-instance-property")
            capturedGetter := RequiredMethod(selection.Getter, "Captured-instance-property selection has no exact getter handle.")

            capturedDeclaringType := RequiredType(selection.DeclaringType, "Captured-instance-property selection has no exact declaring type.")

            capturedMethodIndex := plan.AddMethodWithSignature(capturedGetter, capturedDeclaringType, new Type[](0), selection.ResultType, false, capturedGetter.get_IsAbstract())

            plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), capturedMethodIndex)
        } else if selection.Kind == ColumnarBoundIdentifierKind.LiftedLocal {
            localIndex := plan.AddAmbientLocal(RequiredLocal(selection.Local, "Lifted selection has no box local."))

            plan.AppendAmbientLocalInstruction(ColumnarCodePlanContract.Ldloc(), localIndex)
            boxLocal := RequiredLocal(selection.Local, "Lifted selection has no box local.")
            valueFieldIndex := plan.AddFieldWithSignature(
                RequiredField(selection.ValueField, "Lifted selection has no value field."),
                boxLocal.get_LocalType(),
                selection.ResultType,
                false
            )

            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), valueFieldIndex)
        } else if selection.Kind == ColumnarBoundIdentifierKind.Local {
            localIndex := plan.AddAmbientLocal(RequiredLocal(selection.Local, "Local selection has no local."))

            plan.AppendAmbientLocalInstruction(ColumnarCodePlanContract.Ldloc(), localIndex)
        } else if selection.Kind == ColumnarBoundIdentifierKind.PlanLocal {
            // A PLAN-DECLARED local read (015-B6). There is no pool entry to add: the slot was
            // declared when the statement loop claimed its `:=`, and the executor turns it into a
            // real `LocalBuilder` — in pool order, before the first row replays — with the same
            // `ILGenerator.DeclareLocal` the emitter would have called. One `ldloc` row over the
            // pool index is therefore the identical instruction, including its short form, which
            // `ILGenerator.Emit(OpCode, LocalBuilder)` selects from the slot ordinal on both paths.
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), selection.PlanLocalIndex)
        } else if selection.Kind == ColumnarBoundIdentifierKind.Parameter {
            argumentIndex := GetOrAddArgument(plan, selection.Ordinal, selection.ResultType, false)

            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
        } else if selection.Kind == ColumnarBoundIdentifierKind.ByRefParameter {
            // A ref/out parameter READ: ldarg pushes the argument slot's managed address-of-T and
            // one typed ldind row loads the element — the legacy case-6 deref arm's
            // EmitLoadArgument + EmitLoadByRefElement, with ldind.<t> as ECMA-335's exact primitive
            // shorthand for its ldobj and ldind.ref serving reference elements.
            argumentIndex := GetOrAddArgument(plan, selection.Ordinal, selection.ResultType, true)

            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
            indirectOpcode := ColumnarCodePlanContract.NoOpCode()
            if !TryGetByRefElementOpcode(selection.ResultType, out indirectOpcode) {
                throw new InvalidOperationException("A by-reference parameter selection has no typed indirect-load opcode.")
            }
            plan.AppendInstructionWithoutOperand(indirectOpcode)
        } else if selection.Kind == ColumnarBoundIdentifierKind.CurrentField {
            currentInstanceType := RequiredType(selection.CurrentInstanceType, "Current-field selection has no current-instance type.")

            argumentIndex := GetOrAddArgument(plan, 0, currentInstanceType, selection.CurrentInstanceIsAddress)

            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
            fieldIndex := plan.AddField(RequiredField(selection.FirstField, "Current-field selection has no exact field handle."))

            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldIndex)
        } else if selection.Kind == ColumnarBoundIdentifierKind.CurrentProperty {
            currentInstanceType := RequiredType(selection.CurrentInstanceType, "Current-property selection has no current-instance type.")

            argumentIndex := GetOrAddArgument(plan, 0, currentInstanceType, selection.CurrentInstanceIsAddress)

            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
            getter := RequiredMethod(selection.Getter, "Current-property selection has no exact getter handle.")

            declaringType := RequiredType(selection.DeclaringType, "Current-property selection has no exact declaring type.")

            methodIndex := plan.AddMethodWithSignature(getter, declaringType, new Type[](0), selection.ResultType, false, getter.get_IsAbstract())

            if selection.CurrentInstanceIsAddress {
                plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
            } else {
                plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), methodIndex)
            }
        } else if selection.Kind == ColumnarBoundIdentifierKind.BaseField {
            currentInstanceType := RequiredType(selection.CurrentInstanceType, "Base-field selection has no current-instance type.")

            argumentIndex := GetOrAddArgument(plan, 0, currentInstanceType, false)

            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
            fieldIndex := plan.AddField(RequiredField(selection.FirstField, "Base-field selection has no exact field handle."))

            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldIndex)
        } else if selection.Kind == ColumnarBoundIdentifierKind.BaseProperty {

            // ALWAYS `call`, NEVER `callvirt`. `base.P` names the base's own accessor; dispatching it
            // virtually would run the override that `base` was written to bypass — and in an
            // overriding getter, would run itself.
            currentInstanceType := RequiredType(selection.CurrentInstanceType, "Base-property selection has no current-instance type.")

            argumentIndex := GetOrAddArgument(plan, 0, currentInstanceType, false)

            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
            baseGetter := RequiredMethod(selection.Getter, "Base-property selection has no exact getter handle.")

            baseDeclaringType := RequiredType(selection.DeclaringType, "Base-property selection has no exact declaring type.")

            baseMethodIndex := plan.AddMethodWithSignature(baseGetter, baseDeclaringType, new Type[](0), selection.ResultType, false, false)

            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), baseMethodIndex)
        } else {
            throw new InvalidOperationException("Bound-identifier selection kind is invalid.")
        }

        resultType = selection.ResultType
        return true
    }

    // ARGUMENT ZERO FOLLOWED BY EVERY DISPLAY HOP THE SELECTION RECORDED, leaving the captured
    // instance on the stack for the member read that follows.
    static func AppendCapturedReceiver(plan: ColumnarCodePlan, selection: ColumnarBoundIdentifierSelection, description: string) {
        currentInstanceType := RequiredType(selection.CurrentInstanceType, description + " selection has no current-instance type.")

        receiverFields := selection.ReceiverFields
        if receiverFields.Length == 0 {
            throw new InvalidOperationException(description + " selection has no receiver field.")
        }

        argumentIndex := GetOrAddArgument(plan, 0, currentInstanceType, false)

        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
        hop := 0
        while hop < receiverFields.Length {
            hopFieldIndex := plan.AddField(RequiredField(receiverFields[hop], description + " selection has no receiver field."))

            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), hopFieldIndex)
            hop = hop + 1
        }
    }

    static func TryGetBoundType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out resultType: Type): bool {
        resultType = typeof(int)
        selection := EmptySelection()
        if !TryResolve(nodes, source, node, bindings, out selection) {
            return false
        }

        resultType = selection.ResultType
        return true
    }

    // THE STORAGE TYPE UNDER A `ref`/`out` ARGUMENT. It is deliberately a different question from
    // `TryGetBoundType`: a bare identifier that names a STATIC field of the enclosing type has no
    // `ColumnarBoundIdentifierKind`, because every kind there describes a value read whose selection
    // the value walk consumes, and a static read is owned by `ColumnarSourceStaticMemberPlanner`
    // instead. A by-reference argument asks only for the STORAGE, so the two static arms answer it
    // here and `TryAppendAddressOf` appends the matching `ldsflda`. Asking `TryGetBoundType` alone
    // is what made `Interlocked.Increment(ref Total)` fail before it ever reached the address-of
    // walk: the argument type could not be named, so the call declined at argument collection.
    static func TryGetByRefTargetType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out resultType: Type): bool {
        resultType = typeof(int)
        if TryGetBoundType(nodes, source, node, bindings, out resultType) {
            return true
        }

        if nodes == null || source == null || bindings == null {
            return false
        }

        candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return false
        }

        staticFieldType: Type? = null
        if nodes.Kind(candidate) == ColumnarExpressionNodeKind.MemberAccessExpression() {
            if ColumnarSourceStaticMemberPlanner.TryGetStaticFieldStorageType(nodes, source, candidate, bindings, out staticFieldType) && staticFieldType != null {
                resultType = staticFieldType
                return true
            }

            return false
        }

        if nodes.Kind(candidate) != ColumnarExpressionNodeKind.IdentifierExpression() || nodes.ChildCount(candidate) != 0 || ColumnarExpressionSyntaxFacts.IsExplicitThisIdentifier(nodes, source, candidate) {
            return false
        }

        if TryGetEnclosingStaticFieldType(bindings, nodes.Text(source, candidate), out staticFieldType) && staticFieldType != null {
            resultType = staticFieldType
            return true
        }

        return false
    }

    // The bare-name half of the relation above, shared with the address-of walk so the type a call
    // binds and the storage it addresses can never disagree. A static INT CONSTANT is a literal
    // with no storage and answers no.
    static func TryGetEnclosingStaticFieldType(bindings: ColumnarFragmentBindings, name: string, out fieldType: Type?): bool {
        fieldType = null
        fieldOwner: ColumnarStructDef? = null
        field: FieldBuilder? = null
        if !TryFindEnclosingStaticField(bindings, name, out fieldOwner, out field) || field == null {
            return false
        }

        fieldType = field.get_FieldType()
        return true
    }

    static func TryFindEnclosingStaticField(bindings: ColumnarFragmentBindings, name: string, out fieldOwner: ColumnarStructDef?, out field: FieldBuilder?): bool {
        fieldOwner = null
        field = null
        if bindings == null || name == null || name.Length == 0 {
            return false
        }

        enclosing := bindings.EnclosingTypeDefinition
        if enclosing == null {
            return false
        }

        selectedOwner: ColumnarStructDef? = null
        selectedField: FieldBuilder? = null
        if !ColumnarSourceMemberChainResolver.TryFindStaticFieldOnChain(enclosing, name, out selectedOwner, out selectedField) || selectedField == null {
            return false
        }

        literalValue := 0
        if selectedOwner != null && selectedOwner.StaticIntConstants.TryGetValue(name, out literalValue) {
            return false
        }

        fieldOwner = selectedOwner
        field = selectedField
        return true
    }

    // Member planning needs the semantic receiver type before it chooses a field/getter and,
    // for source value types, must preserve the original local/argument storage address. Ref/out
    // parameters with typed-ldind elements resolve directly (value reads deref through the table);
    // byref elements outside the table remain receiver-only via the fallback below.
    static func TryGetReceiverType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out resultType: Type, out directStorage: bool, out byRefParameter: bool): bool {
        resultType = typeof(int)
        directStorage = false
        byRefParameter = false
        candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return false
        }

        selection := EmptySelection()
        if TryResolve(nodes, source, candidate, bindings, out selection) {
            resultType = selection.ResultType
            directStorage = selection.Kind == ColumnarBoundIdentifierKind.Local || selection.Kind == ColumnarBoundIdentifierKind.Parameter || selection.Kind == ColumnarBoundIdentifierKind.CurrentField || selection.Kind == ColumnarBoundIdentifierKind.ByRefParameter

            byRefParameter = selection.Kind == ColumnarBoundIdentifierKind.ByRefParameter
            return true
        }

        if nodes.Kind(candidate) != ColumnarExpressionNodeKind.IdentifierExpression() || nodes.ChildCount(candidate) != 0 || ColumnarExpressionSyntaxFacts.IsExplicitThisIdentifier(nodes, source, candidate) {
            return false
        }

        name := nodes.Text(source, candidate)
        if name.Length == 0 || !bindings.ParameterOrdinals.ContainsKey(name) || !bindings.ParameterTypes.ContainsKey(name) {
            return false
        }

        parameterType := bindings.ParameterTypes[name]
        ordinal := bindings.ParameterOrdinals[name]
        if parameterType == null || ordinal < 0 || ordinal > 32767 {
            throw new InvalidOperationException("Member-receiver parameter facts are invalid.")
        }

        if !parameterType.get_IsByRef() {
            return false
        }

        elementType := parameterType.GetElementType()
        if elementType == null {
            throw new InvalidOperationException("A by-reference member receiver has no element type.")
        }

        RequireStorableValueType(elementType, "A by-reference member receiver must have a storable element type.")

        resultType = elementType
        directStorage = true
        byRefParameter = true
        return true
    }

    // Ref/out arguments consume the address of a simple live binding. Keep this lookup beside the
    // ordinary identifier owner so the call planner uses the same lexical storage facts as value
    // reads: lifted/boxed captures and current properties remain outside this addressable surface.
    static func TryGetAddressableTargetType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out resultType: Type): bool {
        resultType = typeof(int)
        candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, node)
        if candidate < 0 || nodes.Kind(candidate) != ColumnarExpressionNodeKind.IdentifierExpression() || nodes.ChildCount(candidate) != 0 {
            return false
        }

        selection := EmptySelection()
        if !TryResolve(nodes, source, candidate, bindings, out selection) {
            return false
        }

        if selection.Kind != ColumnarBoundIdentifierKind.Local && selection.Kind != ColumnarBoundIdentifierKind.PlanLocal && selection.Kind != ColumnarBoundIdentifierKind.Parameter && selection.Kind != ColumnarBoundIdentifierKind.ByRefParameter {
            return false
        }

        resultType = selection.ResultType
        return resultType != null && resultType.FullName != "System.Void" && !resultType.get_IsByRef() && !resultType.get_IsGenericTypeDefinition()
    }

    // Append a simple receiver. When preserveValueStorage is true, an ordinary source-struct
    // local/parameter is loaded by managed address (`ldloca`/`ldarga`) and a byref parameter uses
    // its existing address (`ldarg`). Other bindings keep the ordinary value-read lowering.
    static func TryAppendReceiver(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, preserveValueStorage: bool, plan: ColumnarCodePlan, out resultType: Type, out isAddress: bool): bool {
        resultType = typeof(int)
        isAddress = false
        directStorage := false
        byRefParameter := false
        if !TryGetReceiverType(nodes, source, node, bindings, out resultType, out directStorage, out byRefParameter) {
            return false
        }

        candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return false
        }

        if preserveValueStorage && resultType.get_IsValueType() {
            if !directStorage {
                return false
            }

            selection := EmptySelection()
            if TryResolve(nodes, source, candidate, bindings, out selection) && selection.Kind == ColumnarBoundIdentifierKind.CurrentField {
                currentInstanceType := RequiredType(selection.CurrentInstanceType, "Addressable current-field selection has no current-instance type.")

                argumentIndex := GetOrAddArgument(plan, 0, currentInstanceType, selection.CurrentInstanceIsAddress)

                plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)

                field := RequiredField(selection.FirstField, "Addressable current-field selection has no exact field handle.")

                declaringType := RequiredType(selection.DeclaringType, "Addressable current-field selection has no exact declaring type.")

                fieldIndex := plan.AddFieldWithSignature(field, declaringType, selection.ResultType, false)

                plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldflda(), fieldIndex)

                isAddress = true
                return true
            }

            name := nodes.Text(source, candidate)
            if bindings.Locals.ContainsKey(name) {
                localIndex := plan.AddAmbientLocal(bindings.Locals[name])
                plan.AppendAmbientLocalInstruction(ColumnarCodePlanContract.Ldloca(), localIndex)

                isAddress = true
                return true
            }

            if bindings.ParameterOrdinals.ContainsKey(name) {
                argumentIndex := GetOrAddArgument(plan, bindings.ParameterOrdinals[name], resultType, byRefParameter)

                plan.AppendArgumentInstruction(byRefParameter ? ColumnarCodePlanContract.Ldarg() : ColumnarCodePlanContract.Ldarga(), argumentIndex)

                isAddress = true
                return true
            }

            return false
        }

        if byRefParameter {
            if resultType.get_IsValueType() {
                return false
            }

            name := nodes.Text(source, candidate)
            if !bindings.ParameterOrdinals.ContainsKey(name) {
                return false
            }

            argumentIndex := GetOrAddArgument(plan, bindings.ParameterOrdinals[name], resultType, true)

            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)

            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdindRef())

            return true
        }

        if !TryAppend(nodes, source, candidate, bindings, plan, out resultType) {
            return false
        }

        return true
    }

    // THE MANAGED ADDRESS OF A NAME, for a `ref`/`out` argument.
    //
    // A by-ref argument does not pass a value — it passes the CALLER'S STORAGE, so that a write inside
    // the callee lands where the caller can see it. The three storages a name can be are the three
    // this answers, and each has one instruction:
    //
    //   a LOCAL              -> `ldloca`
    //   a PARAMETER          -> `ldarga`, or `ldarg` when the parameter is ITSELF by-ref (it already
    //                           holds an address, and taking the address of the slot would alias the
    //                           wrong thing)
    //   an INSTANCE FIELD    -> `ldarg.0; ldflda`, which is also how `this.count` arrives, since the
    //                           parser flattens the explicit receiver onto the same leaf
    //
    // IT IS NOT `TryAppendReceiver(preserveValueStorage: true)`. That owner takes an address only for a
    // VALUE type, because its question is "must this member call see the original storage"; this one's
    // question is "what storage does this name denote", and a `ref Action<T>` needs an address exactly
    // as a `ref int` does.
    //
    // A lifted or boxed capture, a static field and every composed shape (an array element, a nested
    // member chain) are refused rather than approximated: an address into the wrong storage is a
    // silently wrong program.
    static func TryAppendAddressOf(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out elementType: Type): bool {
        elementType = typeof(int)
        if nodes == null || source == null || bindings == null || plan == null {
            return false
        }

        candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return false
        }

        // `Counter.Total` written out in full is the same storage as the bare `Total` below, and a
        // by-reference argument may name it from anywhere the type is visible.
        if nodes.Kind(candidate) == ColumnarExpressionNodeKind.MemberAccessExpression() {
            staticMemberElement: Type = typeof(int)
            if ColumnarSourceStaticMemberPlanner.TryAppendStaticFieldAddress(nodes, source, candidate, bindings, plan, out staticMemberElement) {
                RequireStorableValueType(staticMemberElement, "A by-reference static field must have a storable type.")

                elementType = staticMemberElement
                return true
            }

            return false
        }

        if nodes.Kind(candidate) != ColumnarExpressionNodeKind.IdentifierExpression() || nodes.ChildCount(candidate) != 0 {
            return false
        }

        name := nodes.Text(source, candidate)
        if name.Length == 0 {
            return false
        }

        explicitThis := ColumnarExpressionSyntaxFacts.IsExplicitThisIdentifier(nodes, source, candidate)
        if !explicitThis {
            if bindings.Locals.ContainsKey(name) {
                local := bindings.Locals[name]
                if local == null || local.get_LocalType() == null {
                    return false
                }

                localType := local.get_LocalType()
                RequireStorableValueType(localType, "A by-reference local must have a storable type.")

                localIndex := plan.AddAmbientLocal(local)
                plan.AppendAmbientLocalInstruction(ColumnarCodePlanContract.Ldloca(), localIndex)

                elementType = localType
                return true
            }

            if bindings.ParameterOrdinals.ContainsKey(name) && bindings.ParameterTypes.ContainsKey(name) {
                parameterType := bindings.ParameterTypes[name]
                if parameterType.get_IsByRef() {
                    byRefElement := parameterType.GetElementType()
                    if byRefElement == null {
                        return false
                    }

                    RequireStorableValueType(byRefElement, "A by-reference parameter must have a storable element type.")

                    byRefIndex := GetOrAddArgument(plan, bindings.ParameterOrdinals[name], byRefElement, true)
                    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), byRefIndex)

                    elementType = byRefElement
                    return true
                }

                RequireStorableValueType(parameterType, "A by-reference parameter must have a storable type.")

                argumentIndex := GetOrAddArgument(plan, bindings.ParameterOrdinals[name], parameterType, false)
                plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarga(), argumentIndex)

                elementType = parameterType
                return true
            }
        }

        // A STATIC FIELD OF THE ENCLOSING TYPE, named bare. This is the arm that was missing, and
        // its absence is the whole of `Interlocked.Increment(ref Total)` declining while the
        // identical call over an instance field, a local or a parameter emitted. A static member
        // belongs to the TYPE, so it is addressable from every body the type owns -- static methods
        // and instance methods alike -- which is why it is asked before the current-instance walk
        // rather than inside it. An explicit `this.` spelling never names a static, so it is
        // excluded here exactly as it is for the local and parameter arms above.
        if !explicitThis {
            staticFieldOwner: ColumnarStructDef? = null
            staticField: FieldBuilder? = null
            if TryFindEnclosingStaticField(bindings, name, out staticFieldOwner, out staticField) && staticField != null {
                staticFieldType := staticField.get_FieldType()
                RequireStorableValueType(staticFieldType, "A by-reference static field must have a storable type.")

                plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldsflda(), ColumnarSourceStaticMemberPlanner.AddStaticField(plan, staticFieldOwner, staticField))

                elementType = staticFieldType
                return true
            }
        }

        selection := EmptySelection()
        if !TryResolveCurrentInstance(name, bindings, out selection) || selection.Kind != ColumnarBoundIdentifierKind.CurrentField {
            return false
        }

        currentInstanceType := RequiredType(selection.CurrentInstanceType, "An addressable current-field selection has no current-instance type.")

        receiverIndex := GetOrAddArgument(plan, 0, currentInstanceType, selection.CurrentInstanceIsAddress)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), receiverIndex)

        field := RequiredField(selection.FirstField, "An addressable current-field selection has no exact field handle.")

        declaringType := RequiredType(selection.DeclaringType, "An addressable current-field selection has no exact declaring type.")

        fieldIndex := plan.AddFieldWithSignature(field, declaringType, selection.ResultType, false)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldflda(), fieldIndex)

        elementType = selection.ResultType
        return true
    }

    static func TryResolve(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out selection: ColumnarBoundIdentifierSelection): bool {
        selection = EmptySelection()
        if nodes == null || source == null || bindings == null || node < 0 || node >= nodes.Kinds.Length || nodes.ChildCount(node) != 0 {
            return false
        }

        isBaseMember := nodes.Kind(node) == ColumnarExpressionNodeKind.BaseMemberExpression()
        if !isBaseMember && nodes.Kind(node) != ColumnarExpressionNodeKind.IdentifierExpression() {
            return false
        }

        name := nodes.Text(source, node)
        if name.Length == 0 {
            return false
        }

        if isBaseMember {
            return TryResolveBaseMember(name, bindings, out selection)
        }

        if ColumnarExpressionSyntaxFacts.IsExplicitThisIdentifier(nodes, source, node) {
            // Written `this.Member` names the LEXICAL owner's member, which inside a display is the
            // captured receiver's — the same answer the bare name gets, by the same two hops.
            return TryResolveCurrentInstance(name, bindings, out selection) || TryResolveCapturedEnclosingInstance(name, bindings, out selection)
        }

        hasBoxed := bindings.BoxedCaptures.ContainsKey(name)
        hasLifted := bindings.LiftedLocals.ContainsKey(name)
        hasLocal := bindings.Locals.ContainsKey(name)
        hasPlanLocal := bindings.PlanLocals.ContainsKey(name)
        hasOrdinal := bindings.ParameterOrdinals.ContainsKey(name)
        hasParameterType := bindings.ParameterTypes.ContainsKey(name)
        if hasOrdinal != hasParameterType {
            throw new InvalidOperationException("Bound-identifier parameter ordinals and types must contain identical names.")
        }

        hasParameter := hasOrdinal

        // 015-B6 — THE PLAN-DECLARED TIER, AND ITS OVERLAP IS A DEFECT RATHER THAN A SHADOWING RULE.
        // `ColumnarFragmentBindings.DeclarePlanLocal` refuses to publish a name the body can already
        // see, so a name in BOTH the plan-local map and any other tier means the driver published
        // through some other route. Say so loudly instead of silently preferring one storage handle.
        if hasPlanLocal {
            if hasBoxed || hasLifted || hasLocal || hasParameter {
                throw new InvalidOperationException("A plan-declared local cannot overlap another live value binding.")
            }

            planLocal := bindings.PlanLocals[name]
            planLocalIndex := planLocal.Item1
            planLocalType := planLocal.Item2
            if planLocalIndex < 0 || planLocalType == null {
                throw new InvalidOperationException("Plan-declared-local facts must identify a pool index and a value type.")
            }

            RequireStorableValueType(planLocalType, "Plan-declared-local facts must identify a storable local.")

            selection = new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.PlanLocal, planLocalType, -1, planLocalIndex, null, null, null, null, null, null, false)

            return true
        }

        if bindings.CapturedInstanceFields.ContainsKey(name) {
            if hasBoxed || hasLifted || hasLocal || hasParameter {
                throw new InvalidOperationException("A captured-instance member cannot overlap another live value binding.")
            }

            captured := bindings.CapturedInstanceFields[name]
            receiverField := captured.Item1
            memberField := captured.Item2
            if receiverField == null || memberField == null {
                throw new InvalidOperationException("Captured-instance-field facts cannot be null.")
            }

            displayType := receiverField.get_DeclaringType()
            if displayType == null || displayType.get_IsValueType() || receiverField.get_IsStatic() || memberField.get_IsStatic() {
                throw new InvalidOperationException("Captured-instance-field facts do not identify an exact instance receiver and member.")
            }

            memberType := memberField.get_FieldType()
            RequireStorableValueType(memberType, "Captured-instance-field facts must identify a readable member value.")

            capturedReceiverChain := new FieldInfo[](1)
            capturedReceiverChain[0] = receiverField
            selection = new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.CapturedInstanceField, memberType, -1, -1, null, receiverField, memberField, null, null, displayType, false, capturedReceiverChain)

            return true
        }

        if hasBoxed {
            if hasLifted || hasLocal || hasParameter {
                throw new InvalidOperationException("A boxed capture cannot overlap another live value binding.")
            }

            boxed := bindings.BoxedCaptures[name]
            boxField := boxed.Item1
            valueType := boxed.Item2
            if boxField == null || valueType == null {
                throw new InvalidOperationException("Boxed-capture facts cannot be null.")
            }

            currentInstanceType := boxField.get_DeclaringType()
            if currentInstanceType == null || currentInstanceType.get_IsValueType() || boxField.get_IsStatic() {
                throw new InvalidOperationException("Boxed-capture facts do not identify an exact current-instance field.")
            }

            valueField := ResolveStrongBoxValueField(boxField.get_FieldType(), valueType)
            selection = new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.BoxedCapture, valueType, -1, -1, null, boxField, valueField, null, null, currentInstanceType, false)

            return true
        }

        if hasLifted {
            if hasLocal {
                throw new InvalidOperationException("A lifted binding cannot also name an ordinary local.")
            }

            lifted := bindings.LiftedLocals[name]
            boxLocal := lifted.Item1
            valueType := lifted.Item2
            if boxLocal == null || valueType == null {
                throw new InvalidOperationException("Lifted-local facts cannot be null.")
            }

            if hasParameter && bindings.ParameterTypes[name] != valueType {
                throw new InvalidOperationException("A lifted parameter must preserve its declared value type.")
            }

            valueField := ResolveStrongBoxValueField(boxLocal.get_LocalType(), valueType)
            selection = new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.LiftedLocal, valueType, -1, -1, boxLocal, null, valueField, null, null, null, false)

            return true
        }

        if hasLocal {
            if hasParameter {
                throw new InvalidOperationException("An ordinary local cannot overlap a parameter binding.")
            }

            local := bindings.Locals[name]
            if local == null || local.get_LocalType() == null {
                throw new InvalidOperationException("Ordinary-local facts must identify a storable local.")
            }

            localType := local.get_LocalType()
            RequireStorableValueType(localType, "Ordinary-local facts must identify a storable local.")

            selection = new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.Local, localType, -1, -1, local, null, null, null, null, null, false)

            return true
        }

        if hasParameter {
            parameterType := bindings.ParameterTypes[name]
            ordinal := bindings.ParameterOrdinals[name]
            if parameterType == null || ordinal < 0 || ordinal > 32767 {
                throw new InvalidOperationException("Ordinary-parameter facts must identify a valid type and ordinal.")
            }

            // A ref/out parameter READ resolves as an address deref over the typed-ldind table:
            // the selection carries the ELEMENT type as its result and the argument slot stays an
            // address-of-T fact. Elements outside the table (structs, enums, nullables, generic
            // parameters) decline so the legacy Ldobj deref arm serves them whole-subtree.
            if parameterType.get_IsByRef() {
                elementType := parameterType.GetElementType()
                if elementType == null {
                    throw new InvalidOperationException("A by-reference parameter has no element type.")
                }

                indirectOpcode := ColumnarCodePlanContract.NoOpCode()
                if !TryGetByRefElementOpcode(elementType, out indirectOpcode) {
                    return false
                }

                selection = new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.ByRefParameter, elementType, ordinal, -1, null, null, null, null, null, null, false)

                return true
            }

            RequireStorableValueType(parameterType, "Ordinary-parameter facts must identify a storable value type.")

            selection = new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.Parameter, parameterType, ordinal, -1, null, null, null, null, null, null, false)

            return true
        }

        // A synthesized closure display materializes snapshot captures as exact current-instance
        // fields. Those fields are the storage for names that remain present in the enclosing-name
        // set, so they resolve before the name-only shadow gate.
        if bindings.CurrentInstance != null && bindings.CurrentInstance.IsClosureDisplay {
            if TryResolveCurrentInstance(name, bindings, out selection) {
                return true
            }

            // A PARENT DISPLAY'S FIELD IS CAPTURE STORAGE TOO, not a member of some type that an
            // enclosing local could shadow. A lambda nested inside a capturing lambda sees the outer
            // scope's captures there and nowhere else, and every one of those names is still in the
            // enclosing-name set — so this resolves ahead of the name-only gate for the same reason
            // the display's own snapshot fields do. A real enclosing TYPE is deliberately not
            // reached here: its members do lose to a local of the same name, and they answer below.
            if TryResolveCapturedParentDisplay(name, bindings, out selection) {
                return true
            }
        }

        // Name-only facts represent an enclosing or otherwise blocked binding whose storage is not
        // available in this body. They must not be guessed from an ordinary source member with the
        // same text.
        if bindings.IsBlocked(name) {
            return false
        }

        // The captured-receiver read is LAST, after the blocked gate: an enclosing LOCAL of the same
        // name shadows the member in the source the display was made from, so a name the outer scope
        // binds must decline here rather than quietly resolve to a field of the enclosing type.
        return TryResolveCurrentInstance(name, bindings, out selection) || TryResolveCapturedEnclosingInstance(name, bindings, out selection)
    }

    // `base.Name` AS A VALUE — the field or property the BASE declares.
    //
    // The current-instance walk above starts at the type being compiled, which is the right answer
    // for `Name` and `this.Name` and the wrong one for `base.Name`: a member the subclass declares
    // must not answer a reference that deliberately named its base. This walk starts one level up,
    // in the source base chain when the base is being emitted alongside this type and in the runtime
    // base's own metadata when it is a baked class. The receiver is argument zero either way — it is
    // the same object; only the member and its dispatch differ.
    static func TryResolveBaseMember(name: string, bindings: ColumnarFragmentBindings, out selection: ColumnarBoundIdentifierSelection): bool {
        selection = EmptySelection()
        root := bindings.CurrentInstance
        if root == null {
            return false
        }

        currentDefinition := root.SourceDefinition
        if currentDefinition == null || !root.IsReference {
            return false
        }

        receiverType := root.ExactType
        sourceBase := currentDefinition.BaseDef
        exactBaseType := currentDefinition.ExactBaseType
        if sourceBase != null && exactBaseType != null {
            baseDefinition := sourceBase
            baseType := RequiredType(exactBaseType, "A source base declaration has no exact base type.")

            openBaseType: Type = baseDefinition.Builder
            baseFacts := ColumnarCurrentInstanceFacts.FromSourceDefinition(baseDefinition)
            field: FieldInfo? = null
            declaringType := typeof(object)
            if ColumnarCurrentInstanceFacts.TryFindField(baseFacts, name, out field, out declaringType) {
                if field == null || field.get_IsStatic() {
                    throw new InvalidOperationException("Base-instance field facts do not identify exact instance storage.")
                }

                selectedField := field
                selectedDeclaringType := declaringType
                if baseType != declaringType && declaringType == openBaseType {
                    selectedField = RebindField(baseType, field)
                    selectedDeclaringType = baseType
                }

                fieldType := selectedField.get_FieldType()
                RequireStorableValueType(fieldType, "Base-instance field facts must identify a storable value type.")

                selection = new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.BaseField, fieldType, 0, -1, null, selectedField, null, null, selectedDeclaringType, receiverType, false)

                return true
            }

            getter: MethodInfo? = null
            propertyType := typeof(object)
            if ColumnarCurrentInstanceFacts.TryFindProperty(baseFacts, name, out getter, out propertyType, out declaringType) {
                if getter == null || propertyType == null || getter.get_IsStatic() {
                    throw new InvalidOperationException("Base-instance property facts do not identify an exact getter.")
                }

                if getter.get_IsAbstract() {
                    return false
                }

                RequireStorableValueType(propertyType, "Base-instance property facts must identify a storable value type.")

                selectedGetter := getter
                selectedDeclaringType := declaringType
                if baseType != declaringType && declaringType == openBaseType {
                    selectedGetter = RebindMethod(baseType, getter)
                    selectedDeclaringType = baseType
                }

                selection = new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.BaseProperty, propertyType, 0, -1, null, null, null, selectedGetter, selectedDeclaringType, receiverType, false)

                return true
            }
        }

        runtimeBase := ColumnarDirectCallPlanner.ResolveExternalRuntimeBase(currentDefinition)
        if runtimeBase == null {
            runtimeBase = typeof(object)
        }

        return TryResolveInheritedExternalMember(runtimeBase, name, ColumnarBoundIdentifierKind.BaseField, ColumnarBoundIdentifierKind.BaseProperty, receiverType, out selection)
    }

    // WHAT A SOURCE TYPE INHERITS FROM AN EXTERNAL BASE IS READ BY ORDINARY RESOLUTION.
    //
    // `TrySelectAdmittedProperty` used to answer this question, and it answers a NARROWER one: a
    // PUBLIC PROPERTY whose result type is on the modelled-value list. So `this.Items` on a
    // `Collection<T>` base — `protected`, typed `IList<T>` — declined at emit, and so did
    // `this.CoreNewLine` on a `TextWriter` base, which is `protected` AND a FIELD AND typed `char[]`.
    // A PUBLIC member whose result type merely happened to be off that list declined with them.
    // There was no rule there, only a list.
    //
    // The rule is the ordinary one, and it is the same rule `this.Member` with a written receiver
    // already applies through `ColumnarInstanceMemberPlanner`: an inherited external member is
    // selected the way a member of a base-TYPED receiver is, at the levels a derived type in another
    // assembly may reach (`public`, `protected`, `protected internal` — never the assembly ones), and
    // with whatever result type it has. Which STORAGE the member happens to use is not a rule either,
    // so a field answers here exactly as a property does.
    //
    // The receiver is argument zero in both cases, which is why the caller supplies the pair of kinds
    // rather than this walk choosing: `base.Name` and `this.Name` name the same member and differ
    // only in dispatch.
    static func TryResolveInheritedExternalMember(lookupType: Type, name: string, fieldKind: ColumnarBoundIdentifierKind, propertyKind: ColumnarBoundIdentifierKind, receiverType: Type, out selection: ColumnarBoundIdentifierSelection): bool {
        selection = EmptySelection()
        runtimeSelection := ColumnarRuntimeInstanceMemberSelection.Empty()
        if !ColumnarRuntimeInstanceMemberResolver.TrySelect(lookupType, name, true, out runtimeSelection) {
            return false
        }

        if runtimeSelection.IsField {
            runtimeField := runtimeSelection.Field
            if runtimeField == null || runtimeField.get_IsStatic() {
                return false
            }

            selection = new ColumnarBoundIdentifierSelection(fieldKind, runtimeSelection.ResultType, 0, -1, null, runtimeField, null, null, runtimeSelection.DeclaringType, receiverType, false)

            return true
        }

        runtimeGetter := runtimeSelection.Getter
        if runtimeGetter == null || runtimeGetter.get_IsAbstract() {
            return false
        }

        selection = new ColumnarBoundIdentifierSelection(propertyKind, runtimeSelection.ResultType, 0, -1, null, null, null, runtimeGetter, runtimeSelection.DeclaringType, receiverType, false)

        return true
    }

    // THE SCOPES A DISPLAY CAPTURED, READ FROM INSIDE IT — TO ANY NESTING DEPTH.
    //
    // A lambda that captures BOTH `this` and a local runs as an instance method on a synthesized
    // display class, and that display holds the enclosing receiver in one field of its own,
    // `<>4__this`. Argument zero there is the DISPLAY, not the object the source wrote `Factor`
    // about, so the current-instance walk finds nothing and the read declined even though the
    // receiver was sitting in a field the same body could reach.
    //
    // A lambda NESTED inside another capturing lambda has the same field holding the PARENT DISPLAY,
    // because the scope that made it is where its outer captures live. So `<>4__this` is one link of
    // a chain, not a single step, and following it as a chain is what makes an inner lambda reach an
    // outer lambda's capture and the method's `this` alike. Nothing here counts levels: it walks
    // display to display until a level declares the name, and that level may be the enclosing TYPE
    // (a field, a property, or a member inherited from an external base, by the same ordinary
    // resolution `this.Member` uses on a written receiver) or another display (a snapshot capture).
    //
    // Only a REFERENCE enclosing instance is ever captured — a value type's `this` is a pointer into
    // its own storage — which is why every hop is a plain reference load with no address and no
    // `constrained` prefix.
    static func TryResolveCapturedEnclosingInstance(name: string, bindings: ColumnarFragmentBindings, out selection: ColumnarBoundIdentifierSelection): bool {
        return TryResolveCapturedScopeChain(name, bindings, false, out selection)
    }

    static func TryResolveCapturedScopeChain(name: string, bindings: ColumnarFragmentBindings, displayLevelsOnly: bool, out selection: ColumnarBoundIdentifierSelection): bool {
        selection = EmptySelection()
        display := bindings.CurrentInstance
        if display == null || !display.IsClosureDisplay {
            return false
        }

        displayType := display.ExactType
        current := display.SourceDefinition
        if current == null {
            return false
        }

        chain := new List<FieldInfo>()
        while current != null {
            enclosingDefinition := current.ClosureEnclosingDef
            if enclosingDefinition == null || !enclosingDefinition.IsReference {
                return false
            }

            capturedReceiverField: FieldBuilder? = null
            if !current.Fields.TryGetValue(ColumnarClosureBindingPlanner.CapturedEnclosingInstanceFieldName(), out capturedReceiverField) || capturedReceiverField == null {
                throw new InvalidOperationException("A display that names an enclosing scope must hold that scope's captured receiver.")
            }

            receiverType := capturedReceiverField.get_FieldType()
            enclosingScopeType: Type = enclosingDefinition.Builder
            if receiverType == null || receiverType != enclosingScopeType {
                throw new InvalidOperationException("A display's captured receiver must be typed by the scope it was captured from.")
            }

            chain.Add(capturedReceiverField)
            if (enclosingDefinition.IsClosureDisplay || !displayLevelsOnly) && TryResolveCapturedMember(name, enclosingDefinition, receiverType, displayType, chain, out selection) {
                return true
            }

            // The name is not declared at this level. A parent DISPLAY may itself have captured the
            // scope that made it, so the walk continues; a real type ends it.
            if !enclosingDefinition.IsClosureDisplay {
                return false
            }

            current = enclosingDefinition
        }

        return false
    }

    // THE SAME WALK, RESTRICTED TO THE DISPLAY LEVELS. A name a parent display declares is the
    // storage for a capture of the enclosing lambda's scope; a name only the enclosing TYPE declares
    // is a member, and a member may be shadowed by an enclosing local, so it is left to the ordinary
    // ordering below.
    static func TryResolveCapturedParentDisplay(name: string, bindings: ColumnarFragmentBindings, out selection: ColumnarBoundIdentifierSelection): bool {
        selection = EmptySelection()
        display := bindings.CurrentInstance
        if display == null || display.SourceDefinition == null {
            return false
        }

        parent := display.SourceDefinition.ClosureEnclosingDef
        if parent == null || !parent.IsClosureDisplay {
            return false
        }

        return TryResolveCapturedScopeChain(name, bindings, true, out selection)
    }

    // THE MEMBER THAT LEVEL DECLARES, IF ANY, AS A READ THROUGH THE HOPS THAT REACHED IT.
    static func TryResolveCapturedMember(name: string, level: ColumnarStructDef, levelType: Type, displayType: Type, chain: List<FieldInfo>, out selection: ColumnarBoundIdentifierSelection): bool {
        selection = EmptySelection()
        levelFacts := ColumnarCurrentInstanceFacts.FromSourceDefinition(level)
        receiverChain := chain.ToArray()

        field: FieldInfo? = null
        declaringType := typeof(object)
        if ColumnarCurrentInstanceFacts.TryFindField(levelFacts, name, out field, out declaringType) {
            if field == null || field.get_IsStatic() || field.get_DeclaringType() != declaringType {
                throw new InvalidOperationException("Captured enclosing-instance field facts do not identify exact instance storage.")
            }

            fieldType := field.get_FieldType()
            RequireStorableValueType(fieldType, "Captured enclosing-instance field facts must identify a storable value type.")

            selection = new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.CapturedInstanceField, fieldType, -1, -1, null, receiverChain[0], field, null, declaringType, displayType, false, receiverChain)

            return true
        }

        getter: MethodInfo? = null
        propertyType := typeof(object)
        if ColumnarCurrentInstanceFacts.TryFindProperty(levelFacts, name, out getter, out propertyType, out declaringType) {
            if getter == null || propertyType == null || getter.get_IsStatic() || getter.get_DeclaringType() != declaringType || getter.get_ReturnType() != propertyType {
                throw new InvalidOperationException("Captured enclosing-instance property facts do not identify an exact getter.")
            }

            RequireStorableValueType(propertyType, "Captured enclosing-instance property facts must identify a storable value type.")

            selection = new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.CapturedInstanceProperty, propertyType, -1, -1, null, receiverChain[0], null, getter, declaringType, displayType, false, receiverChain)

            return true
        }

        // A synthesized display declares every name it holds, so only a real type reaches a base
        // this compilation did not write.
        if level.IsClosureDisplay {
            return false
        }

        inheritedBase := ColumnarInheritedExternalBase.Resolve(level, levelType)
        if inheritedBase == null {
            return false
        }

        inherited := EmptySelection()
        if !TryResolveInheritedExternalMember(inheritedBase, name, ColumnarBoundIdentifierKind.CapturedInstanceField, ColumnarBoundIdentifierKind.CapturedInstanceProperty, levelType, out inherited) {
            return false
        }

        if inherited.Kind == ColumnarBoundIdentifierKind.CapturedInstanceField {
            selection = new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.CapturedInstanceField, inherited.ResultType, -1, -1, null, receiverChain[0], inherited.FirstField, null, inherited.DeclaringType, displayType, false, receiverChain)

            return true
        }

        selection = new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.CapturedInstanceProperty, inherited.ResultType, -1, -1, null, receiverChain[0], null, inherited.Getter, inherited.DeclaringType, displayType, false, receiverChain)

        return true
    }

    static func TryResolveCurrentInstance(name: string, bindings: ColumnarFragmentBindings, out selection: ColumnarBoundIdentifierSelection): bool {
        selection = EmptySelection()
        root := bindings.CurrentInstance
        if root == null {
            return false
        }

        rootType := root.ExactType
        receiverType := OpenCurrentInstanceType(rootType)
        if rootType.get_IsValueType() == root.IsReference {
            throw new InvalidOperationException("Current-instance facts do not match their exact source type.")
        }

        field: FieldInfo? = null
        declaringType := typeof(object)
        if ColumnarCurrentInstanceFacts.TryFindField(root, name, out field, out declaringType) {
            if field == null || field.get_IsStatic() || field.get_DeclaringType() != declaringType {
                throw new InvalidOperationException("Current-instance field facts do not identify exact instance storage.")
            }

            selectedField := field
            selectedDeclaringType := declaringType
            if receiverType != rootType && declaringType == rootType {
                selectedField = RebindField(receiverType, field)
                selectedDeclaringType = receiverType
            }

            fieldType := selectedField.get_FieldType()
            RequireStorableValueType(fieldType, "Current-instance field facts must identify a storable value type.")

            selection = new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.CurrentField, fieldType, 0, -1, null, selectedField, null, null, selectedDeclaringType, receiverType, !root.IsReference)

            return true
        }

        getter: MethodInfo? = null
        propertyType := typeof(object)
        if ColumnarCurrentInstanceFacts.TryFindProperty(root, name, out getter, out propertyType, out declaringType) {
            if getter == null || propertyType == null || getter.get_IsStatic() || getter.get_DeclaringType() != declaringType || getter.get_ReturnType() != propertyType {
                throw new InvalidOperationException("Current-instance property facts do not identify an exact getter.")
            }

            RequireStorableValueType(propertyType, "Current-instance property facts must identify a storable value type.")

            selectedGetter := getter
            selectedDeclaringType := declaringType
            if receiverType != rootType && declaringType == rootType {
                selectedGetter = RebindMethod(receiverType, getter)
                selectedDeclaringType = receiverType
            }

            selection = new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.CurrentProperty, propertyType, 0, -1, null, null, null, selectedGetter, selectedDeclaringType, receiverType, !root.IsReference)

            return true
        }

        // A MEMBER THE TYPE INHERITS FROM A BASE THIS COMPILATION DID NOT WRITE, NAMED WITHOUT A
        // RECEIVER. `class LayerError: Exception` writes no `Message`, so the source facts walk above
        // found nothing and `"layer:" + Message` inside its own `ToString` declined — while
        // `base.Message` resolved, because the base walk already ends in the runtime base's metadata.
        // An unqualified name IS `this.Name`, so the dispatch is the ordinary virtual one and the
        // receiver is argument zero exactly as it is above.
        if !root.IsReference {
            return false
        }

        inheritedBase := ColumnarInheritedExternalBase.Resolve(root.SourceDefinition, rootType)
        if inheritedBase == null {
            return false
        }

        return TryResolveInheritedExternalMember(inheritedBase, name, ColumnarBoundIdentifierKind.CurrentField, ColumnarBoundIdentifierKind.CurrentProperty, receiverType, out selection)
    }

    static func ResolveStrongBoxValueField(boxType: Type, valueType: Type): FieldInfo {
        if boxType == null || valueType == null || valueType.FullName == "System.Void" || valueType.get_IsByRef() || valueType.get_IsGenericTypeDefinition() || !boxType.get_IsGenericType() || boxType.get_IsGenericTypeDefinition() {
            throw new InvalidOperationException("Lifted binding facts must identify a closed StrongBox value type.")
        }

        definition := boxType.GetGenericTypeDefinition()
        arguments := boxType.GetGenericArguments()
        if definition.FullName != "System.Runtime.CompilerServices.StrongBox`1" || arguments.Length != 1 || arguments[0] != valueType {
            throw new InvalidOperationException("Lifted binding storage must be StrongBox<T> for its exact value type.")
        }

        openField := definition.GetField("Value")
        if openField == null {
            throw new InvalidOperationException("StrongBox<T>.Value was not found.")
        }
        if ColumnarTypeOfPlanner.ContainsBuilderBoundType(boxType) {
            rebound := TypeBuilder.GetField(boxType, openField)
            if rebound == null {
                throw new InvalidOperationException("StrongBox<T>.Value could not be rebound onto its builder-bound instantiation.")
            }
            return rebound
        }
        valueField := boxType.GetField("Value")
        if valueField == null || valueField.get_IsStatic() || valueField.get_DeclaringType() != boxType || valueField.get_FieldType() != valueType {
            throw new InvalidOperationException("Lifted binding storage has no exact StrongBox<T>.Value field.")
        }

        return valueField
    }

    static func RequireStorableValueType(valueType: Type, message: string) {
        if valueType == null || valueType.FullName == "System.Void" || valueType.get_IsByRef() || valueType.get_IsGenericTypeDefinition() {
            throw new InvalidOperationException(message)
        }
    }

    // The typed byref-dereference selection the legacy EmitLoadByRefElement lowering implies:
    // ldind.<t> is ECMA-335's exact shorthand for ldobj over each primitive slot (ldind.i8 serves
    // both Int64 and UInt64 — there is no ldind.u8 encoding), and ldind.ref serves storable
    // reference elements. Every element outside this table — structs, enums, nullables, decimal,
    // generic parameters — is unsupported here and remains with the legacy Ldobj deref owner.
    static func TryGetByRefElementOpcode(elementType: Type, out opcodeValue: short): bool {
        opcodeValue = ColumnarCodePlanContract.NoOpCode()
        if elementType == null {
            return false
        }
        if elementType == typeof(sbyte) {
            opcodeValue = ColumnarCodePlanContract.LdindI1()
        } else if elementType == typeof(byte) || elementType == typeof(bool) {
            opcodeValue = ColumnarCodePlanContract.LdindU1()
        } else if elementType == typeof(short) {
            opcodeValue = ColumnarCodePlanContract.LdindI2()
        } else if elementType == typeof(char) || elementType == typeof(ushort) {
            opcodeValue = ColumnarCodePlanContract.LdindU2()
        } else if elementType == typeof(int) {
            opcodeValue = ColumnarCodePlanContract.LdindI4()
        } else if elementType == typeof(uint) {
            opcodeValue = ColumnarCodePlanContract.LdindU4()
        } else if elementType == typeof(long) || elementType == typeof(ulong) {
            opcodeValue = ColumnarCodePlanContract.LdindI8()
        } else if elementType == typeof(float) {
            opcodeValue = ColumnarCodePlanContract.LdindR4()
        } else if elementType == typeof(double) {
            opcodeValue = ColumnarCodePlanContract.LdindR8()
        } else if !elementType.get_IsValueType() && !elementType.get_IsGenericParameter() && !elementType.get_IsByRef() && !elementType.get_IsGenericTypeDefinition() && elementType.FullName != "System.Void" {
            opcodeValue = ColumnarCodePlanContract.LdindRef()
        } else {
            return false
        }
        return true
    }

    static func GetOrAddArgument(plan: ColumnarCodePlan, ordinal: int, valueType: Type, isAddress: bool): int {
        index := 0
        while index < plan.ArgumentCount {
            if plan.ArgumentOrdinals[index] == ordinal {
                existingType := plan.Types[plan.ArgumentTypeIndices[index]]
                if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(existingType, valueType) || plan.ArgumentIsAddress[index] != isAddress {
                    throw new InvalidOperationException("One argument ordinal cannot carry conflicting bound-identifier facts.")
                }

                return index
            }

            index = index + 1
        }

        typeIndex := plan.AddType(valueType)
        return plan.AddArgument(ordinal, typeIndex, isAddress)
    }

    static func RequiredLocal(value: LocalBuilder?, message: string): LocalBuilder {
        if value == null {
            throw new InvalidOperationException(message)
        }

        return value
    }

    static func RequiredField(value: FieldInfo?, message: string): FieldInfo {
        if value == null {
            throw new InvalidOperationException(message)
        }

        return value
    }

    static func RequiredMethod(value: MethodInfo?, message: string): MethodInfo {
        if value == null {
            throw new InvalidOperationException(message)
        }

        return value
    }

    static func OpenCurrentInstanceType(rootType: Type): Type {
        if !rootType.get_IsGenericTypeDefinition() {
            return rootType
        }

        arguments := rootType.GetGenericArguments()
        if arguments.Length == 0 {
            throw new InvalidOperationException("A generic current-instance definition has no exact type parameters.")
        }

        return rootType.MakeGenericType(arguments)
    }

    static func RebindField(receiverType: Type, field: FieldInfo): FieldInfo {
        result := TypeBuilder.GetField(receiverType, field)
        if result == null {
            throw new InvalidOperationException("TypeBuilder.GetField returned no exact rebound field.")
        }

        return (FieldInfo)result
    }

    static func RebindMethod(receiverType: Type, method: MethodInfo): MethodInfo {
        result := TypeBuilder.GetMethod(receiverType, method)
        if result == null {
            throw new InvalidOperationException("TypeBuilder.GetMethod returned no exact rebound method.")
        }

        return (MethodInfo)result
    }

    static func RequiredType(value: Type?, message: string): Type {
        if value == null {
            throw new InvalidOperationException(message)
        }

        return value
    }

    static func EmptySelection(): ColumnarBoundIdentifierSelection {
        return new ColumnarBoundIdentifierSelection(ColumnarBoundIdentifierKind.None, typeof(int), -1, -1, null, null, null, null, null, null, false)
    }

    static func ValidateInputs(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan) {
        ColumnarPlannerSupport.RequirePresent(nodes != null && source != null && bindings != null && plan != null, "Bound-identifier planning inputs cannot be null.")
        ColumnarPlannerSupport.RequireNodeInRange(nodes, node, "Bound-identifier planning received an invalid root node index.")
    }
}
