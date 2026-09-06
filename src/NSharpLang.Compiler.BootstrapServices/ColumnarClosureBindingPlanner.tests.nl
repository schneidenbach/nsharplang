namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import System.Runtime.CompilerServices

// These controls exercise the N# closure-analysis owner directly. Existing lambda-placement and
// bound-identifier suites retain emitted execution/IL coverage; this file pins the live analysis
// state that chooses capture, lift, and enclosing-member behavior before emission starts.
class ClosureBindingControlsBoxedFieldProbe {
    Value: int
}

func ClosureBindingControlsBoxedField(): FieldInfo {
    field := typeof(ClosureBindingControlsBoxedFieldProbe).GetField("Value")
    if field == null {
        throw new InvalidOperationException("The boxed-capture field fixture was not found.")
    }

    return field
}

func ClosureBindingControlsVoidType(): Type {
    value := Type.GetType("System.Void")
    if value == null {
        throw new InvalidOperationException("System.Void was not found.")
    }

    return value
}

func ClosureBindingControlsEmptyLifted(): Dictionary<string, (Box: LocalBuilder, ValueType: Type)> {
    return new Dictionary<string, (Box: LocalBuilder, ValueType: Type)>(StringComparer.Ordinal)
}

func ClosureBindingControlsEmptyBoxed(): Dictionary<string, (BoxField: FieldInfo, ValueType: Type)> {
    return new Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>(StringComparer.Ordinal)
}

func ClosureBindingControlsEmptySiblings(): Dictionary<string, ColumnarSiblingMethodDefinition> {
    return new Dictionary<string, ColumnarSiblingMethodDefinition>(StringComparer.Ordinal)
}

func ClosureBindingControlsIdentifierTree(name: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    root := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), name)
    return builder.Build(root)
}

func ClosureBindingControlsMemberTree(receiverName: string, memberName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), receiverName)
    memberStart := builder.AddToken(memberName)
    children := new int[](1)
    children[0] = receiver
    root := builder.AddNode(
        ColumnarExpressionNodeKind.MemberAccessExpression(),
        memberStart,
        memberName.Length,
        0,
        builder.Source.Length,
        children
    )
    return builder.Build(root)
}

func ClosureBindingControlsBinary(
    builder: ColumnarRangePlannerNodeBuilder,
    left: int,
    right: int
): int {
    operatorStart := builder.AddToken("+")
    children := new int[](2)
    children[0] = left
    children[1] = right
    return builder.AddNode(
        ColumnarExpressionNodeKind.BinaryExpression(),
        operatorStart,
        1,
        0,
        builder.Source.Length,
        children
    )
}

func ClosureBindingControlsBareCaptureWriteTree(name: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    lambdaRead := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), name)
    lambdaChildren := new int[](1)
    lambdaChildren[0] = lambdaRead
    lambda := builder.AddNode(39, -1, 0, 0, builder.Source.Length, lambdaChildren)

    target := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), name)
    value := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    assignmentChildren := new int[](2)
    assignmentChildren[0] = target
    assignmentChildren[1] = value
    assignment := builder.AddNode(14, -1, 0, 0, builder.Source.Length, assignmentChildren)

    rootChildren := new int[](2)
    rootChildren[0] = lambda
    rootChildren[1] = assignment
    root := builder.AddNode(25, -1, 0, 0, builder.Source.Length, rootChildren)
    return builder.Build(root)
}

func ClosureBindingControlsStructuralCaptureWriteTree(name: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    lambdaReceiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), name)
    lambdaMemberStart := builder.AddToken("Value")
    lambdaMemberChildren := new int[](1)
    lambdaMemberChildren[0] = lambdaReceiver
    lambdaBody := builder.AddNode(
        ColumnarExpressionNodeKind.MemberAccessExpression(),
        lambdaMemberStart,
        5,
        0,
        builder.Source.Length,
        lambdaMemberChildren
    )
    lambdaChildren := new int[](1)
    lambdaChildren[0] = lambdaBody
    lambda := builder.AddNode(39, -1, 0, 0, builder.Source.Length, lambdaChildren)

    writeReceiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), name)
    writeMemberStart := builder.AddToken("Value")
    writeMemberChildren := new int[](1)
    writeMemberChildren[0] = writeReceiver
    writeTarget := builder.AddNode(
        ColumnarExpressionNodeKind.MemberAccessExpression(),
        writeMemberStart,
        5,
        0,
        builder.Source.Length,
        writeMemberChildren
    )
    value := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    assignmentChildren := new int[](2)
    assignmentChildren[0] = writeTarget
    assignmentChildren[1] = value
    assignment := builder.AddNode(14, -1, 0, 0, builder.Source.Length, assignmentChildren)

    // Retain a bare root assignment too: ComputeLiftedCandidates must first see a liftable
    // assignment and then reject it because this member-rooted write needs the box value address.
    bareTarget := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), name)
    bareValue := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "2")
    bareAssignmentChildren := new int[](2)
    bareAssignmentChildren[0] = bareTarget
    bareAssignmentChildren[1] = bareValue
    bareAssignment := builder.AddNode(14, -1, 0, 0, builder.Source.Length, bareAssignmentChildren)

    rootChildren := new int[](3)
    rootChildren[0] = lambda
    rootChildren[1] = assignment
    rootChildren[2] = bareAssignment
    root := builder.AddNode(25, -1, 0, 0, builder.Source.Length, rootChildren)
    return builder.Build(root)
}

