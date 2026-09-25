namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Owns the binding, capture, and mutation analysis that determines closure shape before the
// remaining C# display-class and recursive-body lowering debt runs. All maps and sets are the emitter's
// live state; this planner neither snapshots them early nor substitutes another lookup.
class ColumnarClosureBindingPlanner {

    // THE NAME A DISPLAY GIVES THE ENCLOSING RECEIVER IT CAPTURED. One owner, because three separate
    // readers depend on it meaning the same storage: the display definition writes the field, a bare
    // member read hops through it, and a bare call on the lexical owner loads it as its receiver. It
    // is the name Roslyn's closure conversion uses, so a decompiler and a debugger both recognise it.
    static func CapturedEnclosingInstanceFieldName(): string {
        return "<>4__this"
    }

    static func IsVisibleBindingName(
        name: string,
        locals: Dictionary<string, LocalBuilder>,
        parameterOrdinals: Dictionary<string, int>,
        liftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>,
        boxedCaptures: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>?,
        enclosingBindingNames: HashSet<string>
    ): bool {
        return locals.ContainsKey(name) || parameterOrdinals.ContainsKey(name) || liftedLocals.ContainsKey(name) || (boxedCaptures != null && boxedCaptures.ContainsKey(name)) || enclosingBindingNames.Contains(name)
    }

    static func VisibleBindingNamesSnapshot(
        enclosingBindingNames: HashSet<string>,
        locals: Dictionary<string, LocalBuilder>,
        parameterOrdinals: Dictionary<string, int>,
        liftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>,
        boxedCaptures: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>?
    ): HashSet<string> {
        names := new HashSet<string>(enclosingBindingNames, StringComparer.Ordinal)
        names.UnionWith(locals.Keys)
        names.UnionWith(parameterOrdinals.Keys)
        names.UnionWith(liftedLocals.Keys)
        if boxedCaptures != null {
            names.UnionWith(boxedCaptures.Keys)
        }
        return names
    }

    static func CollectBindingNames(nodes: ColumnarNodeTable, source: string, node: int, names: HashSet<string>) {
        kind := nodes.Kind(node)
        if kind == ColumnarStatementNodeKind.VariableDeclarationStatement || kind == ColumnarStatementNodeKind.ForeachStatement {
            if nodes.ValueStart(node) >= 0 {
                names.Add(nodes.Text(source, node))
            }
        } else if kind == ColumnarStatementNodeKind.TypedForeachStatement {
            // A TYPED loop variable keeps its NAME in child 0 — the value slot is the annotation's
            // source span — so the binding is read from there rather than from the node itself.
            if nodes.ChildCount(node) > 0 && nodes.Kind(nodes.Child(node, 0)) == 6 && nodes.ValueStart(nodes.Child(node, 0)) >= 0 {
                names.Add(nodes.Text(source, nodes.Child(node, 0)))
            }
        } else if kind == ColumnarStatementNodeKind.TupleDeconstructionStatement {
            ordinal := 0
            while ordinal < nodes.ChildCount(node) - 1 {
                child := nodes.Child(node, ordinal)
                if nodes.Kind(child) == ColumnarExpressionNodeKind.IdentifierExpression && nodes.ValueStart(child) >= 0 {
                    names.Add(nodes.Text(source, child))
                }
                ordinal = ordinal + 1
            }
        } else if kind == ColumnarStatementNodeKind.CatchClause {
            // A catch clause's binding is asked for rather than counted, because a clause with an
            // exception FILTER carries a third child and a filtered clause with no binding carries
            // the same TWO a bound one used to.
            catchBinding := ColumnarCatchClauseFacts.BindingNode(nodes, node)
            if catchBinding >= 0 {
                names.Add(nodes.Text(source, catchBinding))
            }
        } else if kind == ColumnarStatementNodeKind.TypedLocalDeclaration {
            if nodes.ChildCount(node) == 2 {
                nameChild := nodes.Child(node, 0)
                if nodes.Kind(nameChild) == ColumnarExpressionNodeKind.IdentifierExpression && nodes.ValueStart(nameChild) >= 0 {
                    names.Add(nodes.Text(source, nameChild))
                }
            }
        }

        childOrdinal := 0
        while childOrdinal < nodes.ChildCount(node) {
            CollectBindingNames(nodes, source, nodes.Child(node, childOrdinal), names)
            childOrdinal = childOrdinal + 1
        }
    }

