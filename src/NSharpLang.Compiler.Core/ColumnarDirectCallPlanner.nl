namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

enum ColumnarDirectCallOwnership {
    NotOwned,
    OwnedRejected,
    Planned
}

// Direct owner for fixed-arity, non-generic source methods and the exact external call catalog.
// Receiver and argument types are discovered with callback-free scratch plans before the final
// plan is mutated, so selection never depends on partially emitted IL and every decline is atomic.
class ColumnarDirectCallPlanner {
    static func MayPlanRoot(nodes: ColumnarNodeTable, node: int): bool {
        if nodes == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, node)
        return candidate >= 0 && nodes.Kind(candidate) == ColumnarExpressionNodeKind.CallExpression()
    }

    static func TryEmit(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, il: ILGenerator, out nsharpOwned: bool, out legacyWholeSubtreePlanning: bool, out resultType: Type, modifiedMemberReferences: ColumnarModifiedMemberReferenceLedger? = null): bool {
        ownership := ColumnarDirectCallOwnership.NotOwned
        status := Plan(nodes, source, node, bindings, plan, out ownership, out legacyWholeSubtreePlanning, out resultType)
        ValidateOwnershipBoundary(ownership, legacyWholeSubtreePlanning)
        if status != ColumnarFragmentPlanStatus.Planned {
            nsharpOwned = ownership != ColumnarDirectCallOwnership.NotOwned
            return false
        }

        nsharpOwned = true
        ColumnarCodePlanExecutor.Execute(plan, il, modifiedMemberReferences)
        resultType = ColumnarPlannerSupport.RequiredResultType(plan, "direct call")
        return true
    }

    static func TryGetType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out nsharpOwned: bool, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership := ColumnarDirectCallOwnership.NotOwned
        status := Plan(nodes, source, node, bindings, plan, out ownership, out legacyWholeSubtreePlanning, out resultType)
        ValidateOwnershipBoundary(ownership, legacyWholeSubtreePlanning)
        if status != ColumnarFragmentPlanStatus.Planned {
            nsharpOwned = ownership != ColumnarDirectCallOwnership.NotOwned
            return false
        }

        nsharpOwned = true
        resultType = ColumnarPlannerSupport.RequiredResultType(plan, "direct call")
        return true
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): ColumnarFragmentPlanStatus {
        ValidateInputs(nodes, source, node, bindings, plan)
        plan.PrepareV3()
        if !TryAppendRoot(nodes, source, node, bindings, plan, out ownership, out legacyWholeSubtreePlanning, out resultType) {
            return plan.Status
        }

        plan.CompleteV3(resultType)
        ownership = ColumnarDirectCallOwnership.Planned
        return plan.Status
    }

    // THE ROOT-APPEND SEQUENCE, OWNED ONCE (015-B7). A call root is a checkpoint, a root fragment, the
    // resolved handles, the append and the fragment's completion — the same five steps whether the plan
    // is a standalone schema-v3 expression (`Plan` wraps this between `PrepareV3` and `CompleteV3`) or
    // an open schema-v4 METHOD BODY (`ColumnarMethodBodyPlanner`'s expression door calls it directly).
    // Both callers therefore produce the SAME row sequence, which is the whole of producing the same
    // bytes: `ColumnarIlEmitter.EmitExpressionCore` reaches this owner through
    // `ColumnarRangeIndexPlanner.TryEmitFromFacts`'s SECOND cascade arm for every call root — the four
    // pre-cascade owners have no call arm and the construction owner answers only `new`/object-initializer
    // /array-literal — so byte identity for a claimed call is against one owner.
    //
    // ⚠ A VOID RESULT IS REFUSED HERE RATHER THAN THROWN AT `CompleteFragment`, AND THAT GUARD IS NEW
    // WITH THE SECOND CALLER. `CompleteFragment` admits a `System.Void` result only on a schema-v3 root
    // fragment, which is exactly what `Plan` always hands it — a statement-position `foo()` is planned
    // that way today. A METHOD BODY is neither v3 nor necessarily fragment 0, so `x := SomeVoidCall()` —
    // a shape the parser produces and the host declines at its own supported-type gate — would leave the
    // compiler through a thrown `InvalidOperationException` instead of a decline. The condition below is
    // `CompleteFragment`'s own admission rule spelled the other way round, so `Plan`'s v3 behaviour is
    // bit-for-bit unchanged and only the new caller can reach the refusal. The ownership outs are left
    // exactly as the append set them: the owner really did plan the call, and it is the PLAN that cannot
    // carry the result, so reporting `NotOwned` here would be a false statement about the owner.
    static func TryAppendRoot(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if nodes == null || source == null || bindings == null || plan == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, node)
        if candidate < 0 || nodes.Kind(candidate) != ColumnarExpressionNodeKind.CallExpression() {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            fragment := plan.BeginFragment(-1, ColumnarExpressionNodeKind.CallExpression(), candidate)

            handles := ColumnarRangeIndexHandles.Resolve()
            if !TryAppendCall(nodes, source, candidate, bindings, handles, plan, fragment, 0, out ownership, out legacyWholeSubtreePlanning, out resultType) {
                plan.Rollback(checkpoint)
                return false
            }
            if IsVoidType(resultType) && !plan.IsMethodBodySchema() && (plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() || fragment != 0) {
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

    // This flag is a whole-expression queue boundary, never a recovery route for a rejected N#
    // call. It is true only when a child expression or excluded call family belongs to a later
    // owner; every OwnedRejected result must remain terminal in N#.
    static func ValidateOwnershipBoundary(ownership: ColumnarDirectCallOwnership, legacyWholeSubtreePlanning: bool) {
        if legacyWholeSubtreePlanning && ownership != ColumnarDirectCallOwnership.NotOwned {
            throw new InvalidOperationException("Legacy whole-subtree planning requires a NotOwned direct-call result.")
        }
    }

    static func TryAppendCall(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if nodes == null || source == null || bindings == null || handles == null || plan == null || node < 0 || node >= nodes.Kinds.Length || nodes.Kind(node) != ColumnarExpressionNodeKind.CallExpression() || nodes.ChildCount(node) < 1 || depth > 200 {
            return false
        }

        // 015-B6: a schema-v4 METHOD BODY is admitted alongside v3. This gate threw — a hard crash out
        // of the compiler, not a decline — on every method-body plan, and ALL NINE owners that carried
        // it were widened in ONE move because the value surface routes by operand kind: admitting a
        // subset would mean pre-scanning operands to predict which owner they reach, which is a second
        // copy of the dispatcher's own decision.
        // Its arguments recurse through the shared value dispatcher, so it could not be admitted
        // alone.
        if (plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() && plan.SchemaVersion != ColumnarCodePlanContract.MethodBodySchemaVersion()) || plan.Status != ColumnarFragmentPlanStatus.NotOwned || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Direct-call append requires an open schema-v3 or method-body plan.")
        }

        // Contextual-lambda preflight uses a synthetic parameter frame: its first lambda parameter
        // temporarily occupies ordinal zero even when member lookup still sees the enclosing instance.
        // That frame cannot emit an implicit receiver safely. Contextual lambdas are outside this
        // ownership slice, so leave the whole call to the legacy child planner without mutating the plan.
        if bindings.CurrentInstance != null && bindings.HasParameterOrdinal(0) {
            legacyWholeSubtreePlanning = true
            return false
        }

        callee := ColumnarPlannerSupport.UnwrapParentheses(nodes, nodes.Child(node, 0))
        if callee < 0 {
            return false
        }

        calleeKind := nodes.Kind(callee)
        if calleeKind != ColumnarExpressionNodeKind.IdentifierExpression() && calleeKind != ColumnarExpressionNodeKind.MemberAccessExpression() && calleeKind != 38 && calleeKind != ColumnarExpressionNodeKind.BaseMemberExpression() {
            return false
        }

        // Callable names that are NOT plannable siblings stay legacy: visible local functions and
        // any residual declared-callable name without routed sibling facts decline here exactly as
        // before. A plannable sibling flows through to the sibling-ownership path below.
        if calleeKind == ColumnarExpressionNodeKind.IdentifierExpression() && !ColumnarExpressionSyntaxFacts.IsExplicitThisIdentifier(nodes, source, callee) {
            bareCallable := nodes.Text(source, callee)
            if bindings.IsCallable(bareCallable) && !bindings.HasSiblingCallable(bareCallable) {
                return false
            }
        }

        if calleeKind == ColumnarExpressionNodeKind.IdentifierExpression() {
            bareName := nodes.Text(source, callee)
            explicitThis := ColumnarExpressionSyntaxFacts.IsExplicitThisIdentifier(nodes, source, callee)

            currentFacts := bindings.CurrentInstance
            currentDefinition: ColumnarStructDef? = null
            if currentFacts != null {
                currentDefinition = currentFacts.SourceDefinition
            }

            argumentCount := nodes.ChildCount(node) - 1
            hasInstance := currentDefinition != null && currentFacts != null && (ColumnarSourceDirectCallResolver.HasInstanceDeclarationAtArity(currentDefinition, bareName, argumentCount) || HasExcludedInstanceOwnerAtArity(currentDefinition, currentFacts.ExactType, bareName, argumentCount))

            enclosingDefinition := bindings.EnclosingTypeDefinition
            hasStatic := enclosingDefinition != null && (ColumnarSourceDirectCallResolver.HasStaticDeclarationAtArity(enclosingDefinition, bareName, argumentCount) || HasExcludedStaticOwnerAtArity(enclosingDefinition, bareName, argumentCount))

            hasSibling := bindings.HasSiblingCallable(bareName)

            // A bare name with no source/static/sibling tier may still bind to a method inherited
            // from an external runtime base (`Ok` -> ControllerBase.Ok). Keep those from bailing out
            // early so the inherited-external arm in TryAppendBareCall can select and plan them.
            hasInheritedExternal := currentDefinition != null && !ColumnarSourceDirectCallResolver.HasInstanceDeclaration(currentDefinition, bareName) && HasInheritedExternalInstanceMethod(currentDefinition, bareName, argumentCount)

            // A delegate-typed value with no same-named method tier is invoked through its Invoke
            // method — a local, a parameter, a lifted capture or a FIELD of the current instance
            // alike. Let those bare calls flow to the delegate-invoke owner instead of declining
            // early.
            if !explicitThis && !hasInstance && !hasStatic && !hasSibling && !hasInheritedExternal && !bindings.IsSiblingShadowedByValue(bareName) && !IsDelegateValueCallee(nodes, source, callee, bindings) {
                return false
            }
        }

        argumentTypes := new Type[](nodes.ChildCount(node) - 1)

        // Target-typed arguments (lambdas and method groups) need to sit directly under the call
        // while their provisional type is discovered. When the names already occupy their declared
        // positions, validate that fact against the reachable signatures and erase only those
        // information-free wrappers before asking the type oracle.
        preliminaryPlacement := new int[](0)
        if ColumnarNamedArgumentBinder.HasNamedArgument(nodes, node, 1, argumentTypes.Length) {
            TryFlattenAgreedInPositionNames(nodes, source, node, callee, calleeKind, bindings, handles, depth, plan.IsMethodBodySchema(), argumentTypes.Length, out preliminaryPlacement)
        }

        // NAMED ARGUMENTS ARE PLACED BEFORE ANYTHING ELSE LOOKS AT THEM. Every owner below this point
        // -- argument typing, overload selection, conversions, the argument walk -- reads argument `i`
        // as parameter `i`, and that is the whole reason a name is resolved here: the placement is
        // decided once, against the signatures the call could actually reach, and nothing downstream
        // learns that a name was ever written. A call whose names cannot be placed is left exactly as
        // written and declines, so a mis-placement can never reach IL.
        //
        // A placement that leaves every argument where it was written is FLATTENED into the node
        // table straight away: the wrappers then carry nothing, and a call this planner goes on to
        // decline for some unrelated reason reaches the residual emitter as the positional call it
        // is. A placement that MOVES an argument is kept here and applied to the argument rows below,
        // because only this planner can emit the move while preserving the written evaluation order.
        argumentFacts := ColumnarDirectCallArgumentFacts.Empty(argumentTypes.Length)
        argumentFacts.SourceTypeDefinitions = bindings.SourceTypeDefinitions
        argumentOwnership := ColumnarDirectCallOwnership.NotOwned
        if !TryGetArgumentTypes(nodes, source, node, bindings, handles, depth, ArgumentsAdmitPrimitiveBinary(), plan.IsMethodBodySchema(), argumentTypes, argumentFacts, out argumentOwnership) {
            if argumentOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
            } else {
                legacyWholeSubtreePlanning = true
            }

            return false
        }

        namedPlacement := new int[](0)
        if ColumnarNamedArgumentBinder.HasNamedArgument(nodes, node, 1, argumentTypes.Length) && !TryPlaceNamedCallArguments(nodes, source, node, callee, calleeKind, bindings, handles, depth, plan.IsMethodBodySchema(), argumentTypes, argumentFacts, out namedPlacement) {
            sparseCheckpoint := plan.CreateCheckpoint()
            if calleeKind == 38 && TryAppendExplicitGenericSourceInstanceCall(nodes, source, node, callee, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, out ownership, out legacyWholeSubtreePlanning, out resultType) {
                return true
            }
            plan.Rollback(sparseCheckpoint)
            sparseCheckpoint = plan.CreateCheckpoint()
            if calleeKind == 38 && TryAppendExplicitGenericSiblingCall(nodes, source, node, callee, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, out ownership, out legacyWholeSubtreePlanning, out resultType) {
                return true
            }
            plan.Rollback(sparseCheckpoint)
            sparseCheckpoint = plan.CreateCheckpoint()
            if calleeKind == 38 && TryAppendExplicitGenericStaticCall(nodes, source, node, callee, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, sparseCheckpoint, out ownership, out legacyWholeSubtreePlanning, out resultType) {
                return true
            }
            plan.Rollback(sparseCheckpoint)
            sparseCheckpoint = plan.CreateCheckpoint()
            if TryAppendSparseNamedSiblingCall(nodes, source, node, callee, calleeKind, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, out resultType) {
                return true
            }
            plan.Rollback(sparseCheckpoint)
            sparseCheckpoint = plan.CreateCheckpoint()
            if TryAppendSparseNamedSourceMemberCall(nodes, source, node, callee, calleeKind, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, out resultType) {
                return true
            }
            plan.Rollback(sparseCheckpoint)
            sparseCheckpoint = plan.CreateCheckpoint()
            if TryAppendSparseNamedRuntimeMemberCall(nodes, source, node, callee, calleeKind, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, out resultType) {
                return true
            }
            plan.Rollback(sparseCheckpoint)
            legacyWholeSubtreePlanning = true
            return false
        }

        if namedPlacement.Length == argumentTypes.Length && !ColumnarNamedArgumentBinder.ApplyPlacement(argumentTypes, argumentFacts, namedPlacement) {
            legacyWholeSubtreePlanning = true
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        if TryAppendPlacedCall(nodes, source, node, callee, calleeKind, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, checkpoint, out ownership, out legacyWholeSubtreePlanning, out resultType) {
            return true
        }

        // AN OMITTED TRAILING DEFAULT IS NOT AN ARITY MISMATCH, AND A POSITIONAL CALL NEVER SAID SO.
        // The tier above selects a source declaration by EXACT parameter count, so
        // `Producer.Make("a")` against `Make(a: string, d: string? = null)` found no candidate and
        // declined — in the SAME compilation, while the identical omission through a reference
        // already bound, because the runtime resolver has carried an optional-fill tier for a while.
        // The fill itself was already written and already correct: the sparse tier below places the
        // written arguments into their slots, stores each one as it is evaluated so the WRITTEN order
        // is what runs, and asks the shared constructor-default owner for every slot the call left
        // out. It was only ever reachable behind `HasNamedArgument`, so a call that named nothing
        // could not get to it. Positional calls now reach the SAME owner, after the exact-arity tier
        // has had its say, so an exact-arity overload still wins and the decline the ordinary route
        // reported is restored untouched when no candidate can be filled.
        if !ColumnarNamedArgumentBinder.HasNamedArgument(nodes, node, 1, argumentTypes.Length) {
            declinedOwnership := ownership
            declinedLegacy := legacyWholeSubtreePlanning
            declinedResult := resultType
            fillCheckpoint := plan.CreateCheckpoint()
            if TryAppendSparseNamedSiblingCall(nodes, source, node, callee, calleeKind, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, out resultType) {
                ownership = ColumnarDirectCallOwnership.Planned
                legacyWholeSubtreePlanning = false
                return true
            }
            plan.Rollback(fillCheckpoint)
            fillCheckpoint = plan.CreateCheckpoint()
            if TryAppendSparseNamedSourceMemberCall(nodes, source, node, callee, calleeKind, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, out resultType) {
                ownership = ColumnarDirectCallOwnership.Planned
                legacyWholeSubtreePlanning = false
                return true
            }
            plan.Rollback(fillCheckpoint)
            ownership = declinedOwnership
            legacyWholeSubtreePlanning = declinedLegacy
            resultType = declinedResult
        }

        return false
    }

    // The exact-arity dispatch, unchanged, named so the default-fill retry above can run after it.
    static func TryAppendPlacedCall(nodes: ColumnarNodeTable, source: string, node: int, callee: int, calleeKind: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, checkpoint: ColumnarCodePlanCheckpoint, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        try {
            if calleeKind == ColumnarExpressionNodeKind.IdentifierExpression() {
                return TryAppendBareCall(nodes, source, node, callee, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, checkpoint, out ownership, out legacyWholeSubtreePlanning, out resultType)
            }

            if calleeKind == 38 {
                if TryAppendExplicitGenericSourceInstanceCall(nodes, source, node, callee, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, out ownership, out legacyWholeSubtreePlanning, out resultType) {
                    return true
                }
                if TryAppendExplicitGenericSiblingCall(nodes, source, node, callee, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, out ownership, out legacyWholeSubtreePlanning, out resultType) {
                    return true
                }
                return TryAppendExplicitGenericStaticCall(nodes, source, node, callee, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, checkpoint, out ownership, out legacyWholeSubtreePlanning, out resultType)
            }

            if calleeKind == ColumnarExpressionNodeKind.BaseMemberExpression() {
                return TryAppendBaseCall(nodes, source, node, callee, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, checkpoint, out ownership, out legacyWholeSubtreePlanning, out resultType)
            }

            return TryAppendMemberCall(nodes, source, node, callee, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, checkpoint, out ownership, out legacyWholeSubtreePlanning, out resultType)
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    static func TryAppendExplicitGenericSourceInstanceCall(nodes: ColumnarNodeTable, source: string, callNode: int, callee: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        calleeName := nodes.Text(source, callee)
        separator := calleeName.LastIndexOf(".", StringComparison.Ordinal)
        if separator <= 0 || separator >= calleeName.Length - 1 {
            return false
        }
        receiverName := calleeName.Substring(0, separator)
        memberName := calleeName.Substring(separator + 1)
        receiverType := typeof(object)
        if !TryGetNamedReceiverType(receiverName, bindings, out receiverType) {
            return false
        }
        definition := ColumnarNamedArgumentBinder.FindReceiverDefinition(receiverType, bindings.SourceTypeDefinitions)
        if definition == null {
            return false
        }
        candidates: List<ColumnarInstanceMethodDef>? = null
        let current: ColumnarStructDef? = definition
        while current != null && candidates == null {
            current.MethodOverloads.TryGetValue(memberName, out candidates)
            current = current.BaseDef
        }
        if candidates == null {
            return false
        }

        scope := nodes.BindingScope
        if scope == null {
            return false
        }
        methodArguments := new Type[](ColumnarGenericCalleeFacts.TypeArgumentCount(nodes, callee))
        index := 0
        while index < methodArguments.Length {
            canonical := ""
            claimed := false
            resolvedArgument := typeof(object)
            if !ColumnarTypeOfPlanner.TryBuildTypeCanonical(nodes, source, ColumnarGenericCalleeFacts.TypeArgumentNode(nodes, callee, index), 0, out canonical) || !scope.TryResolveExactExplicitTypeInContext(nodes.EnclosingTypeName, canonical, bindings, out resolvedArgument, out claimed) {
                return false
            }
            methodArguments[index] = resolvedArgument
            index += 1
        }
        ownerParameters := definition.Builder.GetGenericArguments()
        ownerArguments := new Type[](0)
        if receiverType.get_IsGenericType() {
            ownerArguments = receiverType.GetGenericArguments()
        }

        selected: ColumnarInstanceMethodDef? = null
        selectedParameters := new Type[](0)
        selectedReturn := typeof(object)
        selectedUsesParams := false
        bestScore := -1
        tied := false
        for candidate in candidates {
            generics := candidate.Generics
            if generics == null || generics.TypeParams.Length != methodArguments.Length || candidate.ParamNames.Length != candidate.ParamTypes.Length || candidate.ParamDefaultKinds.Length != candidate.ParamTypes.Length || candidate.ParamDefaultTexts.Length != candidate.ParamTypes.Length || candidate.ParamModifierKinds.Length != candidate.ParamTypes.Length {
                continue
            }
            parameters := new Type[](candidate.ParamTypes.Length)
            valid := true
            p := 0
            while p < parameters.Length {
                closedParameter := typeof(object)
                if !ColumnarGenericConstraintPlanner.TrySubstituteGenericMemberType(ownerParameters, ownerArguments, generics.TypeParams, methodArguments, candidate.ParamTypes[p], out closedParameter) {
                    valid = false
                }
                parameters[p] = closedParameter
                p += 1
            }
            closedReturn := typeof(object)
            if !valid || !ColumnarGenericConstraintPlanner.TrySubstituteGenericMemberType(ownerParameters, ownerArguments, generics.TypeParams, methodArguments, candidate.ReturnType, out closedReturn) {
                continue
            }
            score := -1
            if !TryScoreExplicitGenericBoundArguments(nodes, source, callNode, bindings, argumentTypes, argumentFacts, parameters, candidate.ParamNames, candidate.ParamDefaultKinds, candidate.ParamDefaultTexts, candidate.ParamModifierKinds, out score) {
                continue
            }
            if score > bestScore {
                bestScore = score
                selected = candidate
                selectedParameters = parameters
                selectedReturn = closedReturn
                selectedUsesParams = HasExplicitGenericParamsTail(candidate.ParamModifierKinds)
                tied = false
            } else if score >= 0 && score == bestScore {
                candidateUsesParams := HasExplicitGenericParamsTail(candidate.ParamModifierKinds)
                tieBreak := CompareExplicitGenericBoundTie(selectedUsesParams, selectedParameters.Length, candidateUsesParams, parameters.Length, argumentTypes.Length)
                if tieBreak == AnalyzerOverloadSpecificity.RightIsBetter {
                    selected = candidate
                    selectedParameters = parameters
                    selectedReturn = closedReturn
                    selectedUsesParams = candidateUsesParams
                    tied = false
                } else if tieBreak == AnalyzerOverloadSpecificity.NeitherIsBetter {
                    tied = true
                }
            }
        }
        if selected == null || tied || !AppendNamedReceiver(receiverName, receiverType, definition.IsReference, bindings, plan) {
            return false
        }
        if !TryAppendExplicitGenericBoundArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, argumentTypes, argumentFacts, selectedParameters, selected.ParamNames, selected.ParamDefaultKinds, selected.ParamDefaultTexts, selected.ParamModifierKinds) {
            return false
        }
        selectedGenerics := selected.Generics
        sourceRegistry := new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal)
        for sourceDefinition in bindings.SourceTypeDefinitions {
            sourceRegistry[sourceDefinition.DeclaredTypeName] = sourceDefinition
        }
        if selectedGenerics == null || !ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(selectedGenerics.TypeParams, selectedGenerics.SpecialConstraints, selectedGenerics.BaseConstraints, selectedGenerics.InterfaceConstraints, methodArguments, methodArguments, sourceRegistry) {
            return false
        }
        definitionMethod: MethodInfo = selected.Builder
        if receiverType.get_IsGenericType() && !receiverType.get_IsGenericTypeDefinition() {
            definitionMethod = ColumnarClosedGenericMemberResolver.ResolveMethod(receiverType, selected.Builder)
        }
        closedMethod := definitionMethod.MakeGenericMethod(methodArguments)
        methodIndex := plan.AddMethodWithSignature(closedMethod, receiverType, selectedParameters, selectedReturn, false, selected.Builder.get_IsAbstract())
        plan.AppendMethodInstruction((short)(definition.IsReference ? ColumnarCodePlanContract.Callvirt() : ColumnarCodePlanContract.Call()), methodIndex)
        resultType = selectedReturn
        ownership = ColumnarDirectCallOwnership.Planned
        return !IsVoidType(resultType) || callFragment == 0 || plan.IsMethodBodyRootFragment(callFragment)
    }

    static func TryGetNamedReceiverType(name: string, bindings: ColumnarFragmentBindings, out receiverType: Type): bool {
        receiverType = typeof(object)
        if bindings.Locals.ContainsKey(name) {
            receiverType = bindings.Locals[name].get_LocalType()
            return true
        }
        if bindings.PlanLocals.ContainsKey(name) {
            receiverType = bindings.PlanLocals[name].Item2
            return true
        }
        return bindings.ParameterTypes.TryGetValue(name, out receiverType) && !receiverType.get_IsByRef()
    }

    static func AppendNamedReceiver(name: string, receiverType: Type, isReference: bool, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan): bool {
        if bindings.Locals.ContainsKey(name) {
            local := plan.AddAmbientLocal(bindings.Locals[name])
            plan.AppendAmbientLocalInstruction((short)(isReference ? ColumnarCodePlanContract.Ldloc() : ColumnarCodePlanContract.Ldloca()), local)
            return true
        }
        if bindings.PlanLocals.ContainsKey(name) {
            local := bindings.PlanLocals[name].Item1
            plan.AppendPlanLocalInstruction((short)(isReference ? ColumnarCodePlanContract.Ldloc() : ColumnarCodePlanContract.Ldloca()), local)
            return true
        }
        if bindings.ParameterOrdinals.ContainsKey(name) {
            ordinal := bindings.ParameterOrdinals[name]
            argumentIndex := -1
            index := 0
            while index < plan.ArgumentCount {
                if plan.ArgumentOrdinals[index] == ordinal {
                    argumentIndex = index
                    break
                }
                index += 1
            }
            if argumentIndex < 0 {
                argumentIndex = plan.AddArgument(ordinal, plan.AddType(receiverType), false)
            }
            plan.AppendArgumentInstruction((short)(isReference ? ColumnarCodePlanContract.Ldarg() : ColumnarCodePlanContract.Ldarga()), argumentIndex)
            return true
        }
        return false
    }

    static func CopyArgumentFactInto(sourceFacts: ColumnarDirectCallArgumentFacts, sourceIndex: int, targetFacts: ColumnarDirectCallArgumentFacts, targetIndex: int) {
        targetFacts.SourceTypeDefinitions = sourceFacts.SourceTypeDefinitions
        targetFacts.ArgumentNodes[targetIndex] = sourceFacts.ArgumentNodes[sourceIndex]
        targetFacts.IsUnsuffixedIntegerLiteral[targetIndex] = sourceFacts.IsUnsuffixedIntegerLiteral[sourceIndex]
        targetFacts.IsNegativeIntegerLiteral[targetIndex] = sourceFacts.IsNegativeIntegerLiteral[sourceIndex]
        targetFacts.IntegerLiteralValues[targetIndex] = sourceFacts.IntegerLiteralValues[sourceIndex]
        targetFacts.IsNullLiteral[targetIndex] = sourceFacts.IsNullLiteral[sourceIndex]
        targetFacts.IsByRefArgument[targetIndex] = sourceFacts.IsByRefArgument[sourceIndex]
        targetFacts.IsIntegerConstantArrayLiteral[targetIndex] = sourceFacts.IsIntegerConstantArrayLiteral[sourceIndex]
        targetFacts.ArrayLiteralMinimumValues[targetIndex] = sourceFacts.ArrayLiteralMinimumValues[sourceIndex]
        targetFacts.ArrayLiteralMaximumValues[targetIndex] = sourceFacts.ArrayLiteralMaximumValues[sourceIndex]
    }

    static func TryAppendSparseNamedSiblingCall(nodes: ColumnarNodeTable, source: string, callNode: int, callee: int, calleeKind: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, out resultType: Type): bool {
        resultType = typeof(int)
        if calleeKind != ColumnarExpressionNodeKind.IdentifierExpression() {
            return false
        }
        name := nodes.Text(source, callee)
        facts: ColumnarSiblingCallFacts? = null
        if !bindings.SiblingCallables.TryGetValue(name, out facts) || facts == null || facts.TypeParameterCount != 0 || facts.ParameterTypes.Length <= argumentTypes.Length || facts.ParameterNames.Length != facts.ParameterTypes.Length || facts.ParameterDefaultKinds.Length != facts.ParameterTypes.Length || facts.ParameterDefaultTexts.Length != facts.ParameterTypes.Length {
            return false
        }

        placement := new int[](0)
        claimed := new bool[](0)
        if !ColumnarNamedArgumentBinder.TryPlaceSparse(nodes, source, callNode, 1, argumentTypes.Length, facts.ParameterNames, out placement, out claimed) {
            return false
        }
        slot := 0
        while slot < claimed.Length {
            if !claimed[slot] && facts.ParameterDefaultKinds[slot] < 0 {
                return false
            }
            slot += 1
        }

        locals := new int[](facts.ParameterTypes.Length)
        Array.Fill(locals, -1)
        written := 0
        while written < argumentTypes.Length {
            parameterSlot := placement[written]
            singleTypes := new Type[](1)
            singleTypes[0] = argumentTypes[written]
            singleParameters := new Type[](1)
            singleParameters[0] = facts.ParameterTypes[parameterSlot]
            singleFacts := CopyArgumentFact(argumentFacts, written)
            if ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(singleParameters, singleTypes, singleFacts) < 0 || singleFacts.IsByRefArgument[0] || !AppendArgumentSlot(nodes, source, bindings, handles, plan, callFragment, depth + 1, ArgumentsAdmitPrimitiveBinary(), singleTypes, singleParameters, singleFacts, 0) {
                return false
            }
            local := plan.DeclarePlanLocal(plan.AddType(singleParameters[0]))
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), local)
            locals[parameterSlot] = local
            written += 1
        }

        slot = 0
        while slot < facts.ParameterTypes.Length {
            if locals[slot] >= 0 {
                plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), locals[slot])
            } else if !ColumnarConstructionPlanner.TryAppendConstructorDefault(nodes, plan, facts.ParameterTypes[slot], facts.ParameterDefaultKinds[slot], facts.ParameterDefaultTexts[slot], bindings) {
                return false
            }
            slot += 1
        }

        declaringType := facts.Method.get_DeclaringType()
        if declaringType == null {
            return false
        }
        methodIndex := plan.AddMethodWithSignature(facts.Method, declaringType, facts.ParameterTypes, facts.ReturnType, true, false)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
        resultType = facts.ReturnType
        return !IsVoidType(resultType) || callFragment == 0 || plan.IsMethodBodyRootFragment(callFragment)
    }

    static func CopyArgumentFact(sourceFacts: ColumnarDirectCallArgumentFacts, index: int): ColumnarDirectCallArgumentFacts {
        copy := ColumnarDirectCallArgumentFacts.Empty(1)
        copy.SourceTypeDefinitions = sourceFacts.SourceTypeDefinitions
        copy.ArgumentNodes[0] = sourceFacts.ArgumentNodes[index]
        copy.IsUnsuffixedIntegerLiteral[0] = sourceFacts.IsUnsuffixedIntegerLiteral[index]
        copy.IsNegativeIntegerLiteral[0] = sourceFacts.IsNegativeIntegerLiteral[index]
        copy.IntegerLiteralValues[0] = sourceFacts.IntegerLiteralValues[index]
        copy.IsNullLiteral[0] = sourceFacts.IsNullLiteral[index]
        copy.IsByRefArgument[0] = sourceFacts.IsByRefArgument[index]
        copy.IsIntegerConstantArrayLiteral[0] = sourceFacts.IsIntegerConstantArrayLiteral[index]
        copy.ArrayLiteralMinimumValues[0] = sourceFacts.ArrayLiteralMinimumValues[index]
        copy.ArrayLiteralMaximumValues[0] = sourceFacts.ArrayLiteralMaximumValues[index]
        return copy
    }

    static func TryAppendSparseNamedSourceMemberCall(nodes: ColumnarNodeTable, source: string, callNode: int, callee: int, calleeKind: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, out resultType: Type): bool {
        resultType = typeof(int)
        if calleeKind != ColumnarExpressionNodeKind.MemberAccessExpression() || nodes.ChildCount(callee) != 1 {
            return false
        }
        receiverNode := nodes.Child(callee, 0)
        ownerName := ""
        rootName := ""
        if ColumnarPlannerSupport.TryGetQualifiedName(nodes, source, receiverNode, 0, true, out ownerName, out rootName) && !bindings.IsValueBinding(rootName) && !bindings.IsCallable(rootName) {
            scope := nodes.BindingScope
            exactOwnerName := ownerName
            ownerBlocked := false
            if scope == null || scope.TryResolveSourceStaticOwner(nodes.EnclosingTypeName, nodes.VisibleTypeParameterNames, rootName, ownerName, out exactOwnerName, out ownerBlocked) {
                owner := FindExactSourceOwner(exactOwnerName, bindings.SourceTypeDefinitions)
                if owner != null {
                    return TryAppendSparseNamedSourceStaticCall(nodes, source, callNode, nodes.Text(source, callee), owner, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, out resultType)
                }
            }
        }
        receiverType := typeof(object)
        receiverOwnership := ColumnarDirectCallOwnership.NotOwned
        if !TryGetPlannableValueType(nodes, source, receiverNode, bindings, handles, depth + 1, ArgumentsAdmitPrimitiveBinary(), plan.IsMethodBodySchema(), out receiverType, out receiverOwnership) {
            return false
        }
        definition := ColumnarNamedArgumentBinder.FindReceiverDefinition(receiverType, bindings.SourceTypeDefinitions)
        if definition == null {
            return false
        }
        memberName := nodes.Text(source, callee)
        candidates := new List<ColumnarInstanceMethodDef>()
        let current: ColumnarStructDef? = definition
        while current != null {
            foundAtLevel := false
            single: ColumnarInstanceMethodDef? = null
            if current.Methods.TryGetValue(memberName, out single) && single != null {
                candidates.Add(single)
                foundAtLevel = true
            }
            overloads: List<ColumnarInstanceMethodDef>? = null
            if current.MethodOverloads.TryGetValue(memberName, out overloads) {
                for overload in overloads {
                    candidates.Add(overload)
                }
                foundAtLevel = true
            }
            // Ordinary member lookup stops at the first declaration level containing the name.
            // A base method cannot re-enter the set merely because a derived overload needs defaults.
            if foundAtLevel {
                break
            }
            current = current.BaseDef
        }

        selected: ColumnarInstanceMethodDef? = null
        selectedPlacement := new int[](0)
        selectedClaimed := new bool[](0)
        bestScore := -1
        tied := false
        for candidate in candidates {
            placement := new int[](0)
            claimed := new bool[](0)
            if candidate.Generics != null || candidate.ParamTypes.Length <= argumentTypes.Length || candidate.ParamNames.Length != candidate.ParamTypes.Length || candidate.ParamDefaultKinds.Length != candidate.ParamTypes.Length || candidate.ParamDefaultTexts.Length != candidate.ParamTypes.Length || !ColumnarNamedArgumentBinder.TryPlaceSparse(nodes, source, callNode, 1, argumentTypes.Length, candidate.ParamNames, out placement, out claimed) {
                continue
            }
            fillable := true
            score := 0
            slot := 0
            while slot < candidate.ParamTypes.Length {
                if !claimed[slot] && !ColumnarConstructionPlanner.CanUseConstructorDefault(nodes, candidate.ParamTypes[slot], candidate.ParamDefaultKinds[slot], candidate.ParamDefaultTexts[slot], bindings) {
                    fillable = false
                }
                slot += 1
            }
            written := 0
            while fillable && written < argumentTypes.Length {
                expected := new Type[](1)
                expected[0] = candidate.ParamTypes[placement[written]]
                actual := new Type[](1)
                actual[0] = argumentTypes[written]
                scorePart := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(expected, actual, CopyArgumentFact(argumentFacts, written))
                if scorePart < 0 {
                    fillable = false
                } else {
                    score += scorePart
                }
                written += 1
            }
            if !fillable {
                continue
            }
            if score > bestScore {
                bestScore = score
                selected = candidate
                selectedPlacement = placement
                selectedClaimed = claimed
                tied = false
            } else if score == bestScore && selected != null && !Object.ReferenceEquals(selected.Builder, candidate.Builder) {
                tied = true
            }
        }
        if selected == null || tied || !AppendExplicitReceiver(nodes, source, receiverNode, bindings, handles, plan, callFragment, depth + 1, receiverType, definition.IsReference) {
            return false
        }

        locals := new int[](selected.ParamTypes.Length)
        Array.Fill(locals, -1)
        written := 0
        while written < argumentTypes.Length {
            slot := selectedPlacement[written]
            expected := new Type[](1)
            expected[0] = selected.ParamTypes[slot]
            actual := new Type[](1)
            actual[0] = argumentTypes[written]
            oneFacts := CopyArgumentFact(argumentFacts, written)
            if oneFacts.IsByRefArgument[0] || !AppendArgumentSlot(nodes, source, bindings, handles, plan, callFragment, depth + 1, true, actual, expected, oneFacts, 0) {
                return false
            }
            local := plan.DeclarePlanLocal(plan.AddType(expected[0]))
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), local)
            locals[slot] = local
            written += 1
        }
        slot := 0
        while slot < selected.ParamTypes.Length {
            if selectedClaimed[slot] {
                plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), locals[slot])
            } else if !ColumnarConstructionPlanner.TryAppendConstructorDefault(nodes, plan, selected.ParamTypes[slot], selected.ParamDefaultKinds[slot], selected.ParamDefaultTexts[slot], bindings) {
                return false
            }
            slot += 1
        }
        declaringType := selected.Builder.get_DeclaringType()
        if declaringType == null {
            return false
        }
        methodIndex := plan.AddMethodWithSignature(selected.Builder, declaringType, selected.ParamTypes, selected.ReturnType, false, selected.Builder.get_IsAbstract())
        plan.AppendMethodInstruction((short)(definition.IsReference ? ColumnarCodePlanContract.Callvirt() : ColumnarCodePlanContract.Call()), methodIndex)
        resultType = selected.ReturnType
        return !IsVoidType(resultType) || callFragment == 0 || plan.IsMethodBodyRootFragment(callFragment)
    }

    static func TryAppendSparseNamedSourceStaticCall(nodes: ColumnarNodeTable, source: string, callNode: int, memberName: string, owner: ColumnarStructDef, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, out resultType: Type): bool {
        resultType = typeof(int)
        candidates: List<ColumnarStaticMethodDef>? = null
        if !owner.StaticMethods.TryGetValue(memberName, out candidates) || candidates == null {
            return false
        }
        selected: ColumnarStaticMethodDef? = null
        selectedPlacement := new int[](0)
        selectedClaimed := new bool[](0)
        bestScore := -1
        tied := false
        for candidate in candidates {
            placement := new int[](0)
            claimed := new bool[](0)
            if candidate.Generics != null || candidate.ParamTypes.Length <= argumentTypes.Length || candidate.ParamNames.Length != candidate.ParamTypes.Length || candidate.ParamDefaultKinds.Length != candidate.ParamTypes.Length || candidate.ParamDefaultTexts.Length != candidate.ParamTypes.Length || !ColumnarNamedArgumentBinder.TryPlaceSparse(nodes, source, callNode, 1, argumentTypes.Length, candidate.ParamNames, out placement, out claimed) {
                continue
            }
            fillable := true
            score := 0
            slot := 0
            while slot < candidate.ParamTypes.Length {
                if !claimed[slot] && !ColumnarConstructionPlanner.CanUseConstructorDefault(nodes, candidate.ParamTypes[slot], candidate.ParamDefaultKinds[slot], candidate.ParamDefaultTexts[slot], bindings) {
                    fillable = false
                }
                slot += 1
            }
            written := 0
            while fillable && written < argumentTypes.Length {
                expected := new Type[](1)
                expected[0] = candidate.ParamTypes[placement[written]]
                actual := new Type[](1)
                actual[0] = argumentTypes[written]
                scorePart := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(expected, actual, CopyArgumentFact(argumentFacts, written))
                if scorePart < 0 {
                    fillable = false
                } else {
                    score += scorePart
                }
                written += 1
            }
            if !fillable {
                continue
            }
            if score > bestScore {
                bestScore = score
                selected = candidate
                selectedPlacement = placement
                selectedClaimed = claimed
                tied = false
            } else if score == bestScore && selected != null && !Object.ReferenceEquals(selected.Builder, candidate.Builder) {
                tied = true
            }
        }
        if selected == null || tied {
            return false
        }
        locals := new int[](selected.ParamTypes.Length)
        Array.Fill(locals, -1)
        written := 0
        while written < argumentTypes.Length {
            slot := selectedPlacement[written]
            expected := new Type[](1)
            expected[0] = selected.ParamTypes[slot]
            actual := new Type[](1)
            actual[0] = argumentTypes[written]
            oneFacts := CopyArgumentFact(argumentFacts, written)
            if oneFacts.IsByRefArgument[0] || !AppendArgumentSlot(nodes, source, bindings, handles, plan, callFragment, depth + 1, true, actual, expected, oneFacts, 0) {
                return false
            }
            local := plan.DeclarePlanLocal(plan.AddType(expected[0]))
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), local)
            locals[slot] = local
            written += 1
        }
        slot := 0
        while slot < selected.ParamTypes.Length {
            if selectedClaimed[slot] {
                plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), locals[slot])
            } else if !ColumnarConstructionPlanner.TryAppendConstructorDefault(nodes, plan, selected.ParamTypes[slot], selected.ParamDefaultKinds[slot], selected.ParamDefaultTexts[slot], bindings) {
                return false
            }
            slot += 1
        }
        declaringType := selected.Builder.get_DeclaringType()
        if declaringType == null {
            return false
        }
        methodIndex := plan.AddMethodWithSignature(selected.Builder, declaringType, selected.ParamTypes, selected.ReturnType, true, false)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
        resultType = selected.ReturnType
        return !IsVoidType(resultType) || callFragment == 0 || plan.IsMethodBodyRootFragment(callFragment)
    }

    static func TryAppendSparseNamedRuntimeMemberCall(nodes: ColumnarNodeTable, source: string, callNode: int, callee: int, calleeKind: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, out resultType: Type): bool {
        resultType = typeof(int)
        if calleeKind != ColumnarExpressionNodeKind.MemberAccessExpression() || nodes.ChildCount(callee) != 1 {
            return false
        }
        memberName := nodes.Text(source, callee)
        receiverNode := nodes.Child(callee, 0)
        lookupType := typeof(object)
        isStatic := false
        ownerName := ""
        rootName := ""
        scope := nodes.BindingScope
        if ColumnarPlannerSupport.TryGetQualifiedName(nodes, source, receiverNode, 0, true, out ownerName, out rootName) && !bindings.IsValueBinding(rootName) && !bindings.IsCallable(rootName) && scope != null && scope.TryResolveExternalStaticOwnerType(nodes.EnclosingTypeName, nodes.VisibleTypeParameterNames, rootName, ownerName, out lookupType) {
            isStatic = true
        } else {
            receiverOwnership := ColumnarDirectCallOwnership.NotOwned
            if !TryGetPlannableValueType(nodes, source, receiverNode, bindings, handles, depth + 1, ArgumentsAdmitPrimitiveBinary(), plan.IsMethodBodySchema(), out lookupType, out receiverOwnership) || ColumnarNamedArgumentBinder.FindReceiverDefinition(lookupType, bindings.SourceTypeDefinitions) != null {
                return false
            }
        }
        if !ColumnarNamedArgumentBinder.IsReflectable(lookupType) {
            return false
        }

        selected: MethodInfo? = null
        selectedTypes := new Type[](0)
        selectedPlacement := new int[](0)
        selectedClaimed := new bool[](0)
        bestScore := -1
        tied := false
        exactDeclaresName := false
        for declaredMethod in lookupType.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly) {
            if declaredMethod.get_Name() == memberName && declaredMethod.get_IsStatic() == isStatic {
                exactDeclaresName = true
                break
            }
        }
        for method in lookupType.GetMethods() {
            parameters := method.GetParameters()
            if method.get_Name() != memberName || method.get_IsStatic() != isStatic || (exactDeclaresName && method.get_DeclaringType() != lookupType) || method.get_ContainsGenericParameters() || parameters.Length <= argumentTypes.Length {
                continue
            }
            parameterNames := ColumnarNamedArgumentBinder.ReflectedParameterNames(method)
            parameterTypes := new Type[](parameters.Length)
            index := 0
            while index < parameters.Length {
                parameterTypes[index] = parameters[index].get_ParameterType()
                index += 1
            }
            placement := new int[](0)
            claimed := new bool[](0)
            if !ColumnarNamedArgumentBinder.TryPlaceSparse(nodes, source, callNode, 1, argumentTypes.Length, parameterNames, out placement, out claimed) {
                continue
            }
            fillable := true
            score := 0
            slot := 0
            while slot < parameterTypes.Length {
                if !claimed[slot] && !ColumnarExtensionMethodResolver.CanFillOptional(parameters[slot], parameterTypes[slot]) {
                    fillable = false
                }
                slot += 1
            }
            written := 0
            while fillable && written < argumentTypes.Length {
                expected := new Type[](1)
                expected[0] = parameterTypes[placement[written]]
                actual := new Type[](1)
                actual[0] = argumentTypes[written]
                scorePart := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(expected, actual, CopyArgumentFact(argumentFacts, written))
                if scorePart < 0 {
                    fillable = false
                } else {
                    score += scorePart
                }
                written += 1
            }
            if !fillable {
                continue
            }
            if score > bestScore {
                bestScore = score
                selected = method
                selectedTypes = parameterTypes
                selectedPlacement = placement
                selectedClaimed = claimed
                tied = false
            } else if score == bestScore && selected != null && !Object.ReferenceEquals(selected, method) {
                tied = true
            }
        }
        if selected == null || tied {
            return false
        }
        if !isStatic && !AppendExplicitReceiver(nodes, source, receiverNode, bindings, handles, plan, callFragment, depth + 1, lookupType, !lookupType.get_IsValueType()) {
            return false
        }
        locals := new int[](selectedTypes.Length)
        Array.Fill(locals, -1)
        written := 0
        while written < argumentTypes.Length {
            slot := selectedPlacement[written]
            expected := new Type[](1)
            expected[0] = selectedTypes[slot]
            actual := new Type[](1)
            actual[0] = argumentTypes[written]
            oneFacts := CopyArgumentFact(argumentFacts, written)
            if oneFacts.IsByRefArgument[0] || !AppendArgumentSlot(nodes, source, bindings, handles, plan, callFragment, depth + 1, true, actual, expected, oneFacts, 0) {
                return false
            }
            local := plan.DeclarePlanLocal(plan.AddType(expected[0]))
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), local)
            locals[slot] = local
            written += 1
        }
        parameters := selected.GetParameters()
        emitSlot := 0
        while emitSlot < selectedTypes.Length {
            if selectedClaimed[emitSlot] {
                plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), locals[emitSlot])
            } else if !ColumnarExtensionMethodResolver.TryAppendOptionalDefault(plan, parameters[emitSlot], selectedTypes[emitSlot]) {
                return false
            }
            emitSlot += 1
        }
        declaringType := selected.get_DeclaringType()
        if declaringType == null {
            return false
        }
        methodIndex := plan.AddMethodWithSignature(selected, declaringType, selectedTypes, selected.get_ReturnType(), isStatic, selected.get_IsAbstract())
        plan.AppendMethodInstruction((short)(!isStatic && !lookupType.get_IsValueType() ? ColumnarCodePlanContract.Callvirt() : ColumnarCodePlanContract.Call()), methodIndex)
        resultType = selected.get_ReturnType()
        return !IsVoidType(resultType) || callFragment == 0 || plan.IsMethodBodyRootFragment(callFragment)
    }

    static func TryFlattenAgreedInPositionNames(nodes: ColumnarNodeTable, source: string, callNode: int, callee: int, calleeKind: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, depth: int, methodBodySchema: bool, arity: int, out placement: int[]): bool {
        placement = new int[](0)
        candidates := new List<string[]>()
        if calleeKind == ColumnarExpressionNodeKind.IdentifierExpression() {
            bareName := nodes.Text(source, callee)
            siblingFacts: ColumnarSiblingCallFacts? = null
            if bindings.SiblingCallables.TryGetValue(bareName, out siblingFacts) {
                ColumnarNamedArgumentBinder.AddCandidate(candidates, siblingFacts.ParameterNames, arity)
            }
            current := bindings.CurrentInstance
            if current != null {
                ColumnarNamedArgumentBinder.CollectSourceInstanceParameterNames(current.SourceDefinition, bareName, arity, candidates)
            }
            ColumnarNamedArgumentBinder.CollectSourceStaticParameterNames(bindings.EnclosingTypeDefinition, bareName, arity, candidates)
            return ColumnarNamedArgumentBinder.TryAgreedPlacement(nodes, source, callNode, 1, arity, candidates, out placement)
        }

        if calleeKind == 38 {
            genericName := nodes.Text(source, callee)
            siblingFacts: ColumnarSiblingCallFacts? = null
            if genericName.IndexOf(".", StringComparison.Ordinal) < 0 && bindings.SiblingCallables.TryGetValue(genericName, out siblingFacts) && siblingFacts != null && siblingFacts.TypeParameterCount == ColumnarGenericCalleeFacts.TypeArgumentCount(nodes, callee) {
                ColumnarNamedArgumentBinder.AddCandidate(candidates, siblingFacts.ParameterNames, arity)
            }
            return ColumnarNamedArgumentBinder.TryAgreedPlacement(nodes, source, callNode, 1, arity, candidates, out placement)
        }

        if calleeKind == ColumnarExpressionNodeKind.BaseMemberExpression() {
            current := bindings.CurrentInstance
            if current != null && current.SourceDefinition != null {
                ColumnarNamedArgumentBinder.CollectSourceInstanceParameterNames(current.SourceDefinition.BaseDef, nodes.Text(source, callee), arity, candidates)
                ColumnarNamedArgumentBinder.CollectReflectedParameterNames(current.SourceDefinition.ExactBaseType, nodes.Text(source, callee), arity, false, candidates)
            }
            return ColumnarNamedArgumentBinder.TryAgreedPlacement(nodes, source, callNode, 1, arity, candidates, out placement)
        }

        if calleeKind != ColumnarExpressionNodeKind.MemberAccessExpression() || nodes.ChildCount(callee) != 1 {
            return false
        }
        memberName := nodes.Text(source, callee)
        receiverNode := nodes.Child(callee, 0)
        extensionScope := nodes.BindingScope
        if extensionScope != null {
            for extension in extensionScope.ExtensionCandidates(memberName) {
                ColumnarNamedArgumentBinder.AddCandidate(candidates, ColumnarNamedArgumentBinder.ReflectedExtensionParameterNames(extension.Method), arity)
            }
        }
        ownerName := ""
        rootName := ""
        if ColumnarPlannerSupport.TryGetQualifiedName(nodes, source, receiverNode, 0, true, out ownerName, out rootName) && !bindings.IsValueBinding(rootName) && !bindings.IsCallable(rootName) {
            scope := nodes.BindingScope
            exactSourceOwnerName := ownerName
            sourceOwnerBlocked := false
            if scope == null || scope.TryResolveSourceStaticOwner(nodes.EnclosingTypeName, nodes.VisibleTypeParameterNames, rootName, ownerName, out exactSourceOwnerName, out sourceOwnerBlocked) {
                ColumnarNamedArgumentBinder.CollectSourceStaticParameterNames(FindExactSourceOwner(exactSourceOwnerName, bindings.SourceTypeDefinitions), memberName, arity, candidates)
            }
            externalOwnerType := typeof(object)
            if scope != null && scope.TryResolveExternalStaticOwnerType(nodes.EnclosingTypeName, nodes.VisibleTypeParameterNames, rootName, ownerName, out externalOwnerType) {
                ColumnarNamedArgumentBinder.CollectReflectedParameterNames(externalOwnerType, memberName, arity, true, candidates)
            }
        }
        receiverType := typeof(object)
        receiverOwnership := ColumnarDirectCallOwnership.NotOwned
        if TryGetPlannableValueType(nodes, source, receiverNode, bindings, handles, depth + 1, ArgumentsAdmitPrimitiveBinary(), methodBodySchema, out receiverType, out receiverOwnership) {
            ColumnarNamedArgumentBinder.CollectSourceInstanceParameterNames(ColumnarNamedArgumentBinder.FindReceiverDefinition(receiverType, bindings.SourceTypeDefinitions), memberName, arity, candidates)
            ColumnarNamedArgumentBinder.CollectReflectedParameterNames(receiverType, memberName, arity, false, candidates)
        }
        return ColumnarNamedArgumentBinder.TryAgreedPlacement(nodes, source, callNode, 1, arity, candidates, out placement)
    }

    // THE SIGNATURES A CALL'S NAMES COULD BE PLACED AGAINST, gathered from the same declaration
    // registries the arms below select from -- never from a second lookup of their own. A bare name
    // reaches a sibling free function, an instance method of the body's own type, or a static of the
    // enclosing type; a member access reaches the members of its receiver's type, source or external;
    // a `base.M(...)` reaches the base declaration. Whichever of those the call turns out to be, its
    // parameter names are in this set, and the placement is accepted only when every candidate that
    // admits the written names agrees on it.
    static func TryPlaceNamedCallArguments(nodes: ColumnarNodeTable, source: string, callNode: int, callee: int, calleeKind: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, depth: int, methodBodySchema: bool, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, out placement: int[]): bool {
        placement = new int[](0)
        candidates := new List<ColumnarNamedArgumentCandidate>()
        arity := argumentTypes.Length

        if calleeKind == ColumnarExpressionNodeKind.IdentifierExpression() {
            bareName := nodes.Text(source, callee)
            siblingFacts: ColumnarSiblingCallFacts? = null
            if bindings.SiblingCallables.TryGetValue(bareName, out siblingFacts) {
                ColumnarNamedArgumentBinder.AddTypedCandidate(candidates, siblingFacts.ParameterNames, siblingFacts.ParameterTypes, arity)
            }

            currentInstance := bindings.CurrentInstance
            if currentInstance != null {
                ColumnarNamedArgumentBinder.CollectSourceInstanceCandidates(currentInstance.SourceDefinition, bareName, arity, candidates)
            }

            ColumnarNamedArgumentBinder.CollectSourceStaticCandidates(bindings.EnclosingTypeDefinition, bareName, arity, candidates)
            delegateType := typeof(object)
            if candidates.Count == 0 && ColumnarBoundIdentifierPlanner.TryGetBoundType(nodes, source, callee, bindings, out delegateType) && IsDelegateValueType(delegateType) {
                ColumnarNamedArgumentBinder.CollectReflectedCandidates(delegateType, "Invoke", arity, false, candidates)
            }
            return ColumnarNamedArgumentBinder.TryBestPlacement(nodes, source, callNode, 1, argumentTypes, argumentFacts, candidates, out placement)
        }

        if calleeKind == 38 {
            genericName := nodes.Text(source, callee)
            siblingFacts: ColumnarSiblingCallFacts? = null
            if genericName.IndexOf(".", StringComparison.Ordinal) < 0 && bindings.SiblingCallables.TryGetValue(genericName, out siblingFacts) && siblingFacts != null && siblingFacts.TypeParameterCount == ColumnarGenericCalleeFacts.TypeArgumentCount(nodes, callee) {
                ColumnarNamedArgumentBinder.AddTypedCandidate(candidates, siblingFacts.ParameterNames, siblingFacts.ParameterTypes, arity)
            }
            return ColumnarNamedArgumentBinder.TryBestPlacement(nodes, source, callNode, 1, argumentTypes, argumentFacts, candidates, out placement)
        }

        if calleeKind == ColumnarExpressionNodeKind.BaseMemberExpression() {
            currentInstance := bindings.CurrentInstance
            if currentInstance != null && currentInstance.SourceDefinition != null {
                baseDefinition := currentInstance.SourceDefinition.BaseDef
                ColumnarNamedArgumentBinder.CollectSourceInstanceCandidates(baseDefinition, nodes.Text(source, callee), arity, candidates)
                ColumnarNamedArgumentBinder.CollectReflectedCandidates(currentInstance.SourceDefinition.ExactBaseType, nodes.Text(source, callee), arity, false, candidates)
            }

            return ColumnarNamedArgumentBinder.TryBestPlacement(nodes, source, callNode, 1, argumentTypes, argumentFacts, candidates, out placement)
        }

        if calleeKind != ColumnarExpressionNodeKind.MemberAccessExpression() || nodes.ChildCount(callee) != 1 {
            return false
        }

        memberName := nodes.Text(source, callee)
        receiverNode := nodes.Child(callee, 0)
        extensionScope := nodes.BindingScope
        if extensionScope != null {
            for extension in extensionScope.ExtensionCandidates(memberName) {
                ColumnarNamedArgumentBinder.AddTypedCandidate(candidates, ColumnarNamedArgumentBinder.ReflectedExtensionParameterNames(extension.Method), ColumnarNamedArgumentBinder.ReflectedExtensionParameterTypes(extension.Method), arity)
            }
        }

        // A STATIC OWNER IS A TYPE NAME, not a value, so it is spelled rather than typed. The same
        // scope facts the static arm consults answer whether the written root names a source type or
        // an external one.
        ownerName := ""
        rootName := ""
        if ColumnarPlannerSupport.TryGetQualifiedName(nodes, source, receiverNode, 0, true, out ownerName, out rootName) && !bindings.IsValueBinding(rootName) && !bindings.IsCallable(rootName) {
            scope := nodes.BindingScope
            exactSourceOwnerName := ownerName
            sourceOwnerBlocked := false
            if scope == null || scope.TryResolveSourceStaticOwner(nodes.EnclosingTypeName, nodes.VisibleTypeParameterNames, rootName, ownerName, out exactSourceOwnerName, out sourceOwnerBlocked) {
                ColumnarNamedArgumentBinder.CollectSourceStaticCandidates(FindExactSourceOwner(exactSourceOwnerName, bindings.SourceTypeDefinitions), memberName, arity, candidates)
            }

            externalOwnerType := typeof(object)
            if scope != null && scope.TryResolveExternalStaticOwnerType(nodes.EnclosingTypeName, nodes.VisibleTypeParameterNames, rootName, ownerName, out externalOwnerType) {
                ColumnarNamedArgumentBinder.CollectReflectedCandidates(externalOwnerType, memberName, arity, true, candidates)
            }
        }

        // AN INSTANCE RECEIVER IS TYPED, by the same non-mutating oracle the argument rows were typed
        // with. A receiver the oracle cannot type simply contributes no candidate.
        receiverType := typeof(object)
        receiverOwnership := ColumnarDirectCallOwnership.NotOwned
        if TryGetPlannableValueType(nodes, source, receiverNode, bindings, handles, depth + 1, ArgumentsAdmitPrimitiveBinary(), methodBodySchema, out receiverType, out receiverOwnership) {
            ColumnarNamedArgumentBinder.CollectSourceInstanceCandidates(ColumnarNamedArgumentBinder.FindReceiverDefinition(receiverType, bindings.SourceTypeDefinitions), memberName, arity, candidates)
            ColumnarNamedArgumentBinder.CollectReflectedCandidates(receiverType, memberName, arity, false, candidates)
        }

        return ColumnarNamedArgumentBinder.TryBestPlacement(nodes, source, callNode, 1, argumentTypes, argumentFacts, candidates, out placement)
    }

    static func TryScoreExplicitGenericBoundArguments(nodes: ColumnarNodeTable, source: string, callNode: int, bindings: ColumnarFragmentBindings, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, parameterTypes: Type[], parameterNames: string[], defaultKinds: int[], defaultTexts: string[], modifierKinds: int[], out score: int): bool {
        score = -1
        if parameterTypes.Length != parameterNames.Length || parameterTypes.Length != defaultKinds.Length || parameterTypes.Length != defaultTexts.Length || parameterTypes.Length != modifierKinds.Length {
            return false
        }
        if TryScoreExplicitGenericParamsArguments(nodes, source, callNode, bindings, argumentTypes, argumentFacts, parameterTypes, parameterNames, defaultKinds, defaultTexts, modifierKinds, out score) {
            return true
        }
        if argumentTypes.Length == 0 && parameterTypes.Length == 0 {
            score = 0
            return true
        }

        placement := new int[](0)
        claimed := new bool[](0)
        if !ColumnarNamedArgumentBinder.TryPlaceSparse(nodes, source, callNode, 1, argumentTypes.Length, parameterNames, out placement, out claimed) {
            return false
        }
        slot := 0
        while slot < claimed.Length {
            if !claimed[slot] && !ColumnarConstructionPlanner.CanUseConstructorDefault(nodes, parameterTypes[slot], defaultKinds[slot], defaultTexts[slot], bindings) {
                return false
            }
            slot += 1
        }
        score = 0
        written := 0
        while written < argumentTypes.Length {
            expected := new Type[](1)
            expected[0] = parameterTypes[placement[written]]
            actual := new Type[](1)
            actual[0] = argumentTypes[written]
            part := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(expected, actual, CopyArgumentFact(argumentFacts, written))
            if part < 0 {
                score = -1
                return false
            }
            score = score + part
            written += 1
        }
        return true
    }

    static func HasExplicitGenericParamsTail(modifierKinds: int[]): bool {
        return modifierKinds.Length > 0 && modifierKinds[modifierKinds.Length - 1] == 3
    }

    // The analyzer compares applicability scores first, then prefers normal form and fewer filled
    // defaults. Generic source emission already has the same closed candidate facts here; ask the
    // shared language rule instead of turning equal written-argument scores into an ambiguity.
    static func CompareExplicitGenericBoundTie(leftUsesParams: bool, leftParameterCount: int, rightUsesParams: bool, rightParameterCount: int, argumentCount: int): int {
        return AnalyzerOverloadSpecificity.CompareTieBreaks(
            false,
            true,
            true,
            leftUsesParams,
            rightUsesParams,
            Math.Max(0, leftParameterCount - argumentCount),
            Math.Max(0, rightParameterCount - argumentCount),
            AnalyzerOverloadSpecificity.NeitherIsBetter
        )
    }

    static func TryScoreExplicitGenericParamsArguments(nodes: ColumnarNodeTable, source: string, callNode: int, bindings: ColumnarFragmentBindings, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, parameterTypes: Type[], parameterNames: string[], defaultKinds: int[], defaultTexts: string[], modifierKinds: int[], out score: int): bool {
        score = -1
        if parameterTypes.Length == 0 || modifierKinds[parameterTypes.Length - 1] != 3 || !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(parameterTypes[parameterTypes.Length - 1]) {
            return false
        }
        fixedCount := parameterTypes.Length - 1
        elementType := parameterTypes[fixedCount].GetElementType()
        claimed := new bool[](fixedCount)
        paramsArrayClaimed := false
        expandedSeen := false
        nextFixed := 0
        score = 0
        written := 0
        while written < argumentTypes.Length {
            raw := nodes.Child(callNode, 1 + written)
            value := ColumnarNamedArgumentBinder.ArgumentValueNode(nodes, raw)
            name := ColumnarNamedArgumentBinder.ArgumentName(nodes, source, raw)
            slot := -1
            completeParamsArray := (name != null && ColumnarNamedArgumentBinder.ParameterIndexOf(parameterNames, name) == fixedCount) || nodes.Kind(value) == 64
            if completeParamsArray {
                if paramsArrayClaimed || expandedSeen {
                    score = -1
                    return false
                }
                paramsArrayClaimed = true
                slot = fixedCount
            } else if name != null {
                slot = ColumnarNamedArgumentBinder.ParameterIndexOf(parameterNames, name)
                if slot < 0 || slot >= fixedCount || claimed[slot] {
                    score = -1
                    return false
                }
                claimed[slot] = true
            } else {
                while nextFixed < fixedCount && claimed[nextFixed] {
                    nextFixed += 1
                }
                if nextFixed < fixedCount {
                    slot = nextFixed
                    claimed[slot] = true
                    nextFixed += 1
                } else {
                    if paramsArrayClaimed {
                        score = -1
                        return false
                    }
                    expandedSeen = true
                }
            }
            expected := new Type[](1)
            expected[0] = slot >= 0 ? parameterTypes[slot] : elementType
            actual := new Type[](1)
            actual[0] = argumentTypes[written]
            part := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(expected, actual, CopyArgumentFact(argumentFacts, written))
            if part < 0 {
                score = -1
                return false
            }
            score = score + part
            written += 1
        }
        fixedSlot := 0
        while fixedSlot < fixedCount {
            if !claimed[fixedSlot] && !ColumnarConstructionPlanner.CanUseConstructorDefault(nodes, parameterTypes[fixedSlot], defaultKinds[fixedSlot], defaultTexts[fixedSlot], bindings) {
                score = -1
                return false
            }
            fixedSlot += 1
        }
        return true
    }

    static func TryAppendExplicitGenericBoundArguments(nodes: ColumnarNodeTable, source: string, callNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, parameterTypes: Type[], parameterNames: string[], defaultKinds: int[], defaultTexts: string[], modifierKinds: int[]): bool {
        checkpoint := plan.CreateCheckpoint()
        if TryAppendExplicitGenericParamsArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, parameterTypes, parameterNames, defaultKinds, defaultTexts, modifierKinds) {
            return true
        }
        plan.Rollback(checkpoint)
        directScore := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(parameterTypes, argumentTypes, argumentFacts)
        directPlacement := new int[](0)
        directArgumentsInOrder := argumentTypes.Length == 0 && parameterTypes.Length == 0
        if argumentTypes.Length > 0 && parameterTypes.Length == argumentTypes.Length && ColumnarNamedArgumentBinder.TryPlace(nodes, source, callNode, 1, argumentTypes.Length, parameterNames, parameterTypes.Length, out directPlacement) {
            directArgumentsInOrder = true
            directWritten := 0
            while directWritten < directPlacement.Length {
                if directPlacement[directWritten] != directWritten {
                    directArgumentsInOrder = false
                }
                directWritten += 1
            }
        }
        if (argumentFacts.RequiresReorder || directArgumentsInOrder) && directScore >= 0 && AppendArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth, ArgumentsAdmitPrimitiveBinary(), argumentTypes, parameterTypes, argumentFacts) {
            return true
        }
        plan.Rollback(checkpoint)

        placement := new int[](0)
        claimed := new bool[](0)
        if !ColumnarNamedArgumentBinder.TryPlaceSparse(nodes, source, callNode, 1, argumentTypes.Length, parameterNames, out placement, out claimed) {
            plan.Rollback(checkpoint)
            return false
        }
        slot := 0
        while slot < claimed.Length {
            if !claimed[slot] && !ColumnarConstructionPlanner.CanUseConstructorDefault(nodes, parameterTypes[slot], defaultKinds[slot], defaultTexts[slot], bindings) {
                plan.Rollback(checkpoint)
                return false
            }
            slot += 1
        }

        locals := new int[](parameterTypes.Length)
        Array.Fill(locals, -1)
        written := 0
        while written < argumentTypes.Length {
            parameterSlot := placement[written]
            actual := new Type[](1)
            actual[0] = argumentTypes[written]
            expected := new Type[](1)
            expected[0] = parameterTypes[parameterSlot]
            oneFacts := CopyArgumentFact(argumentFacts, written)
            if ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(expected, actual, oneFacts) < 0 || !AppendArgumentSlot(nodes, source, bindings, handles, plan, callFragment, depth, ArgumentsAdmitPrimitiveBinary(), actual, expected, oneFacts, 0) {
                plan.Rollback(checkpoint)
                return false
            }
            local := plan.DeclarePlanLocal(plan.AddType(expected[0]))
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), local)
            locals[parameterSlot] = local
            written += 1
        }
        slot = 0
        while slot < parameterTypes.Length {
            if locals[slot] >= 0 {
                plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), locals[slot])
            } else if !ColumnarConstructionPlanner.TryAppendConstructorDefault(nodes, plan, parameterTypes[slot], defaultKinds[slot], defaultTexts[slot], bindings) {
                plan.Rollback(checkpoint)
                return false
            }
            slot += 1
        }
        return true
    }

    static func TryAppendExplicitGenericSiblingCall(nodes: ColumnarNodeTable, source: string, callNode: int, callee: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        name := nodes.Text(source, callee)
        facts: ColumnarSiblingCallFacts? = null
        if name.IndexOf(".", StringComparison.Ordinal) >= 0 || !bindings.SiblingCallables.TryGetValue(name, out facts) || facts == null || facts.TypeParameterCount != ColumnarGenericCalleeFacts.TypeArgumentCount(nodes, callee) || facts.ParameterNames.Length != facts.ParameterTypes.Length || facts.ParameterDefaultKinds.Length != facts.ParameterTypes.Length || facts.ParameterDefaultTexts.Length != facts.ParameterTypes.Length || facts.ParameterModifierKinds.Length != facts.ParameterTypes.Length || bindings.IsSiblingShadowedByValue(name) {
            legacyWholeSubtreePlanning = true
            return false
        }

        scope := nodes.BindingScope
        if scope == null {
            legacyWholeSubtreePlanning = true
            return false
        }
        typeArguments := new Type[](ColumnarGenericCalleeFacts.TypeArgumentCount(nodes, callee))
        typeIndex := 0
        while typeIndex < typeArguments.Length {
            canonical := ""
            resolved := typeof(object)
            claimed := false
            if !ColumnarTypeOfPlanner.TryBuildTypeCanonical(nodes, source, ColumnarGenericCalleeFacts.TypeArgumentNode(nodes, callee, typeIndex), 0, out canonical) || !scope.TryResolveExactExplicitTypeInContext(nodes.EnclosingTypeName, canonical, bindings, out resolved, out claimed) {
                legacyWholeSubtreePlanning = true
                return false
            }
            typeArguments[typeIndex] = resolved
            typeIndex += 1
        }

        method := facts.Method
        genericParameters := method.GetGenericArguments()
        if genericParameters.Length != typeArguments.Length {
            legacyWholeSubtreePlanning = true
            return false
        }
        parameterTypes := new Type[](facts.ParameterTypes.Length)
        parameterIndex := 0
        while parameterIndex < parameterTypes.Length {
            substituted := typeof(object)
            if !ColumnarGenericConstraintPlanner.TrySubstituteGenericTypeArguments(genericParameters, typeArguments, facts.ParameterTypes[parameterIndex], out substituted) {
                legacyWholeSubtreePlanning = true
                return false
            }
            parameterTypes[parameterIndex] = substituted
            parameterIndex += 1
        }
        returnType := typeof(object)
        if !ColumnarGenericConstraintPlanner.TrySubstituteGenericTypeArguments(genericParameters, typeArguments, facts.ReturnType, out returnType) {
            legacyWholeSubtreePlanning = true
            return false
        }
        if !TryAppendExplicitGenericBoundArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, argumentTypes, argumentFacts, parameterTypes, facts.ParameterNames, facts.ParameterDefaultKinds, facts.ParameterDefaultTexts, facts.ParameterModifierKinds) {
            legacyWholeSubtreePlanning = true
            return false
        }

        closedMethod := method.MakeGenericMethod(typeArguments)
        declaringType := method.get_DeclaringType()
        if declaringType == null {
            legacyWholeSubtreePlanning = true
            return false
        }
        methodIndex := plan.AddMethodWithSignature(closedMethod, declaringType, parameterTypes, returnType, true, false)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
        resultType = returnType
        ownership = ColumnarDirectCallOwnership.Planned
        return !IsVoidType(resultType) || callFragment == 0 || plan.IsMethodBodyRootFragment(callFragment)
    }

    // A trailing params array has three ordinary call shapes: a direct array, an omitted empty
    // array, or expanded element arguments. Named fixed arguments still use the same placement
    // rule, and every written value is parked before signature-order reload so side effects remain
    // in source order.
    static func TryAppendExplicitGenericParamsArguments(nodes: ColumnarNodeTable, source: string, callNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, parameterTypes: Type[], parameterNames: string[], defaultKinds: int[], defaultTexts: string[], modifierKinds: int[]): bool {
        if parameterTypes.Length == 0 || modifierKinds[parameterTypes.Length - 1] != 3 || !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(parameterTypes[parameterTypes.Length - 1]) {
            return false
        }
        fixedCount := parameterTypes.Length - 1
        paramsSlot := fixedCount
        paramsType := parameterTypes[paramsSlot]
        elementType := paramsType.GetElementType()

        fixedLocals := new int[](fixedCount)
        Array.Fill(fixedLocals, -1)
        expandedLocals := new int[](argumentTypes.Length)
        expandedCount := 0
        paramsArrayLocal := -1
        nextFixed := 0
        written := 0
        while written < argumentTypes.Length {
            raw := nodes.Child(callNode, 1 + written)
            value := ColumnarNamedArgumentBinder.ArgumentValueNode(nodes, raw)
            name := ColumnarNamedArgumentBinder.ArgumentName(nodes, source, raw)
            slot := -1
            completeParamsArray := (name != null && ColumnarNamedArgumentBinder.ParameterIndexOf(parameterNames, name) == paramsSlot) || nodes.Kind(value) == 64
            if completeParamsArray {
                if paramsArrayLocal >= 0 || expandedCount > 0 {
                    return false
                }
                slot = paramsSlot
            } else if name != null {
                slot = ColumnarNamedArgumentBinder.ParameterIndexOf(parameterNames, name)
                if slot < 0 || slot >= fixedCount || fixedLocals[slot] >= 0 {
                    return false
                }
            } else {
                while nextFixed < fixedCount && fixedLocals[nextFixed] >= 0 {
                    nextFixed += 1
                }
                if nextFixed < fixedCount {
                    slot = nextFixed
                    nextFixed += 1
                } else if paramsArrayLocal >= 0 {
                    return false
                }
            }

            expected := slot >= 0 ? parameterTypes[slot] : elementType
            actual := new Type[](1)
            actual[0] = argumentTypes[written]
            expectedArray := new Type[](1)
            expectedArray[0] = expected
            oneFacts := CopyArgumentFact(argumentFacts, written)
            if nodes.Kind(value) == 64 && nodes.ChildCount(value) == 1 {
                oneFacts.ArgumentNodes[0] = nodes.Child(value, 0)
            }
            if ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(expectedArray, actual, oneFacts) < 0 || !AppendArgumentSlot(nodes, source, bindings, handles, plan, callFragment, depth + 1, ArgumentsAdmitPrimitiveBinary(), actual, expectedArray, oneFacts, 0) {
                return false
            }
            local := plan.DeclarePlanLocal(plan.AddType(expected))
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), local)
            if slot == paramsSlot {
                paramsArrayLocal = local
            } else if slot >= 0 {
                fixedLocals[slot] = local
            } else {
                expandedLocals[expandedCount] = local
                expandedCount += 1
            }
            written += 1
        }

        slot := 0
        while slot < fixedCount {
            if fixedLocals[slot] >= 0 {
                plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), fixedLocals[slot])
            } else if !ColumnarConstructionPlanner.TryAppendConstructorDefault(nodes, plan, parameterTypes[slot], defaultKinds[slot], defaultTexts[slot], bindings) {
                return false
            }
            slot += 1
        }
        if paramsArrayLocal >= 0 {
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), paramsArrayLocal)
            return true
        }
        countIndex := plan.AddInt32(expandedCount)
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), countIndex)
        elementTypeIndex := plan.AddType(elementType)
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Newarr(), elementTypeIndex)
        index := 0
        while index < expandedCount {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
            arrayIndex := plan.AddInt32(index)
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), arrayIndex)
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), expandedLocals[index])
            ColumnarConstructionPlanner.AppendArrayElementStore(plan, elementType)
            index += 1
        }
        return true
    }

    static func TryAppendExplicitGenericSourceStaticCall(nodes: ColumnarNodeTable, source: string, callNode: int, ownerName: string, memberName: string, owner: ColumnarStructDef, methodArguments: Type[], bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, out resultType: Type): bool {
        resultType = typeof(int)
        candidates: List<ColumnarStaticMethodDef>? = null
        if !owner.StaticMethods.TryGetValue(memberName, out candidates) || candidates == null {
            return false
        }
        scope := nodes.BindingScope
        if scope == null {
            return false
        }
        // The outer resolver has already selected this exact source declaration. Its live builder
        // is therefore the owner identity for a non-generic type; asking the file scope to resolve
        // the short spelling again can lose an otherwise valid source owner. A constructed generic
        // receiver still needs that scope lookup to recover its written owner arguments.
        ownerType: Type = owner.Builder
        ownerParameters := owner.Builder.GetGenericArguments()
        if ownerParameters.Length > 0 {
            ownerClaimed := false
            if !scope.TryResolveExactExplicitTypeInContext(nodes.EnclosingTypeName, ownerName, bindings, out ownerType, out ownerClaimed) {
                return false
            }
        }
        ownerArguments := ownerType.get_IsGenericType() ? ownerType.GetGenericArguments() : new Type[](0)

        selected: ColumnarStaticMethodDef? = null
        selectedParameters := new Type[](0)
        selectedReturn := typeof(object)
        selectedUsesParams := false
        bestScore := -1
        tied := false
        for candidate in candidates {
            generics := candidate.Generics
            if generics == null || generics.TypeParams.Length != methodArguments.Length || candidate.ParamNames.Length != candidate.ParamTypes.Length || candidate.ParamDefaultKinds.Length != candidate.ParamTypes.Length || candidate.ParamDefaultTexts.Length != candidate.ParamTypes.Length || candidate.ParamModifierKinds.Length != candidate.ParamTypes.Length {
                continue
            }
            parameters := new Type[](candidate.ParamTypes.Length)
            valid := true
            index := 0
            while index < parameters.Length {
                closed := typeof(object)
                if !ColumnarGenericConstraintPlanner.TrySubstituteGenericMemberType(ownerParameters, ownerArguments, generics.TypeParams, methodArguments, candidate.ParamTypes[index], out closed) {
                    valid = false
                }
                parameters[index] = closed
                index += 1
            }
            closedReturn := typeof(object)
            if !valid || !ColumnarGenericConstraintPlanner.TrySubstituteGenericMemberType(ownerParameters, ownerArguments, generics.TypeParams, methodArguments, candidate.ReturnType, out closedReturn) {
                continue
            }
            score := -1
            if !TryScoreExplicitGenericBoundArguments(nodes, source, callNode, bindings, argumentTypes, argumentFacts, parameters, candidate.ParamNames, candidate.ParamDefaultKinds, candidate.ParamDefaultTexts, candidate.ParamModifierKinds, out score) {
                continue
            }
            if score > bestScore {
                bestScore = score
                selected = candidate
                selectedParameters = parameters
                selectedReturn = closedReturn
                selectedUsesParams = HasExplicitGenericParamsTail(candidate.ParamModifierKinds)
                tied = false
            } else if score == bestScore && selected != null && !Object.ReferenceEquals(selected.Builder, candidate.Builder) {
                candidateUsesParams := HasExplicitGenericParamsTail(candidate.ParamModifierKinds)
                tieBreak := CompareExplicitGenericBoundTie(selectedUsesParams, selectedParameters.Length, candidateUsesParams, parameters.Length, argumentTypes.Length)
                if tieBreak == AnalyzerOverloadSpecificity.RightIsBetter {
                    selected = candidate
                    selectedParameters = parameters
                    selectedReturn = closedReturn
                    selectedUsesParams = candidateUsesParams
                    tied = false
                } else if tieBreak == AnalyzerOverloadSpecificity.NeitherIsBetter {
                    tied = true
                }
            }
        }
        if selected == null || tied || !TryAppendExplicitGenericBoundArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, argumentTypes, argumentFacts, selectedParameters, selected.ParamNames, selected.ParamDefaultKinds, selected.ParamDefaultTexts, selected.ParamModifierKinds) {
            return false
        }
        selectedGenerics := selected.Generics
        sourceRegistry := new Dictionary<string, ColumnarStructDef>(StringComparer.Ordinal)
        for sourceDefinition in bindings.SourceTypeDefinitions {
            sourceRegistry[sourceDefinition.DeclaredTypeName] = sourceDefinition
        }
        if selectedGenerics == null || !ColumnarGenericConstraintPlanner.TryValidateGenericSiblingConstraints(selectedGenerics.TypeParams, selectedGenerics.SpecialConstraints, selectedGenerics.BaseConstraints, selectedGenerics.InterfaceConstraints, methodArguments, methodArguments, sourceRegistry) {
            return false
        }
        definitionMethod: MethodInfo = selected.Builder
        if ownerType.get_IsGenericType() && !ownerType.get_IsGenericTypeDefinition() {
            definitionMethod = ColumnarClosedGenericMemberResolver.ResolveMethod(ownerType, selected.Builder)
        }
        closedMethod := definitionMethod.MakeGenericMethod(methodArguments)
        methodIndex := plan.AddMethodWithSignature(closedMethod, ownerType, selectedParameters, selectedReturn, true, false)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
        resultType = selectedReturn
        return !IsVoidType(resultType) || callFragment == 0 || plan.IsMethodBodyRootFragment(callFragment)
    }

    // The explicit generic callee stores its complete dotted value name and its type-reference
    // children. Resolve those facts before consulting the exact external catalog; unsupported
    // generic callees remain outside this fixed direct-call owner with a fully rolled-back plan.
    static func TryAppendExplicitGenericStaticCall(nodes: ColumnarNodeTable, source: string, callNode: int, callee: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, checkpoint: ColumnarCodePlanCheckpoint, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)

        calleeName := nodes.Text(source, callee)
        separator := calleeName.LastIndexOf(".", StringComparison.Ordinal)
        if separator <= 0 || separator == calleeName.Length - 1 {
            plan.Rollback(checkpoint)
            return false
        }

        ownerName := calleeName.Substring(0, separator)
        memberName := calleeName.Substring(separator + 1)
        rootSeparator := ownerName.IndexOf(".", StringComparison.Ordinal)
        rootName := rootSeparator > 0 ? ownerName.Substring(0, rootSeparator) : ownerName
        if bindings.IsValueBinding(rootName) || bindings.IsCallable(rootName) || bindings.Enums.ContainsKey(ownerName) || bindings.Enums.ContainsKey(rootName) {
            plan.Rollback(checkpoint)
            return false
        }
        if nodes.HasAdditionalRootBinding(rootName) || ContainsName(nodes.VisibleTypeParameterNames, rootName) {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            plan.Rollback(checkpoint)
            return false
        }

        scope := nodes.BindingScope
        if scope != null && scope.IsFileImportAliasRoot(rootName) {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }
        if scope != null && ownerName != rootName && scope.IsTypeAliasRoot(rootName) {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }
        if scope == null {
            plan.Rollback(checkpoint)
            return false
        }

        typeArguments := new Type[](ColumnarGenericCalleeFacts.TypeArgumentCount(nodes, callee))
        typeArgumentIndex := 0
        while typeArgumentIndex < typeArguments.Length {
            canonical := ""
            resolvedType := typeof(object)
            claimed := false
            if !ColumnarTypeOfPlanner.TryBuildTypeCanonical(nodes, source, ColumnarGenericCalleeFacts.TypeArgumentNode(nodes, callee, typeArgumentIndex), 0, out canonical) || !scope.TryResolveExactExplicitTypeInContext(nodes.EnclosingTypeName, canonical, bindings, out resolvedType, out claimed) {
                if claimed {
                    ownership = ColumnarDirectCallOwnership.OwnedRejected
                }
                plan.Rollback(checkpoint)
                return false
            }
            typeArguments[typeArgumentIndex] = resolvedType
            typeArgumentIndex += 1
        }

        exactSourceOwnerName := ""
        sourceOwnerBlocked := false
        sourceOwnerResolved := scope == null
        sourceOwner: ColumnarStructDef? = null
        resolvedSourceOwnerType := typeof(object)
        resolvedSourceOwnerClaimed := false
        if scope.TryResolveExactExplicitTypeInContext(nodes.EnclosingTypeName, ownerName, bindings, out resolvedSourceOwnerType, out resolvedSourceOwnerClaimed) && (ColumnarTypeOfPlanner.IsClosedSourceGeneric(resolvedSourceOwnerType) || resolvedSourceOwnerType is TypeBuilder) {
            sourceOwner = ColumnarNamedArgumentBinder.FindReceiverDefinition(resolvedSourceOwnerType, bindings.SourceTypeDefinitions)
            sourceOwnerResolved = sourceOwner != null
            sourceOwnerBlocked = true
        } else {
            sourceOwnerResolved = scope.TryResolveSourceStaticOwner(nodes.EnclosingTypeName, nodes.VisibleTypeParameterNames, rootName, ownerName, out exactSourceOwnerName, out sourceOwnerBlocked)
        }
        if sourceOwnerResolved && sourceOwner == null {
            selectedSourceOwnerName := ownerName
            if scope != null {
                selectedSourceOwnerName = exactSourceOwnerName
            }
            sourceOwner = FindExactSourceOwner(selectedSourceOwnerName, bindings.SourceTypeDefinitions)
        }
        if sourceOwnerResolved && sourceOwner == null {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            plan.Rollback(checkpoint)
            return false
        }
        if sourceOwner != null {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            if TryAppendExplicitGenericSourceStaticCall(nodes, source, callNode, ownerName, memberName, sourceOwner, typeArguments, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, out resultType) {
                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }
            plan.Rollback(checkpoint)
            return false
        }
        if sourceOwnerBlocked {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            plan.Rollback(checkpoint)
            return false
        }
        arrayDeclaringTypeIdentity := ""
        if ColumnarExternalBindingPlans.TryGetArrayEmptyExplicitGenericOwner(ownerName, memberName, typeArguments.Length, argumentTypes.Length, out arrayDeclaringTypeIdentity) {
            if IsArrayEmptySourceElement(typeArguments[0], bindings.SourceTypeDefinitions) {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
                arrayType := typeof(object)
                if !scope.TryResolveExternalStaticOwner(nodes.EnclosingTypeName, nodes.VisibleTypeParameterNames, rootName, ownerName, arrayDeclaringTypeIdentity, out arrayType) {
                    plan.Rollback(checkpoint)
                    return false
                }

                arraySelection := ColumnarRuntimeDirectCallSelection.Empty()
                if !ColumnarRuntimeDirectCallResolver.TrySelectArrayEmpty(arrayType, typeArguments[0], out arraySelection) || !AppendRuntimeSelection(nodes, source, callNode, -1, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, arraySelection, out resultType) {
                    plan.Rollback(checkpoint)
                    return false
                }

                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }
        }

        externalPlan := ColumnarExternalBindingPlans.GetExplicitGenericStaticCallPlan(ownerName, memberName, TypeNames(typeArguments), TypeNames(argumentTypes))
        if !externalPlan.IsSupported {
            plan.Rollback(checkpoint)
            return false
        }

        ownership = ColumnarDirectCallOwnership.OwnedRejected
        lookupType := typeof(object)
        if !scope.TryResolveExternalStaticOwner(nodes.EnclosingTypeName, nodes.VisibleTypeParameterNames, rootName, ownerName, externalPlan.DeclaringTypeName, out lookupType) {
            plan.Rollback(checkpoint)
            return false
        }

        runtimeSelection := ColumnarRuntimeDirectCallSelection.Empty()
        if !ColumnarRuntimeDirectCallResolver.TrySelect(externalPlan, lookupType, true, out runtimeSelection) || !AppendRuntimeSelection(nodes, source, callNode, -1, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, runtimeSelection, out resultType) {
            plan.Rollback(checkpoint)
            return false
        }

        ownership = ColumnarDirectCallOwnership.Planned
        return true
    }

    static func IsArrayEmptySourceElement(elementType: Type, sourceDefinitions: IEnumerable<ColumnarStructDef>): bool {
        if !(elementType is TypeBuilder) {
            return false
        }

        candidate := ColumnarSourceDefinitionResolver.FindByBuilderIdentity(sourceDefinitions, elementType)
        if candidate == null || !candidate.IsReference || candidate.Builder.get_IsGenericTypeDefinition() {
            return false
        }

        return true
    }

    // `base.M(args)` — THE MEMBER THE BASE DECLARES, DISPATCHED NON-VIRTUALLY.
    //
    // Argument zero is the receiver here exactly as it is for an implicit-`this` call, so only two
    // things differ, and both are the whole point of writing `base`:
    //
    //   * LOOKUP STARTS AT THE DIRECT BASE. An override that calls `base.M()` must reach the
    //     implementation it replaced, so the subclass's own declaration is skipped rather than
    //     preferred.
    //   * DISPATCH IS `call`, NEVER `callvirt`. A virtual dispatch would re-enter the override and
    //     recurse until the stack is gone; the whole reason the CLR has a non-virtual call on a
    //     virtual method is this one form.
    //
    // Both halves of the base surface are covered by the owners that already exist: a base being
    // emitted in this same compilation resolves through the source resolver against the recorded
    // base definition, and a runtime base through the ordinary runtime resolver. An ABSTRACT base
    // member is refused — there is no implementation to reach, and `call` on one is unverifiable IL.
    static func TryAppendBaseCall(nodes: ColumnarNodeTable, source: string, callNode: int, callee: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, checkpoint: ColumnarCodePlanCheckpoint, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        memberName := nodes.Text(source, callee)
        current := bindings.CurrentInstance
        currentDefinition: ColumnarStructDef? = null
        if current != null {
            currentDefinition = current.SourceDefinition
        }

        if nodes.ChildCount(callee) != 0 || memberName.Length == 0 || current == null || currentDefinition == null {
            plan.Rollback(checkpoint)
            return false
        }

        sourceBase := currentDefinition.BaseDef
        exactBaseType := currentDefinition.ExactBaseType
        if sourceBase != null && exactBaseType != null {
            closedBase := ColumnarSourceDirectCallResolver.ExactSourceTypeMatch(sourceBase, exactBaseType)
            // The last argument says what `base.` means to the family-receiver rule: the written
            // receiver is the base, but argument zero is `this`, so the receiver IS the accessing type.
            sourceSelection := ColumnarSourceDirectCallResolver.ResolveKnownInstance(sourceBase, exactBaseType, closedBase, memberName, argumentTypes, argumentFacts, currentDefinition, true, true)

            if sourceSelection.IsSelected && !sourceSelection.IsAbstract {
                if !AppendSourceSelection(nodes, source, callNode, -1, true, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, NonVirtualBaseSelection(sourceSelection, current.ExactType), out resultType) {
                    plan.Rollback(checkpoint)
                    return false
                }

                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }

            if sourceSelection.IsSourceType && ColumnarSourceDirectCallResolver.HasInstanceDeclaration(sourceBase, memberName) {
                plan.Rollback(checkpoint)
                return false
            }
        }

        // No source base declares the name — the base is a runtime class (declared or the implicit
        // `System.Object`), and its members are ordinary runtime instance members.
        runtimeBase := ResolveExternalRuntimeBase(currentDefinition)
        if runtimeBase == null {
            runtimeBase = typeof(object)
        }

        // `base.M()` inside a derived type reaches everything the base declares protected.
        runtimeSelection := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveInheritedWithFacts(runtimeBase, memberName, argumentTypes, argumentFacts, false)

        runtimeMethod := runtimeSelection.Method
        if !runtimeSelection.IsSelected || runtimeMethod == null || runtimeMethod.get_IsAbstract() {
            plan.Rollback(checkpoint)
            return false
        }

        receiverIndex := ColumnarBoundIdentifierPlanner.GetOrAddArgument(plan, 0, current.ExactType, false)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), receiverIndex)

        if !AppendArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, ArgumentsAdmitPrimitiveBinary(), argumentTypes, runtimeSelection.ParameterTypes, argumentFacts) {
            plan.Rollback(checkpoint)
            return false
        }

        runtimeMethodIndex := plan.AddMethodWithSignature(runtimeMethod, runtimeSelection.DeclaringType, runtimeSelection.ParameterTypes, runtimeSelection.ReturnType, false, false)

        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), runtimeMethodIndex)
        resultType = runtimeSelection.ReturnType
        if IsVoidType(resultType) && callFragment != 0 && !plan.IsMethodBodyRootFragment(callFragment) {
            plan.Rollback(checkpoint)
            return false
        }

        ownership = ColumnarDirectCallOwnership.Planned
        return true
    }

    // The base's selection, re-stated for the `base.` form: the RECEIVER is the current instance (it
    // is argument zero, whatever the base's own type is) and the dispatch is non-virtual. Everything
    // that names the member — the handle, its declaring type and its closed signature — is the base
    // selection's own.
    static func NonVirtualBaseSelection(selection: ColumnarSourceDirectCallSelection, receiverType: Type): ColumnarSourceDirectCallSelection {
        return new ColumnarSourceDirectCallSelection(
            selection.Status,
            ColumnarSourceDirectCallDispatch.Call,
            selection.SourceDefinition,
            receiverType,
            selection.DeclaringType,
            selection.Method,
            selection.ParameterTypes,
            selection.ReturnType,
            selection.ReceiverIsReference,
            selection.IsStatic,
            selection.IsAbstract
        )
    }

    static func TryAppendBareCall(nodes: ColumnarNodeTable, source: string, callNode: int, callee: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, checkpoint: ColumnarCodePlanCheckpoint, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if nodes.ChildCount(callee) != 0 {
            plan.Rollback(checkpoint)
            return false
        }

        memberName := nodes.Text(source, callee)
        explicitThis := ColumnarExpressionSyntaxFacts.IsExplicitThisIdentifier(nodes, source, callee)

        if memberName.Length == 0 {
            plan.Rollback(checkpoint)
            return false
        }

        // A plannable sibling takes precedence over the enclosing type's own instance/static
        // members, mirroring the mechanical host's bare-call order. Other callable names (visible
        // local functions and residual declared-callable names) stay legacy exactly as before.
        if !explicitThis && bindings.HasSiblingCallable(memberName) {
            return TryAppendSiblingCall(nodes, source, callNode, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, memberName, checkpoint, out ownership, out legacyWholeSubtreePlanning, out resultType)
        }

        if !explicitThis && bindings.IsCallable(memberName) {
            plan.Rollback(checkpoint)
            return false
        }

        // A delegate-typed value binding (local/parameter/lifted/boxed) with no same-named method
        // tier is invoked through the delegate's Invoke method. The mechanical host's pinned
        // method-beats-value order means any instance method (at any arity) on the current type, any
        // static method at this arity on the enclosing type, or any sibling keeps the name terminal
        // for its own owner, so those cases fall through to ordinary resolution below.
        // The name must not be a METHOD's on any tier — the mechanical host's pinned
        // method-beats-value order means any instance method (at any arity) on the current type, any
        // static method at this arity on the enclosing type, or any sibling keeps the name terminal
        // for its own owner. What is left is a delegate-typed VALUE, and it no longer matters whether
        // that value shadows a sibling nor whether the receiver was written: a delegate field of the
        // current instance is as callable as a delegate local, `this.` in front of it changes
        // nothing, and all of them are `Invoke` on the value's own type.
        if !bindings.HasSiblingCallable(memberName) && !HasCurrentInstanceMethodAnyArity(bindings, memberName) && !HasEnclosingStaticMethodAtArity(bindings, memberName, argumentTypes.Length) && ((!explicitThis && bindings.IsSiblingShadowedByValue(memberName)) || IsDelegateValueCallee(nodes, source, callee, bindings)) {
            return TryAppendDelegateInvoke(nodes, source, callNode, callee, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, checkpoint, out ownership, out legacyWholeSubtreePlanning, out resultType)
        }

        current := bindings.CurrentInstance
        currentDefinition: ColumnarStructDef? = null
        if current != null {
            currentDefinition = current.SourceDefinition
        }

        if currentDefinition != null && ColumnarSourceDirectCallResolver.HasInstanceDeclarationAtArity(currentDefinition, memberName, argumentTypes.Length) {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            if !explicitThis && bindings.IsValueBinding(memberName) {
                plan.Rollback(checkpoint)
                return false
            }

            selection := ColumnarSourceDirectCallResolver.ResolveImplicitInstance(currentDefinition, current.ExactType, memberName, argumentTypes, argumentFacts)

            if !selection.IsSelected {
                if HasExcludedInstanceOwnerAtArity(currentDefinition, current.ExactType, memberName, argumentTypes.Length) {
                    ownership = ColumnarDirectCallOwnership.NotOwned
                    legacyWholeSubtreePlanning = true
                }

                plan.Rollback(checkpoint)
                return false
            }

            if !AppendSourceSelection(nodes, source, callNode, -1, true, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, selection, out resultType) {
                plan.Rollback(checkpoint)
                return false
            }

            ownership = ColumnarDirectCallOwnership.Planned
            return true
        }

        if currentDefinition != null && HasExcludedInstanceOwnerAtArity(currentDefinition, current.ExactType, memberName, argumentTypes.Length) {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }

        // Implicit-`this` (bare `Ok(data)`) or explicit-`this` (`this.Ok(data)`, which the parser
        // flattens to this same leaf-identifier callee) call to a method INHERITED FROM AN EXTERNAL
        // RUNTIME BASE class (-> Microsoft.AspNetCore.Mvc.ControllerBase.Ok(object) inside a source
        // `WeatherController: ControllerBase`). A source declaration of this name at any arity hides
        // the entire external chain and was resolved above, so this branch fires only when the source
        // hierarchy declares nothing of the name; a value binding shadows the bare form but not the
        // explicit `this.` form. Selection reuses the exact runtime member-call machinery (fixed
        // arity, non-generic, ordinary parameters, conversion-admitted overload ranking, and the
        // receiver's call/callvirt instruction) applied to the recorded external base and its own
        // inherited chain, loading the current instance as the receiver. A non-selected inherited
        // shape (excluded generic/params/by-ref, arity mismatch, or ambiguous set) is not claimed.
        if currentDefinition != null && (explicitThis || !bindings.IsValueBinding(memberName)) && !ColumnarSourceDirectCallResolver.HasInstanceDeclaration(currentDefinition, memberName) {
            externalBase := ResolveExternalRuntimeBase(currentDefinition)
            // A SOURCE CLASS WITH NO `:` CLAUSE STILL HAS A BASE, AND IT IS `System.Object`. The walk
            // above reports the implicit base as NO answer because it contributes nothing BEYOND
            // object's own surface — but object's own surface is exactly what `this.GetType()` asks
            // for, and with nothing here to answer it the whole call was claimed and rejected, while
            // `(this as object).GetType()` emitted. A reference receiver is `ldarg.0` either way; a
            // value `this` is a managed pointer whose inherited dispatch needs a box, so a struct
            // keeps the existing answer.
            if externalBase == null && current.IsReference {
                externalBase = typeof(object)
            }
            if externalBase != null {
                inherited := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveInheritedWithFacts(externalBase, memberName, argumentTypes, argumentFacts, false)

                if inherited.IsSelected {
                    ownership = ColumnarDirectCallOwnership.OwnedRejected
                    if !AppendInheritedImplicitSelection(nodes, source, callNode, current.ExactType, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, inherited, out resultType) {
                        plan.Rollback(checkpoint)
                        return false
                    }

                    ownership = ColumnarDirectCallOwnership.Planned
                    return true
                }
            }
        }

        if explicitThis {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            plan.Rollback(checkpoint)
            return false
        }

        enclosing := bindings.EnclosingTypeDefinition
        if enclosing == null || !ColumnarSourceDirectCallResolver.HasStaticDeclarationAtArity(enclosing, memberName, argumentTypes.Length) {
            plan.Rollback(checkpoint)
            return false
        }

        ownership = ColumnarDirectCallOwnership.OwnedRejected
        if bindings.IsValueBinding(memberName) {
            plan.Rollback(checkpoint)
            return false
        }

        staticSelection := ColumnarSourceDirectCallResolver.ResolveImplicitStatic(enclosing, enclosing.Builder, memberName, argumentTypes, argumentFacts)

        if !staticSelection.IsSelected {
            if HasExcludedStaticOwnerAtArity(enclosing, memberName, argumentTypes.Length) {
                ownership = ColumnarDirectCallOwnership.NotOwned
                legacyWholeSubtreePlanning = true
            }

            plan.Rollback(checkpoint)
            return false
        }

        if !AppendSourceSelection(nodes, source, callNode, -1, false, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, staticSelection, out resultType) {
            plan.Rollback(checkpoint)
            return false
        }

        ownership = ColumnarDirectCallOwnership.Planned
        return true
    }

    // The external runtime base this definition inherits from, through the one inherited-base walk.
    // The definition is asked without an exact receiver type, so a base template written in the
    // link's own type parameters stays open — which is what a call planned against the DEFINITION
    // needs; a caller holding a closed receiver asks `ColumnarInheritedExternalBase.Resolve` with it.
    static func ResolveExternalRuntimeBase(definition: ColumnarStructDef): Type? {
        return ColumnarInheritedExternalBase.Resolve(definition, null)
    }

    // A loose existence check for the entry-gate only: does the recorded external base (or its own
    // inherited chain) declare any instance method of this name and arity that a derived type here
    // may reach? Exact overload selection and the excluded-shape fence run in the inherited-external
    // arm; this just keeps a plausible inherited call from bailing out with the other unknown bare
    // names.
    //
    // IT ASKS THE SAME CANDIDATE SET THE ARM BEHIND IT RESOLVES OVER, which it did not: the gate
    // enumerated PUBLIC methods only, so `SetItem(0, value)` inside a `Collection<T>` subclass — a
    // `protected virtual` member the arm behind this gate selects perfectly well — bailed out here
    // and declined as an unresolvable bare call, while `this.SetItem(0, value)` emitted. The two
    // spellings name the same member of the same receiver; a gate narrower than its own arm is a gap,
    // not a rule.
    static func HasInheritedExternalInstanceMethod(definition: ColumnarStructDef, memberName: string, argumentCount: int): bool {
        externalBase := ResolveExternalRuntimeBase(definition)
        if externalBase == null {
            return false
        }

        return ColumnarOrdinaryRuntimeDirectCallResolver.HasInstanceMethodAtArity(externalBase, memberName, argumentCount, true)
    }

    // Emit a bare implicit-`this` call to an inherited external-base instance method: load the
    // current instance (argument zero) as the receiver value, emit each argument on its exact
    // parameter type, and dispatch with the receiver's exact call/callvirt instruction. The
    // declaring type is the external method's real CLR owner; the loaded instance is verifiably
    // assignable to it, so no receiver cast is required.
    static func AppendInheritedImplicitSelection(nodes: ColumnarNodeTable, source: string, callNode: int, receiverType: Type, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, inferredArgumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, selection: ColumnarOrdinaryRuntimeDirectCallSelection, out resultType: Type): bool {
        resultType = typeof(int)
        method := selection.Method
        if !selection.IsSelected || method == null || selection.IsStatic {
            return false
        }

        argumentIndex := ColumnarBoundIdentifierPlanner.GetOrAddArgument(plan, 0, receiverType, false)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)

        if !AppendArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, ArgumentsAdmitPrimitiveBinary(), inferredArgumentTypes, selection.ParameterTypes, argumentFacts) {
            return false
        }

        methodIndex := plan.AddMethodWithSignature(method, selection.DeclaringType, selection.ParameterTypes, selection.ReturnType, false, method.get_IsAbstract())

        plan.AppendMethodInstruction((short)(selection.UsesCallVirtual ? ColumnarCodePlanContract.Callvirt() : ColumnarCodePlanContract.Call()), methodIndex)

        resultType = selection.ReturnType
        return !IsVoidType(resultType) || callFragment == 0 || plan.IsMethodBodyRootFragment(callFragment)
    }

    // Emit an explicit-receiver call to an inherited external-base instance method (`this.Ok(data)`
    // or `controller.Ok(data)` where the receiver is a source type that extends a runtime base): load
    // the source receiver as a value against its own exact type, emit each argument, and dispatch the
    // inherited method. The loaded receiver is verifiably assignable to the method's declaring type.
    static func AppendInheritedExplicitSelection(nodes: ColumnarNodeTable, source: string, callNode: int, receiverNode: int, receiverType: Type, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, inferredArgumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, selection: ColumnarOrdinaryRuntimeDirectCallSelection, out resultType: Type): bool {
        resultType = typeof(int)
        method := selection.Method
        if !selection.IsSelected || method == null || selection.IsStatic {
            return false
        }

        if !AppendExplicitReceiver(nodes, source, receiverNode, bindings, handles, plan, callFragment, depth + 1, receiverType, true) {
            return false
        }

        if !AppendArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, ArgumentsAdmitPrimitiveBinary(), inferredArgumentTypes, selection.ParameterTypes, argumentFacts) {
            return false
        }

        methodIndex := plan.AddMethodWithSignature(method, selection.DeclaringType, selection.ParameterTypes, selection.ReturnType, false, method.get_IsAbstract())

        plan.AppendMethodInstruction((short)(selection.UsesCallVirtual ? ColumnarCodePlanContract.Callvirt() : ColumnarCodePlanContract.Call()), methodIndex)

        resultType = selection.ReturnType
        return !IsVoidType(resultType) || callFragment == 0 || plan.IsMethodBodyRootFragment(callFragment)
    }

    // A bare call to a top-level sibling function. The direct owner plans only the ordinary,
    // fixed-arity, non-generic shape the mechanical host would emit as a plain static Call; every
    // other admissible sibling shape (generic, by-ref/out/params parameters, arity mismatch, a
    // value binding that shadows the name, or an argument the planner cannot lower) yields the
    // whole subtree to the legacy sibling arm so its exact behavior is preserved. Because the name
    // is a sibling, this owner is terminal: it never falls through to the enclosing type's own
    // instance or static members, matching the host's bare-call precedence.
    static func TryAppendSiblingCall(nodes: ColumnarNodeTable, source: string, callNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, memberName: string, checkpoint: ColumnarCodePlanCheckpoint, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)

        facts := bindings.SiblingCallables[memberName]
        if facts == null {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }

        // A local, parameter, lifted local, or boxed capture of the same name shadows the sibling.
        // The host then emits a delegate invoke or reports the method/value collision; keep the
        // whole subtree for that legacy path.
        if bindings.IsSiblingShadowedByValue(memberName) {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }

        // Generic siblings, by-ref/out/params parameters, and arity mismatches are all shapes the
        // legacy sibling arm still owns (generic inference, expanded params, by-ref argument
        // emission, or an outright decline). Preserve the subtree for it.
        if facts.TypeParameterCount > 0 || HasNonOrdinarySiblingParameter(facts.ParameterTypes, facts.ParameterModifierKinds) || facts.ParameterTypes.Length != argumentTypes.Length {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }

        if !AppendSiblingSelection(nodes, source, callNode, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, facts, out resultType) {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }

        ownership = ColumnarDirectCallOwnership.Planned
        return true
    }

    // `d(args)` — CALLING A DELEGATE-TYPED VALUE WITHOUT WRITING `.Invoke`.
    //
    // The two spellings are the same call, so this owner answers the bare one by resolving the same
    // member the dotted one resolves: `Invoke` on the delegate's own type, through the ordinary
    // runtime resolver, with the CALLEE NODE ITSELF as the receiver. Nothing about the delegate is
    // special-cased — the arguments are appended by the shared argument walk against `Invoke`'s
    // parameter types, and the dispatch is the `callvirt` any instance method of a reference type
    // gets.
    //
    // The value may be a local, a parameter, a lifted capture or a FIELD of the current instance:
    // whichever it is, `AppendExplicitReceiver` plans the identifier exactly as it would in any other
    // receiver position, so a delegate field no longer has to be copied to a local first.
    static func TryAppendDelegateInvoke(nodes: ColumnarNodeTable, source: string, callNode: int, callee: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, checkpoint: ColumnarCodePlanCheckpoint, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)

        delegateType := typeof(object)
        if !ColumnarBoundIdentifierPlanner.TryGetBoundType(nodes, source, callee, bindings, out delegateType) || !IsDelegateValueType(delegateType) {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }

        calleeCandidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, callee)
        if calleeCandidate < 0 {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }

        selection := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveWithFacts(delegateType, "Invoke", argumentTypes, argumentFacts, false)

        if !selection.IsSelected || !AppendOrdinaryRuntimeSelection(nodes, source, callNode, calleeCandidate, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, selection, out resultType) {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }

        ownership = ColumnarDirectCallOwnership.Planned
        return true
    }

    // IS THIS VALUE A DELEGATE? The question is asked of the CLR's own hierarchy rather than of a
    // list of delegate names, so a `Func`, an `Action`, an `EventHandler` and a delegate declared by
    // a referenced assembly all answer alike.
    //
    // A delegate instantiated over a type parameter of the type being emitted — `Action<T>` inside
    // `Holder<T>` — is a `TypeBuilderInstantiation`, and reflection queries THROW on one; its open
    // definition is a baked runtime type and answers for it, because closing a generic type cannot
    // change what it derives from.
    static func IsDelegateValueType(valueType: Type): bool {
        candidate := valueType
        if valueType.get_IsGenericType() && !valueType.get_IsGenericTypeDefinition() && RuntimeTypeShapeFacts.ContainsBuilderBoundType(valueType) {
            candidate = valueType.GetGenericTypeDefinition()
        }

        if candidate is TypeBuilder || candidate.get_IsGenericParameter() || candidate == typeof(Delegate) || candidate == typeof(MulticastDelegate) {
            return false
        }

        try {
            return typeof(Delegate).IsAssignableFrom(candidate)
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }
    }

    // Does this bare callee name a delegate-typed value? Asked before the method tiers are consulted
    // is wrong and asked after them is right, so this is only ever a LAST classification: a method of
    // the name wins wherever one exists.
    static func IsDelegateValueCallee(nodes: ColumnarNodeTable, source: string, callee: int, bindings: ColumnarFragmentBindings): bool {
        calleeType := typeof(object)
        return ColumnarBoundIdentifierPlanner.TryGetBoundType(nodes, source, callee, bindings, out calleeType) && IsDelegateValueType(calleeType)
    }

    // A same-named instance method anywhere on the current type's hierarchy keeps a bare call
    // terminal for its own owner regardless of arity, exactly as the mechanical host's delegate
    // arm consults the method chain before invoking a value.
    static func HasCurrentInstanceMethodAnyArity(bindings: ColumnarFragmentBindings, memberName: string): bool {
        current := bindings.CurrentInstance
        if current == null {
            return false
        }

        currentDefinition := current.SourceDefinition
        return currentDefinition != null && ColumnarSourceDirectCallResolver.HasInstanceDeclaration(currentDefinition, memberName)
    }

    static func HasEnclosingStaticMethodAtArity(bindings: ColumnarFragmentBindings, memberName: string, argumentCount: int): bool {
        enclosing := bindings.EnclosingTypeDefinition
        return enclosing != null && ColumnarSourceDirectCallResolver.HasStaticDeclarationAtArity(enclosing, memberName, argumentCount)
    }

    // Every plannable sibling parameter must be an ordinary (non-by-ref) value with no ref/out/
    // params/this modifier. A by-ref parameter type or any non-None modifier kind returns true so
    // the caller yields to the legacy sibling arm.
    static func HasNonOrdinarySiblingParameter(parameterTypes: Type[], modifierKinds: int[]): bool {
        index := 0
        while index < parameterTypes.Length {
            if parameterTypes[index] == null || parameterTypes[index].get_IsByRef() {
                return true
            }

            index += 1
        }

        index = 0
        while index < modifierKinds.Length {
            if modifierKinds[index] != 0 {
                return true
            }

            index += 1
        }

        return false
    }

    static func AppendSiblingSelection(nodes: ColumnarNodeTable, source: string, callNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, inferredArgumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, facts: ColumnarSiblingCallFacts, out resultType: Type): bool {
        resultType = typeof(int)
        method := facts.Method
        if method == null {
            return false
        }

        if !AppendArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, ArgumentsAdmitPrimitiveBinary(), inferredArgumentTypes, facts.ParameterTypes, argumentFacts) {
            return false
        }

        declaringType := method.get_DeclaringType()
        if declaringType == null {
            return false
        }

        methodIndex := plan.AddMethodWithSignature(method, declaringType, facts.ParameterTypes, facts.ReturnType, true, false)

        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
        resultType = facts.ReturnType
        return !IsVoidType(resultType) || callFragment == 0 || plan.IsMethodBodyRootFragment(callFragment)
    }

    static func TryAppendMemberCall(nodes: ColumnarNodeTable, source: string, callNode: int, callee: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, checkpoint: ColumnarCodePlanCheckpoint, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if nodes.ChildCount(callee) != 1 {
            plan.Rollback(checkpoint)
            return false
        }

        memberName := nodes.Text(source, callee)
        receiverNode := nodes.Child(callee, 0)
        ownerName := ""
        rootName := ""
        sourceOwner: ColumnarStructDef? = null
        qualifiedOwner := ColumnarPlannerSupport.TryGetQualifiedName(nodes, source, receiverNode, 0, true, out ownerName, out rootName)

        // A CONSTRUCTED GENERIC TYPE RECEIVER — `Comparer<int>.Create(...)`. `TryGetQualifiedName`
        // cannot spell it (its walk admits a bare identifier and a dotted member access, and a kind-70
        // node is neither), so it is resolved to a CLOSED runtime type first and then goes straight to
        // the ordinary static overload resolver every other external static call reaches. There is no
        // table tier for it: a constructed generic owner has no hand-written binding plan and needs
        // none, because `ResolveWithFacts` reads the closed type's own metadata.
        if ColumnarGenericTypeReceiverFacts.IsReceiver(nodes, receiverNode) {
            constructedReceiverType := typeof(object)
            constructedClaimedBySource := false
            if !ColumnarGenericTypeReceiverFacts.TryResolveReceiverType(nodes, source, receiverNode, bindings, out constructedReceiverType, out constructedClaimedBySource) {
                if constructedClaimedBySource {
                    // A SOURCE-declared generic head — `Box<int>.Create(42)`,
                    // `Result<int, string>.Ok(42)`. The static member is declared once on the OPEN
                    // definition, so it is selected by the ordinary source static resolver against
                    // the CONSTRUCTED type: that resolver already substitutes the receiver's type
                    // arguments into the parameter and return types and rebinds the handle through
                    // `TypeBuilder.GetMethod`, which is what a member of a constructed generic
                    // `TypeBuilder` type requires. Nothing here is per-type: the definition is found
                    // by builder identity, the overload by ordinary resolution.
                    ownership = ColumnarDirectCallOwnership.OwnedRejected
                    constructedSourceType := typeof(object)
                    if ColumnarGenericTypeReceiverFacts.TryResolveSourceReceiverType(nodes, source, receiverNode, bindings, out constructedSourceType) {
                        constructedSourceOwner := ColumnarGenericTypeReceiverFacts.FindSourceDefinition(constructedSourceType, bindings.SourceTypeDefinitions)
                        if constructedSourceOwner != null {
                            constructedSourceSelection := ColumnarSourceDirectCallResolver.ResolveClassifiedStaticInCompilation(constructedSourceOwner, constructedSourceType, memberName, argumentTypes, argumentFacts, bindings.EnclosingTypeDefinition)
                            if constructedSourceSelection.IsSelected && AppendSourceSelection(nodes, source, callNode, -1, false, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, constructedSourceSelection, out resultType) {
                                ownership = ColumnarDirectCallOwnership.Planned
                                return true
                            }

                            // An EXCLUDED static shape on the constructed owner — a generic method,
                            // a params/by-ref/varargs declaration — has no fixed handle this planner
                            // can bind, exactly as on a non-constructed source owner. Leave the whole
                            // subtree to the owner that closes it rather than claiming and rejecting.
                            if HasExcludedStaticOwnerAtArity(constructedSourceOwner, memberName, argumentTypes.Length) {
                                ownership = ColumnarDirectCallOwnership.NotOwned
                                legacyWholeSubtreePlanning = true
                            }
                        }
                    }
                }

                plan.Rollback(checkpoint)
                return false
            }

            constructedSelection := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveWithFacts(constructedReceiverType, memberName, argumentTypes, argumentFacts, true)
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            if !constructedSelection.IsSelected || !AppendOrdinaryRuntimeSelection(nodes, source, callNode, -1, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, constructedSelection, out resultType) {
                plan.Rollback(checkpoint)
                return false
            }

            ownership = ColumnarDirectCallOwnership.Planned
            return true
        }

        staticSyntax := qualifiedOwner && !bindings.IsValueBinding(rootName) && !bindings.IsCallable(rootName) && !bindings.Enums.ContainsKey(ownerName) && !bindings.Enums.ContainsKey(rootName)
        scope := nodes.BindingScope

        if staticSyntax {

            // Sequential interface-method bindings shadow every same-spelled static root,
            // including source owners. Classify the shadow before either source or runtime
            // lookup so no later tier can reinterpret the root as a type name.
            if nodes.HasAdditionalRootBinding(rootName) || ContainsName(nodes.VisibleTypeParameterNames, rootName) {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
                plan.Rollback(checkpoint)
                return false
            }

            if scope != null && scope.IsFileImportAliasRoot(rootName) {

                // File-import alias calls include call-style newtype construction and other
                // alias-member forms outside fixed direct-method ownership. Preserve the entire
                // subtree for their owning lowering; never reinterpret the alias as a type. A
                // NAMESPACE alias is deliberately not here: it qualifies a type name rather than
                // binding one, and the owner resolution below expands it.
                ownership = ColumnarDirectCallOwnership.NotOwned
                legacyWholeSubtreePlanning = true
                plan.Rollback(checkpoint)
                return false
            }

            if scope != null && ownerName != rootName && scope.IsTypeAliasRoot(rootName) {

                // Direct alias owners remain eligible for exact source/runtime resolution. A
                // nested chain such as ByteArrayPool.Shared.Rent has a value-or-nested-type
                // receiver, so fixed direct-call ownership must preserve the complete subtree
                // for the composed-expression owner instead of treating the chain as a type.
                ownership = ColumnarDirectCallOwnership.NotOwned
                legacyWholeSubtreePlanning = true
                plan.Rollback(checkpoint)
                return false
            }

            exactSourceOwnerName := ownerName
            sourceOwnerBlocked := false
            sourceOwnerResolved := scope == null
            if scope != null {
                sourceOwnerResolved = scope.TryResolveSourceStaticOwner(nodes.EnclosingTypeName, nodes.VisibleTypeParameterNames, rootName, ownerName, out exactSourceOwnerName, out sourceOwnerBlocked)
            }

            if sourceOwnerResolved {
                sourceOwner = FindExactSourceOwner(exactSourceOwnerName, bindings.SourceTypeDefinitions)
            }

            if sourceOwnerResolved && sourceOwner == null {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
                plan.Rollback(checkpoint)
                return false
            }

            if sourceOwner != null {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
                sourceSelection := ColumnarSourceDirectCallResolver.ResolveClassifiedStaticInCompilation(sourceOwner, sourceOwner.Builder, memberName, argumentTypes, argumentFacts, bindings.EnclosingTypeDefinition)

                if !sourceSelection.IsSelected {
                    if HasExcludedStaticOwnerAtArity(sourceOwner, memberName, argumentTypes.Length) {
                        ownership = ColumnarDirectCallOwnership.NotOwned
                        legacyWholeSubtreePlanning = true
                    }

                    plan.Rollback(checkpoint)
                    return false
                }

                if !AppendSourceSelection(nodes, source, callNode, -1, false, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, sourceSelection, out resultType) {
                    plan.Rollback(checkpoint)
                    return false
                }

                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }

            if sourceOwnerBlocked {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
                plan.Rollback(checkpoint)
                return false
            }

            externalPlan := ColumnarExternalBindingPlans.GetStaticCallPlan(ownerName, memberName, TypeNames(argumentTypes))

            if externalPlan.IsSupported && !ContainsByRefArgument(argumentFacts) {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
                lookupType := typeof(object)
                if scope == null || !scope.TryResolveExternalStaticOwner(nodes.EnclosingTypeName, nodes.VisibleTypeParameterNames, rootName, ownerName, externalPlan.DeclaringTypeName, out lookupType) {
                    plan.Rollback(checkpoint)
                    return false
                }

                runtimeSelection := ColumnarRuntimeDirectCallSelection.Empty()
                if !ColumnarRuntimeDirectCallResolver.TrySelect(externalPlan, lookupType, true, out runtimeSelection) || !AppendRuntimeSelection(nodes, source, callNode, -1, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, runtimeSelection, out resultType) {
                    plan.Rollback(checkpoint)
                    return false
                }

                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }

            lookupType := typeof(object)
            if scope == null || !scope.TryResolveExternalStaticOwnerType(nodes.EnclosingTypeName, nodes.VisibleTypeParameterNames, rootName, ownerName, out lookupType) {
                // A DOTTED RECEIVER THE SCOPE CANNOT NAME AS A TYPE IS A VALUE, NOT A DEAD END.
                // `Encoding.UTF8`, `Console.Out`, `CultureInfo.InvariantCulture` — a type name followed
                // by a static PROPERTY read — is an ordinary instance receiver, and the value-receiver
                // owner below already plans exactly that shape. Handing the whole subtree to the legacy
                // emitter arm instead meant such a call could be a STATEMENT but never an ARGUMENT: a
                // nested value is typed by PLANNING it, and there is no legacy arm inside a plan, so
                // `Convert.ToHexString(Encoding.UTF8.GetBytes(root))` declined while the identical call
                // bound to a local emitted.
                //
                // THE LEGACY HAND-OFF IS STILL THE ANSWER WHEN THE VALUE ROUTE DECLINES, and it is
                // restored verbatim rather than replaced by whatever the value route reported: a chain
                // this owner has never claimed must not start hard-declining shapes the legacy arm
                // still emits.
                plan.Rollback(checkpoint)
                chainOwnership := ColumnarDirectCallOwnership.NotOwned
                chainLegacy := false
                if TryAppendValueReceiverMemberCall(nodes, source, callNode, receiverNode, memberName, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, checkpoint, out chainOwnership, out chainLegacy, out resultType) {
                    ownership = chainOwnership
                    legacyWholeSubtreePlanning = chainLegacy
                    return true
                }

                plan.Rollback(checkpoint)
                ownership = ColumnarDirectCallOwnership.NotOwned
                legacyWholeSubtreePlanning = true
                return false
            }

            ordinary := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveWithFacts(lookupType, memberName, argumentTypes, argumentFacts, true)

            if ordinary.IsSelected {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
                if !AppendOrdinaryRuntimeSelection(nodes, source, callNode, -1, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, ordinary, out resultType) {
                    plan.Rollback(checkpoint)
                    return false
                }

                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }

            // A GENERIC method definition is an excluded shape for the ordinary tier, because its
            // signature still mentions its own type parameters. Close it by inference from the
            // arguments and it becomes an ordinary MethodInfo the same append path emits.
            genericStatic := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(lookupType, memberName, argumentTypes, argumentFacts, true)

            if genericStatic.IsSelected {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
                if !AppendOrdinaryRuntimeSelection(nodes, source, callNode, -1, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, genericStatic, out resultType) {
                    plan.Rollback(checkpoint)
                    return false
                }

                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }

            // A TRAILING-OPTIONAL STATIC METHOD, on the same footing as the instance one below: the
            // call omitted an argument whose default the CALLER writes. It is tried even when a
            // same-named method was owned-rejected, because "a method of this name exists but no
            // overload binds at this arity" is EXACTLY the state an omitted defaulted argument
            // produces.
            optionalStatic := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveOptionalFill(lookupType, memberName, argumentTypes, argumentFacts, true)

            if optionalStatic.IsSelected {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
                if !AppendOptionalFillRuntimeSelection(nodes, source, callNode, -1, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, optionalStatic, out resultType) {
                    plan.Rollback(checkpoint)
                    return false
                }

                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }

            // THE LAST TIER: THE CALL SITE PACKS A `params` TAIL. Asked after the fixed-arity,
            // generic and trailing-optional resolvers, because each of those binds a candidate
            // applicable in its NORMAL form and C# prefers all of them to an expanded one.
            expandedStatic := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveExpandedWithFacts(lookupType, memberName, argumentTypes, argumentFacts, true)

            if expandedStatic.IsSelected {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
                if !AppendOrdinaryRuntimeSelection(nodes, source, callNode, -1, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, expandedStatic, out resultType) {
                    plan.Rollback(checkpoint)
                    return false
                }

                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }

            if ordinary.IsOwnedRejected {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
            } else {
                legacyWholeSubtreePlanning = true
            }

            plan.Rollback(checkpoint)
            return false
        }

        return TryAppendValueReceiverMemberCall(nodes, source, callNode, receiverNode, memberName, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, checkpoint, out ownership, out legacyWholeSubtreePlanning, out resultType)
    }

    // THE RECEIVER-IS-A-VALUE HALF of a member call, reached both by an ordinary `value.Member(...)`
    // and by a dotted chain whose head the scope could not name as a type (see the static arm above).
    static func TryAppendValueReceiverMemberCall(nodes: ColumnarNodeTable, source: string, callNode: int, receiverNode: int, memberName: string, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, checkpoint: ColumnarCodePlanCheckpoint, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        scope := nodes.BindingScope
        receiverType := typeof(int)
        receiverOwnership := ColumnarDirectCallOwnership.NotOwned
        // The RECEIVER surface stays the plain one: its append side (`AppendReceiver`) is the plain
        // dispatcher, and a type side that admitted more than the append side would only manufacture
        // declines one step later. What it DOES gain from `015-B9` is the enclosing frame, so a receiver
        // types in the position it is appended into exactly as an argument does.
        //
        // ⚠ 015-B13 — THIS LINE IS THE PAIR-HALF OF **TWO** APPEND SITES, AND THEY ARE PINNED TOGETHER
        // RATHER THAN LEFT AS UNEXPLAINED PLAIN CALLS. `AppendExtensionReceiver` and
        // `AppendExplicitReceiver` are the two append sides this `false` is matched with; a slice that
        // widens either one must widen this reading in the SAME slice, or it recreates on the receiver
        // side exactly the type-side/append-side disagreement `015-B13` removed from the delegate-invoke
        // argument loop above. `015-B12`'s census listed all three as one family of "hard-coded PLAIN
        // inner positions"; they are two families — an argument site that had no matching decision, and
        // a receiver PAIR that has one and states it here.
        if !TryGetPlannableValueType(nodes, source, receiverNode, bindings, handles, depth + 1, false, plan.IsMethodBodySchema(), out receiverType, out receiverOwnership) || IsVoidType(receiverType) {
            if receiverOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
            } else {
                legacyWholeSubtreePlanning = true
            }

            plan.Rollback(checkpoint)
            return false
        }

        sourceInstance := ColumnarSourceDirectCallResolver.ResolveExplicitInstanceInCompilation(receiverType, memberName, argumentTypes, bindings.SourceTypeDefinitions, argumentFacts, bindings.EnclosingTypeDefinition)

        if sourceInstance.IsSourceType {
            sourceDefinition := sourceInstance.SourceDefinition
            if sourceDefinition == null || !ColumnarSourceDirectCallResolver.HasInstanceDeclaration(sourceDefinition, memberName) {

                // The source receiver declares nothing of this name, so a same-named method may be
                // inherited from its EXTERNAL runtime base (`this.Ok`/`controller.Ok` ->
                // ControllerBase.Ok). Resolve it with the runtime member-call machinery and emit the
                // already-typed source receiver followed by the inherited dispatch, keeping the
                // explicit-receiver form consistent with the bare inherited-external call.
                if sourceDefinition != null {
                    externalBase := ResolveExternalRuntimeBase(sourceDefinition)
                    if externalBase != null {
                        inherited := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveInheritedWithFacts(externalBase, memberName, argumentTypes, argumentFacts, false)

                        if inherited.IsSelected {
                            ownership = ColumnarDirectCallOwnership.OwnedRejected
                            if !AppendInheritedExplicitSelection(nodes, source, callNode, receiverNode, receiverType, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, inherited, out resultType) {
                                plan.Rollback(checkpoint)
                                return false
                            }

                            ownership = ColumnarDirectCallOwnership.Planned
                            return true
                        }
                    }
                }

                legacyWholeSubtreePlanning = true
                plan.Rollback(checkpoint)
                return false
            }

            ownership = ColumnarDirectCallOwnership.OwnedRejected
            if !sourceInstance.IsSelected {
                if HasExcludedInstanceOwnerAtArity(sourceDefinition, receiverType, memberName, argumentTypes.Length) {
                    ownership = ColumnarDirectCallOwnership.NotOwned
                    legacyWholeSubtreePlanning = true
                }
                plan.Rollback(checkpoint)
                return false
            }

            if !AppendSourceSelection(nodes, source, callNode, receiverNode, false, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, sourceInstance, out resultType) {
                plan.Rollback(checkpoint)
                return false
            }

            ownership = ColumnarDirectCallOwnership.Planned
            return true
        }

        receiverName := receiverType.FullName ?? receiverType.Name
        instancePlan := ColumnarExternalBindingPlans.GetInstanceCallPlan(receiverName, memberName, TypeNames(argumentTypes))

        if instancePlan.IsSupported && !ContainsByRefArgument(argumentFacts) {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            runtimeInstance := ColumnarRuntimeDirectCallSelection.Empty()
            selectedInstance := ColumnarRuntimeDirectCallResolver.TrySelect(instancePlan, receiverType, false, out runtimeInstance)
            if !selectedInstance || !AppendRuntimeSelection(nodes, source, callNode, receiverNode, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, runtimeInstance, out resultType) {
                plan.Rollback(checkpoint)
                return false
            }

            ownership = ColumnarDirectCallOwnership.Planned
            return true
        }

        ordinaryInstance := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveWithFacts(receiverType, memberName, argumentTypes, argumentFacts, false)

        if ordinaryInstance.IsSelected {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            if !AppendOrdinaryRuntimeSelection(nodes, source, callNode, receiverNode, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, ordinaryInstance, out resultType) {
                plan.Rollback(checkpoint)
                return false
            }

            ownership = ColumnarDirectCallOwnership.Planned
            return true
        }

        // A GENERIC instance method definition, closed by inference from the arguments, before the
        // fallbacks below: it is an ordinary member of the receiver's own type and must win against an
        // extension of the same name exactly as a non-generic instance member does.
        genericInstance := ColumnarRuntimeGenericMethodResolver.ResolveWithFacts(receiverType, memberName, argumentTypes, argumentFacts, false)

        if genericInstance.IsSelected {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            if !AppendOrdinaryRuntimeSelection(nodes, source, callNode, receiverNode, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, genericInstance, out resultType) {
                plan.Rollback(checkpoint)
                return false
            }

            ownership = ColumnarDirectCallOwnership.Planned
            return true
        }

        // No instance member of this name bound at the supplied arity. Two fallbacks remain before
        // the call is yielded, both terminal in N#: (1) a trailing-optional instance method on the
        // receiver's own type (`app.Run()` -> WebApplication.Run(string url = null),
        // `service.GetSymbols(snapshot, file)` -> `GetSymbols(snapshot, file, kind = null)`); (2) an
        // external extension method exported by a referenced assembly
        // (`builder.Services.AddControllers()`).
        //
        // THE TWO FALLBACKS DIFFER ON OWNED-REJECTED, AND THE DIFFERENCE IS PRECEDENCE. The optional
        // fill selects an instance member of the receiver's OWN type, so it runs whatever the
        // exact-arity tier said — and "a method of this name exists but no overload binds at this
        // arity" is exactly the state an omitted defaulted argument produces, which is why gating it
        // on a NOT-owned-rejected result made every such call decline. Extension lookup keeps the
        // gate: an extension may only be reached when the receiver has no matching instance method.
        optionalInstance := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveOptionalFill(receiverType, memberName, argumentTypes, argumentFacts, false)

        if optionalInstance.IsSelected {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            if !AppendOptionalFillRuntimeSelection(nodes, source, callNode, receiverNode, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, optionalInstance, out resultType) {
                plan.Rollback(checkpoint)
                return false
            }

            ownership = ColumnarDirectCallOwnership.Planned
            return true
        }

        if !ordinaryInstance.IsOwnedRejected {
            if scope != null {
                extension := ColumnarExtensionMethodSelection.None()
                if scope.TryResolveExtensionMethod(receiverType, memberName, argumentTypes, argumentFacts, out extension) && extension.IsSelected {
                    ownership = ColumnarDirectCallOwnership.OwnedRejected
                    if !AppendExtensionSelection(nodes, source, callNode, receiverNode, receiverType, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, extension, out resultType) {
                        plan.Rollback(checkpoint)
                        return false
                    }

                    ownership = ColumnarDirectCallOwnership.Planned
                    return true
                }
            }
        }

        // THE LAST TIER, for an instance receiver: the call site packs a `params` tail. It runs after
        // the extension lookup as well, because an extension is a NORMAL-form binding on a method the
        // receiver's own type does not declare, and preferring a packed instance call to it would
        // change which member a written call reaches.
        expandedInstance := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveExpandedWithFacts(receiverType, memberName, argumentTypes, argumentFacts, false)

        if expandedInstance.IsSelected {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            if !AppendOrdinaryRuntimeSelection(nodes, source, callNode, receiverNode, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, expandedInstance, out resultType) {
                plan.Rollback(checkpoint)
                return false
            }

            ownership = ColumnarDirectCallOwnership.Planned
            return true
        }

        if ordinaryInstance.IsOwnedRejected {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
        } else {
            legacyWholeSubtreePlanning = true
        }

        plan.Rollback(checkpoint)
        return false
    }

    // Emit an external extension call as an ordinary static `call` row: load the receiver as the
    // first argument, emit each explicit argument on its exact parameter type, fill every trailing
    // optional from its null metadata default, and dispatch the static method. The receiver's value
    // is verifiably assignable to the extension's declared receiver parameter, so no cast is emitted.
    static func AppendExtensionSelection(nodes: ColumnarNodeTable, source: string, callNode: int, receiverNode: int, receiverType: Type, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, selection: ColumnarExtensionMethodSelection, out resultType: Type): bool {
        resultType = typeof(int)
        method := selection.Method
        if !selection.IsSelected || method == null {
            return false
        }

        parameterTypes := selection.ParameterTypes
        explicitCount := selection.ExplicitArgumentCount
        if !AppendExtensionReceiver(nodes, source, receiverNode, parameterTypes[0], bindings, handles, plan, callFragment, depth + 1) {
            return false
        }

        parameters := method.GetParameters()
        if parameters == null || parameters.Length != parameterTypes.Length {
            return false
        }

        paramsElementType := selection.ParamsElementType
        if paramsElementType != null {
            // THE SELECTED SIGNATURE IS UNCHANGED; only the arguments are shaped differently. The
            // fixed ones are emitted exactly as any call's are and the rest are stored into a fresh
            // array, which is then the last ordinary argument of the same static call.
            expandedParameterTypes := ColumnarParamsExpansion.ExpandedParameterTypesOrNull(parameters, parameterTypes, 1, explicitCount)
            if expandedParameterTypes == null || !AppendExpandedArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, ArgumentsAdmitPrimitiveBinary(), argumentTypes, expandedParameterTypes, argumentFacts, ColumnarParamsExpansion.FixedArgumentCount(parameterTypes, 1), paramsElementType) {
                return false
            }
        } else {
            leadingParameterTypes := ColumnarExtensionMethodResolver.ExplicitParameterTypes(parameterTypes, explicitCount)
            if !AppendArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, ArgumentsAdmitPrimitiveBinary(), argumentTypes, leadingParameterTypes, argumentFacts) {
                return false
            }

            defaultIndex := 1 + explicitCount
            while defaultIndex < parameterTypes.Length {
                if !ColumnarExtensionMethodResolver.TryAppendOptionalDefault(plan, parameters[defaultIndex], parameterTypes[defaultIndex]) {
                    return false
                }

                defaultIndex += 1
            }
        }

        methodIndex := plan.AddMethodWithSignature(method, selection.DeclaringType, parameterTypes, selection.ReturnType, true, false)

        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
        resultType = selection.ReturnType
        return !IsVoidType(resultType) || callFragment == 0 || plan.IsMethodBodyRootFragment(callFragment)
    }

    // Load the extension receiver as an ordinary value in the call fragment, mirroring how each call
    // argument is emitted. Only reference receivers reach this owner, so no receiver address is taken.
    static func AppendExtensionReceiver(nodes: ColumnarNodeTable, source: string, receiverNode: int, expectedType: Type, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int): bool {
        emittedType := typeof(int)
        if !ColumnarRangeIndexPlanner.TryAppendPlannableValue(nodes, source, receiverNode, bindings, handles, plan, callFragment, depth, out emittedType) {
            return false
        }

        return !IsVoidType(emittedType) && ColumnarExtensionMethodResolver.ReferenceAssignableFrom(expectedType, emittedType)
    }

    // Emit a trailing-optional instance/static runtime call: emit the receiver (instance only), emit
    // each explicit argument on its exact leading parameter type, fill every trailing optional from
    // its null metadata default, and dispatch with the receiver's exact call/callvirt instruction.
    static func AppendOptionalFillRuntimeSelection(nodes: ColumnarNodeTable, source: string, callNode: int, receiverNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, selection: ColumnarRuntimeOptionalCallSelection, out resultType: Type): bool {
        resultType = typeof(int)
        method := selection.Method
        if !selection.IsSelected || method == null {
            return false
        }

        parameterTypes := selection.ParameterTypes
        explicitCount := selection.ExplicitArgumentCount
        if !selection.IsStatic && !AppendExplicitReceiver(nodes, source, receiverNode, bindings, handles, plan, callFragment, depth + 1, selection.LookupType, selection.ReceiverIsReference) {
            return false
        }

        leadingParameterTypes := ExtensionLeadingTypes(parameterTypes, explicitCount)
        if !AppendArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, ArgumentsAdmitPrimitiveBinary(), argumentTypes, leadingParameterTypes, argumentFacts) {
            return false
        }

        parameters := method.GetParameters()
        if parameters == null || parameters.Length != parameterTypes.Length {
            return false
        }

        defaultIndex := explicitCount
        while defaultIndex < parameterTypes.Length {
            if !ColumnarExtensionMethodResolver.TryAppendOptionalDefault(plan, parameters[defaultIndex], parameterTypes[defaultIndex]) {
                return false
            }

            defaultIndex += 1
        }

        methodIndex := plan.AddMethodWithSignature(method, selection.DeclaringType, parameterTypes, selection.ReturnType, selection.IsStatic, method.get_IsAbstract())

        plan.AppendMethodInstruction((short)(selection.UsesCallVirtual ? ColumnarCodePlanContract.Callvirt() : ColumnarCodePlanContract.Call()), methodIndex)

        resultType = selection.ReturnType
        return !IsVoidType(resultType) || callFragment == 0 || plan.IsMethodBodyRootFragment(callFragment)
    }

    static func ExtensionLeadingTypes(parameterTypes: Type[], count: int): Type[] {
        result := new Type[](count)
        index := 0
        while index < count {
            result[index] = parameterTypes[index]
            index += 1
        }

        return result
    }

    static func AppendOrdinaryRuntimeSelection(nodes: ColumnarNodeTable, source: string, callNode: int, receiverNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, inferredArgumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, selection: ColumnarOrdinaryRuntimeDirectCallSelection, out resultType: Type): bool {
        method := selection.Method
        if !selection.IsSelected || method == null {
            resultType = typeof(int)
            return false
        }

        // AN EXPANDED SELECTION WRITES TWO DIFFERENT SIGNATURES AND MUST KEEP THEM APART. The method
        // ROW carries the signature the callee declares; the ARGUMENT rows carry the per-argument list
        // the call site writes, with the packing in between. The by-ref mode check below is skipped
        // for one, and skipping it is not a relaxation: it compares the written argument count against
        // the DECLARED parameter count, which an expanded call deliberately differs from, and a
        // `params` tail cannot be by-ref while a `ref` argument in a fixed slot fails its conversion.
        if selection.IsExpanded {
            expandedElementType := selection.ExpandedElementType
            if expandedElementType == null {
                resultType = typeof(int)
                return false
            }

            if !selection.IsStatic && !AppendExplicitReceiver(nodes, source, receiverNode, bindings, handles, plan, callFragment, depth + 1, selection.LookupType, selection.ReceiverIsReference) {
                resultType = typeof(int)
                return false
            }

            if !AppendExpandedArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, ArgumentsAdmitPrimitiveBinary(), inferredArgumentTypes, selection.ParameterTypes, argumentFacts, selection.FixedArgumentCount, expandedElementType) {
                resultType = typeof(int)
                return false
            }

            expandedMethodIndex := plan.AddMethodWithSignature(method, selection.DeclaringType, selection.DeclaredParameterTypes, selection.ReturnType, selection.IsStatic, method.get_IsAbstract())
            plan.AppendMethodInstruction((short)(selection.UsesCallVirtual ? ColumnarCodePlanContract.Callvirt() : ColumnarCodePlanContract.Call()), expandedMethodIndex)
            resultType = selection.ReturnType
            return !IsVoidType(resultType) || callFragment == 0 || plan.IsMethodBodyRootFragment(callFragment)
        }

        if !ByRefArgumentModesMatch(nodes, source, callNode, argumentFacts, method) {
            resultType = typeof(int)
            return false
        }

        materialized := new ColumnarRuntimeDirectCallSelection(method, selection.LookupType, selection.DeclaringType, selection.ParameterTypes, selection.ReturnType, selection.Kind, selection.IsStatic, selection.ReceiverIsReference)

        return AppendRuntimeSelection(nodes, source, callNode, receiverNode, bindings, handles, plan, callFragment, depth, inferredArgumentTypes, argumentFacts, materialized, out resultType)
    }

    // `ref T` AND `out T` ARE NOT THE SAME PARAMETER, and reflection tells them apart only through
    // `ParameterInfo.IsOut`. The spelling has to match it in both directions at the ordinary runtime
    // boundary, because a matching managed address alone would otherwise let `ref x` bind an `out`
    // parameter — silently changing the caller's definite-assignment and write contract.
    static func ByRefArgumentModesMatch(nodes: ColumnarNodeTable, source: string, callNode: int, argumentFacts: ColumnarDirectCallArgumentFacts, method: MethodInfo): bool {
        if nodes == null || source == null || method == null || argumentFacts == null {
            return false
        }

        try {
            parameters := method.GetParameters()
            if parameters == null || parameters.Length != nodes.ChildCount(callNode) - 1 || argumentFacts.ArgumentNodes.Length != parameters.Length {
                return false
            }

            index := 0
            while index < parameters.Length {

                // The argument that landed in THIS parameter's slot -- a named argument may have been
                // written somewhere else in the list, and `ref`/`out` is matched against the parameter
                // it binds to, not the position it was typed at.
                argumentNode := argumentFacts.ArgumentNodes[index]
                if parameters[index].get_ParameterType().get_IsByRef() {
                    candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, argumentNode)
                    if candidate < 0 || nodes.Kind(candidate) != 54 || nodes.ChildCount(candidate) != 1 {
                        return false
                    }

                    modifier := nodes.Text(source, candidate)
                    if parameters[index].get_IsOut() {
                        if modifier != "out" {
                            return false
                        }
                    } else if modifier != "ref" {
                        return false
                    }
                } else if ByRefArgumentTarget(nodes, source, argumentNode) >= 0 {
                    return false
                }

                index += 1
            }

            return true
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }
    }

    static func AppendSourceSelection(nodes: ColumnarNodeTable, source: string, callNode: int, receiverNode: int, implicitReceiver: bool, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, inferredArgumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, selection: ColumnarSourceDirectCallSelection, out resultType: Type): bool {
        resultType = typeof(int)
        method := selection.Method
        if !selection.IsSelected || method == null {
            return false
        }

        if !selection.IsStatic {
            if implicitReceiver {
                AppendImplicitReceiver(plan, selection)
            } else if !AppendExplicitReceiver(nodes, source, receiverNode, bindings, handles, plan, callFragment, depth + 1, selection.ReceiverType, selection.ReceiverIsReference) {
                return false
            }

            AppendInterfaceReceiverWidening(plan, selection)
        }

        if !AppendArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, ArgumentsAdmitPrimitiveBinary(), inferredArgumentTypes, selection.ParameterTypes, argumentFacts) {
            return false
        }

        methodIndex := plan.AddMethodWithSignature(method, selection.DeclaringType, selection.ParameterTypes, selection.ReturnType, selection.IsStatic, selection.IsAbstract)

        opcode := (short)(selection.Dispatch == ColumnarSourceDirectCallDispatch.CallVirtual ? ColumnarCodePlanContract.Callvirt() : ColumnarCodePlanContract.Call())

        plan.AppendMethodInstruction(opcode, methodIndex)
        resultType = selection.ReturnType
        return !IsVoidType(resultType) || callFragment == 0 || plan.IsMethodBodyRootFragment(callFragment)
    }

    static func AppendRuntimeSelection(nodes: ColumnarNodeTable, source: string, callNode: int, receiverNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, inferredArgumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, selection: ColumnarRuntimeDirectCallSelection, out resultType: Type): bool {
        resultType = typeof(int)
        method := selection.Method
        if method == null {
            return false
        }

        if !selection.IsStatic && !AppendExplicitReceiver(nodes, source, receiverNode, bindings, handles, plan, callFragment, depth + 1, selection.LookupType, selection.ReceiverIsReference) {
            return false
        }

        if !AppendArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, ArgumentsAdmitPrimitiveBinary(), inferredArgumentTypes, selection.ParameterTypes, argumentFacts) {
            return false
        }

        methodIndex := plan.AddMethodWithSignature(method, selection.DeclaringType, selection.ParameterTypes, selection.ReturnType, selection.IsStatic, method.get_IsAbstract())

        plan.AppendMethodInstruction((short)(selection.UsesCallVirtual ? ColumnarCodePlanContract.Callvirt() : ColumnarCodePlanContract.Call()), methodIndex)

        resultType = selection.ReturnType
        return !IsVoidType(resultType) || callFragment == 0 || plan.IsMethodBodyRootFragment(callFragment)
    }

    // A SLOT A **BASE** INTERFACE DECLARED, REACHED THROUGH THE DERIVED ONE.
    //
    // `interface ITestCase: INamed` makes every `ITestCase` an `INamed`, and the selection walk
    // already finds `INamed`'s declaration through `InterfaceBases` — but the receiver on the stack
    // is still spelled `ITestCase`, and the sealed plan refused it with "reference receiver for
    // 'Name' does not match its declaring type". Reflection cannot settle that: both interfaces are
    // unbaked `TypeBuilder`s, and `IsAssignableFrom` / `GetInterfaces` throw `NotSupportedException`
    // over one, so the validator has no way to know the edge the SOURCE declared.
    //
    // The widening is therefore written into the plan, which is the same answer this planner already
    // gives for an ARGUMENT flowing into a source interface (`AppendArgumentConversion`'s
    // `exactSourceInterfaceFlow` arm emits exactly this `castclass`). Stating the conversion makes
    // the receiver's stack type the declaring interface, so the plan is checkable end to end rather
    // than checked by exception.
    //
    // ONLY AN INTERFACE DECLARING TYPE, and only when it is not the receiver's own type. A base
    // CLASS slot needs nothing: `IsExactDynamicBaseUpcast` walks a builder's base chain, which
    // Reflection.Emit does answer. A value receiver is loaded as a managed ADDRESS, which a
    // `castclass` cannot consume, so it is left to the arms that own boxing.
    static func AppendInterfaceReceiverWidening(plan: ColumnarCodePlan, selection: ColumnarSourceDirectCallSelection) {
        if !selection.ReceiverIsReference || !selection.DeclaringType.get_IsInterface() {
            return
        }

        if RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(selection.ReceiverType, selection.DeclaringType) {
            return
        }

        declaringIndex := plan.AddType(selection.DeclaringType)
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Castclass(), declaringIndex)
    }

    static func AppendImplicitReceiver(plan: ColumnarCodePlan, selection: ColumnarSourceDirectCallSelection) {
        argumentIndex := ColumnarBoundIdentifierPlanner.GetOrAddArgument(plan, 0, selection.ReceiverType, !selection.ReceiverIsReference)

        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
    }

    static func AppendExplicitReceiver(nodes: ColumnarNodeTable, source: string, receiverNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int, depth: int, expectedType: Type, receiverIsReference: bool): bool {
        receiverType := typeof(int)
        directStorage := false
        byRefParameter := false
        if !receiverIsReference && ColumnarInstanceMemberPlanner.TryAppendAddressableValueReceiver(nodes, source, receiverNode, bindings, plan, parentFragment, expectedType) {
            return true
        }

        if ColumnarBoundIdentifierPlanner.TryGetReceiverType(nodes, source, receiverNode, bindings, out receiverType, out directStorage, out byRefParameter) {
            if !RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(receiverType, expectedType) {
                return false
            }

            preserveAddress := !receiverIsReference && directStorage
            isAddress := false
            if preserveAddress {
                return ColumnarBoundIdentifierPlanner.TryAppendReceiver(nodes, source, receiverNode, bindings, true, plan, out receiverType, out isAddress) && isAddress
            }

            candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, receiverNode)
            if candidate < 0 {
                return false
            }

            receiverFragment := plan.BeginFragment(parentFragment, nodes.Kind(candidate), candidate)

            if !ColumnarBoundIdentifierPlanner.TryAppendReceiver(nodes, source, receiverNode, bindings, false, plan, out receiverType, out isAddress) || isAddress || !RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(receiverType, expectedType) {
                return false
            }

            plan.CompleteFragment(receiverFragment, receiverType)
            if !receiverIsReference {
                ColumnarInstanceMemberPlanner.AppendTemporaryAddress(plan, receiverType)
            }

            return true
        }

        if !ColumnarRangeIndexPlanner.TryAppendPlannableValue(nodes, source, receiverNode, bindings, handles, plan, parentFragment, depth, out receiverType) || !RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(receiverType, expectedType) {
            return false
        }

        if !receiverIsReference {
            ColumnarInstanceMemberPlanner.AppendTemporaryAddress(plan, receiverType)
        }

        return true
    }

    // THE ARGUMENT VALUE SURFACE, DECIDED ONCE (015-B9).
    //
    // `allowPrimitiveBinary` selects between the dispatcher's two value surfaces: the PLAIN one and the
    // one that also admits a primitive binary and a construction. Until this slice every one of this
    // owner's eight argument sites passed a hard-coded `false`, while the CONSTRUCTION owner reached the
    // same dispatcher through `TryAppendConstructionValue` with `true` — so `new Foo(a + b)` was
    // claimable and `Foo(a + b)` was not, for no reason either owner stated. That asymmetry was an
    // owner-scope artifact of the construction slice, not a rule about calls, and it cost the live corpus
    // real bodies (`Point::GetDistance`, `return Math.Sqrt(x * x + y * y)`).
    //
    // The decision lives here rather than at the eight sites so it has ONE name, ONE home and ONE
    // mutation anchor. The TYPE side (`TryGetArgumentTypes`) and the APPEND side (`AppendArguments`) must
    // read the same answer: a type side that admitted more would defer the decline by one step, and a
    // type side that admitted less would refuse a shape the append would have planned — which is exactly
    // the bug the enclosing-frame fix above removes.
    static func ArgumentsAdmitPrimitiveBinary(): bool {
        return true
    }

    static func AppendArguments(nodes: ColumnarNodeTable, source: string, callNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int, depth: int, allowPrimitiveBinary: bool, inferredTypes: Type[], parameterTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): bool {
        if inferredTypes.Length != parameterTypes.Length || nodes.ChildCount(callNode) - 1 != parameterTypes.Length || argumentFacts == null || argumentFacts.IsUnsuffixedIntegerLiteral.Length != parameterTypes.Length || argumentFacts.IsNegativeIntegerLiteral.Length != parameterTypes.Length || argumentFacts.IntegerLiteralValues.Length != parameterTypes.Length || argumentFacts.IsNullLiteral.Length != parameterTypes.Length || argumentFacts.IsIntegerConstantArrayLiteral.Length != parameterTypes.Length || argumentFacts.ArrayLiteralMinimumValues.Length != parameterTypes.Length || argumentFacts.ArrayLiteralMaximumValues.Length != parameterTypes.Length || argumentFacts.ArgumentNodes.Length != parameterTypes.Length || argumentFacts.WrittenOrderSlots.Length != parameterTypes.Length {
            return false
        }

        // A NAMED ARGUMENT THAT MOVED IS STILL EVALUATED WHERE IT WAS WRITTEN. `Send(body: Build(),
        // to: Lookup())` runs `Build()` first because that is the order the author wrote, and the call
        // still receives `to` first because that is the order the signature keeps -- so the written
        // order is evaluated into temporaries and the temporaries are handed over in slot order.
        // Nothing is spilled when the two orders agree, which is every call whose names were written
        // where the signature keeps them.
        if argumentFacts.RequiresReorder {
            return AppendReorderedArguments(nodes, source, bindings, handles, plan, parentFragment, depth, allowPrimitiveBinary, inferredTypes, parameterTypes, argumentFacts)
        }

        index := 0
        while index < parameterTypes.Length {
            if !AppendArgumentSlot(nodes, source, bindings, handles, plan, parentFragment, depth, allowPrimitiveBinary, inferredTypes, parameterTypes, argumentFacts, index) {
                return false
            }

            index += 1
        }

        return true
    }

    // THE ARGUMENTS OF A CALL WHOSE TAIL PACKS INTO A `params` ARRAY. The fixed arguments are emitted
    // exactly as any other call's are — the same slot appender, so the same conversions, the same
    // by-ref and null-literal rules — and every argument past them is stored into one fresh array
    // that becomes the call's last ordinary argument. `expandedParameterTypes` is as long as the
    // supplied arguments and already carries the element type in every packed position, so each slot
    // is emitted against the type it must actually convert to.
    //
    // EVALUATION ORDER IS THE WRITTEN ORDER, unchanged: `newarr` runs after the fixed arguments and
    // before the first element, and the elements run left to right, which is where a C# call site
    // evaluates them too.
    static func AppendExpandedArguments(nodes: ColumnarNodeTable, source: string, callNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int, depth: int, allowPrimitiveBinary: bool, inferredTypes: Type[], expandedParameterTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, fixedCount: int, elementType: Type): bool {
        if elementType == null || fixedCount < 0 || fixedCount > expandedParameterTypes.Length {
            return false
        }

        if inferredTypes.Length != expandedParameterTypes.Length || nodes.ChildCount(callNode) - 1 != expandedParameterTypes.Length || argumentFacts == null || argumentFacts.IsUnsuffixedIntegerLiteral.Length != expandedParameterTypes.Length || argumentFacts.IsNegativeIntegerLiteral.Length != expandedParameterTypes.Length || argumentFacts.IntegerLiteralValues.Length != expandedParameterTypes.Length || argumentFacts.IsNullLiteral.Length != expandedParameterTypes.Length || argumentFacts.IsIntegerConstantArrayLiteral.Length != expandedParameterTypes.Length || argumentFacts.ArrayLiteralMinimumValues.Length != expandedParameterTypes.Length || argumentFacts.ArrayLiteralMaximumValues.Length != expandedParameterTypes.Length || argumentFacts.ArgumentNodes.Length != expandedParameterTypes.Length || argumentFacts.WrittenOrderSlots.Length != expandedParameterTypes.Length {
            return false
        }

        // A NAMED ARGUMENT CANNOT NAME A PACKED ONE — the elements have no parameter of their own to
        // be named for — so a site whose written order and slot order disagree is left to decline
        // rather than reordered into an array whose positions are the author's.
        if argumentFacts.RequiresReorder {
            return false
        }

        index := 0
        while index < fixedCount {
            if !AppendArgumentSlot(nodes, source, bindings, handles, plan, parentFragment, depth, allowPrimitiveBinary, inferredTypes, expandedParameterTypes, argumentFacts, index) {
                return false
            }

            index += 1
        }

        elementTypeIndex := plan.AddType(elementType)
        ColumnarParamsExpansion.AppendArrayHeader(plan, elementTypeIndex, expandedParameterTypes.Length - fixedCount)
        while index < expandedParameterTypes.Length {
            ColumnarParamsExpansion.AppendElementPrologue(plan, index - fixedCount)
            if !AppendArgumentSlot(nodes, source, bindings, handles, plan, parentFragment, depth, allowPrimitiveBinary, inferredTypes, expandedParameterTypes, argumentFacts, index) {
                return false
            }

            ColumnarParamsExpansion.AppendElementEpilogue(plan, elementTypeIndex)
            index += 1
        }

        return true
    }

    // Evaluate the arguments in the order they were WRITTEN, each into a temporary of its parameter's
    // type, then load the temporaries in the order the signature keeps. A by-reference parameter's
    // type is itself a managed pointer, so its temporary holds the caller's ADDRESS and preserves the
    // alias across later argument evaluation; it must not copy the pointed-to value.
    static func AppendReorderedArguments(nodes: ColumnarNodeTable, source: string, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int, depth: int, allowPrimitiveBinary: bool, inferredTypes: Type[], parameterTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): bool {
        slotLocals := new int[](parameterTypes.Length)
        guard := 0
        while guard < parameterTypes.Length {
            if parameterTypes[guard] == null || argumentFacts.IsByRefArgument[guard] != parameterTypes[guard].get_IsByRef() {
                return false
            }

            slotLocals[guard] = -1
            guard += 1
        }

        written := 0
        while written < parameterTypes.Length {
            slot := argumentFacts.WrittenOrderSlots[written]
            if slot < 0 || slot >= parameterTypes.Length || slotLocals[slot] >= 0 || !AppendArgumentSlot(nodes, source, bindings, handles, plan, parentFragment, depth, allowPrimitiveBinary, inferredTypes, parameterTypes, argumentFacts, slot) {
                return false
            }

            localIndex := plan.DeclarePlanLocal(plan.AddType(parameterTypes[slot]))
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), localIndex)
            slotLocals[slot] = localIndex
            written += 1
        }

        reload := 0
        while reload < parameterTypes.Length {
            if slotLocals[reload] < 0 {
                return false
            }

            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), slotLocals[reload])
            reload += 1
        }

        return true
    }

    // ONE argument slot: the row at `index` -- its node, its inferred type and its literal facts --
    // planned against the parameter that slot belongs to.
    static func AppendArgumentSlot(nodes: ColumnarNodeTable, source: string, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int, depth: int, allowPrimitiveBinary: bool, inferredTypes: Type[], parameterTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, index: int): bool {

        // THE ARGUMENT THAT LANDED IN THIS SLOT, which is the call's child at this position only
        // when nothing was named: a named argument was placed by its name, and the row carrying
        // it moved with it.
        argumentNode := argumentFacts.ArgumentNodes[index]

        // A `ref`/`out` ARGUMENT PASSES STORAGE, NOT A VALUE. The written `ref x` is a modifier
        // node over the name, and what goes on the stack is the name's managed address, so this
        // arm bypasses the value walk entirely — there is no conversion to apply and no temporary
        // to make, because either would alias something the caller cannot see.
        if argumentFacts.IsByRefArgument[index] {
            byRefTarget := ByRefArgumentTarget(nodes, source, argumentNode)
            byRefElement := typeof(int)
            if byRefTarget < 0 || !parameterTypes[index].get_IsByRef() || !ColumnarBoundIdentifierPlanner.TryAppendAddressOf(nodes, source, byRefTarget, bindings, plan, out byRefElement) {
                return false
            }

            expectedElement := parameterTypes[index].GetElementType()
            if expectedElement == null || !RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(expectedElement, byRefElement) {
                return false
            }

            return true
        }

        if argumentFacts.IsNullLiteral[index] {
            candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, argumentNode)
            if candidate < 0 || !ColumnarNullableArgumentLowering.TryAppendNullArgument(plan, parentFragment, nodes.Kind(candidate), candidate, parameterTypes[index]) {
                return false
            }

            return true
        }

        if argumentFacts.IsUnsuffixedIntegerLiteral[index] {
            literalTarget := parameterTypes[index]
            liftTarget := false
            if !ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(literalTarget, argumentFacts.IntegerLiteralValues[index], argumentFacts.IsNegativeIntegerLiteral[index]) {
                nullableElement := typeof(int)
                if ColumnarNullableArgumentLowering.TryGetSupportedNullableElement(parameterTypes[index], out nullableElement) && ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(nullableElement, argumentFacts.IntegerLiteralValues[index], argumentFacts.IsNegativeIntegerLiteral[index]) {
                    literalTarget = nullableElement
                    liftTarget = true
                }
            }

            if ColumnarSourceDirectCallResolver.CanAdoptIntegerLiteral(literalTarget, argumentFacts.IntegerLiteralValues[index], argumentFacts.IsNegativeIntegerLiteral[index]) {
                if !TryAppendTargetTypedIntegerArgument(nodes, argumentNode, plan, parentFragment, literalTarget, argumentFacts.IntegerLiteralValues[index]) || liftTarget && !ColumnarNullableArgumentLowering.TryAppendValueLift(plan, literalTarget, parameterTypes[index]) {
                    return false
                }

                return true
            }
        }

        // AN ARRAY LITERAL WRITTEN AT AN ARRAY PARAMETER TAKES THAT PARAMETER'S ELEMENT TYPE, which
        // is what the score one owner over already admitted it on. `[0]` infers `int[]` and is not
        // an `int[]` the call converts — it is a `byte[]` the call WRITES — so it is planned
        // against the declared parameter rather than inferred and then converted.
        if argumentFacts.IsIntegerConstantArrayLiteral[index] && ColumnarSourceDirectCallResolver.CanAdoptIntegerConstantArrayLiteral(parameterTypes[index], argumentFacts.ArrayLiteralMinimumValues[index], argumentFacts.ArrayLiteralMaximumValues[index]) {
            if !ColumnarConstructionPlanner.TryAppendTargetTypedArray(nodes, source, argumentNode, bindings, handles, plan, parentFragment, depth + 1, parameterTypes[index]) {
                return false
            }

            return true
        }

        actualType := typeof(int)
        valuePlanned := false
        if allowPrimitiveBinary {
            valuePlanned = ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, argumentNode, bindings, handles, plan, parentFragment, depth, out actualType)
        } else {
            valuePlanned = ColumnarRangeIndexPlanner.TryAppendPlannableValue(nodes, source, argumentNode, bindings, handles, plan, parentFragment, depth, out actualType)
        }
        if !valuePlanned || !RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(actualType, inferredTypes[index]) || !AppendArgumentConversion(plan, actualType, parameterTypes[index], argumentFacts.SourceTypeDefinitions) {
            return false
        }

        return true
    }

    static func TryAppendTargetTypedIntegerArgument(nodes: ColumnarNodeTable, argumentNode: int, plan: ColumnarCodePlan, parentFragment: int, targetType: Type, value: long): bool {
        candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, argumentNode)
        if candidate < 0 {
            return false
        }

        fragment := plan.BeginFragment(parentFragment, nodes.Kind(candidate), candidate)

        if targetType == typeof(long) || targetType == typeof(ulong) {
            valueIndex := plan.AddInt64(value)
            plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), valueIndex)
        } else {
            valueIndex := plan.AddInt32((int)value)
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
        }

        plan.CompleteFragment(fragment, targetType)
        return true
    }

    static func AppendArgumentConversion(plan: ColumnarCodePlan, actualType: Type, parameterType: Type, sourceTypeDefinitions: System.Collections.Generic.IEnumerable<ColumnarStructDef>): bool {
        flow := ColumnarDirectCallArgumentFlow.None
        if !ColumnarSourceDirectCallResolver.TryClassifyArgumentFlow(parameterType, actualType, sourceTypeDefinitions, out flow) {
            return false
        }

        sourceInterfaceIsReference := false
        exactSourceInterfaceFlow := false
        if flow == ColumnarDirectCallArgumentFlow.Reference || flow == ColumnarDirectCallArgumentFlow.Boxing {
            exactSourceInterfaceFlow = ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(actualType, parameterType, sourceTypeDefinitions, out sourceInterfaceIsReference)
            if exactSourceInterfaceFlow && sourceInterfaceIsReference != (flow == ColumnarDirectCallArgumentFlow.Reference) {
                throw new InvalidOperationException("Source interface conversion flow disagrees with its declaration shape.")
            }
        }

        if flow == ColumnarDirectCallArgumentFlow.Identity {
            return true
        }

        if flow == ColumnarDirectCallArgumentFlow.Reference {
            if exactSourceInterfaceFlow {
                targetIndex := plan.AddType(parameterType)
                plan.AppendTypeInstruction(ColumnarCodePlanContract.Castclass(), targetIndex)
            }
            return true
        }

        if flow == ColumnarDirectCallArgumentFlow.Boxing {
            typeIndex := plan.AddType(actualType)
            plan.AppendTypeInstruction(ColumnarCodePlanContract.Box(), typeIndex)
            if exactSourceInterfaceFlow {
                targetIndex := plan.AddType(parameterType)
                plan.AppendTypeInstruction(ColumnarCodePlanContract.Castclass(), targetIndex)
            }
            return true
        }

        if flow == ColumnarDirectCallArgumentFlow.Nullable {
            return ColumnarNullableArgumentLowering.TryAppendValueLift(plan, actualType, parameterType)
        }

        if flow == ColumnarDirectCallArgumentFlow.Constructed {
            return ColumnarDirectCallConstructedConversions.TryAppend(plan, parameterType, actualType)
        }

        if flow == ColumnarDirectCallArgumentFlow.UserImplicit {
            selection := ColumnarSourceImplicitConversionResolver.ResolveExact(actualType, parameterType, sourceTypeDefinitions)

            return ColumnarSourceImplicitConversionResolver.TryAppendCall(plan, selection)
        }

        if flow == ColumnarDirectCallArgumentFlow.ExternalImplicit {
            return TryAppendExternalImplicitConversion(plan, actualType, parameterType)
        }

        if flow != ColumnarDirectCallArgumentFlow.ImplicitNumeric {
            return false
        }

        if parameterType == typeof(int) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
            return true
        }

        if parameterType == typeof(long) && actualType != typeof(uint) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI8())
            return true
        }

        if parameterType == typeof(float) && actualType != typeof(uint) && actualType != typeof(ulong) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvR4())
            return true
        }

        if parameterType == typeof(double) && actualType != typeof(uint) && actualType != typeof(ulong) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvR8())
            return true
        }

        if parameterType == typeof(decimal) {
            return AppendDecimalImplicitConversion(plan, actualType)
        }

        return false
    }

    // THE `call op_Implicit` AN EXTERNAL TYPE'S OPERATOR NAMES. The selection is made by the SAME
    // owner the analyzer consulted, over the same two CLR types, so the method emitted here is the
    // one the front end accepted the call on. A selection that is no longer there is a decline and
    // never a guess.
    static func TryAppendExternalImplicitConversion(plan: ColumnarCodePlan, actualType: Type, parameterType: Type): bool {
        if !ColumnarSourceDirectCallResolver.HasExternalImplicitConversion(actualType, parameterType) {
            return false
        }

        selection := ExternalUserDefinedConversions.ResolveImplicit(actualType, parameterType)
        method := selection.Method
        if !selection.IsSelected || method == null {
            return false
        }

        declaringType := method.get_DeclaringType()
        parameters := method.GetParameters()
        if declaringType == null || parameters.Length != 1 {
            return false
        }

        parameterTypes := new Type[](1)
        parameterTypes[0] = parameters[0].get_ParameterType()
        methodIndex := plan.AddMethodWithSignature(method, declaringType, parameterTypes, method.get_ReturnType(), true, false)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
        return true
    }

    static func AppendDecimalImplicitConversion(plan: ColumnarCodePlan, actualType: Type): bool {
        conversionSource := actualType
        if actualType == typeof(byte) || actualType == typeof(sbyte) || actualType == typeof(short) || actualType == typeof(ushort) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
            conversionSource = typeof(int)
        }

        parameterTypes := new Type[](1)
        parameterTypes[0] = conversionSource
        conversion := typeof(decimal).GetMethod("op_Implicit", parameterTypes)
        if conversion == null || conversion.get_ReturnType() != typeof(decimal) || !conversion.get_IsStatic() || conversion.get_IsGenericMethod() {
            return false
        }

        methodIndex := plan.AddMethodWithSignature(conversion, typeof(decimal), parameterTypes, typeof(decimal), true, false)

        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
        return true
    }

    // DOES ANY ARGUMENT PASS STORAGE? A modelled external binding row names a value signature and has
    // no `ref`/`out` shape to offer, so a call written with one must fall through to ordinary
    // resolution instead of being claimed here and then rejected.
    static func ContainsByRefArgument(argumentFacts: ColumnarDirectCallArgumentFacts): bool {
        if argumentFacts == null || argumentFacts.IsByRefArgument == null {
            return false
        }

        index := 0
        while index < argumentFacts.IsByRefArgument.Length {
            if argumentFacts.IsByRefArgument[index] {
                return true
            }

            index += 1
        }

        return false
    }

    static func TryGetArgumentTypes(nodes: ColumnarNodeTable, source: string, callNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, depth: int, allowPrimitiveBinary: bool, methodBodySchema: bool, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        if argumentFacts == null || argumentFacts.IsUnsuffixedIntegerLiteral.Length != argumentTypes.Length || argumentFacts.IsNegativeIntegerLiteral.Length != argumentTypes.Length || argumentFacts.IntegerLiteralValues.Length != argumentTypes.Length || argumentFacts.IsNullLiteral.Length != argumentTypes.Length {
            throw new InvalidOperationException("Direct-call argument syntax facts must match the argument type slots.")
        }

        index := 0
        while index < argumentTypes.Length {

            // A `name:` wrapper is placement, not value: the row records the argument UNDERNEATH the
            // name, and the name itself is read once, by the binder that decides which slot this row
            // ends up in.
            argumentNode := ColumnarNamedArgumentBinder.ArgumentValueNode(nodes, nodes.Child(callNode, index + 1))
            argumentFacts.ArgumentNodes[index] = argumentNode
            argumentCandidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, argumentNode)
            if argumentCandidate >= 0 && nodes.Kind(argumentCandidate) == ColumnarExpressionNodeKind.NullLiteralExpression() {
                argumentTypes[index] = typeof(object)
                argumentFacts.IsNullLiteral[index] = true
                index += 1
                continue
            }

            byRefTarget := ByRefArgumentTarget(nodes, source, argumentNode)
            if byRefTarget >= 0 {
                byRefStorageType := typeof(int)
                if !ColumnarBoundIdentifierPlanner.TryGetByRefTargetType(nodes, source, byRefTarget, bindings, out byRefStorageType) || IsVoidType(byRefStorageType) {
                    return false
                }

                argumentTypes[index] = byRefStorageType
                argumentFacts.IsByRefArgument[index] = true
                index += 1
                continue
            }

            valueTypeNode := argumentNode
            if nodes.Kind(argumentNode) == 64 && nodes.ChildCount(argumentNode) == 1 {
                valueTypeNode = nodes.Child(argumentNode, 0)
            }
            argumentType := typeof(int)
            if !TryGetPlannableValueType(nodes, source, valueTypeNode, bindings, handles, depth + 1, allowPrimitiveBinary, methodBodySchema, out argumentType, out nestedOwnership) || IsVoidType(argumentType) {
                return false
            }

            argumentTypes[index] = argumentType
            literalValue := 0L
            literalNegative := false
            if argumentType == typeof(int) && TryGetTargetTypedIntegerArgumentValue(nodes, source, argumentNode, out literalValue, out literalNegative) {
                argumentFacts.IsUnsuffixedIntegerLiteral[index] = true
                argumentFacts.IsNegativeIntegerLiteral[index] = literalNegative
                argumentFacts.IntegerLiteralValues[index] = literalValue
            }

            minimumElement := 0L
            maximumElement := 0L
            if TryGetIntegerConstantArrayLiteralRange(nodes, source, argumentNode, out minimumElement, out maximumElement) {
                argumentFacts.IsIntegerConstantArrayLiteral[index] = true
                argumentFacts.ArrayLiteralMinimumValues[index] = minimumElement
                argumentFacts.ArrayLiteralMaximumValues[index] = maximumElement
            }

            index += 1
        }

        return true
    }

    // THE NAME UNDER A `ref x` / `out x` ARGUMENT, or -1 when the argument is not one.
    //
    // Kind 54 is the argument-modifier node: the keyword lives in its value span and it has exactly
    // one child, the storage being passed. `in` is NOT answered here — it is a read-only reference
    // with its own overload-resolution rules, and admitting it through the `ref`/`out` door would bind
    // the wrong overload.
    static func ByRefArgumentTarget(nodes: ColumnarNodeTable, source: string, argumentNode: int): int {
        if argumentNode < 0 || argumentNode >= nodes.Kinds.Length || nodes.Kind(argumentNode) != 54 || nodes.ChildCount(argumentNode) != 1 {
            return -1
        }

        modifier := nodes.Text(source, argumentNode)
        if modifier != "ref" && modifier != "out" {
            return -1
        }

        return nodes.Child(argumentNode, 0)
    }

    static func TryGetTargetTypedIntegerArgumentValue(nodes: ColumnarNodeTable, source: string, node: int, out value: long, out isNegative: bool): bool {
        value = 0
        isNegative = false
        candidate := ColumnarPlannerSupport.UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return false
        }

        if nodes.Kind(candidate) == ColumnarExpressionNodeKind.UnaryExpression() {
            if nodes.ChildCount(candidate) != 1 || nodes.Text(source, candidate) != "-" {
                return false
            }

            isNegative = true
            candidate = nodes.Child(candidate, 0)
            if candidate < 0 {
                return false
            }
        }

        magnitude := 0
        if nodes.Kind(candidate) != ColumnarExpressionNodeKind.IntLiteralExpression() || nodes.ChildCount(candidate) != 0 || !ColumnarScalarLiteralPlanner.TryGetTargetTypedIntegerMagnitude(nodes.Text(source, candidate), out magnitude) {
            return false
        }

        value = isNegative ? -(long)magnitude : (long)magnitude
        return true
    }

    // THE WIDEST CONSTANTS AN ARRAY LITERAL WROTE, IN EACH DIRECTION, or false when the argument is not
    // an array literal of integer constants at all.
    //
    // The literal's ELEMENTS are what decide whether it fits a `byte[]` parameter, and the resolver that
    // asks is deliberately node-free — so the two endpoints travel with the argument facts instead. An
    // EMPTY literal answers false: it has no constant to carry, so its ordinary inferred type is the
    // whole answer, and claiming otherwise would make `[]` adopt every array parameter in the set at once.
    static func TryGetIntegerConstantArrayLiteralRange(nodes: ColumnarNodeTable, source: string, argumentNode: int, out minimumValue: long, out maximumValue: long): bool {
        minimumValue = 0L
        maximumValue = 0L
        literal := ColumnarPlannerSupport.UnwrapParentheses(nodes, argumentNode)
        if literal < 0 || nodes.Kind(literal) != ColumnarExpressionNodeKind.ArrayLiteralExpression() {
            return false
        }

        elementCount := nodes.ChildCount(literal)
        if elementCount == 0 {
            return false
        }

        elementIndex := 0
        while elementIndex < elementCount {
            elementValue := 0L
            elementNegative := false
            if !TryGetTargetTypedIntegerArgumentValue(nodes, source, nodes.Child(literal, elementIndex), out elementValue, out elementNegative) {
                return false
            }

            if elementIndex == 0 || elementValue < minimumValue {
                minimumValue = elementValue
            }

            if elementIndex == 0 || elementValue > maximumValue {
                maximumValue = elementValue
            }

            elementIndex += 1
        }

        return true
    }

    // ⚠ THE SCRATCH TYPES A VALUE IN THE FRAME IT WILL BE APPENDED INTO, NOT AT A PLAN ROOT (015-B9).
    //
    // `enclosingNode` is the node whose fragment this value will be appended UNDER — the call that owns
    // the argument list or the receiver, the `new`/array literal that owns an element or a length — and the
    // scratch opens that node's own fragment before the value is planned. That
    // is not decoration: `ColumnarRangeIndexPlanner`'s value dispatcher decides one thing from the sign
    // of the parent fragment, `allowOrdinaryIntIndex = parentFragment >= 0`, and the rule it feeds is
    // about plan ROOTS ("an ordinary `arr[0]` at a root belongs to the host, because the facade only owns
    // an index root whose selector may produce Index/Range"). An argument is never a root — `AppendArguments`
    // always appends it under the call's fragment — so a scratch that planned it at `-1` asked about a
    // position the value can never occupy and refused `f(arr[0])` at the TYPE step while the APPEND step
    // admitted it. The two sides now ask the same question. `015-B8` measured the old refusal from the
    // outside as "the owner declines an index access in argument position"; there was never such a rule.
    static func TryGetPlannableValueType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, depth: int, allowPrimitiveBinary: bool, methodBodySchema: bool, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = typeof(int)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        syntaxAdmitted := IsAdmittedValueSyntax(nodes, source, node, depth)
        if allowPrimitiveBinary && !syntaxAdmitted {
            syntaxAdmitted = ColumnarPrimitiveBinaryPlanner.IsAdmittedSyntax(nodes, source, node, depth)
        }
        if allowPrimitiveBinary && !syntaxAdmitted && ColumnarConstructionPlanner.MayPlanRoot(nodes, node) {
            syntaxAdmitted = ColumnarConstructionPlanner.IsAdmittedConstructionValueSyntax(nodes, source, node, bindings, handles, depth)
        }
        if !syntaxAdmitted {
            return false
        }

        // A BRANCH-MERGE TYPES THROUGH ITS OWN OWNER'S METHOD-BODY SCRATCH, not through the schema-v3
        // one below: the reference arm of `??` appends `pop`, a method-body opcode a v3 plan THROWS on
        // rather than declining. See `ColumnarConditionalPlanner.TryGetBranchMergeValueType`.
        // ⚠ THE SCRATCH TAKES THE DESTINATION'S SCHEMA, and that is not decoration either. The
        // reference arm of `??` needs `pop`, which only a METHOD-BODY plan admits — so a v4 scratch in
        // front of a schema-v3 destination would TYPE a `list.Add(name ?? "d")` the append step then
        // declines, and a type/append disagreement in the call owner is a TERMINAL decline rather than
        // the legacy fall-back the shape deserves. `DhWriteCompanion`'s
        // `Directory.CreateDirectory(parent ?? directory)` is the shape that measured it.
        if ColumnarConditionalPlanner.IsBranchMergeValue(nodes, source, node) {
            return ColumnarConditionalPlanner.TryGetBranchMergeValueType(nodes, source, node, bindings, handles, methodBodySchema, out resultType)
        }

        // 015-B8 — THE ONE SCRATCH SITE A CLAIMED BODY ACTUALLY REACHES, MEASURED RATHER THAN ASSUMED.
        // Nine declaration-then-call probe shapes were built one at a time with the plan-local refusal
        // disabled and every scratch site tagged: EIGHT crashed and all eight crashed HERE — arguments,
        // receivers, external statics, nested calls, index and member receivers alike. The mirror is what
        // lets this scratch represent the enclosing body's slots while it types them.
        scratch := new ColumnarCodePlan()
        scratch.EnablePlanLocalMirror(bindings.PlanLocalMirrorTypes())
        scratch.EnableNestedValueFrame()
        scratch.PrepareV3()
        valuePlanned := false
        if allowPrimitiveBinary {
            valuePlanned = ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, node, bindings, handles, scratch, -1, depth, out resultType, out nestedOwnership)
        } else {
            valuePlanned = ColumnarRangeIndexPlanner.TryAppendPlannableValue(nodes, source, node, bindings, handles, scratch, -1, depth, out resultType, out nestedOwnership)
        }
        if !valuePlanned {
            return false
        }

        scratch.CompleteV3(resultType)
        ColumnarCodePlanExecutor.Validate(scratch)
        return true
    }

    // THE GATE TAKES `source` BECAUSE THREE VALUE FORMS ARE SPELLED IN THE SOURCE TEXT, NOT IN THE KIND.
    // `a && b`, `a || b` and `a ?? b` are all node kind 12 — the operator TEXT is what separates them
    // from `a + b`, and it lives in the source span, so a gate with no `source` could not tell a
    // branch-merge from an arithmetic binary and refused all of them. The ternary (kind 13) needs no
    // text, but it belongs to the same owner and is admitted beside them.
    static func IsAdmittedValueSyntax(nodes: ColumnarNodeTable, source: string, node: int, depth: int): bool {
        if depth > 200 || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        kind := nodes.Kind(node)
        // A ref/out wrapper is a value-expression child only when its target is a simple lexical
        // storage binding. The ordinary external-call owner performs the exact address and mode
        // checks later; admitting the wrapper here lets a nested external call preserve normal
        // left-to-right argument evaluation without opening source/sibling byref surfaces.
        if kind == 54 {
            if nodes.ChildCount(node) != 1 {
                return false
            }
            target := ColumnarPlannerSupport.UnwrapParentheses(nodes, nodes.Child(node, 0))
            return target >= 0 && nodes.Kind(target) == ColumnarExpressionNodeKind.IdentifierExpression() && nodes.ChildCount(target) == 0
        }

        // Await is admitted as nested value syntax only so the recursive planner can ask the live
        // scope whether blocking await is enabled. With the default disabled binding the append is
        // atomic and the ordinary emitter retains ownership.
        if kind == 53 {
            return nodes.ChildCount(node) == 1 && IsAdmittedValueSyntax(nodes, source, nodes.Child(node, 0), depth + 1)
        }

        if kind == ColumnarExpressionNodeKind.ParenthesizedExpression() {
            return nodes.ChildCount(node) == 1 && IsAdmittedValueSyntax(nodes, source, nodes.Child(node, 0), depth + 1)
        }

        if kind == ColumnarExpressionNodeKind.NewExpression() || kind == ColumnarExpressionNodeKind.ObjectInitializerExpression() || kind == ColumnarExpressionNodeKind.ArrayLiteralExpression() {
            return ColumnarConstructionPlanner.IsAdmittedValueSyntax(nodes, source, node, depth)
        }

        // A cast's first child is a TYPE subtree in the type-kernel encoding, so only the operand
        // participates in expression-syntax admission.
        if kind == ColumnarExpressionNodeKind.CastExpression() {
            return nodes.ChildCount(node) == 2 && IsAdmittedValueSyntax(nodes, source, nodes.Child(node, 1), depth + 1)
        }

        if kind == ColumnarExpressionNodeKind.IntLiteralExpression() || kind == ColumnarExpressionNodeKind.FloatLiteralExpression() || kind == ColumnarExpressionNodeKind.CharLiteralExpression() || kind == ColumnarExpressionNodeKind.StringLiteralExpression() || kind == ColumnarExpressionNodeKind.BoolLiteralExpression() || kind == ColumnarExpressionNodeKind.NullLiteralExpression() || kind == ColumnarExpressionNodeKind.IdentifierExpression() || kind == ColumnarExpressionNodeKind.BaseMemberExpression() || kind == ColumnarExpressionNodeKind.NameOfExpression() || kind == ColumnarExpressionNodeKind.TypeOfExpression() || kind == ColumnarExpressionNodeKind.RangeExpression() || kind == ColumnarExpressionNodeKind.IndexAccessExpression() || kind == ColumnarExpressionNodeKind.UnaryExpression() || kind == ColumnarExpressionNodeKind.MemberAccessExpression() {
            return true
        }

        // THE BRANCH-MERGE VALUE FORMS — the ternary and the short-circuit/null-coalescing binaries.
        // `ColumnarRangeIndexPlanner`'s value dispatcher has owned all three in every value position
        // since the conditional planner landed, but this gate — the ONE syntax preflight the call
        // owner's argument and receiver typing runs first — never admitted them, so `list.Add(flag ?
        // "a" : "b")` was refused before the dispatcher was ever asked. In an ordinary body the refusal
        // was invisible (the call fell back to the legacy emitter arm, which has its own kind-13
        // lowering); inside a `func*` there IS no legacy arm, so the same argument declined the whole
        // generator at `emit.iterator.unsupported-shape`. Admitting them here is what makes the
        // plan-side conditional owner serve call arguments too.
        //
        // A `throw` arm is deliberately NOT admitted: the type step below plans the value into a
        // schema-v3 scratch, and `ColumnarThrowExpressionPlanner.TryAppendThrow` requires a METHOD-BODY
        // schema, so a throw arm would be admitted here only to decline one step later.
        if ColumnarConditionalPlanner.IsBranchMergeValue(nodes, source, node) {
            operandIndex := 0
            while operandIndex < nodes.ChildCount(node) {
                if !IsAdmittedBranchOperandSyntax(nodes, source, nodes.Child(node, operandIndex), depth + 1) {
                    return false
                }

                operandIndex += 1
            }

            return true
        }

        if kind != ColumnarExpressionNodeKind.CallExpression() || nodes.ChildCount(node) < 1 {
            return false
        }

        callee := ColumnarPlannerSupport.UnwrapParentheses(nodes, nodes.Child(node, 0))
        if callee < 0 || (nodes.Kind(callee) != ColumnarExpressionNodeKind.IdentifierExpression() && nodes.Kind(callee) != ColumnarExpressionNodeKind.MemberAccessExpression() && nodes.Kind(callee) != ColumnarExpressionNodeKind.BaseMemberExpression()) {
            return false
        }

        index := 1
        while index < nodes.ChildCount(node) {

            // A `name:` wrapper is placement rather than value syntax: what has to be admitted is the
            // argument underneath the name.
            if !IsAdmittedValueSyntax(nodes, source, ColumnarNamedArgumentBinder.ArgumentValueNode(nodes, nodes.Child(node, index)), depth + 1) {
                return false
            }

            index += 1
        }

        return true
    }

    // AN OPERAND OF A BRANCH-MERGE IS ALWAYS A CONSTRUCTION VALUE, so its admission is the wider one.
    // `ColumnarConditionalPlanner`'s three arms — the ternary's condition and both arms, the
    // short-circuit operands, the `??` left and fallback — every one of them appends through
    // `ColumnarRangeIndexPlanner.TryAppendConstructionValue`, which is the `allowPrimitiveBinary = true`
    // surface. A gate that asked only the narrow question would refuse `flag && count > 0 ? a : b`
    // at the preflight while the append step would have planned it, so the two ask the same question.
    static func IsAdmittedBranchOperandSyntax(nodes: ColumnarNodeTable, source: string, node: int, depth: int): bool {
        if IsAdmittedValueSyntax(nodes, source, node, depth) {
            return true
        }

        return source != null && ColumnarPrimitiveBinaryPlanner.IsAdmittedSyntax(nodes, source, node, depth)
    }

    // Excluded declarations belong to later call owners only when the declaration set selected
    // by source hiding can bind this invocation's arity. A same-named generic or by-ref method at
    // another fixed arity must not fence an ordinary call, while params and varargs retain their
    // expanded arity. The resolver owns each declaration's excluded-shape classification; this
    // planner only follows the same hierarchy tier order used for source method selection.
    static func HasExcludedInstanceOwnerAtArity(root: ColumnarStructDef, receiverType: Type, memberName: string, argumentCount: int): bool {
        if !ColumnarSourceDirectCallResolver.HasExcludedInstanceDeclaration(root, memberName) {
            return false
        }

        hasExcluded := false
        if IsClosedSourceType(root, receiverType) {
            return TryClassifyLocalExcludedInstanceOwner(root, memberName, argumentCount, out hasExcluded) && hasExcluded
        }

        return TryClassifyExcludedInstanceOwner(root, memberName, argumentCount, out hasExcluded) && hasExcluded
    }

    static func TryClassifyExcludedInstanceOwner(current: ColumnarStructDef, memberName: string, argumentCount: int, out hasExcluded: bool): bool {
        if TryClassifyLocalExcludedInstanceOwner(current, memberName, argumentCount, out hasExcluded) {
            return true
        }

        if current.IsInterface {
            baseIndex := 0
            while baseIndex < current.InterfaceBases.Count {
                if TryClassifyExcludedInstanceOwner(current.InterfaceBases[baseIndex], memberName, argumentCount, out hasExcluded) {
                    return true
                }

                baseIndex += 1
            }
        }

        baseDefinition := current.BaseDef
        if baseDefinition != null {
            return TryClassifyExcludedInstanceOwner(baseDefinition, memberName, argumentCount, out hasExcluded)
        }

        hasExcluded = false
        return false
    }

    static func TryClassifyLocalExcludedInstanceOwner(current: ColumnarStructDef, memberName: string, argumentCount: int, out hasExcluded: bool): bool {
        hasExcluded = false
        overloads := new List<ColumnarInstanceMethodDef>()
        if !current.MethodOverloads.TryGetValue(memberName, out overloads) {
            return false
        }

        if overloads == null {
            throw new InvalidOperationException("Source instance-method overload facts cannot be null.")
        }

        hasRawArity := false
        index := 0
        while index < overloads.Count {
            candidate := overloads[index]
            if candidate.ParamTypes.Length == argumentCount {
                hasRawArity = true
            }

            if ColumnarSourceDirectCallResolver.ExcludedInstanceDefinitionCanOwnArity(candidate, argumentCount) {
                hasExcluded = true
            }

            index += 1
        }

        return hasRawArity || hasExcluded
    }

    static func HasExcludedStaticOwnerAtArity(root: ColumnarStructDef, memberName: string, argumentCount: int): bool {
        if !ColumnarSourceDirectCallResolver.HasExcludedStaticDeclaration(root, memberName) {
            return false
        }

        hasExcluded := false
        return TryClassifyExcludedStaticOwner(root, memberName, argumentCount, out hasExcluded) && hasExcluded
    }

    static func TryClassifyExcludedStaticOwner(current: ColumnarStructDef, memberName: string, argumentCount: int, out hasExcluded: bool): bool {
        hasExcluded = false
        overloads := new List<ColumnarStaticMethodDef>()
        if current.StaticMethods.TryGetValue(memberName, out overloads) {
            if overloads == null {
                throw new InvalidOperationException("Source static-method overload facts cannot be null.")
            }

            hasRawArity := false
            index := 0
            while index < overloads.Count {
                candidate := overloads[index]
                if candidate.ParamTypes.Length == argumentCount {
                    hasRawArity = true
                }

                if ColumnarSourceDirectCallResolver.ExcludedStaticDefinitionCanOwnArity(candidate, argumentCount) {
                    hasExcluded = true
                }

                index += 1
            }

            if hasRawArity || hasExcluded {
                return true
            }
        }

        baseDefinition := current.BaseDef
        if baseDefinition != null {
            return TryClassifyExcludedStaticOwner(baseDefinition, memberName, argumentCount, out hasExcluded)
        }

        return false
    }

    static func IsClosedSourceType(definition: ColumnarStructDef, receiverType: Type): bool {
        definitionType: Type = definition.Builder
        return definitionType != receiverType && receiverType.get_IsGenericType() && !receiverType.get_IsGenericTypeDefinition() && receiverType.GetGenericTypeDefinition() == definitionType
    }

    static func FindExactSourceOwner(ownerName: string, sourceDefinitions: System.Collections.Generic.IEnumerable<ColumnarStructDef>): ColumnarStructDef? {
        selected: ColumnarStructDef? = null
        for candidate in sourceDefinitions {
            if candidate == null || candidate.DeclaredTypeName == null {
                throw new InvalidOperationException("Direct-call source owner facts cannot be null.")
            }

            declaredName := candidate.DeclaredTypeName
            if declaredName == ownerName {
                if selected != null && selected != candidate {
                    throw new InvalidOperationException("One exact direct-call source owner cannot map to two definitions.")
                }

                selected = candidate
            }
        }

        return selected
    }

    static func TypeNames(types: Type[]): string[] {
        result := new string[](types.Length)
        index := 0
        while index < types.Length {
            result[index] = types[index].FullName ?? types[index].Name
            index += 1
        }

        return result
    }

    static func ContainsName(values: string[], name: string): bool {
        index := 0
        while index < values.Length {
            if values[index] == name {
                return true
            }

            index += 1
        }

        return false
    }

    static func IsVoidType(valueType: Type): bool {
        return valueType != null && valueType.FullName == "System.Void"
    }

    static func ValidateInputs(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan) {
        ColumnarPlannerSupport.RequirePresent(nodes != null && source != null && bindings != null && plan != null, "Direct-call planning inputs cannot be null.")
        ColumnarPlannerSupport.RequireNodeInRange(nodes, node, "Direct-call planning received an invalid root node index.")
    }
}