func ClosureBindingControlsShadowedCaptureTree(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    parameter := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "shadow")
    lambdaShadow := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "shadow")
    lambdaOuter := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "outer")
    lambdaBody := ClosureBindingControlsBinary(builder, lambdaShadow, lambdaOuter)
    lambdaChildren := new int[](2)
    lambdaChildren[0] = parameter
    lambdaChildren[1] = lambdaBody
    lambda := builder.AddNode(39, -1, 0, 0, builder.Source.Length, lambdaChildren)

    shadowTarget := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "shadow")
    shadowValue := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    shadowAssignmentChildren := new int[](2)
    shadowAssignmentChildren[0] = shadowTarget
    shadowAssignmentChildren[1] = shadowValue
    shadowAssignment := builder.AddNode(14, -1, 0, 0, builder.Source.Length, shadowAssignmentChildren)

    outerTarget := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "outer")
    outerValue := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "2")
    outerAssignmentChildren := new int[](2)
    outerAssignmentChildren[0] = outerTarget
    outerAssignmentChildren[1] = outerValue
    outerAssignment := builder.AddNode(14, -1, 0, 0, builder.Source.Length, outerAssignmentChildren)

    rootChildren := new int[](3)
    rootChildren[0] = lambda
    rootChildren[1] = shadowAssignment
    rootChildren[2] = outerAssignment
    root := builder.AddNode(25, -1, 0, 0, builder.Source.Length, rootChildren)
    return builder.Build(root)
}

func ClosureBindingControlsReferences(
    definition: ColumnarStructDef?,
    name: string,
    locals: Dictionary<string, LocalBuilder>
): bool {
    tree := ClosureBindingControlsIdentifierTree(name)
    return ColumnarClosureBindingPlanner.BodyReferencesEnclosingChain(
        tree.Nodes,
        tree.Source,
        tree.Root,
        new HashSet<string>(StringComparer.Ordinal),
        definition,
        locals,
        ClosureBindingControlsEmptyLifted(),
        new Dictionary<string, int>(StringComparer.Ordinal),
        ClosureBindingControlsEmptySiblings()
    )
}

test "closure binding visibility reads every live tier and snapshots no map" {
    local := ExternalProbeLocal(typeof(int))
    locals := new Dictionary<string, LocalBuilder>(StringComparer.Ordinal)
    locals["local"] = local
    parameterOrdinals := new Dictionary<string, int>(StringComparer.Ordinal)
    parameterOrdinals["parameter"] = 3
    lifted := ClosureBindingControlsEmptyLifted()
    lifted["lifted"] = (Box: local, ValueType: typeof(int))
    boxed := ClosureBindingControlsEmptyBoxed()
    boxed["boxed"] = (BoxField: ClosureBindingControlsBoxedField(), ValueType: typeof(int))
    enclosing := new HashSet<string>(StringComparer.Ordinal)
    enclosing.Add("enclosing")

    assert ColumnarClosureBindingPlanner.IsVisibleBindingName("local", locals, parameterOrdinals, lifted, boxed, enclosing)
    assert ColumnarClosureBindingPlanner.IsVisibleBindingName("parameter", locals, parameterOrdinals, lifted, boxed, enclosing)
    assert ColumnarClosureBindingPlanner.IsVisibleBindingName("lifted", locals, parameterOrdinals, lifted, boxed, enclosing)
    assert ColumnarClosureBindingPlanner.IsVisibleBindingName("boxed", locals, parameterOrdinals, lifted, boxed, enclosing)
    assert ColumnarClosureBindingPlanner.IsVisibleBindingName("enclosing", locals, parameterOrdinals, lifted, boxed, enclosing)
    assert !ColumnarClosureBindingPlanner.IsVisibleBindingName("missing", locals, parameterOrdinals, lifted, boxed, enclosing)
    assert !ColumnarClosureBindingPlanner.IsVisibleBindingName("boxed", locals, parameterOrdinals, lifted, null, enclosing)

    snapshot := ColumnarClosureBindingPlanner.VisibleBindingNamesSnapshot(
        enclosing,
        locals,
        parameterOrdinals,
        lifted,
        boxed
    )
    assert snapshot.Count == 5
    assert snapshot.Contains("local")
    assert snapshot.Contains("parameter")
    assert snapshot.Contains("lifted")
    assert snapshot.Contains("boxed")
    assert snapshot.Contains("enclosing")

    locals["late"] = local
    assert !snapshot.Contains("late")
}