    // Build the enclosing capture-name union and the ordered result at the same point the lambda is
    // reached. Keys views are acquired in the original local/parameter/lifted order.
    static func PlanOrderedCaptureSet(
        nodes: ColumnarNodeTable,
        source: string,
        bodyNode: int,
        lambdaOrdinals: Dictionary<string, int>,
        locals: Dictionary<string, LocalBuilder>,
        parameterOrdinals: Dictionary<string, int>,
        liftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>
    ): SortedSet<string> {
        return PlanOrderedCaptureSet(nodes, source, bodyNode, lambdaOrdinals, locals, parameterOrdinals, liftedLocals, null)
    }

    // THE SAME SET, ASKED FROM INSIDE A DISPLAY. A body that is itself a closure sees the scope above
    // it as boxed captures rather than locals — the boxes ride fields of the display it runs on — and
    // a lambda written there captures those names exactly as the scope above captured them. Leaving
    // them out of the union is what made a MUTATED local unreachable from a lambda nested one level
    // deeper than the one that lifted it.
    static func PlanOrderedCaptureSet(
        nodes: ColumnarNodeTable,
        source: string,
        bodyNode: int,
        lambdaOrdinals: Dictionary<string, int>,
        locals: Dictionary<string, LocalBuilder>,
        parameterOrdinals: Dictionary<string, int>,
        liftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>,
        boxedCaptures: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>?
    ): SortedSet<string> {
        enclosingCapturableNames := new HashSet<string>(locals.Keys, StringComparer.Ordinal)
        enclosingCapturableNames.UnionWith(parameterOrdinals.Keys)
        enclosingCapturableNames.UnionWith(liftedLocals.Keys)
        if boxedCaptures != null {
            enclosingCapturableNames.UnionWith(boxedCaptures.Keys)
        }
        boundParameterNames := new HashSet<string>(lambdaOrdinals.Keys, StringComparer.Ordinal)
        captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(nodes, source, bodyNode, boundParameterNames, enclosingCapturableNames)
        return new SortedSet<string>(captures, StringComparer.Ordinal)
    }

