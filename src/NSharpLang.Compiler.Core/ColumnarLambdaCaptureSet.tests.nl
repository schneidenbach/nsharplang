namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

// Build a HashSet<string> (ordinal) from a name array — the capture fixtures' enclosing-capturable and
// bound-parameter sets.
func CaptureSetNames(values: string[]): HashSet<string> {
    set := new HashSet<string>(StringComparer.Ordinal)
    index := 0
    while index < values.Length {
        set.Add(values[index])
        index = index + 1
    }

    return set
}

func CaptureSetEmptyNames(): HashSet<string> {
    return new HashSet<string>(StringComparer.Ordinal)
}

test "capture set captures an enclosing name read in the body" {
    builder := new ColumnarRangePlannerNodeBuilder()
    root := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "count")
    tree := builder.Build(root)

    enclosing := new string[](1)
    enclosing[0] = "count"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 1
    assert captures.Contains("count")
}

test "capture set captures multiple enclosing names through a container expression" {
    builder := new ColumnarRangePlannerNodeBuilder()
    left := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "total")
    right := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "amount")
    operatorStart := builder.AddToken("+")
    children := new int[](2)
    children[0] = left
    children[1] = right
    root := builder.AddNode(
        ColumnarExpressionNodeKind.BinaryExpression(),
        operatorStart,
        1,
        operatorStart,
        1,
        children
    )
    tree := builder.Build(root)

    enclosing := new string[](2)
    enclosing[0] = "total"
    enclosing[1] = "amount"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 2
    assert captures.Contains("total")
    assert captures.Contains("amount")
}

test "capture set excludes a name bound by the lambda's own parameters" {
    builder := new ColumnarRangePlannerNodeBuilder()
    root := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "x")
    tree := builder.Build(root)

    enclosing := new string[](1)
    enclosing[0] = "x"
    bound := new string[](1)
    bound[0] = "x"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetNames(bound),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 0
}

test "capture set excludes a nested lambda's parameter but captures its free names" {
    builder := new ColumnarRangePlannerNodeBuilder()
    nestedParameter := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "y")
    bodyLeft := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "y")
    bodyRight := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "z")
    operatorStart := builder.AddToken("+")
    bodyChildren := new int[](2)
    bodyChildren[0] = bodyLeft
    bodyChildren[1] = bodyRight
    nestedBody := builder.AddNode(
        ColumnarExpressionNodeKind.BinaryExpression(),
        operatorStart,
        1,
        operatorStart,
        1,
        bodyChildren
    )
    // Kind 39 is the parser's lambda node: children = [param identifiers..., body].
    lambdaChildren := new int[](2)
    lambdaChildren[0] = nestedParameter
    lambdaChildren[1] = nestedBody
    root := builder.AddNode(39, -1, 0, 0, builder.Source.Length, lambdaChildren)
    tree := builder.Build(root)

    enclosing := new string[](2)
    enclosing[0] = "y"
    enclosing[1] = "z"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 1
    assert captures.Contains("z")
    assert !captures.Contains("y")
}

test "capture set captures a member-access base but not the member name" {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "item")
    // A member access (kind 8) carries the member NAME in its value span and the receiver as its only
    // child, so the member name is never a capture candidate; only the base is walked.
    memberStart := builder.AddToken("Tags")
    memberChildren := new int[](1)
    memberChildren[0] = receiver
    root := builder.AddNode(
        ColumnarExpressionNodeKind.MemberAccessExpression(),
        memberStart,
        4,
        memberStart,
        4,
        memberChildren
    )
    tree := builder.Build(root)

    enclosing := new string[](2)
    enclosing[0] = "item"
    enclosing[1] = "Tags"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 1
    assert captures.Contains("item")
    assert !captures.Contains("Tags")
}