test "closure binding collection retains every structural declaration name" {
    builder := new ColumnarRangePlannerNodeBuilder()
    localStart := builder.AddToken("local")
    local := builder.AddNode(24, localStart, 5, localStart, 5, new int[](0))
    foreachStart := builder.AddToken("item")
    foreachDeclaration := builder.AddNode(29, foreachStart, 4, foreachStart, 4, new int[](0))

    first := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "first")
    second := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "second")
    deconstructionValue := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    deconstructionChildren := new int[](3)
    deconstructionChildren[0] = first
    deconstructionChildren[1] = second
    deconstructionChildren[2] = deconstructionValue
    deconstruction := builder.AddNode(30, -1, 0, 0, builder.Source.Length, deconstructionChildren)

    typedName := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "typed")
    typedType := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "int")
    typedChildren := new int[](2)
    typedChildren[0] = typedName
    typedChildren[1] = typedType
    typed := builder.AddNode(40, -1, 0, 0, builder.Source.Length, typedChildren)

    caughtName := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "caught")
    catchBody := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "0")
    catchChildren := new int[](2)
    catchChildren[0] = caughtName
    catchChildren[1] = catchBody
    caught := builder.AddNode(50, -1, 0, 0, builder.Source.Length, catchChildren)

    rootChildren := new int[](5)
    rootChildren[0] = local
    rootChildren[1] = foreachDeclaration
    rootChildren[2] = deconstruction
    rootChildren[3] = typed
    rootChildren[4] = caught
    root := builder.AddNode(25, -1, 0, 0, builder.Source.Length, rootChildren)
    tree := builder.Build(root)

    names := new HashSet<string>(StringComparer.Ordinal)
    ColumnarClosureBindingPlanner.CollectBindingNames(tree.Nodes, tree.Source, tree.Root, names)
    assert names.Count == 6
    assert names.Contains("local")
    assert names.Contains("item")
    assert names.Contains("first")
    assert names.Contains("second")
    assert names.Contains("typed")
    assert names.Contains("caught")
    assert !names.Contains("int")
}

test "closure capture planning takes live tiers in sorted order and honors lambda shadows" {
    builder := new ColumnarRangePlannerNodeBuilder()
    localName := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "local")
    parameterName := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "parameter")
    liftedName := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "lifted")
    shadowName := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "shadow")
    left := ClosureBindingControlsBinary(builder, localName, parameterName)
    right := ClosureBindingControlsBinary(builder, liftedName, shadowName)
    body := ClosureBindingControlsBinary(builder, left, right)
    tree := builder.Build(body)

    local := ExternalProbeLocal(typeof(int))
    locals := new Dictionary<string, LocalBuilder>(StringComparer.Ordinal)
    locals["local"] = local
    parameterOrdinals := new Dictionary<string, int>(StringComparer.Ordinal)
    parameterOrdinals["parameter"] = 1
    lifted := ClosureBindingControlsEmptyLifted()
    lifted["lifted"] = (Box: local, ValueType: typeof(int))
    lambdaOrdinals := new Dictionary<string, int>(StringComparer.Ordinal)
    lambdaOrdinals["shadow"] = 0

    captures := ColumnarClosureBindingPlanner.PlanOrderedCaptureSet(
        tree.Nodes,
        tree.Source,
        tree.Root,
        lambdaOrdinals,
        locals,
        parameterOrdinals,
        lifted
    )
    assert captures.GetType() == typeof(SortedSet<string>)
    assert captures.Count == 3
    assert captures.Contains("local")
    assert captures.Contains("parameter")
    assert captures.Contains("lifted")
    assert !captures.Contains("shadow")

    // The downstream display-class declaration loop consumes this SortedSet directly, so its
    // ordinal comparer and concrete enumeration order are the capture-field order.
    enumerator := captures.GetEnumerator()
    try {
        assert enumerator.MoveNext()
        assert enumerator.get_Current() == "lifted"
        assert enumerator.MoveNext()
        assert enumerator.get_Current() == "local"
        assert enumerator.MoveNext()
        assert enumerator.get_Current() == "parameter"
        assert !enumerator.MoveNext()
    } finally {
        enumerator.Dispose()
    }
}

