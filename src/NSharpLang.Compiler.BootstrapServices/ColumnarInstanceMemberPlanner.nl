namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit

enum ColumnarInstanceMemberKind {
    None,
    Field,
    Property,
    ArrayLength
}

class ColumnarInstanceMemberSelection {
    Kind: ColumnarInstanceMemberKind
    ReceiverIsReference: bool
    PreserveDirectValueStorage: bool
    DeclaringType: Type
    ResultType: Type
    Field: FieldInfo?
    Getter: MethodInfo?

    constructor(kind: ColumnarInstanceMemberKind, receiverIsReference: bool, preserveDirectValueStorage: bool, declaringType: Type, resultType: Type, field: FieldInfo?, getter: MethodInfo?) {
        Kind = kind
        ReceiverIsReference = receiverIsReference
        PreserveDirectValueStorage = preserveDirectValueStorage
        DeclaringType = declaringType
        ResultType = resultType
        Field = field
        Getter = getter
    }
}

// Direct production owner for one statically-bound instance field or zero-arity readable
// property. The range/index orchestrator supplies callback-free receiver fragments; this owner
// chooses the exact source/runtime member, semantic result, receiver address form, and opcode.
class ColumnarInstanceMemberPlanner {
    static func MayPlanRoot(nodes: ColumnarNodeTable, node: int): bool {
        if nodes == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        candidate := UnwrapParentheses(nodes, node)
        return candidate >= 0 && nodes.Kind(candidate) == ColumnarExpressionNodeKind.MemberAccessExpression()
    }

    // A claim is terminal even when member selection later rejects a static, inaccessible,
    // malformed, or unknown member. Unknown receiver expressions remain with later ownership
    // slices; no receiver is emitted merely to discover that this owner declines.
    static func ClaimsRoot(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings): bool {
        if nodes == null || source == null || bindings == null {
            return false
        }

        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 || nodes.Kind(candidate) != ColumnarExpressionNodeKind.MemberAccessExpression() || nodes.ChildCount(candidate) != 1 {
            return false
        }

        receiverType := typeof(int)
        _directStorage := false
        _byRefParameter := false
        receiver := nodes.Child(candidate, 0)
        if ColumnarBoundIdentifierPlanner.TryGetReceiverType(nodes, source, receiver, bindings, out receiverType, out _directStorage, out _byRefParameter) {
            return CanOwnReceiver(receiverType, bindings)
        }

        if !TryGetComposedReceiverType(nodes, source, receiver, bindings, out receiverType) {
            return false
        }

        return CanOwnReceiver(receiverType, bindings)
    }

    static func TryEmit(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, il: ILGenerator, out resultType: Type): bool {
        if Plan(nodes, source, node, bindings, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
        return true
    }

    static func TryGetType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        if Plan(nodes, source, node, bindings, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }

        resultType = RequiredResultType(plan)
        return true
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        ValidateInputs(nodes, source, node, bindings, plan)
        plan.PrepareV3()
        resultType := typeof(int)
        if !TryAppendRoot(nodes, source, node, bindings, plan, out resultType) {
            return plan.Status
        }

        plan.CompleteV3(resultType)
        return plan.Status
    }