    static func BodyReferencesEnclosingChain(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bound: HashSet<string>,
        currentDefinition: ColumnarStructDef?,
        locals: Dictionary<string, LocalBuilder>,
        liftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>,
        parameterOrdinals: Dictionary<string, int>,
        siblings: IReadOnlyDictionary<string, ColumnarSiblingMethodDefinition>
    ): bool {
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.BareNew || kind == ColumnarExpressionNodeKind.TypeOfExpression {
            return false
        }
        // A GENERIC CALLEE'S TYPE ARGUMENTS ARE TYPES, ITS CHILD 0 IS AN EXPRESSION. The whole node
        // used to be skipped because every child was a TYPE-kernel root; child 0 is now the callee
        // expression the type arguments were written on, and it is walked exactly as a plain call's
        // callee is — so `Bump<int>(x)` on the lexical owner reaches the same instance-member test
        // the un-annotated `Bump(x)` one line away already reached.
        if kind == ColumnarExpressionNodeKind.GenericCallee {
            return BodyReferencesEnclosingChain(nodes, source, ColumnarGenericCalleeFacts.CalleeExpressionNode(nodes, node), bound, currentDefinition, locals, liftedLocals, parameterOrdinals, siblings)
        }
        // A BARE `this` IS THE ENCLOSING INSTANCE, SPELLED OUT. It needs the same captured receiver a
        // bare call on the lexical owner needs, and it needs it whether or not the body also names a
        // member — `() => Describe(this)` captures nothing else at all.
        if kind == ColumnarExpressionNodeKind.ThisExpression && currentDefinition != null {
            return true
        }
        if ColumnarLambdaNodeFacts.IsLambda(kind) {
            nestedBound := new HashSet<string>(bound, StringComparer.Ordinal)
            nestedBound.UnionWith(BoundParamsOf(nodes, source, node))
            return BodyReferencesEnclosingChain(nodes, source, nodes.Child(node, nodes.ChildCount(node) - 1), nestedBound, currentDefinition, locals, liftedLocals, parameterOrdinals, siblings)
        }
        if kind == ColumnarExpressionNodeKind.IdentifierExpression && nodes.ValueStart(node) >= 0 && currentDefinition != null {
            name := nodes.Text(source, node)
            if !bound.Contains(name) && !locals.ContainsKey(name) && !liftedLocals.ContainsKey(name) && !parameterOrdinals.ContainsKey(name) && (!siblings.ContainsKey(name) || ColumnarSiblingHiding.IsHiddenByEnclosingMember(currentDefinition, name)) {
                field: FieldBuilder? = null
                if ColumnarSourceMemberChainResolver.TryFindFieldOnChain(currentDefinition, name, out field) {
                    return true
                }
                method: ColumnarInstanceMethodDef? = null
                if ColumnarSourceMemberChainResolver.TryFindMethodOnChain(currentDefinition, name, out method) {
                    return true
                }
                staticField: FieldBuilder? = null
                if ColumnarSourceMemberChainResolver.TryFindStaticFieldOnChain(currentDefinition, name, out staticField) {
                    return true
                }
                staticProperty: ColumnarPropertyDef? = null
                if ColumnarSourceMemberChainResolver.TryFindStaticPropertyOnChain(currentDefinition, name, out staticProperty) {
                    return true
                }
            }
        }
        if kind == ColumnarExpressionNodeKind.IsExpression || kind == ColumnarExpressionNodeKind.AsExpression {
            return BodyReferencesEnclosingChain(nodes, source, nodes.Child(node, 0), bound, currentDefinition, locals, liftedLocals, parameterOrdinals, siblings)
        }
        first := kind == ColumnarExpressionNodeKind.NewExpression || kind == ColumnarExpressionNodeKind.CastExpression ? 1 : 0
        childOrdinal := first
        while childOrdinal < nodes.ChildCount(node) {
            if BodyReferencesEnclosingChain(nodes, source, nodes.Child(node, childOrdinal), bound, currentDefinition, locals, liftedLocals, parameterOrdinals, siblings) {
                return true
            }
            childOrdinal = childOrdinal + 1
        }
        return false
    }