test "closure lift candidates retain prior state, exclude structural writes, and shadow lambda parameters" {
    bare := ClosureBindingControlsBareCaptureWriteTree("value")
    prior := new HashSet<string>(StringComparer.Ordinal)
    prior.Add("earlier")
    candidates: HashSet<string>? = prior
    ColumnarClosureBindingPlanner.ComputeLiftedCandidates(bare.Nodes, bare.Source, bare.Root, ref candidates)
    assert Object.ReferenceEquals(candidates, prior)
    assert candidates != null
    assert candidates.Count == 2
    assert candidates.Contains("earlier")
    assert candidates.Contains("value")

    structural := ClosureBindingControlsStructuralCaptureWriteTree("cell")
    structuralCandidates: HashSet<string>? = null
    ColumnarClosureBindingPlanner.ComputeLiftedCandidates(structural.Nodes, structural.Source, structural.Root, ref structuralCandidates)
    assert structuralCandidates == null

    writtenNames := new SortedSet<string>(StringComparer.Ordinal)
    writtenNames.Add("cell")
    assert ColumnarClosureBindingPlanner.IsAnyNameWritten(
        structural.Nodes,
        structural.Source,
        structural.Root,
        writtenNames
    )
    missingNames := new SortedSet<string>(StringComparer.Ordinal)
    missingNames.Add("other")
    assert !ColumnarClosureBindingPlanner.IsAnyNameWritten(
        structural.Nodes,
        structural.Source,
        structural.Root,
        missingNames
    )

    shadowed := ClosureBindingControlsShadowedCaptureTree()
    shadowCandidates: HashSet<string>? = null
    ColumnarClosureBindingPlanner.ComputeLiftedCandidates(shadowed.Nodes, shadowed.Source, shadowed.Root, ref shadowCandidates)
    assert shadowCandidates != null
    assert shadowCandidates.Count == 1
    assert shadowCandidates.Contains("outer")
    assert !shadowCandidates.Contains("shadow")

    opaqueBuilder := new ColumnarRangePlannerNodeBuilder()
    opaque := opaqueBuilder.AddNode(
        ColumnarExpressionNodeKind.ObjectInitializerExpression(),
        -1,
        0,
        0,
        0,
        new int[](0)
    )
    opaqueTree := opaqueBuilder.Build(opaque)
    assert ColumnarClosureBindingPlanner.ContainsCaptureOpaqueKind(opaqueTree.Nodes, opaqueTree.Root)
    simple := ClosureBindingControlsIdentifierTree("plain")
    assert !ColumnarClosureBindingPlanner.ContainsCaptureOpaqueKind(simple.Nodes, simple.Root)
}

test "closure liftability and StrongBox field selection retain exact CLR behavior" {
    assert ColumnarClosureBindingPlanner.IsLiftableValueType(typeof(int))
    genericBuilder := TypeOfCreateBuilder(
        "ClosureBindingLiftabilityOpen",
        "ColumnarClosureBindingPlannerTests.ClosureBindingLiftabilityOpen",
        1
    )
    genericParameter := genericBuilder.GetGenericArguments()[0]
    assert !ColumnarClosureBindingPlanner.IsLiftableValueType(genericParameter)

    actual := ColumnarClosureBindingPlanner.StrongBoxValueField(typeof(int))
    if actual == null {
        throw new InvalidOperationException("StrongBox<int>.Value was not selected.")
    }
    expected := typeof(StrongBox<int>).GetField("Value")
    if expected == null {
        throw new InvalidOperationException("The CLR StrongBox<int>.Value field was not found.")
    }
    expectedDefinition := typeof(StrongBox<int>).GetGenericTypeDefinition()
    actualOwner := actual.get_DeclaringType()
    if actualOwner == null {
        throw new InvalidOperationException("StrongBox<int>.Value has no declaring type.")
    }
    assert actualOwner == typeof(StrongBox<int>)
    assert actualOwner.GetGenericTypeDefinition() == expectedDefinition
    assert Object.ReferenceEquals(actual, expected)
    assert actual.get_FieldType() == typeof(int)

    assert throws ArgumentException {
        ColumnarClosureBindingPlanner.StrongBoxValueField(ClosureBindingControlsVoidType())
    }
    assert throws ArgumentNullException {
        ColumnarClosureBindingPlanner.StrongBoxValueField(null)
    }
}