test "capture set steps over the type child of a cast expression" {
    builder := new ColumnarRangePlannerNodeBuilder()
    typeChild := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "Widget")
    valueChild := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "w")
    // A cast (kind 16) has its TYPE subtree at child[0] and the value at child[1]; the type child is
    // never a capture candidate.
    castChildren := new int[](2)
    castChildren[0] = typeChild
    castChildren[1] = valueChild
    root := builder.AddNode(
        ColumnarExpressionNodeKind.CastExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        castChildren
    )
    tree := builder.Build(root)

    enclosing := new string[](2)
    enclosing[0] = "Widget"
    enclosing[1] = "w"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 1
    assert captures.Contains("w")
    assert !captures.Contains("Widget")
}

test "capture set skips a typeof subtree entirely" {
    builder := new ColumnarRangePlannerNodeBuilder()
    typeChild := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "T")
    typeofChildren := new int[](1)
    typeofChildren[0] = typeChild
    root := builder.AddNode(
        ColumnarExpressionNodeKind.TypeOfExpression(),
        -1,
        0,
        0,
        builder.Source.Length,
        typeofChildren
    )
    tree := builder.Build(root)

    enclosing := new string[](1)
    enclosing[0] = "T"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 0
}

test "capture set skips a value-less masquerading type identifier" {
    builder := new ColumnarRangePlannerNodeBuilder()
    // A value-less identifier (valueStart -1) is a masquerading TYPE node, never a name read; the scan
    // must skip it without reading its text.
    root := builder.AddNode(ColumnarExpressionNodeKind.IdentifierExpression(), -1, 0, 0, 0, new int[](0))
    tree := builder.Build(root)

    enclosing := new string[](1)
    enclosing[0] = "ignored"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 0
}

test "capture set does not capture a name absent from the enclosing scope" {
    builder := new ColumnarRangePlannerNodeBuilder()
    root := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "localOnly")
    tree := builder.Build(root)

    enclosing := new string[](1)
    enclosing[0] = "other"

    captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(
        tree.Nodes,
        tree.Source,
        root,
        CaptureSetEmptyNames(),
        CaptureSetNames(enclosing)
    )

    assert captures.Count == 0
}

// WHERE A LAMBDA'S SYNTHESIZED METHOD GOES WHEN ITS OWN BODY DECIDES ITS RETURN TYPE.
//
// `f := () => this.Value` names no delegate target, so the method is defined SIGNATURE-LESS and gets
// its return type after the body is emitted. That is the only thing that differs from a targeted
// lambda: the PLACEMENT question is the same one, and asking it only on the targeted path is why the
// `:=` spelling declined at `emit.body` on a body the `Func<int>` spelling emitted happily.
func InferredPlacementModuleBuilder(name: string): ModuleBuilder {
    assemblyName := "NSharpTests." + name
    dynamicAssembly := AssemblyBuilder.DefineDynamicAssembly(
        new AssemblyName(assemblyName),
        AssemblyBuilderAccess.Run
    )

    return dynamicAssembly.DefineDynamicModule(assemblyName)
}

func InferredPlacementEnclosing(module: ModuleBuilder, name: string): ColumnarStructDef {
    builder := module.DefineType(
        "InferredPlacementTests." + name,
        TypeAttributes.Public | TypeAttributes.Class | TypeAttributes.BeforeFieldInit,
        typeof(object)
    )

    return new ColumnarStructDef(
        builder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        name
    )
}

// The same enclosing type declared as a VALUE type, which is the one `this` a delegate cannot bind.
func InferredPlacementValueEnclosing(module: ModuleBuilder, name: string): ColumnarStructDef {
    builder := module.DefineType(
        "InferredPlacementTests." + name,
        TypeAttributes.Public | TypeAttributes.Sealed | TypeAttributes.BeforeFieldInit,
        typeof(ValueType)
    )

    return new ColumnarStructDef(
        builder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        false,
        false,
        false,
        name
    )
}