    // WHETHER A MIXED-CAPTURE LAMBDA NEEDS THE ENCLOSING RECEIVER AT ALL: does its body name an
    // INSTANCE member of the lexical owner, or `this` itself? That is C#'s rule — a static member
    // belongs to the TYPE and is reached without a receiver, so it does not put `<>4__this` on the
    // display, while a field, a property or a method of the instance does.
    //
    // This mirrors BodyReferencesEnclosingChain's walk and narrows its member test to the INSTANCE
    // members. It used to narrow further, to instance METHODS alone, because the closure emitter had
    // no field-read route through the captured receiver and admitting a capture it could not emit
    // would have been worse than declining; `ColumnarBoundIdentifierPlanner`'s captured-receiver read
    // is that route, so the test is now the whole instance-member question it was always asking.
    static func BodyReferencesEnclosingInstanceMemberChain(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bound: HashSet<string>,
        currentDefinition: ColumnarStructDef?,
        locals: Dictionary<string, LocalBuilder>,
        liftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>,
        parameterOrdinals: Dictionary<string, int>,
        siblings: IReadOnlyDictionary<string, ColumnarSiblingMethodDefinition>
    ): bool {
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.BareNew || kind == ColumnarExpressionNodeKind.TypeOfExpression {
            return false
        }
        if kind == ColumnarExpressionNodeKind.GenericCallee {
            return BodyReferencesEnclosingInstanceMemberChain(nodes, source, ColumnarGenericCalleeFacts.CalleeExpressionNode(nodes, node), bound, currentDefinition, locals, liftedLocals, parameterOrdinals, siblings)
        }
        // A BARE `this` NEEDS THE ENCLOSING INSTANCE, exactly as a bare call on the lexical owner does.
        if kind == ColumnarExpressionNodeKind.ThisExpression && currentDefinition != null {
            return true
        }
        if ColumnarLambdaNodeFacts.IsLambda(kind) {
            nestedBound := new HashSet<string>(bound, StringComparer.Ordinal)
            nestedBound.UnionWith(BoundParamsOf(nodes, source, node))
            return BodyReferencesEnclosingInstanceMemberChain(nodes, source, nodes.Child(node, nodes.ChildCount(node) - 1), nestedBound, currentDefinition, locals, liftedLocals, parameterOrdinals, siblings)
        }
        if kind == ColumnarExpressionNodeKind.IdentifierExpression && nodes.ValueStart(node) >= 0 && currentDefinition != null {
            name := nodes.Text(source, node)
            if !bound.Contains(name) && !locals.ContainsKey(name) && !liftedLocals.ContainsKey(name) && !parameterOrdinals.ContainsKey(name) && (!siblings.ContainsKey(name) || ColumnarSiblingHiding.IsHiddenByEnclosingMember(currentDefinition, name)) {
                field: FieldBuilder? = null
                if ColumnarSourceMemberChainResolver.TryFindFieldOnChain(currentDefinition, name, out field) {
                    return true
                }
                property: ColumnarPropertyDef? = null
                if ColumnarSourceMemberChainResolver.TryFindPropertyOnChain(currentDefinition, name, out property) {
                    return true
                }
                method: ColumnarInstanceMethodDef? = null
                if ColumnarSourceMemberChainResolver.TryFindMethodOnChain(currentDefinition, name, out method) {
                    return true
                }
            }
        }
        if kind == ColumnarExpressionNodeKind.IsExpression || kind == ColumnarExpressionNodeKind.AsExpression {
            return BodyReferencesEnclosingInstanceMemberChain(nodes, source, nodes.Child(node, 0), bound, currentDefinition, locals, liftedLocals, parameterOrdinals, siblings)
        }
        first := kind == ColumnarExpressionNodeKind.NewExpression || kind == ColumnarExpressionNodeKind.CastExpression ? 1 : 0
        childOrdinal := first
        while childOrdinal < nodes.ChildCount(node) {
            if BodyReferencesEnclosingInstanceMemberChain(nodes, source, nodes.Child(node, childOrdinal), bound, currentDefinition, locals, liftedLocals, parameterOrdinals, siblings) {
                return true
            }
            childOrdinal = childOrdinal + 1
        }
        return false
    }

    static func ComputeLiftedCandidates(nodes: ColumnarNodeTable, source: string, bodyRoot: int, ref liftedCandidates: HashSet<string>?) {
        inLambdas := new SortedSet<string>(StringComparer.Ordinal)
        CollectNamesInsideLambdas(nodes, source, bodyRoot, inLambdas)
        if inLambdas.Count == 0 {
            return
        }

        enumerator := inLambdas.GetEnumerator()
        try {
            while enumerator.MoveNext() {
                name := enumerator.get_Current()
                single := new SortedSet<string>(StringComparer.Ordinal)
                single.Add(name)
                if IsNameBareAssigned(nodes, source, bodyRoot, single) && !IsNameStructurallyWritten(nodes, source, bodyRoot, single) {
                    if liftedCandidates == null {
                        liftedCandidates = new HashSet<string>(StringComparer.Ordinal)
                    }
                    liftedCandidates.Add(name)
                }
            }
        } finally {
            enumerator.Dispose()
        }
    }

    static func IsLiftableValueType(valueType: Type): bool {
        return ColumnarTypeOfPlanner.IsSupportedType(valueType) && !(valueType.Assembly is AssemblyBuilder) && !valueType.IsGenericParameter && !valueType.ContainsGenericParameters && !RuntimeTypeShapeFacts.ContainsBuilderBoundType(valueType)
    }

