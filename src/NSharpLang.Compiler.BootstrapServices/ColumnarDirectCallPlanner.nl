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

        candidate := UnwrapParentheses(nodes, node)
        return candidate >= 0 && nodes.Kind(candidate) == ColumnarExpressionNodeKind.CallExpression()
    }

    static func TryEmit(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, il: ILGenerator, out nsharpOwned: bool, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership := ColumnarDirectCallOwnership.NotOwned
        status := Plan(nodes, source, node, bindings, plan, out ownership, out legacyWholeSubtreePlanning, out resultType)
        ValidateOwnershipBoundary(ownership, legacyWholeSubtreePlanning)
        if status != ColumnarFragmentPlanStatus.Planned {
            nsharpOwned = ownership != ColumnarDirectCallOwnership.NotOwned
            return false
        }

        nsharpOwned = true
        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
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
        resultType = RequiredResultType(plan)
        return true
    }

    static func Plan(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): ColumnarFragmentPlanStatus {
        ValidateInputs(nodes, source, node, bindings, plan)
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        plan.PrepareV3()
        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 || nodes.Kind(candidate) != ColumnarExpressionNodeKind.CallExpression() {
            return plan.Status
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            fragment := plan.BeginFragment(-1, ColumnarExpressionNodeKind.CallExpression(), candidate)

            handles := ColumnarRangeIndexHandles.Resolve()
            if !TryAppendCall(nodes, source, candidate, bindings, handles, plan, fragment, 0, out ownership, out legacyWholeSubtreePlanning, out resultType) {
                plan.Rollback(checkpoint)
                return plan.Status
            }

            plan.CompleteFragment(fragment, resultType)
            plan.CompleteV3(resultType)
            ownership = ColumnarDirectCallOwnership.Planned
            return plan.Status
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

        if plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion() || plan.Status != ColumnarFragmentPlanStatus.NotOwned || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException("Direct-call append requires an open schema-v3 plan.")
        }

        // Contextual-lambda preflight uses a synthetic parameter frame: its first lambda parameter
        // temporarily occupies ordinal zero even when member lookup still sees the enclosing instance.
        // That frame cannot emit an implicit receiver safely. Contextual lambdas are outside this
        // ownership slice, so leave the whole call to the legacy child planner without mutating the plan.
        if bindings.CurrentInstance != null && bindings.HasParameterOrdinal(0) {
            legacyWholeSubtreePlanning = true
            return false
        }

        callee := UnwrapParentheses(nodes, nodes.Child(node, 0))
        if callee < 0 {
            return false
        }

        calleeKind := nodes.Kind(callee)
        if calleeKind != ColumnarExpressionNodeKind.IdentifierExpression() && calleeKind != ColumnarExpressionNodeKind.MemberAccessExpression() {
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

            // A delegate-typed local/parameter/lifted/boxed value with no same-named method tier is
            // invoked through its Invoke method. Let those bare calls flow to the delegate-invoke
            // owner instead of declining early.
            if !explicitThis && !hasInstance && !hasStatic && !hasSibling
                && !bindings.IsSiblingShadowedByValue(bareName) {
                return false
            }
        }

        argumentTypes := new Type[](nodes.ChildCount(node) - 1)
        argumentFacts := ColumnarDirectCallArgumentFacts.Empty(argumentTypes.Length)
        argumentFacts.SourceTypeDefinitions = bindings.SourceTypeDefinitions
        argumentOwnership := ColumnarDirectCallOwnership.NotOwned
        if !TryGetArgumentTypes(nodes, source, node, bindings, handles, depth, false, argumentTypes, argumentFacts, out argumentOwnership) {
            if argumentOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
            } else {
                legacyWholeSubtreePlanning = true
            }

            return false
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            if calleeKind == ColumnarExpressionNodeKind.IdentifierExpression() {
                return TryAppendBareCall(nodes, source, node, callee, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, checkpoint, out ownership, out legacyWholeSubtreePlanning, out resultType)
            }

            return TryAppendMemberCall(nodes, source, node, callee, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, checkpoint, out ownership, out legacyWholeSubtreePlanning, out resultType)
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
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
        if !explicitThis && bindings.IsSiblingShadowedByValue(memberName)
            && !bindings.HasSiblingCallable(memberName)
            && !HasCurrentInstanceMethodAnyArity(bindings, memberName)
            && !HasEnclosingStaticMethodAtArity(bindings, memberName, argumentTypes.Length) {
            return TryAppendDelegateInvoke(nodes, source, callNode, callee, bindings, handles, plan, callFragment, depth, argumentTypes, checkpoint, out ownership, out legacyWholeSubtreePlanning, out resultType)
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

    // Invoke a delegate-typed value binding (`zero()` where `zero: Func<int>`): load the delegate
    // value, emit each argument exactly typed against Invoke's parameters, and `callvirt Invoke`.
    // Only closed System.Func/System.Action over baked runtime types are admitted, and every
    // argument must land on Invoke's parameter type with no implicit conversion — the mechanical
    // host's stored-delegate arm accepts exactly this shape. Anything outside it (a non-delegate
    // value, an arity mismatch, an argument the planner cannot lower to the exact type, or a void
    // result in a value position) yields the whole subtree to the legacy delegate-invoke arm.
    static func TryAppendDelegateInvoke(nodes: ColumnarNodeTable, source: string, callNode: int, callee: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, argumentTypes: Type[], checkpoint: ColumnarCodePlanCheckpoint, out ownership: ColumnarDirectCallOwnership, out legacyWholeSubtreePlanning: bool, out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)

        delegateType := typeof(object)
        if !ColumnarBoundIdentifierPlanner.TryGetBoundType(nodes, source, callee, bindings, out delegateType)
            || !ColumnarRuntimeInstanceMemberResolver.IsSupportedDelegateType(delegateType) {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }

        invoke := delegateType.GetMethod("Invoke")
        if invoke == null || invoke.get_IsStatic() || invoke.get_IsGenericMethod() {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }

        parameters := invoke.GetParameters()
        returnType := invoke.get_ReturnType()
        if parameters == null || returnType == null
            || parameters.Length != argumentTypes.Length {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }

        calleeCandidate := UnwrapParentheses(nodes, callee)
        if calleeCandidate < 0 {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }

        delegateFragment := plan.BeginFragment(callFragment, nodes.Kind(calleeCandidate), calleeCandidate)
        loadedType := typeof(object)
        if !ColumnarBoundIdentifierPlanner.TryAppend(nodes, source, calleeCandidate, bindings, plan, out loadedType) || loadedType != delegateType {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }

        plan.CompleteFragment(delegateFragment, loadedType)

        parameterTypes := new Type[](parameters.Length)
        index := 0
        while index < parameters.Length {
            parameter := parameters[index]
            if parameter == null {
                throw new InvalidOperationException("Delegate Invoke parameters cannot be null.")
            }

            expected := parameter.get_ParameterType()
            if expected == null {
                throw new InvalidOperationException("Delegate Invoke parameter types cannot be null.")
            }

            parameterTypes[index] = expected
            actual := typeof(int)
            if !ColumnarRangeIndexPlanner.TryAppendPlannableValue(nodes, source, nodes.Child(callNode, index + 1), bindings, handles, plan, callFragment, depth + 1, out actual) || actual != expected {
                legacyWholeSubtreePlanning = true
                plan.Rollback(checkpoint)
                return false
            }

            index += 1
        }

        methodIndex := plan.AddMethodWithSignature(invoke, delegateType, parameterTypes, returnType, false, invoke.get_IsAbstract())
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), methodIndex)
        resultType = returnType
        if callFragment != 0 && IsVoidType(resultType) {
            legacyWholeSubtreePlanning = true
            plan.Rollback(checkpoint)
            return false
        }

        ownership = ColumnarDirectCallOwnership.Planned
        return true
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
        return currentDefinition != null
            && ColumnarSourceDirectCallResolver.HasInstanceDeclaration(currentDefinition, memberName)
    }

    static func HasEnclosingStaticMethodAtArity(bindings: ColumnarFragmentBindings, memberName: string, argumentCount: int): bool {
        enclosing := bindings.EnclosingTypeDefinition
        return enclosing != null
            && ColumnarSourceDirectCallResolver.HasStaticDeclarationAtArity(enclosing, memberName, argumentCount)
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

        if !AppendArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, false, inferredArgumentTypes, facts.ParameterTypes, argumentFacts) {
            return false
        }

        declaringType := method.get_DeclaringType()
        if declaringType == null {
            return false
        }

        methodIndex := plan.AddMethodWithSignature(method, declaringType, facts.ParameterTypes, facts.ReturnType, true, false)

        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
        resultType = facts.ReturnType
        return callFragment == 0 || !IsVoidType(resultType)
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
        qualifiedOwner := TryGetQualifiedName(nodes, source, receiverNode, 0, out ownerName, out rootName)

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

            if scope != null && scope.IsImportAliasRoot(rootName) {

                // File-import alias calls include call-style newtype construction and other
                // alias-member forms outside fixed direct-method ownership. Preserve the entire
                // subtree for their owning lowering; never reinterpret the alias as a type.
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
                sourceSelection := ColumnarSourceDirectCallResolver.ResolveClassifiedStatic(sourceOwner, sourceOwner.Builder, memberName, argumentTypes, argumentFacts)

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

            if externalPlan.IsSupported {
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
                legacyWholeSubtreePlanning = true
                plan.Rollback(checkpoint)
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

            if ordinary.IsOwnedRejected {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
            } else {
                legacyWholeSubtreePlanning = true
            }

            plan.Rollback(checkpoint)
            return false
        }

        receiverType := typeof(int)
        receiverOwnership := ColumnarDirectCallOwnership.NotOwned
        if !TryGetPlannableValueType(nodes, source, receiverNode, bindings, handles, depth + 1, false, out receiverType, out receiverOwnership) || IsVoidType(receiverType) {
            if receiverOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                ownership = ColumnarDirectCallOwnership.OwnedRejected
            } else {
                legacyWholeSubtreePlanning = true
            }

            plan.Rollback(checkpoint)
            return false
        }

        sourceInstance := ColumnarSourceDirectCallResolver.ResolveExplicitInstance(receiverType, memberName, argumentTypes, bindings.SourceTypeDefinitions, argumentFacts)

        if sourceInstance.IsSourceType {
            sourceDefinition := sourceInstance.SourceDefinition
            if sourceDefinition == null || !ColumnarSourceDirectCallResolver.HasInstanceDeclaration(sourceDefinition, memberName) {
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

        if instancePlan.IsSupported {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            runtimeInstance := ColumnarRuntimeDirectCallSelection.Empty()
            if !ColumnarRuntimeDirectCallResolver.TrySelect(instancePlan, receiverType, false, out runtimeInstance) || !AppendRuntimeSelection(nodes, source, callNode, receiverNode, bindings, handles, plan, callFragment, depth, argumentTypes, argumentFacts, runtimeInstance, out resultType) {
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

        if ordinaryInstance.IsOwnedRejected {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
        } else {
            legacyWholeSubtreePlanning = true
        }

        plan.Rollback(checkpoint)
        return false
    }

    static func AppendOrdinaryRuntimeSelection(nodes: ColumnarNodeTable, source: string, callNode: int, receiverNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, callFragment: int, depth: int, inferredArgumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, selection: ColumnarOrdinaryRuntimeDirectCallSelection, out resultType: Type): bool {
        method := selection.Method
        if !selection.IsSelected || method == null {
            resultType = typeof(int)
            return false
        }

        materialized := new ColumnarRuntimeDirectCallSelection(method, selection.LookupType, selection.DeclaringType, selection.ParameterTypes, selection.ReturnType, selection.Kind, selection.IsStatic, selection.ReceiverIsReference)

        return AppendRuntimeSelection(nodes, source, callNode, receiverNode, bindings, handles, plan, callFragment, depth, inferredArgumentTypes, argumentFacts, materialized, out resultType)
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
        }

        if !AppendArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, false, inferredArgumentTypes, selection.ParameterTypes, argumentFacts) {
            return false
        }

        methodIndex := plan.AddMethodWithSignature(method, selection.DeclaringType, selection.ParameterTypes, selection.ReturnType, selection.IsStatic, selection.IsAbstract)

        opcode := selection.Dispatch == ColumnarSourceDirectCallDispatch.CallVirtual ? ColumnarCodePlanContract.Callvirt() : ColumnarCodePlanContract.Call()

        plan.AppendMethodInstruction(opcode, methodIndex)
        resultType = selection.ReturnType
        return callFragment == 0 || !IsVoidType(resultType)
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

        if !AppendArguments(nodes, source, callNode, bindings, handles, plan, callFragment, depth + 1, false, inferredArgumentTypes, selection.ParameterTypes, argumentFacts) {
            return false
        }

        methodIndex := plan.AddMethodWithSignature(method, selection.DeclaringType, selection.ParameterTypes, selection.ReturnType, selection.IsStatic, method.get_IsAbstract())

        plan.AppendMethodInstruction(selection.UsesCallVirtual ? ColumnarCodePlanContract.Callvirt() : ColumnarCodePlanContract.Call(), methodIndex)

        resultType = selection.ReturnType
        return callFragment == 0 || !IsVoidType(resultType)
    }

    static func AppendImplicitReceiver(plan: ColumnarCodePlan, selection: ColumnarSourceDirectCallSelection) {
        argumentIndex := ColumnarBoundIdentifierPlanner.GetOrAddArgument(
            plan,
            0,
            selection.ReceiverType,
            !selection.ReceiverIsReference)

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
            if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(receiverType, expectedType) {
                return false
            }

            preserveAddress := !receiverIsReference && directStorage
            isAddress := false
            if preserveAddress {
                return ColumnarBoundIdentifierPlanner.TryAppendReceiver(nodes, source, receiverNode, bindings, true, plan, out receiverType, out isAddress) && isAddress
            }

            candidate := UnwrapParentheses(nodes, receiverNode)
            if candidate < 0 {
                return false
            }

            receiverFragment := plan.BeginFragment(parentFragment, nodes.Kind(candidate), candidate)

            if !ColumnarBoundIdentifierPlanner.TryAppendReceiver(nodes, source, receiverNode, bindings, false, plan, out receiverType, out isAddress) || isAddress || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(receiverType, expectedType) {
                return false
            }

            plan.CompleteFragment(receiverFragment, receiverType)
            if !receiverIsReference {
                ColumnarInstanceMemberPlanner.AppendTemporaryAddress(plan, receiverType)
            }

            return true
        }

        if !ColumnarRangeIndexPlanner.TryAppendPlannableValue(nodes, source, receiverNode, bindings, handles, plan, parentFragment, depth, out receiverType) || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(receiverType, expectedType) {
            return false
        }

        if !receiverIsReference {
            ColumnarInstanceMemberPlanner.AppendTemporaryAddress(plan, receiverType)
        }

        return true
    }

    static func AppendArguments(nodes: ColumnarNodeTable, source: string, callNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, plan: ColumnarCodePlan, parentFragment: int, depth: int, allowPrimitiveBinary: bool, inferredTypes: Type[], parameterTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): bool {
        if inferredTypes.Length != parameterTypes.Length || nodes.ChildCount(callNode) - 1 != parameterTypes.Length || argumentFacts == null || argumentFacts.IsUnsuffixedIntegerLiteral.Length != parameterTypes.Length || argumentFacts.IsNegativeIntegerLiteral.Length != parameterTypes.Length || argumentFacts.IntegerLiteralValues.Length != parameterTypes.Length || argumentFacts.IsNullLiteral.Length != parameterTypes.Length {
            return false
        }

        index := 0
        while index < parameterTypes.Length {
            argumentNode := nodes.Child(callNode, index + 1)
            if argumentFacts.IsNullLiteral[index] {
                candidate := UnwrapParentheses(nodes, argumentNode)
                if candidate < 0 || !ColumnarNullableArgumentLowering.TryAppendNullArgument(plan, parentFragment, nodes.Kind(candidate), candidate, parameterTypes[index]) {
                    return false
                }

                index += 1
                continue
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

                    index += 1
                    continue
                }
            }

            actualType := typeof(int)
            valuePlanned := false
            if allowPrimitiveBinary {
                valuePlanned =
                    ColumnarRangeIndexPlanner.TryAppendConstructionValue(
                        nodes, source, argumentNode, bindings, handles, plan,
                        parentFragment, depth, out actualType)
            } else {
                valuePlanned = ColumnarRangeIndexPlanner.TryAppendPlannableValue(
                    nodes, source, argumentNode, bindings, handles, plan,
                    parentFragment, depth, out actualType)
            }
            if !valuePlanned || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(actualType, inferredTypes[index]) || !AppendArgumentConversion(plan, actualType, parameterTypes[index], argumentFacts.SourceTypeDefinitions) {
                return false
            }

            index += 1
        }

        return true
    }

    static func TryAppendTargetTypedIntegerArgument(nodes: ColumnarNodeTable, argumentNode: int, plan: ColumnarCodePlan, parentFragment: int, targetType: Type, value: long): bool {
        candidate := UnwrapParentheses(nodes, argumentNode)
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
        if flow == ColumnarDirectCallArgumentFlow.Reference
            || flow == ColumnarDirectCallArgumentFlow.Boxing {
            exactSourceInterfaceFlow = ColumnarReferenceConversionFacts
                .TryClassifyExactSourceInterfaceUpcast(
                    actualType,
                    parameterType,
                    sourceTypeDefinitions,
                    out sourceInterfaceIsReference)
            if exactSourceInterfaceFlow
                && sourceInterfaceIsReference
                    != (flow == ColumnarDirectCallArgumentFlow.Reference) {
                throw new InvalidOperationException(
                    "Source interface conversion flow disagrees with its declaration shape.")
            }
        }

        if flow == ColumnarDirectCallArgumentFlow.Identity {
            return true
        }

        if flow == ColumnarDirectCallArgumentFlow.Reference {
            if exactSourceInterfaceFlow {
                targetIndex := plan.AddType(parameterType)
                plan.AppendTypeInstruction(
                    ColumnarCodePlanContract.Castclass(), targetIndex)
            }
            return true
        }

        if flow == ColumnarDirectCallArgumentFlow.Boxing {
            typeIndex := plan.AddType(actualType)
            plan.AppendTypeInstruction(ColumnarCodePlanContract.Box(), typeIndex)
            if exactSourceInterfaceFlow {
                targetIndex := plan.AddType(parameterType)
                plan.AppendTypeInstruction(
                    ColumnarCodePlanContract.Castclass(), targetIndex)
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

    static func TryGetArgumentTypes(nodes: ColumnarNodeTable, source: string, callNode: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, depth: int, allowPrimitiveBinary: bool, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        if argumentFacts == null || argumentFacts.IsUnsuffixedIntegerLiteral.Length != argumentTypes.Length || argumentFacts.IsNegativeIntegerLiteral.Length != argumentTypes.Length || argumentFacts.IntegerLiteralValues.Length != argumentTypes.Length || argumentFacts.IsNullLiteral.Length != argumentTypes.Length {
            throw new InvalidOperationException("Direct-call argument syntax facts must match the argument type slots.")
        }

        index := 0
        while index < argumentTypes.Length {
            argumentNode := nodes.Child(callNode, index + 1)
            argumentCandidate := UnwrapParentheses(nodes, argumentNode)
            if argumentCandidate >= 0 && nodes.Kind(argumentCandidate) == ColumnarExpressionNodeKind.NullLiteralExpression() {
                argumentTypes[index] = typeof(object)
                argumentFacts.IsNullLiteral[index] = true
                index += 1
                continue
            }

            argumentType := typeof(int)
            if !TryGetPlannableValueType(nodes, source, argumentNode, bindings, handles, depth + 1, allowPrimitiveBinary, out argumentType, out nestedOwnership) || IsVoidType(argumentType) {
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

            index += 1
        }

        return true
    }

    static func TryGetTargetTypedIntegerArgumentValue(nodes: ColumnarNodeTable, source: string, node: int, out value: long, out isNegative: bool): bool {
        value = 0
        isNegative = false
        candidate := UnwrapParentheses(nodes, node)
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

    static func TryGetPlannableValueType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, handles: ColumnarRangeIndexHandles, depth: int, allowPrimitiveBinary: bool, out resultType: Type, out nestedOwnership: ColumnarDirectCallOwnership): bool {
        resultType = typeof(int)
        nestedOwnership = ColumnarDirectCallOwnership.NotOwned
        syntaxAdmitted := IsAdmittedValueSyntax(nodes, node, depth)
        if allowPrimitiveBinary && !syntaxAdmitted {
            syntaxAdmitted = ColumnarPrimitiveBinaryPlanner.IsAdmittedSyntax(
                nodes, source, node, depth)
        }
        if allowPrimitiveBinary && !syntaxAdmitted
            && ColumnarConstructionPlanner.MayPlanRoot(nodes, node) {
            syntaxAdmitted =
                ColumnarConstructionPlanner.IsAdmittedConstructionValueSyntax(
                    nodes, source, node, bindings, handles, depth)
        }
        if !syntaxAdmitted {
            return false
        }

        scratch := new ColumnarCodePlan()
        scratch.PrepareV3()
        valuePlanned := false
        if allowPrimitiveBinary {
            valuePlanned = ColumnarRangeIndexPlanner.TryAppendConstructionValue(
                nodes, source, node, bindings, handles, scratch,
                -1, depth, out resultType, out nestedOwnership)
        } else {
            valuePlanned = ColumnarRangeIndexPlanner.TryAppendPlannableValue(
                nodes, source, node, bindings, handles, scratch,
                -1, depth, out resultType, out nestedOwnership)
        }
        if !valuePlanned {
            return false
        }

        scratch.CompleteV3(resultType)
        ColumnarCodePlanExecutor.Validate(scratch)
        return true
    }

    static func IsAdmittedValueSyntax(nodes: ColumnarNodeTable, node: int, depth: int): bool {
        if depth > 200 || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.ParenthesizedExpression() {
            return nodes.ChildCount(node) == 1 && IsAdmittedValueSyntax(nodes, nodes.Child(node, 0), depth + 1)
        }

        if kind == ColumnarExpressionNodeKind.NewExpression()
            || kind == ColumnarExpressionNodeKind.ObjectInitializerExpression()
            || kind == ColumnarExpressionNodeKind.ArrayLiteralExpression() {
            return ColumnarConstructionPlanner.IsAdmittedValueSyntax(
                nodes, node, depth)
        }

        // A cast's first child is a TYPE subtree in the type-kernel encoding, so only the operand
        // participates in expression-syntax admission.
        if kind == ColumnarExpressionNodeKind.CastExpression() {
            return nodes.ChildCount(node) == 2
                && IsAdmittedValueSyntax(nodes, nodes.Child(node, 1), depth + 1)
        }

        if kind == ColumnarExpressionNodeKind.IntLiteralExpression() || kind == ColumnarExpressionNodeKind.FloatLiteralExpression() || kind == ColumnarExpressionNodeKind.CharLiteralExpression() || kind == ColumnarExpressionNodeKind.StringLiteralExpression() || kind == ColumnarExpressionNodeKind.BoolLiteralExpression() || kind == ColumnarExpressionNodeKind.NullLiteralExpression() || kind == ColumnarExpressionNodeKind.IdentifierExpression() || kind == ColumnarExpressionNodeKind.NameOfExpression() || kind == ColumnarExpressionNodeKind.TypeOfExpression() || kind == ColumnarExpressionNodeKind.RangeExpression() || kind == ColumnarExpressionNodeKind.IndexAccessExpression() || kind == ColumnarExpressionNodeKind.UnaryExpression() || kind == ColumnarExpressionNodeKind.MemberAccessExpression() {
            return true
        }

        if kind != ColumnarExpressionNodeKind.CallExpression() || nodes.ChildCount(node) < 1 {
            return false
        }

        callee := UnwrapParentheses(nodes, nodes.Child(node, 0))
        if callee < 0 || (nodes.Kind(callee) != ColumnarExpressionNodeKind.IdentifierExpression() && nodes.Kind(callee) != ColumnarExpressionNodeKind.MemberAccessExpression()) {
            return false
        }

        index := 1
        while index < nodes.ChildCount(node) {
            if !IsAdmittedValueSyntax(nodes, nodes.Child(node, index), depth + 1) {
                return false
            }

            index += 1
        }

        return true
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

    static func TryGetQualifiedName(nodes: ColumnarNodeTable, source: string, node: int, depth: int, out qualifiedName: string, out rootName: string): bool {
        qualifiedName = ""
        rootName = ""
        if depth > 200 || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.IdentifierExpression() {
            if nodes.ChildCount(node) != 0 || ColumnarExpressionSyntaxFacts.IsExplicitThisIdentifier(nodes, source, node) {
                return false
            }

            rootName = nodes.Text(source, node)
            qualifiedName = rootName
            return rootName.Length > 0
        }

        if kind != ColumnarExpressionNodeKind.MemberAccessExpression() || nodes.ChildCount(node) != 1 {
            return false
        }

        prefix := ""
        if !TryGetQualifiedName(nodes, source, nodes.Child(node, 0), depth + 1, out prefix, out rootName) {
            return false
        }

        member := nodes.Text(source, node)
        if member.Length == 0 {
            return false
        }

        qualifiedName = prefix + "." + member
        return true
    }

    static func IsVoidType(valueType: Type): bool {
        return valueType != null && valueType.FullName == "System.Void"
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
            throw new InvalidOperationException("Direct-call planning inputs cannot be null.")
        }

        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Direct-call planning received an invalid root node index.")
        }
    }

    static func RequiredResultType(plan: ColumnarCodePlan): Type {
        resultType := plan.ResultType
        if resultType == null {
            throw new InvalidOperationException("Planned direct call has no result type.")
        }

        return resultType
    }
}