test "an inferred zero-parameter lambda that reads the instance becomes an instance method on it" {
    module := InferredPlacementModuleBuilder("InferredInstancePlacement")
    programType := module.DefineType("InferredPlacementTests.Program", TypeAttributes.Public | TypeAttributes.Class, typeof(object))
    enclosing := InferredPlacementEnclosing(module, "Holder")

    placement := ColumnarLambdaPlacementPlanner.PlanInferredPlacement(
        programType,
        enclosing,
        new int[](1),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        Type.EmptyTypes,
        true
    )

    assert placement != null
    assert placement.Mode == ColumnarLambdaPlacementMode.InstanceThis
    assert placement.OrdinalShift == 1
    assert !placement.Method.get_IsStatic()
    assert placement.Method.get_IsPrivate()
    assert ColumnarConstructionPlanner.SameObject(placement.OwnerTypeForBody, enclosing.Builder)
    assert ColumnarConstructionPlanner.SameObject(placement.CurrentStructForBody, enclosing)
}

test "an inferred zero-parameter lambda inside a type stays a static method on that type" {
    module := InferredPlacementModuleBuilder("InferredStaticPlacement")
    programType := module.DefineType("InferredPlacementTests.Program", TypeAttributes.Public | TypeAttributes.Class, typeof(object))
    enclosing := InferredPlacementEnclosing(module, "Holder")

    placement := ColumnarLambdaPlacementPlanner.PlanInferredPlacement(
        programType,
        enclosing,
        new int[](1),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        Type.EmptyTypes,
        false
    )

    assert placement != null
    assert placement.Mode == ColumnarLambdaPlacementMode.StaticEnclosing
    assert placement.OrdinalShift == 0
    assert placement.Method.get_IsStatic()
    assert ColumnarConstructionPlanner.SameObject(placement.CurrentStructForBody, enclosing)
    assert ColumnarConstructionPlanner.SameObject(placement.OwnerTypeForBody, enclosing.Builder)
}

test "a noncapturing lambda whose signature names a nested type stays on its enclosing declaration" {
    module := InferredPlacementModuleBuilder("NestedSignaturePlacement")
    programType := module.DefineType("InferredPlacementTests.Program", TypeAttributes.Public | TypeAttributes.Class, typeof(object))
    enclosing := InferredPlacementEnclosing(module, "Holder")
    nested: Type = ListEnumeratorControlDefineNested(enclosing.Builder, "Cached", 0)
    parameterTypes := new Type[](1)
    parameterTypes[0] = nested

    placement := ColumnarLambdaPlacementPlanner.PlanNonCapturingPlacement(
        programType,
        enclosing,
        new int[](1),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        typeof(string),
        parameterTypes,
        false
    )

    assert placement != null
    assert placement.Mode == ColumnarLambdaPlacementMode.StaticEnclosing
    assert placement.OrdinalShift == 0
    assert placement.Method.get_IsStatic()
    assert ColumnarConstructionPlanner.SameObject(placement.CurrentStructForBody, enclosing)
    assert ColumnarConstructionPlanner.SameObject(placement.OwnerTypeForBody, enclosing.Builder)
}

// A VALUE TYPE'S `this` IS NOT BINDABLE: it is a pointer into storage the constructor owns, and a
// delegate over it would carry a copy with different mutation semantics. A CONSTRUCTOR BODY'S `this`
// used to be refused on the same terms and is not any more: inside a REFERENCE type's constructor
// `ldarg.0` IS the object being constructed, the same reference every later method sees — which is
// why `this.handler = () => this.Name` now emits in the constructor that sets the very field it
// reads. The targeted path and the inferred one refuse on exactly the same terms.
test "an inferred placement refuses a this-capture it cannot bind" {
    module := InferredPlacementModuleBuilder("InferredRefusedPlacement")
    programType := module.DefineType("InferredPlacementTests.Program", TypeAttributes.Public | TypeAttributes.Class, typeof(object))
    valueEnclosing := InferredPlacementValueEnclosing(module, "ValueHolder")
    visible := new Dictionary<string, Type>(StringComparer.Ordinal)

    refused := ColumnarLambdaPlacementPlanner.PlanInferredPlacement(programType, valueEnclosing, new int[](1), visible, Type.EmptyTypes, true)
    assert refused == null
    noEnclosing := ColumnarLambdaPlacementPlanner.PlanInferredPlacement(programType, null, new int[](1), visible, Type.EmptyTypes, true)
    assert noEnclosing == null
}