    static func StrongBoxValueField(valueType: Type): FieldInfo? {
        openStrongBox := typeof(System.Runtime.CompilerServices.StrongBox<int>).GetGenericTypeDefinition()
        arguments := new Type[](1)
        arguments[0] = valueType
        boxType := openStrongBox.MakeGenericType(arguments)
        openField := openStrongBox.GetField("Value")
        if openField == null {
            throw new InvalidOperationException("StrongBox<T>.Value was not found.")
        }
        if RuntimeTypeShapeFacts.ContainsBuilderBoundType(boxType) {
            return TypeBuilder.GetField(boxType, openField)
        }
        return boxType.GetField("Value")
    }

    static func StrongBoxConstructor(valueType: Type): ConstructorInfo {
        openStrongBox := typeof(System.Runtime.CompilerServices.StrongBox<int>).GetGenericTypeDefinition()
        openArgument := openStrongBox.GetGenericArguments()[0]
        openConstructor := openStrongBox.GetConstructor([openArgument])
        if openConstructor == null {
            throw new InvalidOperationException("StrongBox<T>(T) was not found.")
        }
        arguments := new Type[](1)
        arguments[0] = valueType
        boxType := openStrongBox.MakeGenericType(arguments)
        if RuntimeTypeShapeFacts.ContainsBuilderBoundType(boxType) {
            return TypeBuilder.GetConstructor(boxType, openConstructor)
        }
        constructor := boxType.GetConstructor([valueType])
        if constructor == null {
            throw new InvalidOperationException("StrongBox<T>(T) was not found on its exact instantiation.")
        }
        return constructor
    }

    static func ContainsCaptureOpaqueKind(nodes: ColumnarNodeTable, node: int): bool {
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.MatchExpression || kind == ColumnarExpressionNodeKind.GuardedPattern || (kind >= ColumnarExpressionNodeKind.RelationalPattern && kind <= ColumnarExpressionNodeKind.UnionCasePattern) || kind == ColumnarExpressionNodeKind.WithExpression || kind == ColumnarExpressionNodeKind.TypeBindingPattern || (kind >= ColumnarExpressionNodeKind.ListPattern && kind <= ColumnarExpressionNodeKind.PropertyPattern) {
            return true
        }
        childOrdinal := 0
        while childOrdinal < nodes.ChildCount(node) {
            if ContainsCaptureOpaqueKind(nodes, nodes.Child(node, childOrdinal)) {
                return true
            }
            childOrdinal = childOrdinal + 1
        }
        return false
    }

    static func IsAnyNameWritten(nodes: ColumnarNodeTable, source: string, node: int, names: SortedSet<string>): bool {
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.AssignmentExpression || kind == ColumnarExpressionNodeKind.PostfixUnary {
            target := nodes.Child(node, 0)
            while (nodes.Kind(target) == ColumnarExpressionNodeKind.MemberAccessExpression || nodes.Kind(target) == ColumnarExpressionNodeKind.IndexAccessExpression) && nodes.ChildCount(target) > 0 {
                target = nodes.Child(target, 0)
            }
            if nodes.Kind(target) == ColumnarExpressionNodeKind.IdentifierExpression && nodes.ValueStart(target) >= 0 && names.Contains(nodes.Text(source, target)) {
                return true
            }
        } else if kind == ColumnarStatementNodeKind.ForeachStatement {
            if names.Contains(nodes.Text(source, node)) {
                return true
            }
        } else if kind == ColumnarStatementNodeKind.TypedForeachStatement {
            if nodes.ChildCount(node) > 0 && nodes.Kind(nodes.Child(node, 0)) == 6 && names.Contains(nodes.Text(source, nodes.Child(node, 0))) {
                return true
            }
        } else if kind == ColumnarStatementNodeKind.TupleDeconstructionStatement {
            nameOrdinal := 0
            while nameOrdinal < nodes.ChildCount(node) - 1 {
                child := nodes.Child(node, nameOrdinal)
                if nodes.Kind(child) == ColumnarExpressionNodeKind.IdentifierExpression && names.Contains(nodes.Text(source, child)) {
                    return true
                }
                nameOrdinal = nameOrdinal + 1
            }
        }

        childOrdinal := 0
        while childOrdinal < nodes.ChildCount(node) {
            if IsAnyNameWritten(nodes, source, nodes.Child(node, childOrdinal), names) {
                return true
            }
            childOrdinal = childOrdinal + 1
        }
        return false
    }

