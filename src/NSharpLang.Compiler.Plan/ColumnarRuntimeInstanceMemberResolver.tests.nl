namespace NSharpLang.Compiler.Columnar

import NSharpLang.Compiler

test "builder-bound key-value pairs resolve their value getter" {
    sourceValueType := TypeOfCreateBuilder("RuntimeMemberSourceValue", "RuntimeMemberSourceValueAsm", 0)
    pairArguments := new System.Type[](2)
    pairArguments[0] = typeof(string)
    pairArguments[1] = sourceValueType
    pairType := typeof(System.Collections.Generic.KeyValuePair<int, int>).GetGenericTypeDefinition().MakeGenericType(pairArguments)

    selection := ColumnarRuntimeInstanceMemberSelection.Empty()
    assert ColumnarRuntimeInstanceMemberResolver.TrySelect(pairType, "Value", out selection)
    assert !selection.IsField
    assert RuntimeTypeShapeFacts.ExactTypeShapeMatches(selection.ResultType, sourceValueType)
    getter := selection.Getter
    assert getter != null
    assert RuntimeTypeShapeFacts.ExactTypeShapeMatches(getter.DeclaringType, pairType)

    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "pair", 0, pairType)
    tree := InstanceMemberTree("pair", "Value")
    plan := InstanceMemberPlan(tree, bindings)
    assert plan.MethodCount == 1

    discoveryPlan := new ColumnarCodePlan()
    discoveryPlan.PrepareMethodBody()
    discoveryPlan.IteratorTypeDiscovery = true
    discoveredType := typeof(object)
    assert ColumnarRangeIndexPlanner.TryAppendConstructionValue(
        tree.Nodes,
        tree.Source,
        tree.Root,
        bindings,
        ColumnarRangeIndexHandles.Resolve(),
        discoveryPlan,
        -1,
        0,
        out discoveredType
    )
    assert RuntimeTypeShapeFacts.ExactTypeShapeMatches(discoveredType, sourceValueType)
}


// THE INHERITED-EXTERNAL-BASE FORM OF THE RELATION, which both the analyzer's metadata arm and the
// emitter's candidate filter ask. A member of a REFERENCED assembly is never reachable by its
// `assembly` half, so the only thing `allowInheritedProtected` opens is the family surface.
test "an inherited external base offers its family surface and nothing else" {
    assert AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.Public, false)
    assert AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.Public, true)

    assert !AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.Family, false)
    assert AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.Family, true)

    assert AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.FamilyOrAssembly, true)
    assert !AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.FamilyOrAssembly, false)

    // `private protected` across an assembly boundary is unreachable however derived the reader is:
    // its `assembly` half can never be satisfied.
    assert !AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.PrivateProtected, true)

    // `internal` and `private` are never reachable from another assembly.
    assert !AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.Assembly, true)
    assert !AnalyzerMemberResolution.IsReachableReflectedLevel(MemberAccessibility.Private, true)

    // The emitter's copy of the question is the same relation, so the two cannot drift.
    assert ColumnarRuntimeInstanceMemberResolver.IsReachableInheritedLevel(MemberAccessibility.Family, true)
    assert !ColumnarRuntimeInstanceMemberResolver.IsReachableInheritedLevel(MemberAccessibility.Family, false)
    assert !ColumnarRuntimeInstanceMemberResolver.IsReachableInheritedLevel(MemberAccessibility.Assembly, true)
    assert ColumnarRuntimeInstanceMemberResolver.IsReachableInheritedLevel(MemberAccessibility.Public, false)
}
