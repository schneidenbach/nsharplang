namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Owns the binding, capture, and mutation analysis that determines closure shape before the
// remaining C# display-class and recursive-body lowering debt runs. All maps and sets are the emitter's
// live state; this planner neither snapshots them early nor substitutes another lookup.
class ColumnarClosureBindingPlanner {
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
        if kind == 24 || kind == 29 {
            if nodes.ValueStart(node) >= 0 {
                names.Add(nodes.Text(source, node))
            }
        } else if kind == 30 {
            ordinal := 0
            while ordinal < nodes.ChildCount(node) - 1 {
                child := nodes.Child(node, ordinal)
                if nodes.Kind(child) == 6 && nodes.ValueStart(child) >= 0 {
                    names.Add(nodes.Text(source, child))
                }
                ordinal = ordinal + 1
            }
        } else if kind == 40 || kind == 50 {
            if nodes.ChildCount(node) == 2 {
                nameChild := nodes.Child(node, 0)
                if nodes.Kind(nameChild) == 6 && nodes.ValueStart(nameChild) >= 0 {
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
        enclosingCapturableNames := new HashSet<string>(locals.Keys, StringComparer.Ordinal)
        enclosingCapturableNames.UnionWith(parameterOrdinals.Keys)
        enclosingCapturableNames.UnionWith(liftedLocals.Keys)
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
        if kind == 38 || kind == 42 || kind == 55 {
            return false
        }
        if kind == 39 {
            nestedBound := new HashSet<string>(bound, StringComparer.Ordinal)
            nestedBound.UnionWith(BoundParamsOf(nodes, source, node))
            return BodyReferencesEnclosingChain(nodes, source, nodes.Child(node, nodes.ChildCount(node) - 1), nestedBound, currentDefinition, locals, liftedLocals, parameterOrdinals, siblings)
        }
        if kind == 6 && nodes.ValueStart(node) >= 0 && currentDefinition != null {
            name := nodes.Text(source, node)
            if !bound.Contains(name) && !locals.ContainsKey(name) && !liftedLocals.ContainsKey(name) && !parameterOrdinals.ContainsKey(name) && !siblings.ContainsKey(name) {
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
        if kind == 46 || kind == 47 {
            return BodyReferencesEnclosingChain(nodes, source, nodes.Child(node, 0), bound, currentDefinition, locals, liftedLocals, parameterOrdinals, siblings)
        }
        first := kind == 15 || kind == 16 ? 1 : 0
        childOrdinal := first
        while childOrdinal < nodes.ChildCount(node) {
            if BodyReferencesEnclosingChain(nodes, source, nodes.Child(node, childOrdinal), bound, currentDefinition, locals, liftedLocals, parameterOrdinals, siblings) {
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
        return ColumnarTypeOfPlanner.IsSupportedType(valueType) && !(valueType.get_Assembly() is AssemblyBuilder) && !valueType.get_IsGenericParameter() && !valueType.get_ContainsGenericParameters() && !ColumnarTypeOfPlanner.ContainsBuilderBoundType(valueType)
    }

    static func StrongBoxValueField(valueType: Type): FieldInfo? {
        openStrongBox := typeof(System.Runtime.CompilerServices.StrongBox<int>).GetGenericTypeDefinition()
        arguments := new Type[](1)
        arguments[0] = valueType
        return openStrongBox.MakeGenericType(arguments).GetField("Value")
    }

    static func ContainsCaptureOpaqueKind(nodes: ColumnarNodeTable, node: int): bool {
        kind := nodes.Kind(node)
        if kind == 18 || kind == 19 || (kind >= 32 && kind <= 37) || kind == 52 || kind == 61 || (kind >= 65 && kind <= 68) {
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
        if kind == 14 || kind == 44 {
            target := nodes.Child(node, 0)
            while (nodes.Kind(target) == 8 || nodes.Kind(target) == 10) && nodes.ChildCount(target) > 0 {
                target = nodes.Child(target, 0)
            }
            if nodes.Kind(target) == 6 && nodes.ValueStart(target) >= 0 && names.Contains(nodes.Text(source, target)) {
                return true
            }
        } else if kind == 29 {
            if names.Contains(nodes.Text(source, node)) {
                return true
            }
        } else if kind == 30 {
            nameOrdinal := 0
            while nameOrdinal < nodes.ChildCount(node) - 1 {
                child := nodes.Child(node, nameOrdinal)
                if nodes.Kind(child) == 6 && names.Contains(nodes.Text(source, child)) {
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
        if kind == 38 || kind == 42 || kind == 55 {
            return
        }
        if kind == 39 {
            CollectUnboundNames(nodes, source, nodes.Child(node, nodes.ChildCount(node) - 1), BoundParamsOf(nodes, source, node), names)
            return
        }
        if kind == 46 || kind == 47 {
            CollectNamesInsideLambdas(nodes, source, nodes.Child(node, 0), names)
            return
        }
        first := kind == 15 || kind == 16 ? 1 : 0
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
            if nodes.Kind(parameterNode) == 6 {
                bound.Add(nodes.Text(source, parameterNode))
            }
            parameterOrdinal = parameterOrdinal + 1
        }
        return bound
    }

    static func CollectUnboundNames(nodes: ColumnarNodeTable, source: string, node: int, bound: HashSet<string>, names: SortedSet<string>) {
        kind := nodes.Kind(node)
        if kind == 38 || kind == 42 || kind == 55 {
            return
        }
        if kind == 39 {
            nestedBound := new HashSet<string>(bound, StringComparer.Ordinal)
            nestedBound.UnionWith(BoundParamsOf(nodes, source, node))
            CollectUnboundNames(nodes, source, nodes.Child(node, nodes.ChildCount(node) - 1), nestedBound, names)
            return
        }
        if kind == 6 && nodes.ValueStart(node) >= 0 {
            name := nodes.Text(source, node)
            if !bound.Contains(name) {
                names.Add(name)
            }
        }
        if kind == 46 || kind == 47 {
            CollectUnboundNames(nodes, source, nodes.Child(node, 0), bound, names)
            return
        }
        first := kind == 15 || kind == 16 ? 1 : 0
        childOrdinal := first
        while childOrdinal < nodes.ChildCount(node) {
            CollectUnboundNames(nodes, source, nodes.Child(node, childOrdinal), bound, names)
            childOrdinal = childOrdinal + 1
        }
    }

    static func IsNameBareAssigned(nodes: ColumnarNodeTable, source: string, node: int, names: SortedSet<string>): bool {
        if nodes.Kind(node) == 39 {
            bound := BoundParamsOf(nodes, source, node)
            remaining := new SortedSet<string>(names, StringComparer.Ordinal)
            remaining.ExceptWith(bound)
            return remaining.Count > 0 && IsNameBareAssigned(nodes, source, nodes.Child(node, nodes.ChildCount(node) - 1), remaining)
        }
        kind := nodes.Kind(node)
        if kind == 14 || kind == 44 {
            target := nodes.Child(node, 0)
            if nodes.Kind(target) == 6 && nodes.ValueStart(target) >= 0 && names.Contains(nodes.Text(source, target)) {
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
        if kind == 14 || kind == 44 {
            structuralTarget := nodes.Child(node, 0)
            if nodes.Kind(structuralTarget) == 8 || nodes.Kind(structuralTarget) == 10 {
                while (nodes.Kind(structuralTarget) == 8 || nodes.Kind(structuralTarget) == 10) && nodes.ChildCount(structuralTarget) > 0 {
                    structuralTarget = nodes.Child(structuralTarget, 0)
                }
                if nodes.Kind(structuralTarget) == 6 && nodes.ValueStart(structuralTarget) >= 0 && names.Contains(nodes.Text(source, structuralTarget)) {
                    return true
                }
            }
        } else if kind == 29 {
            if names.Contains(nodes.Text(source, node)) {
                return true
            }
        } else if kind == 30 {
            nameOrdinal := 0
            while nameOrdinal < nodes.ChildCount(node) - 1 {
                child := nodes.Child(node, nameOrdinal)
                if nodes.Kind(child) == 6 && names.Contains(nodes.Text(source, child)) {
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