    static func CollectNamesInsideLambdas(nodes: ColumnarNodeTable, source: string, node: int, names: SortedSet<string>) {
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.BareNew || kind == ColumnarExpressionNodeKind.TypeOfExpression {
            return
        }
        if kind == ColumnarExpressionNodeKind.GenericCallee {
            CollectNamesInsideLambdas(nodes, source, ColumnarGenericCalleeFacts.CalleeExpressionNode(nodes, node), names)
            return
        }
        if ColumnarLambdaNodeFacts.IsLambda(kind) {
            CollectUnboundNames(nodes, source, nodes.Child(node, nodes.ChildCount(node) - 1), BoundParamsOf(nodes, source, node), names)
            return
        }
        if kind == ColumnarExpressionNodeKind.IsExpression || kind == ColumnarExpressionNodeKind.AsExpression {
            CollectNamesInsideLambdas(nodes, source, nodes.Child(node, 0), names)
            return
        }
        first := kind == ColumnarExpressionNodeKind.NewExpression || kind == ColumnarExpressionNodeKind.CastExpression ? 1 : 0
        childOrdinal := first
        while childOrdinal < nodes.ChildCount(node) {
            CollectNamesInsideLambdas(nodes, source, nodes.Child(node, childOrdinal), names)
            childOrdinal = childOrdinal + 1
        }
    }

    static func BoundParamsOf(nodes: ColumnarNodeTable, source: string, lambdaNode: int): HashSet<string> {
        bound := new HashSet<string>(StringComparer.Ordinal)
        parameterOrdinal := 0
        while parameterOrdinal < nodes.ChildCount(lambdaNode) - 1 {
            parameterNode := nodes.Child(lambdaNode, parameterOrdinal)
            if nodes.Kind(parameterNode) == ColumnarExpressionNodeKind.IdentifierExpression {
                bound.Add(nodes.Text(source, parameterNode))
            }
            parameterOrdinal = parameterOrdinal + 1
        }
        return bound
    }

    static func CollectUnboundNames(nodes: ColumnarNodeTable, source: string, node: int, bound: HashSet<string>, names: SortedSet<string>) {
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.GenericCallee {
            // GenericCallee stores the CALLEE in its own value span and its children are TYPE
            // arguments. A bare callee can therefore be a local-function sibling edge, while
            // walking the children would incorrectly capture `T`/`U` type names. Qualified
            // spellings are not lexical local-function names and remain with their receiver/type
            // owners; the closure planner later intersects this candidate with exact declarations
            // from the same local-function scope.
            callee := nodes.Text(source, node)
            if callee.Length > 0 && callee.IndexOf(".", StringComparison.Ordinal) < 0 && !bound.Contains(callee) {
                names.Add(callee)
            }
            return
        }
        if kind == ColumnarExpressionNodeKind.BareNew || kind == ColumnarExpressionNodeKind.TypeOfExpression {
            return
        }
        if ColumnarLambdaNodeFacts.IsLambda(kind) {
            nestedBound := new HashSet<string>(bound, StringComparer.Ordinal)
            nestedBound.UnionWith(BoundParamsOf(nodes, source, node))
            CollectUnboundNames(nodes, source, nodes.Child(node, nodes.ChildCount(node) - 1), nestedBound, names)
            return
        }
        if kind == ColumnarExpressionNodeKind.IdentifierExpression && nodes.ValueStart(node) >= 0 {
            name := nodes.Text(source, node)
            if !bound.Contains(name) {
                names.Add(name)
            }
        }
        if kind == ColumnarExpressionNodeKind.IsExpression || kind == ColumnarExpressionNodeKind.AsExpression {
            CollectUnboundNames(nodes, source, nodes.Child(node, 0), bound, names)
            return
        }
        first := kind == ColumnarExpressionNodeKind.NewExpression || kind == ColumnarExpressionNodeKind.CastExpression ? 1 : 0
        childOrdinal := first
        while childOrdinal < nodes.ChildCount(node) {
            CollectUnboundNames(nodes, source, nodes.Child(node, childOrdinal), bound, names)
            childOrdinal = childOrdinal + 1
        }
    }