test "enclosing member references use source base chains and live binding precedence" {
    baseDefinition := SourceCallDefinition("ClosureBindingChainBase", true)
    derivedDefinition := SourceCallDefinition("ClosureBindingChainDerived", true)
    derivedDefinition.BaseDef = baseDefinition

    instanceField := ConstructionDefinePublicField(
        baseDefinition.Builder,
        "InstanceField",
        typeof(int)
    )
    baseDefinition.Fields["InstanceField"] = instanceField
    instanceMethod := SourceCallPublicInstance(
        baseDefinition,
        "InstanceMethod",
        new Type[](0),
        typeof(int)
    )
    staticField := ConstructionDefineField(
        baseDefinition.Builder,
        "StaticField",
        typeof(int),
        22
    )
    baseDefinition.StaticFields["StaticField"] = staticField
    staticProperty := ColumnarPropertyDef.Define(
        baseDefinition.Builder,
        "get_StaticProperty",
        (MethodAttributes)22,
        typeof(int),
        "set_StaticProperty",
        (MethodAttributes)22
    )
    baseDefinition.StaticProperties["StaticProperty"] = staticProperty

    foundOwner: ColumnarStructDef? = null
    foundField: FieldBuilder? = null
    assert ColumnarSourceMemberChainResolver.TryFindFieldOnChain(
        derivedDefinition,
        "InstanceField",
        out foundOwner,
        out foundField
    )
    assert Object.ReferenceEquals(foundOwner, baseDefinition)
    assert Object.ReferenceEquals(foundField, instanceField)

    foundMethod: ColumnarInstanceMethodDef? = null
    assert ColumnarSourceMemberChainResolver.TryFindMethodOnChain(
        derivedDefinition,
        "InstanceMethod",
        out foundMethod
    )
    assert Object.ReferenceEquals(foundMethod, instanceMethod)

    emptyLocals := new Dictionary<string, LocalBuilder>(StringComparer.Ordinal)
    assert ClosureBindingControlsReferences(derivedDefinition, "InstanceField", emptyLocals)
    assert ClosureBindingControlsReferences(derivedDefinition, "InstanceMethod", emptyLocals)
    assert ClosureBindingControlsReferences(derivedDefinition, "StaticField", emptyLocals)
    assert ClosureBindingControlsReferences(derivedDefinition, "StaticProperty", emptyLocals)

    emptyLocals["InstanceField"] = ExternalProbeLocal(typeof(int))
    assert !ClosureBindingControlsReferences(derivedDefinition, "InstanceField", emptyLocals)
}

test "source arity lookup preserves the caller out slot when a later candidate fails" {
    derived := SourceCallDefinition("ClosureBindingArityDerived", true)
    baseDefinition := SourceCallDefinition("ClosureBindingArityBase", true)
    derived.BaseDef = baseDefinition

    oneParameter := new Type[](1)
    oneParameter[0] = typeof(int)
    SourceCallPublicInstance(derived, "Probe", oneParameter, typeof(int))

    // The derived overload list completes normally with an arity miss. The malformed base row
    // then throws while its signature is read. A factored helper must keep the caller's out slot
    // untouched across that normal miss and the later failure.
    malformedOverloads := new List<ColumnarInstanceMethodDef>()
    malformed: ColumnarInstanceMethodDef = null
    malformedOverloads.Add(malformed)
    baseDefinition.MethodOverloads["Probe"] = malformedOverloads

    sentinel := SourceCallPublicInstance(
        derived,
        "Sentinel",
        new Type[](0),
        typeof(int)
    )
    result: ColumnarInstanceMethodDef? = sentinel
    assert throws NullReferenceException {
        ColumnarSourceMemberChainResolver.TryFindMethodOnChain(
            derived,
            "Probe",
            0,
            out result
        )
    }
    assert Object.ReferenceEquals(result, sentinel)
}