    // THE ROOT-APPEND SEQUENCE, OWNED ONCE (015-B14) — the factoring `015-B7` applied to the
    // direct-call owner and `015-B9` to the primitive-binary owner, for the same reason. A
    // member-access root is a kind test, a checkpoint, a root fragment, the append and the fragment's
    // completion; whether the plan around it is a standalone schema-v3 expression (`Plan` wraps this
    // between `PrepareV3` and `CompleteV3`) or an open schema-v4 METHOD BODY
    // (`ColumnarMethodBodyPlanner`'s expression door calls it directly) is the wrapper's business, not
    // the sequence's. Both callers therefore produce the SAME row sequence, which is the whole of
    // producing the same bytes.
    //
    // ⚠ BYTE IDENTITY FOR A KIND-8 ROOT IS AGAINST **TWO** OWNERS, NOT ONE, AND THIS IS THE SECOND.
    // `ColumnarRangeIndexPlanner.TryEmitFromFacts` reaches a member-access root through its SEVENTH
    // arm — `ColumnarExternalStaticMemberPlanner`, whose `MayPlanRoot` is the same unqualified
    // `kind == MemberAccess` test this class's is — and only then through the EIGHTH, which is this
    // one. The door's arm asks both questions in that order; this sequence is what it calls when the
    // first one declines.
    //
    // 015-B11 — A ROOT PASSES THE PLAIN SURFACE, AND THAT IS THE SAME RULE `015-B10` APPLIED TO
    // `ColumnarRangeIndexPlanner.Plan`'s true root: a root has no enclosing position to inherit a
    // surface FROM, exactly as it has no parent fragment to point at. `ClaimsRoot`'s type side
    // (`TryGetComposedReceiverType`) answers the same question the same way, so the two sides of a
    // ROOT member access agree — which is the invariant `015-B9`'s overturn 1 was about.
    //
    // The null contract is the softer one the second caller needs: `Plan` still THROWS through
    // `ValidateInputs` before it gets here, so its behaviour is unchanged, and a door that hands this
    // a null table declines instead of crashing.
    static func TryAppendRoot(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        if nodes == null || source == null || bindings == null || plan == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 || nodes.Kind(candidate) != ColumnarExpressionNodeKind.MemberAccessExpression() {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            fragment := plan.BeginFragment(-1, ColumnarExpressionNodeKind.MemberAccessExpression(), candidate)

            if !TryAppend(nodes, source, candidate, bindings, plan, fragment, false, out resultType) {
                plan.Rollback(checkpoint)
                return false
            }

            plan.CompleteFragment(fragment, resultType)
            return true
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    // ⚠ 015-B11 — `allowPrimitiveBinary` IS THE POSITION'S SURFACE, INHERITED RATHER THAN CHOSEN.
    // This owner's composed-receiver append is reached from the shared value dispatcher
    // (`ColumnarRangeIndexPlanner.TryAppendPlannableValueCore`'s member-access arm), which HOLDS the
    // surface of the position the whole expression occupies and, until this slice, dropped it at the
    // call. So `Callee(items[i + 1].X)` declined inside an expression the dispatcher otherwise
    // claimed while `Callee(items[i].X)` did not — the FOURTH instance of the family `015-B9` closed
    // twice in the call owner and `015-B10` closed at five sites in the index/range owner. The
    // parameter is REQUIRED rather than defaulted, so every caller states its own position.
    static func TryAppend(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, parentFragment: int, allowPrimitiveBinary: bool, out resultType: Type): bool {
        resultType = typeof(int)
        if nodes == null || source == null || bindings == null || plan == null || node < 0 || node >= nodes.Kinds.Length || nodes.Kind(node) != ColumnarExpressionNodeKind.MemberAccessExpression() || nodes.ChildCount(node) != 1 {
            return false
        }

        // 015-B6: a schema-v4 METHOD BODY is admitted alongside v3. This gate threw — a hard crash out
        // of the compiler, not a decline — on every method-body plan, and ALL NINE owners that carried
        // it were widened in ONE move because the value surface routes by operand kind: admitting a
        // subset would mean pre-scanning operands to predict which owner they reach, which is a second
        // copy of the dispatcher's own decision.
        // Its receiver recurses through the shared value dispatcher, so it could not be admitted
        // alone.
        if (plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() && plan.SchemaVersion != ColumnarCodePlanContract.MethodBodySchemaVersion()) || plan.Status != ColumnarFragmentPlanStatus.NotOwned || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Instance-member append requires an open schema-v3 or method-body plan.")
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            receiver := nodes.Child(node, 0)
            memberName := RewriteTupleMemberName(nodes, source, receiver, nodes.Text(source, node), bindings)

            receiverType := typeof(int)
            directStorage := false
            byRefParameter := false
            boundReceiver := ColumnarBoundIdentifierPlanner.TryGetReceiverType(nodes, source, receiver, bindings, out receiverType, out directStorage, out byRefParameter)

            selection := EmptySelection()
            if boundReceiver {
                if !TrySelect(receiverType, memberName, bindings, out selection) {
                    plan.Rollback(checkpoint)
                    return false
                }

                preserveAddress := !selection.ReceiverIsReference && directStorage && (selection.PreserveDirectValueStorage || byRefParameter)

                receiverIsAddress := false
                if preserveAddress {
                    if !ColumnarBoundIdentifierPlanner.TryAppendReceiver(nodes, source, receiver, bindings, true, plan, out receiverType, out receiverIsAddress) || !receiverIsAddress {
                        plan.Rollback(checkpoint)
                        return false
                    }
                } else {
                    receiverFragment := plan.BeginFragment(parentFragment, nodes.Kind(UnwrapParentheses(nodes, receiver)), UnwrapParentheses(nodes, receiver))

                    if !ColumnarBoundIdentifierPlanner.TryAppendReceiver(nodes, source, receiver, bindings, false, plan, out receiverType, out receiverIsAddress) || receiverIsAddress {
                        plan.Rollback(checkpoint)
                        return false
                    }

                    plan.CompleteFragment(receiverFragment, receiverType)
                    if !selection.ReceiverIsReference {
                        AppendTemporaryAddress(plan, receiverType)
                    }
                }
            } else {
                receiverNode := UnwrapParentheses(nodes, receiver)
                if receiverNode < 0 {
                    plan.Rollback(checkpoint)
                    return false
                }

                if nodes.Kind(receiverNode) == ColumnarExpressionNodeKind.IndexAccessExpression() {
                    // A List/array/string element receiver plans as a self-contained value fragment
                    // through the range/index owner, then composes with the ordinary member
                    // selection below (`issues[i].Id`). 015-B11: the element's SELECTOR inherits the
                    // surface of the position this whole member access occupies, so `issues[i + 1].Id`
                    // is claimable wherever `issues[i].Id` already was.
                    handles := ColumnarRangeIndexHandles.Resolve()
                    receiverPlanned := false
                    if allowPrimitiveBinary {
                        receiverPlanned = ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, receiverNode, bindings, handles, plan, parentFragment, 0, out receiverType)
                    } else {
                        receiverPlanned = ColumnarRangeIndexPlanner.TryAppendPlannableValue(nodes, source, receiverNode, bindings, handles, plan, parentFragment, 0, out receiverType)
                    }

                    if !receiverPlanned {
                        plan.Rollback(checkpoint)
                        return false
                    }
                } else {
                    receiverFragment := plan.BeginFragment(parentFragment, nodes.Kind(receiverNode), receiverNode)

                    if !TryAppendComposedReceiver(nodes, source, receiverNode, bindings, plan, out receiverType) {
                        plan.Rollback(checkpoint)
                        return false
                    }

                    plan.CompleteFragment(receiverFragment, receiverType)
                }

                if !TrySelect(receiverType, memberName, bindings, out selection) {
                    plan.Rollback(checkpoint)
                    return false
                }

                if !selection.ReceiverIsReference {
                    AppendTemporaryAddress(plan, receiverType)
                }
            }

            AppendSelection(plan, selection)
            resultType = selection.ResultType
            return true
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    // Leaves an exact managed address to a value-typed instance field. This is intentionally
    // narrower than ordinary member reads: properties and non-addressable receiver expressions
    // cannot preserve mutation semantics and remain with later receiver owners.
    static func TryAppendAddressableValueReceiver(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, parentFragment: int, expectedType: Type): bool {
        if nodes == null || source == null || bindings == null || plan == null || expectedType == null || !expectedType.get_IsValueType() || expectedType.get_IsGenericTypeDefinition() {
            return false
        }

        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 || nodes.Kind(candidate) != ColumnarExpressionNodeKind.MemberAccessExpression() || nodes.ChildCount(candidate) != 1 {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            receiver := nodes.Child(candidate, 0)
            receiverType := typeof(int)
            directStorage := false
            byRefParameter := false
            if !ColumnarBoundIdentifierPlanner.TryGetReceiverType(nodes, source, receiver, bindings, out receiverType, out directStorage, out byRefParameter) {
                plan.Rollback(checkpoint)
                return false
            }

            memberName := RewriteTupleMemberName(nodes, source, receiver, nodes.Text(source, candidate), bindings)
            selection := EmptySelection()
            if !TrySelect(receiverType, memberName, bindings, out selection) || selection.Kind != ColumnarInstanceMemberKind.Field || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(selection.ResultType, expectedType) {
                plan.Rollback(checkpoint)
                return false
            }

            receiverIsAddress := false
            if selection.ReceiverIsReference {
                receiverNode := UnwrapParentheses(nodes, receiver)
                if receiverNode < 0 {
                    plan.Rollback(checkpoint)
                    return false
                }

                receiverFragment := plan.BeginFragment(parentFragment, nodes.Kind(receiverNode), receiverNode)
                if !ColumnarBoundIdentifierPlanner.TryAppendReceiver(nodes, source, receiver, bindings, false, plan, out receiverType, out receiverIsAddress) || receiverIsAddress {
                    plan.Rollback(checkpoint)
                    return false
                }

                plan.CompleteFragment(receiverFragment, receiverType)
            } else if (!directStorage && !byRefParameter) || !ColumnarBoundIdentifierPlanner.TryAppendReceiver(nodes, source, receiver, bindings, true, plan, out receiverType, out receiverIsAddress) || !receiverIsAddress {
                plan.Rollback(checkpoint)
                return false
            }

            field := selection.Field
            if field == null {
                throw new InvalidOperationException("Addressable instance-field selection has no exact handle.")
            }

            fieldIndex := plan.AddFieldWithSignature(field, selection.DeclaringType, selection.ResultType, false)
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldflda(), fieldIndex)
            return true
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    static func TryGetComposedReceiverType(nodes: ColumnarNodeTable, source: string, receiver: int, bindings: ColumnarFragmentBindings, out receiverType: Type): bool {
        receiverType = typeof(int)
        receiverNode := UnwrapParentheses(nodes, receiver)
        if receiverNode < 0 {
            return false
        }

        // 015-B8 — armed BEFORE the prepare, which is the whole reason the mirror is a property of the
        // PLAN rather than a step after `PrepareV3()`: only the index-access arm below prepares this
        // scratch itself, and the other four hand it to a callee whose own `Plan()` prepares it.
        //
        // ⚠ 015-B14 — IT IS NO LONGER INERT. `015-B8` recorded this arming as inert "because no claimed
        // body reaches a composed receiver"; the door's kind-8 arm is exactly such a body, and
        // `q := items` followed by `return q[0].X` types its index receiver HERE, through a scratch whose
        // only knowledge of `q` is this mirror. Without the arming that body would not merely decline —
        // the append would throw on an empty local pool, which is the crash `015-B8` armed against.
        scratch := new ColumnarCodePlan()
        scratch.EnablePlanLocalMirror(bindings.PlanLocalMirrorTypes())
        kind := nodes.Kind(receiverNode)
        if kind == ColumnarExpressionNodeKind.IndexAccessExpression() {
            // A List/array/string element receiver's type comes from planning the index access into
            // a throwaway schema-v3 plan; the open root fragment enables ordinary int indexing.
            //
            // ⚠ 015-B11 — THIS SITE STAYS ON THE PLAIN SURFACE ON PURPOSE, AND THAT IS NOT THE SAME
            // DECISION AS `TryAppend`'s. Its only caller is `ClaimsRoot`, which asks about a plan
            // ROOT, and a root inherits nothing — the identical ruling `015-B10` recorded at
            // `ColumnarRangeIndexPlanner.Plan`. Widening it would make this owner's TYPE side wider
            // than its APPEND side for a root, which is the mirror image of `015-B9`'s overturn 1.
            //
            // ⚠ 015-B14 RE-MEASURED IT AND FOUND A STRONGER REASON THAN A SYMMETRY ARGUMENT. The
            // cascade's instance-member arm sets `nsharpOwned = ClaimsRoot(...)` and
            // `ColumnarIlEmitter.EmitExpressionCore` follows the facade with `if (nsharpOwned) return
            // false;` — so a root this side TYPES but the append side REFUSES declines the WHOLE
            // FUNCTION rather than falling back. Widening here would take `a[i + 1].X` from "the legacy
            // emitter compiles it" to "the function is declined": a production regression, not merely a
            // wider type side. This is why the site is NOT the fifth instance of the inherited-surface
            // family that `015-B9`–`015-B12` closed at four owners.
            scratch.PrepareV3()
            rootFragment := scratch.BeginFragment(-1, kind, receiverNode)
            handles := ColumnarRangeIndexHandles.Resolve()
            return ColumnarRangeIndexPlanner.TryAppendPlannableValue(nodes, source, receiverNode, bindings, handles, scratch, rootFragment, 0, out receiverType)
        }
        if kind == ColumnarExpressionNodeKind.MemberAccessExpression() {
            return ColumnarExternalStaticMemberPlanner.TryGetType(nodes, source, receiverNode, bindings, scratch, out receiverType)
        }

        if IsScalarLiteralKind(kind) {
            return ColumnarScalarLiteralPlanner.TryGetType(nodes, source, receiverNode, scratch, out receiverType)
        }

        if kind == ColumnarExpressionNodeKind.NameOfExpression() {
            return ColumnarNameOfPlanner.TryGetType(nodes, source, receiverNode, scratch, out receiverType)
        }

        if kind == ColumnarExpressionNodeKind.TypeOfExpression() {
            return ColumnarTypeOfPlanner.TryGetType(nodes, source, receiverNode, bindings, scratch, out receiverType)
        }

        return false
    }

    static func TryAppendComposedReceiver(nodes: ColumnarNodeTable, source: string, receiverNode: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out receiverType: Type): bool {
        receiverType = typeof(int)
        kind := nodes.Kind(receiverNode)
        if kind == ColumnarExpressionNodeKind.MemberAccessExpression() {
            return ColumnarExternalStaticMemberPlanner.TryAppendStaticMember(nodes, source, receiverNode, bindings, plan, out receiverType)
        }

        if IsScalarLiteralKind(kind) {
            return ColumnarScalarLiteralPlanner.TryAppendLiteral(nodes, source, receiverNode, plan, out receiverType)
        }

        if kind == ColumnarExpressionNodeKind.NameOfExpression() {
            return ColumnarNameOfPlanner.TryAppendNameOf(nodes, source, receiverNode, plan, out receiverType)
        }

        if kind == ColumnarExpressionNodeKind.TypeOfExpression() {
            return ColumnarTypeOfPlanner.TryAppendTypeOf(nodes, source, receiverNode, bindings, plan, out receiverType)
        }

        return false
    }

    static func IsScalarLiteralKind(kind: int): bool {
        return kind == ColumnarExpressionNodeKind.IntLiteralExpression() || kind == ColumnarExpressionNodeKind.FloatLiteralExpression() || kind == ColumnarExpressionNodeKind.CharLiteralExpression() || kind == ColumnarExpressionNodeKind.StringLiteralExpression()
    }

    static func CanOwnReceiver(receiverType: Type, bindings: ColumnarFragmentBindings): bool {
        if receiverType.get_IsSZArray() {
            return true
        }

        source := EmptySelection()
        if TryClassifySource(receiverType, bindings, out source) {
            return true
        }

        return ColumnarRuntimeInstanceMemberResolver.CanOwnReceiver(receiverType)
    }

    static func TrySelect(receiverType: Type, memberName: string, bindings: ColumnarFragmentBindings, out selection: ColumnarInstanceMemberSelection): bool {
        selection = EmptySelection()
        if receiverType.get_IsSZArray() {
            if memberName != "Length" {
                return false
            }

            selection = new ColumnarInstanceMemberSelection(ColumnarInstanceMemberKind.ArrayLength, true, false, receiverType, typeof(int), null, null)

            return true
        }

        sourceClass := EmptySelection()
        if TryClassifySource(receiverType, bindings, out sourceClass) {
            return TrySelectSource(receiverType, memberName, bindings, sourceClass, out selection)
        }

        runtime := ColumnarRuntimeInstanceMemberSelection.Empty()
        if !ColumnarRuntimeInstanceMemberResolver.TrySelect(receiverType, memberName, out runtime) {
            return false
        }

        selection = new ColumnarInstanceMemberSelection(runtime.IsField ? ColumnarInstanceMemberKind.Field : ColumnarInstanceMemberKind.Property, runtime.ReceiverIsReference, false, runtime.DeclaringType, runtime.ResultType, runtime.Field, runtime.Getter)

        return true
    }

    // Classification returns a sentinel selection carrying only the receiver shape and whether
    // the legacy addressable source-local semantics apply. Member lookup remains separate so a
    // missing/static/inaccessible member is still a terminal owned decline.
    static func TryClassifySource(receiverType: Type, bindings: ColumnarFragmentBindings, out classification: ColumnarInstanceMemberSelection): bool {
        classification = EmptySelection()
        selected: ColumnarStructDef? = null
        closed := false
        for candidate in bindings.SourceTypeDefinitions {
            if candidate == null || candidate.Builder == null {
                throw new InvalidOperationException("Source instance-member definitions cannot be null.")
            }

            candidateType: Type = candidate.Builder
            matches := false
            if candidateType == receiverType {
                matches = true
            }

            candidateClosed := false
            if !matches && receiverType.get_IsGenericType() && !receiverType.get_IsGenericTypeDefinition() && receiverType.GetGenericTypeDefinition() == candidateType {
                matches = true
                candidateClosed = true
            }

            if matches {
                if selected != null && selected != candidate {
                    throw new InvalidOperationException("One exact receiver type cannot map to two source definitions.")
                }

                selected = candidate
                closed = candidateClosed
            }
        }

        if selected != null {
            if receiverType.get_IsValueType() == selected.IsReference {
                throw new InvalidOperationException("Source instance-member reference facts do not match the receiver type.")
            }

            classification = new ColumnarInstanceMemberSelection(ColumnarInstanceMemberKind.None, selected.IsReference, !closed, selected.Builder, typeof(int), null, null)

            return true
        }

        selectedFacts := bindings.CurrentInstance
        if selectedFacts == null || selectedFacts.ExactType != receiverType {
            return false
        }

        if receiverType.get_IsValueType() == selectedFacts.IsReference {
            throw new InvalidOperationException("Exact instance-member facts do not match their receiver type.")
        }

        if selectedFacts.SourceDefinition != null {
            throw new InvalidOperationException("Current source instance facts must be present in the live source definition registry.")
        }

        classification = new ColumnarInstanceMemberSelection(ColumnarInstanceMemberKind.None, selectedFacts.IsReference, true, receiverType, typeof(int), null, null)

        return true
    }

    static func TrySelectSource(receiverType: Type, memberName: string, bindings: ColumnarFragmentBindings, classification: ColumnarInstanceMemberSelection, out selection: ColumnarInstanceMemberSelection): bool {
        selection = EmptySelection()
        source: ColumnarStructDef? = null
        for candidate in bindings.SourceTypeDefinitions {
            candidateType: Type = candidate.Builder
            if candidateType == receiverType {
                source = candidate
            } else if receiverType.get_IsGenericType() && !receiverType.get_IsGenericTypeDefinition() && receiverType.GetGenericTypeDefinition() == candidateType {
                source = candidate
            }
        }

        if source != null {
            return TrySelectSourceDefinition(receiverType, memberName, source, classification, out selection)
        }

        facts := bindings.CurrentInstance
        if facts != null && facts.ExactType == receiverType {
            return TrySelectExactFacts(receiverType, memberName, facts, classification, out selection)
        }

        throw new InvalidOperationException("Classified source instance facts disappeared during member selection.")
    }

    static func TrySelectSourceDefinition(receiverType: Type, memberName: string, root: ColumnarStructDef, classification: ColumnarInstanceMemberSelection, out selection: ColumnarInstanceMemberSelection): bool {
        selection = EmptySelection()
        if memberName.Length == 0 {
            return false
        }

        ValidateSourceHierarchy(root)
        current: ColumnarStructDef? = root
        currentExactType := receiverType
        found := false
        foundStatic := false
        foundField: FieldInfo? = null
        foundProperty: ColumnarPropertyDef? = null
        foundDeclaring := typeof(object)
        foundExactDeclaring := typeof(object)
        while current != null {
            localField := current.Fields.ContainsKey(memberName)
            localProperty := current.Properties.ContainsKey(memberName)
            localStaticField := current.StaticFields.ContainsKey(memberName)
            localStaticProperty := current.StaticProperties.ContainsKey(memberName)
            declarationCount := (localField ? 1 : 0) + (localProperty ? 1 : 0) + (localStaticField ? 1 : 0) + (localStaticProperty ? 1 : 0)

            if declarationCount > 1 || declarationCount > 0 && (found || foundStatic) {
                throw new InvalidOperationException("Source member declarations cannot shadow another member in their hierarchy.")
            }

            if declarationCount > 0 {
                found = localField || localProperty
                foundStatic = localStaticField || localStaticProperty
                foundDeclaring = current.Builder
                foundExactDeclaring = currentExactType
                if localField {
                    foundField = current.Fields[memberName]
                } else if localProperty {
                    foundProperty = current.Properties[memberName]
                }
            }

            baseDefinition := current.BaseDef
            if baseDefinition == null {
                current = null
                continue
            }

            exactBaseTemplate := current.ExactBaseType
            if exactBaseTemplate == null {
                throw new InvalidOperationException("Source instance-member base facts have no exact type template.")
            }
            emittedBaseTemplate := current.Builder.get_BaseType()
            if emittedBaseTemplate == null || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(exactBaseTemplate, emittedBaseTemplate) {
                throw new InvalidOperationException("Source instance-member exact base template does not match emitted inheritance.")
            }

            currentWasClosed := !ContainsOpenTypeParameters(currentExactType)
            currentArguments := currentExactType.get_IsGenericType() ? currentExactType.GetGenericArguments() : new Type[](0)
            currentExactType = currentArguments.Length == 0 ? exactBaseTemplate : SubstituteTypeArguments(exactBaseTemplate, currentArguments)
            if !ExactTypeOwnsDefinition(currentExactType, baseDefinition) {
                throw new InvalidOperationException("Source instance-member exact base type does not match its definition.")
            }
            if currentWasClosed && ContainsOpenTypeParameters(currentExactType) {
                throw new InvalidOperationException("A closed source receiver cannot map to an open generic base.")
            }
            current = baseDefinition
        }

        if foundStatic || !found {
            return false
        }

        if foundField != null {
            field := foundField
            if field.get_IsStatic() || field.get_IsLiteral() || field.get_DeclaringType() != foundDeclaring {
                throw new InvalidOperationException("Source instance field facts do not identify exact storage.")
            }

            if !field.get_IsPublic() {
                return false
            }

            resultType := field.get_FieldType()
            declaringType := foundDeclaring
            selectedField := field
            foundArguments := foundExactDeclaring.get_IsGenericType() ? foundExactDeclaring.GetGenericArguments() : new Type[](0)
            if foundArguments.Length > 0 {
                resultType = SubstituteTypeArguments(resultType, foundArguments)
            }
            if foundExactDeclaring != foundDeclaring {
                selectedField = RebindField(foundExactDeclaring, field)
                declaringType = foundExactDeclaring
            }

            if !IsStorableResult(resultType) {
                return false
            }

            selection = new ColumnarInstanceMemberSelection(ColumnarInstanceMemberKind.Field, classification.ReceiverIsReference, classification.PreserveDirectValueStorage, declaringType, resultType, selectedField, null)

            return true
        }

        property := foundProperty
        if property == null || property.Getter == null || property.PropertyType == null {
            throw new InvalidOperationException("Source instance property facts cannot be null.")
        }

        getter: MethodInfo = property.Getter
        if getter.get_IsStatic() || getter.get_DeclaringType() != foundDeclaring || getter.get_ReturnType() != property.PropertyType || property.GetterParameterCount != 0 {
            throw new InvalidOperationException("Source instance property facts do not identify an exact zero-arity getter.")
        }

        if !getter.get_IsPublic() {
            return false
        }

        propertyType := property.PropertyType
        declaringPropertyType := foundDeclaring
        selectedGetter := getter
        foundPropertyArguments := foundExactDeclaring.get_IsGenericType() ? foundExactDeclaring.GetGenericArguments() : new Type[](0)
        if foundPropertyArguments.Length > 0 {
            propertyType = SubstituteTypeArguments(propertyType, foundPropertyArguments)
        }
        if foundExactDeclaring != foundDeclaring {
            selectedGetter = RebindMethod(foundExactDeclaring, getter)
            declaringPropertyType = foundExactDeclaring
        }

        if !IsStorableResult(propertyType) {
            return false
        }

        selection = new ColumnarInstanceMemberSelection(ColumnarInstanceMemberKind.Property, classification.ReceiverIsReference, classification.PreserveDirectValueStorage, declaringPropertyType, propertyType, null, selectedGetter)

        return true
    }

    static func TrySelectExactFacts(_receiverType: Type, memberName: string, root: ColumnarCurrentInstanceFacts, classification: ColumnarInstanceMemberSelection, out selection: ColumnarInstanceMemberSelection): bool {
        selection = EmptySelection()
        ValidateExactHierarchy(root)
        current: ColumnarCurrentInstanceFacts? = root
        foundField: FieldInfo? = null
        foundProperty: ColumnarCurrentPropertyFact? = null
        foundDeclaring := typeof(object)
        found := false
        while current != null {
            if current.SourceDefinition != null {
                throw new InvalidOperationException("Exact instance-member facts cannot mix source definitions into their hierarchy.")
            }

            localField := current.Fields.ContainsKey(memberName)
            localProperty := current.Properties.ContainsKey(memberName)
            declarationCount := (localField ? 1 : 0) + (localProperty ? 1 : 0)
            if declarationCount > 1 || declarationCount > 0 && found {
                throw new InvalidOperationException("Exact member facts cannot shadow another member in their hierarchy.")
            }

            if declarationCount > 0 {
                found = true
                foundDeclaring = current.ExactType
                if localField {
                    foundField = current.Fields[memberName]
                } else {
                    foundProperty = current.Properties[memberName]
                }
            }

            current = current.BaseFacts
        }

        if !found {
            return false
        }

        if foundField != null {
            field := foundField
            if field.get_IsStatic() || field.get_IsLiteral() || field.get_DeclaringType() != foundDeclaring {
                throw new InvalidOperationException("Exact instance field facts do not identify exact storage.")
            }

            if !field.get_IsPublic() || !IsStorableResult(field.get_FieldType()) {
                return false
            }

            selection = new ColumnarInstanceMemberSelection(ColumnarInstanceMemberKind.Field, classification.ReceiverIsReference, classification.PreserveDirectValueStorage, foundDeclaring, field.get_FieldType(), field, null)

            return true
        }

        property := foundProperty
        if property == null || property.Getter == null || property.PropertyType == null {
            throw new InvalidOperationException("Exact instance property facts cannot be null.")
        }

        getter := property.Getter
        if getter.get_IsStatic() || getter.get_DeclaringType() != foundDeclaring || getter.get_ReturnType() != property.PropertyType || property.GetterParameterCount != 0 || getter.GetParameters().Length != 0 {
            throw new InvalidOperationException("Exact instance property facts do not identify an exact zero-arity getter.")
        }

        if !getter.get_IsPublic() || !IsStorableResult(property.PropertyType) {
            return false
        }

        selection = new ColumnarInstanceMemberSelection(ColumnarInstanceMemberKind.Property, classification.ReceiverIsReference, classification.PreserveDirectValueStorage, foundDeclaring, property.PropertyType, null, getter)

        return true
    }

    static func ValidateSourceHierarchy(root: ColumnarStructDef) {
        slow: ColumnarStructDef? = root
        fast: ColumnarStructDef? = root
        while fast != null && fast.BaseDef != null {
            if slow != null {
                slow = slow.BaseDef
            }

            next := fast.BaseDef
            if next == null {
                return
            }

            fast = next.BaseDef
            if slow != null && slow == fast {
                throw new InvalidOperationException("Source instance-member hierarchy contains a cycle.")
            }
        }
    }

    static func ExactTypeOwnsDefinition(exactType: Type, definition: ColumnarStructDef): bool {
        if ColumnarConstructionPlanner.SameObject(exactType, definition.Builder) {
            return !definition.Builder.get_IsGenericTypeDefinition()
        }

        return exactType.get_IsGenericType() && !exactType.get_IsGenericTypeDefinition() && ColumnarConstructionPlanner.SameObject(exactType.GetGenericTypeDefinition(), definition.Builder)
    }

    static func ContainsOpenTypeParameters(valueType: Type): bool {
        if valueType.get_IsGenericParameter() || valueType.get_IsGenericTypeDefinition() {
            return true
        }
        if !valueType.get_IsGenericType() {
            return false
        }

        arguments := valueType.GetGenericArguments()
        index := 0
        while index < arguments.Length {
            if ContainsOpenTypeParameters(arguments[index]) {
                return true
            }
            index += 1
        }
        return false
    }

    static func ValidateExactHierarchy(root: ColumnarCurrentInstanceFacts) {
        slow: ColumnarCurrentInstanceFacts? = root
        fast: ColumnarCurrentInstanceFacts? = root
        while fast != null && fast.BaseFacts != null {
            if slow != null {
                slow = slow.BaseFacts
            }

            next := fast.BaseFacts
            if next == null {
                return
            }

            fast = next.BaseFacts
            if slow != null && slow == fast {
                throw new InvalidOperationException("Exact instance-member hierarchy contains a cycle.")
            }
        }
    }

    static func AppendSelection(plan: ColumnarCodePlan, selection: ColumnarInstanceMemberSelection) {
        if selection.Kind == ColumnarInstanceMemberKind.ArrayLength {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldlen())
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
            return
        }

        if selection.Kind == ColumnarInstanceMemberKind.Field {
            field := selection.Field
            if field == null {
                throw new InvalidOperationException("Selected instance field has no exact handle.")
            }

            fieldIndex := plan.AddFieldWithSignature(field, selection.DeclaringType, selection.ResultType, false)

            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldIndex)

            return
        }

        if selection.Kind != ColumnarInstanceMemberKind.Property || selection.Getter == null {
            throw new InvalidOperationException("Selected instance property has no exact getter.")
        }

        getter := selection.Getter
        methodIndex := plan.AddMethodWithSignature(getter, selection.DeclaringType, new Type[](0), selection.ResultType, false, getter.get_IsAbstract())

        plan.AppendMethodInstruction(selection.ReceiverIsReference ? ColumnarCodePlanContract.Callvirt() : ColumnarCodePlanContract.Call(), methodIndex)
    }

    static func AppendTemporaryAddress(plan: ColumnarCodePlan, receiverType: Type) {
        typeIndex := plan.AddType(receiverType)
        localIndex := plan.DeclarePlanLocal(typeIndex)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), localIndex)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), localIndex)
    }

    static func RewriteTupleMemberName(nodes: ColumnarNodeTable, source: string, receiver: int, memberName: string, bindings: ColumnarFragmentBindings): string {
        candidate := UnwrapParentheses(nodes, receiver)
        if candidate < 0 || nodes.Kind(candidate) != ColumnarExpressionNodeKind.IdentifierExpression() || nodes.ChildCount(candidate) != 0 {
            return memberName
        }

        receiverName := nodes.Text(source, candidate)
        if !bindings.TupleNames.ContainsKey(receiverName) {
            return memberName
        }

        names := bindings.TupleNames[receiverName]
        i := 0
        while i < names.Length {
            if String.Equals(names[i], memberName, StringComparison.Ordinal) {
                return "Item" + (i + 1).ToString()
            }

            i += 1
        }

        return memberName
    }

    static func SubstituteTypeArguments(signatureType: Type, arguments: Type[]): Type {
        if signatureType.get_IsGenericParameter() && signatureType.get_DeclaringMethod() == null {
            position := signatureType.get_GenericParameterPosition()
            if position < 0 || position >= arguments.Length {
                throw new InvalidOperationException("Source member generic parameter position is invalid.")
            }

            return arguments[position]
        }

        if signatureType.get_IsSZArray() {
            element := signatureType.GetElementType()
            if element == null {
                throw new InvalidOperationException("Source member array signature has no element type.")
            }

            return SubstituteTypeArguments(element, arguments).MakeArrayType()
        }

        if signatureType.get_IsGenericType() && !signatureType.get_IsGenericTypeDefinition() {
            definition := signatureType.GetGenericTypeDefinition()
            rawArguments := signatureType.GetGenericArguments()
            resolved := new Type[](rawArguments.Length)
            i := 0
            while i < rawArguments.Length {
                resolved[i] = SubstituteTypeArguments(rawArguments[i], arguments)
                i += 1
            }

            return definition.MakeGenericType(resolved)
        }

        if signatureType.get_HasElementType() {
            element := signatureType.GetElementType()
            if element == null {
                throw new InvalidOperationException("Source member compound signature has no element type.")
            }

            if SubstituteTypeArguments(element, arguments) != element {
                throw new InvalidOperationException("Source member compound signature substitution is unsupported.")
            }
        }

        return signatureType
    }

    static func RebindField(receiverType: Type, field: FieldInfo): FieldInfo {
        rebound := TypeBuilder.GetField(receiverType, field)
        if rebound == null {
            throw new InvalidOperationException("TypeBuilder.GetField returned no exact instance field.")
        }

        return rebound
    }

    static func RebindMethod(receiverType: Type, method: MethodInfo): MethodInfo {
        rebound := TypeBuilder.GetMethod(receiverType, method)
        if rebound == null {
            throw new InvalidOperationException("TypeBuilder.GetMethod returned no exact instance getter.")
        }

        return rebound
    }

    static func IsStorableResult(resultType: Type): bool {
        return resultType != null && resultType.FullName != "System.Void" && !resultType.get_IsByRef() && !resultType.get_IsGenericTypeDefinition()
    }

    static func EmptySelection(): ColumnarInstanceMemberSelection {
        return new ColumnarInstanceMemberSelection(ColumnarInstanceMemberKind.None, false, false, typeof(object), typeof(int), null, null)
    }

    static func UnwrapParentheses(nodes: ColumnarNodeTable, node: int): int {
        depth := 0
        while node >= 0 && node < nodes.Kinds.Length && nodes.Kind(node) == ColumnarExpressionNodeKind.ParenthesizedExpression() {
            if depth > 200 || nodes.ChildCount(node) != 1 {
                return -1
            }

            node = nodes.Child(node, 0)
            depth += 1
        }

        return node
    }

    static func ValidateInputs(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan) {
        if nodes == null || source == null || bindings == null || plan == null {
            throw new InvalidOperationException("Instance-member planning inputs cannot be null.")
        }

        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Instance-member planning received an invalid root node index.")
        }
    }

    static func RequiredResultType(plan: ColumnarCodePlan): Type {
        resultType := plan.ResultType
        if resultType == null {
            throw new InvalidOperationException("Planned instance-member expression has no result type.")
        }

        return resultType
    }
}