    static func IsNameBareAssigned(nodes: ColumnarNodeTable, source: string, node: int, names: SortedSet<string>): bool {
        if ColumnarLambdaNodeFacts.IsLambda(nodes.Kind(node)) {
            bound := BoundParamsOf(nodes, source, node)
            remaining := new SortedSet<string>(names, StringComparer.Ordinal)
            remaining.ExceptWith(bound)
            return remaining.Count > 0 && IsNameBareAssigned(nodes, source, nodes.Child(node, nodes.ChildCount(node) - 1), remaining)
        }
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.AssignmentExpression || kind == ColumnarExpressionNodeKind.PostfixUnary {
            target := nodes.Child(node, 0)
            if nodes.Kind(target) == ColumnarExpressionNodeKind.IdentifierExpression && nodes.ValueStart(target) >= 0 && names.Contains(nodes.Text(source, target)) {
                return true
            }
        }
        childOrdinal := 0
        while childOrdinal < nodes.ChildCount(node) {
            if IsNameBareAssigned(nodes, source, nodes.Child(node, childOrdinal), names) {
                return true
            }
            childOrdinal = childOrdinal + 1
        }
        return false
    }

    static func IsNameStructurallyWritten(nodes: ColumnarNodeTable, source: string, node: int, names: SortedSet<string>): bool {
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.AssignmentExpression || kind == ColumnarExpressionNodeKind.PostfixUnary {
            structuralTarget := nodes.Child(node, 0)
            if nodes.Kind(structuralTarget) == ColumnarExpressionNodeKind.MemberAccessExpression || nodes.Kind(structuralTarget) == ColumnarExpressionNodeKind.IndexAccessExpression {
                while (nodes.Kind(structuralTarget) == ColumnarExpressionNodeKind.MemberAccessExpression || nodes.Kind(structuralTarget) == ColumnarExpressionNodeKind.IndexAccessExpression) && nodes.ChildCount(structuralTarget) > 0 {
                    structuralTarget = nodes.Child(structuralTarget, 0)
                }
                if nodes.Kind(structuralTarget) == ColumnarExpressionNodeKind.IdentifierExpression && nodes.ValueStart(structuralTarget) >= 0 && names.Contains(nodes.Text(source, structuralTarget)) {
                    return true
                }
            }
        } else if kind == ColumnarStatementNodeKind.ForeachStatement {
            if names.Contains(nodes.Text(source, node)) {
                return true
            }
        } else if kind == ColumnarStatementNodeKind.TypedForeachStatement {
            if nodes.ChildCount(node) > 0 && nodes.Kind(nodes.Child(node, 0)) == 6 && names.Contains(nodes.Text(source, nodes.Child(node, 0))) {
                return true
            }
        } else if kind == ColumnarStatementNodeKind.TupleDeconstructionStatement {
            nameOrdinal := 0
            while nameOrdinal < nodes.ChildCount(node) - 1 {
                child := nodes.Child(node, nameOrdinal)
                if nodes.Kind(child) == ColumnarExpressionNodeKind.IdentifierExpression && names.Contains(nodes.Text(source, child)) {
                    return true
                }
                nameOrdinal = nameOrdinal + 1
            }
        }

        childOrdinal := 0
        while childOrdinal < nodes.ChildCount(node) {
            if IsNameStructurallyWritten(nodes, source, nodes.Child(node, childOrdinal), names) {
                return true
            }
            childOrdinal = childOrdinal + 1
        }
        return false
    }
}
