namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection

func AdversarialDirectCallOneType(value: Type): Type[] {
    result := new Type[](1)
    result[0] = value
    return result
}

func AdversarialRequiredGenericRuntimeMethod(lookupType: Type, memberName: string, parameterCount: int): MethodInfo {
    selected: MethodInfo? = null
    for candidate in lookupType.GetMethods() {
        if candidate.get_Name() == memberName && candidate.get_IsStatic() && candidate.get_IsGenericMethodDefinition() && candidate.GetParameters().Length == parameterCount {
            if selected != null {
                throw new InvalidOperationException("The adversarial runtime method fixture was ambiguous.")
            }

            selected = candidate
        }
    }

    if selected == null {
        throw new InvalidOperationException("The adversarial generic runtime method fixture was not found.")
    }

    return selected
}

test "direct-call planner preserves terminal ownership from recursive call children" {
    owner := SourceCallDefinition("AdversarialNestedOwner", true)
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    SourceCallPublicStatic(owner, "Inner", oneInt, typeof(int))
    SourceCallPublicStatic(owner, "Outer", oneInt, typeof(int))

    builder := new ColumnarRangePlannerNodeBuilder()
    innerOwner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "AdversarialNestedOwner")

    innerMember := DirectCallAppendMember(builder, innerOwner, "Inner")
    badArgument := builder.AddLeaf(ColumnarExpressionNodeKind.StringLiteralExpression(), "\"bad\"")

    innerCall := DirectCallAppendCall(builder, innerMember, DirectCallOneArgument(badArgument))

    outerOwner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "AdversarialNestedOwner")

    outerMember := DirectCallAppendMember(builder, outerOwner, "Outer")
    root := DirectCallAppendCall(builder, outerMember, DirectCallOneArgument(innerCall))

    tree := builder.Build(root)
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning := true
    DirectCallRejected(tree, DirectCallSingleDefinitionBindings(owner), out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacyWholeSubtreePlanning
}

test "direct-call planner preserves terminal ownership through range-index recursion" {
    owner := SourceCallDefinition("AdversarialRangeOwner", true)
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    SourceCallPublicStatic(owner, "Inner", oneInt, typeof(int))
    SourceCallPublicStatic(owner, "Outer", oneInt, typeof(int))

    builder := new ColumnarRangePlannerNodeBuilder()
    innerOwner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "AdversarialRangeOwner")

    innerMember := DirectCallAppendMember(builder, innerOwner, "Inner")
    badArgument := builder.AddLeaf(ColumnarExpressionNodeKind.StringLiteralExpression(), "\"bad\"")

    innerCall := DirectCallAppendCall(builder, innerMember, DirectCallOneArgument(badArgument))

    caretStart := builder.AddToken("^")
    fromEnd := builder.AddNode(ColumnarExpressionNodeKind.UnaryExpression(), caretStart, 1, caretStart, 1, ColumnarRangePlannerChildren1(innerCall))

    values := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "values")

    indexed := builder.AddNode(ColumnarExpressionNodeKind.IndexAccessExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren2(values, fromEnd))

    outerOwner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "AdversarialRangeOwner")

    outerMember := DirectCallAppendMember(builder, outerOwner, "Outer")
    root := DirectCallAppendCall(builder, outerMember, DirectCallOneArgument(indexed))

    bindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(bindings, "values", 0, typeof(int[]))
    tree := builder.Build(root)
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning := true
    DirectCallRejected(tree, bindings, out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacyWholeSubtreePlanning
}

test "direct-call planner marks later-owner children as a whole-subtree boundary" {
    owner := SourceCallDefinition("AdversarialWholeSubtreeOwner", true)
    oneInt := AdversarialDirectCallOneType(typeof(int))
    SourceCallPublicStatic(owner, "Consume", oneInt, typeof(int))

    tree := DirectCallParsedTree("AdversarialWholeSubtreeOwner.Consume(value + 1)")
    bindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(bindings, "value", 0, typeof(int))

    plan := new ColumnarCodePlan()
    nsharpOwned := true
    legacyWholeSubtreePlanning := false
    resultType := typeof(string)
    assert !ColumnarDirectCallPlanner.TryGetType(tree.Nodes, tree.Source, tree.Root, bindings, plan, out nsharpOwned, out legacyWholeSubtreePlanning, out resultType)
    assert !nsharpOwned
    assert legacyWholeSubtreePlanning
    ColumnarRangePlannerAssertEmptyRollback(plan)
}

test "direct-call planner compares repeated builder-bound generic types structurally" {
    item := SourceCallDefinition("AdversarialGenericItem", true)
    box := SourceCallGenericDefinition("AdversarialGenericBox")
    boxType: Type = box.Builder
    boxArguments := boxType.GetGenericArguments()
    assert boxArguments.Length == 1

    listDefinition := typeof(List<int>).GetGenericTypeDefinition()
    openListArguments := new Type[](1)
    openListArguments[0] = boxArguments[0]
    listOfParameter := listDefinition.MakeGenericType(openListArguments)
    SourceCallPublicInstance(box, "Items", new Type[](0), listOfParameter)

    itemType: Type = item.Builder
    itemArguments := new Type[](1)
    itemArguments[0] = itemType
    listOfItem := listDefinition.MakeGenericType(itemArguments)
    consumer := SourceCallDefinition("AdversarialGenericConsumer", true)
    consumeParameters := new Type[](1)
    consumeParameters[0] = listOfItem
    SourceCallPublicStatic(consumer, "Consume", consumeParameters, typeof(int))

    closedBox := boxType.MakeGenericType(itemArguments)
    definitions := new ColumnarStructDef[](3)
    definitions[0] = item
    definitions[1] = box
    definitions[2] = consumer
    bindings := DirectCallBindings(definitions)
    ColumnarRangePlannerAddParameter(bindings, "box", 0, closedBox)

    builder := new ColumnarRangePlannerNodeBuilder()
    boxValue := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "box")

    itemsMember := DirectCallAppendMember(builder, boxValue, "Items")
    itemsCall := DirectCallAppendCall(builder, itemsMember, DirectCallNoArguments())

    consumerOwner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "AdversarialGenericConsumer")

    consumeMember := DirectCallAppendMember(builder, consumerOwner, "Consume")

    root := DirectCallAppendCall(builder, consumeMember, DirectCallOneArgument(itemsCall))

    plan := DirectCallPlan(builder.Build(root), bindings)
    assert plan.ResultType == typeof(int)
    assert DirectCallHasMethod(plan, "Items")
    assert DirectCallHasMethod(plan, "Consume")
}

test "direct-call planner defers weaker source overloads when an excluded family can win" {
    owner := SourceCallDefinition("AdversarialMixedSourceOwner", true)
    intParameters := AdversarialDirectCallOneType(typeof(int))
    longParameters := AdversarialDirectCallOneType(typeof(long))
    objectParameters := AdversarialDirectCallOneType(typeof(object))
    paramsParameters := AdversarialDirectCallOneType(typeof(int[]))
    paramsKinds := new int[](1)
    paramsKinds[0] = 3

    SourceCallPublicInstance(owner, "NumericOrGeneric", longParameters, typeof(int))
    excludedNumeric := SourceCallPublicInstance(owner, "NumericOrGeneric", intParameters, typeof(int))
    SourceCallMakeGeneric(excludedNumeric.Builder)

    SourceCallPublicStatic(owner, "BoxingOrParams", objectParameters, typeof(int))
    SourceCallDefineStatic(owner, "BoxingOrParams", paramsParameters, paramsKinds, typeof(int), (MethodAttributes)22)

    SourceCallPublicStatic(owner, "ExactOrExcluded", intParameters, typeof(int))
    excludedExact := SourceCallPublicStatic(owner, "ExactOrExcluded", intParameters, typeof(int))
    SourceCallMakeGeneric(excludedExact.Builder)
    SourceCallDefineStatic(owner, "ExactOrExcluded", paramsParameters, paramsKinds, typeof(int), (MethodAttributes)22)

    ownerType: Type = owner.Builder
    bindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(bindings, "receiver", 0, ownerType)
    ColumnarRangePlannerAddParameter(bindings, "value", 1, typeof(int))

    numericTree := DirectCallInstanceTree("receiver", "NumericOrGeneric", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))
    numericOwnership := ColumnarDirectCallOwnership.OwnedRejected
    numericLegacy := false
    DirectCallRejected(numericTree, bindings, out numericOwnership, out numericLegacy)

    assert numericOwnership == ColumnarDirectCallOwnership.NotOwned
    assert numericLegacy

    boxingTree := DirectCallQualifiedTree("AdversarialMixedSourceOwner", "BoxingOrParams", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))
    boxingOwnership := ColumnarDirectCallOwnership.OwnedRejected
    boxingLegacy := false
    DirectCallRejected(boxingTree, bindings, out boxingOwnership, out boxingLegacy)

    assert boxingOwnership == ColumnarDirectCallOwnership.NotOwned
    assert boxingLegacy

    exactTree := DirectCallQualifiedTree("AdversarialMixedSourceOwner", "ExactOrExcluded", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))
    exactPlan := DirectCallPlan(exactTree, bindings)
    exactMethodIndex := exactPlan.OperandIndices[exactPlan.OperationCount - 1]

    assert exactPlan.OpCodeValues[exactPlan.OperationCount - 1] == ColumnarCodePlanContract.Call()
    assert exactPlan.MethodParameterTypes[exactMethodIndex][0] == typeof(int)
}

test "direct-call planner fences excluded declarations by the invocation arity" {
    owner := SourceCallDefinition("AdversarialExcludedArityOwner", true)
    ownerType: Type = owner.Builder
    oneInt := AdversarialDirectCallOneType(typeof(int))
    twoInts := new Type[](2)
    twoInts[0] = typeof(int)
    twoInts[1] = typeof(int)

    wrongStatic := SourceCallPublicStatic(owner, "WrongStatic", twoInts, typeof(int))
    SourceCallMakeGeneric(wrongStatic.Builder)

    wrongInstanceParams := new Type[](3)
    wrongInstanceParams[0] = typeof(int)
    wrongInstanceParams[1] = typeof(int)
    wrongInstanceParams[2] = typeof(int[])
    wrongInstanceKinds := new int[](3)
    wrongInstanceKinds[2] = 3
    SourceCallDefineInstance(owner, "WrongInstance", wrongInstanceParams, wrongInstanceKinds, typeof(int), (MethodAttributes)6)

    wrongBareInstance := SourceCallPublicInstance(owner, "BarePick", twoInts, typeof(int))
    SourceCallMakeGeneric(wrongBareInstance.Builder)
    SourceCallPublicStatic(owner, "BarePick", oneInt, typeof(string))

    liveStatic := SourceCallPublicStatic(owner, "LiveStatic", oneInt, typeof(int))
    SourceCallMakeGeneric(liveStatic.Builder)

    liveInstanceParams := new Type[](2)
    liveInstanceParams[0] = typeof(int)
    liveInstanceParams[1] = typeof(int[])
    liveInstanceKinds := new int[](2)
    liveInstanceKinds[1] = 3
    SourceCallDefineInstance(owner, "LiveInstance", liveInstanceParams, liveInstanceKinds, typeof(int), (MethodAttributes)6)

    liveBareInstance := SourceCallPublicInstance(owner, "BareLive", oneInt, typeof(int))
    SourceCallMakeGeneric(liveBareInstance.Builder)
    SourceCallPublicStatic(owner, "BareLive", oneInt, typeof(string))

    definitions := DirectCallSingleDefinitionBindings(owner)

    wrongStaticTree := DirectCallQualifiedTree("AdversarialExcludedArityOwner", "WrongStatic", DirectCallOneText("1"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))
    wrongStaticOwnership := ColumnarDirectCallOwnership.NotOwned
    wrongStaticLegacy := true
    DirectCallRejected(wrongStaticTree, definitions, out wrongStaticOwnership, out wrongStaticLegacy)
    assert wrongStaticOwnership == ColumnarDirectCallOwnership.OwnedRejected
    assert !wrongStaticLegacy

    instanceBindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(instanceBindings, "receiver", 0, ownerType)
    wrongInstanceTree := DirectCallInstanceTree("receiver", "WrongInstance", DirectCallOneText("1"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))
    wrongInstanceOwnership := ColumnarDirectCallOwnership.NotOwned
    wrongInstanceLegacy := true
    DirectCallRejected(wrongInstanceTree, instanceBindings, out wrongInstanceOwnership, out wrongInstanceLegacy)
    assert wrongInstanceOwnership == ColumnarDirectCallOwnership.OwnedRejected
    assert !wrongInstanceLegacy

    bareBindings := DirectCallSingleDefinitionBindings(owner)
    bareBindings.CurrentInstance = ColumnarCurrentInstanceFacts.FromSourceDefinition(owner)
    bareBindings.SetEnclosingTypeDefinition(owner)
    bareTree := DirectCallBareTree("BarePick", DirectCallOneText("1"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))
    barePlan := DirectCallPlan(bareTree, bareBindings)
    bareMethodIndex := barePlan.OperandIndices[barePlan.OperationCount - 1]
    assert barePlan.Methods[bareMethodIndex].get_Name() == "BarePick"
    assert barePlan.MethodIsStatic[bareMethodIndex]
    assert barePlan.ResultType == typeof(string)

    liveStaticTree := DirectCallQualifiedTree("AdversarialExcludedArityOwner", "LiveStatic", DirectCallOneText("1"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))
    liveStaticOwnership := ColumnarDirectCallOwnership.OwnedRejected
    liveStaticLegacy := false
    DirectCallRejected(liveStaticTree, definitions, out liveStaticOwnership, out liveStaticLegacy)
    assert liveStaticOwnership == ColumnarDirectCallOwnership.NotOwned
    assert liveStaticLegacy

    liveInstanceTree := DirectCallInstanceTree("receiver", "LiveInstance", DirectCallOneText("1"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))
    liveInstanceOwnership := ColumnarDirectCallOwnership.OwnedRejected
    liveInstanceLegacy := false
    DirectCallRejected(liveInstanceTree, instanceBindings, out liveInstanceOwnership, out liveInstanceLegacy)
    assert liveInstanceOwnership == ColumnarDirectCallOwnership.NotOwned
    assert liveInstanceLegacy

    liveBareTree := DirectCallBareTree("BareLive", DirectCallOneText("1"), DirectCallOneKind(ColumnarExpressionNodeKind.IntLiteralExpression()))
    liveBareOwnership := ColumnarDirectCallOwnership.OwnedRejected
    liveBareLegacy := false
    DirectCallRejected(liveBareTree, bareBindings, out liveBareOwnership, out liveBareLegacy)
    assert liveBareOwnership == ColumnarDirectCallOwnership.NotOwned
    assert liveBareLegacy
}

test "ordinary runtime direct-call classification defers excluded candidates only when the fixed match is weaker" {
    objectParameters := AdversarialDirectCallOneType(typeof(object))
    fixedConcat := RequiredRuntimeDirectCallMethod(typeof(string), "Concat", objectParameters)
    genericConcat := AdversarialRequiredGenericRuntimeMethod(typeof(string), "Concat", 1)
    candidates := new MethodInfo[](2)
    candidates[0] = genericConcat
    candidates[1] = fixedConcat
    reversed := new MethodInfo[](2)
    reversed[0] = fixedConcat
    reversed[1] = genericConcat

    exact := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveFromCandidates(typeof(string), "Concat", objectParameters, true, candidates)
    exactReversed := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveFromCandidates(typeof(string), "Concat", objectParameters, true, reversed)

    assert exact.IsSelected
    assert exact.ParameterTypes.Length == 1
    assert exact.ParameterTypes[0] == typeof(object)
    assert exactReversed.IsSelected
    assert exactReversed.ParameterTypes.Length == 1
    assert exactReversed.ParameterTypes[0] == typeof(object)

    arrayArguments := AdversarialDirectCallOneType(typeof(int[]))
    weaker := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveFromCandidates(typeof(string), "Concat", arrayArguments, true, candidates)
    weakerReversed := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveFromCandidates(typeof(string), "Concat", arrayArguments, true, reversed)

    assert weaker.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Excluded
    assert weaker.IsExcluded
    assert weaker.Method == null
    assert weakerReversed.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Excluded
    assert weakerReversed.IsExcluded
    assert weakerReversed.Method == null
}

test "direct-call planner keeps additional-root static shadows terminal" {
    tree := DirectCallQualifiedTree("Math", "Abs", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))
    additionalNames := new string[](1)
    additionalNames[0] = "Math"
    ExternalStampScopeFull(tree, "import System", "", new string[](0), ExternalEmptyStructs(), additionalNames)

    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "value", 0, typeof(int))
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning := true
    DirectCallRejected(tree, bindings, out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacyWholeSubtreePlanning
}

test "direct-call planner keeps additional-root source static shadows terminal" {
    owner := SourceCallDefinition("AdversarialAdditionalRootOwner", true)
    oneInt := AdversarialDirectCallOneType(typeof(int))
    SourceCallPublicStatic(owner, "Run", oneInt, typeof(int))

    tree := DirectCallQualifiedTree("AdversarialAdditionalRootOwner", "Run", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))
    additionalNames := new string[](1)
    additionalNames[0] = "AdversarialAdditionalRootOwner"
    ExternalStampScopeFull(tree, tree.Source, "", new string[](0), ExternalEmptyStructs(), additionalNames)

    bindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(bindings, "value", 0, typeof(int))
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning := true
    DirectCallRejected(tree, bindings, out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacyWholeSubtreePlanning
}

test "direct-call planner keeps visible type-parameter source static shadows terminal" {
    owner := SourceCallDefinition("AdversarialVisibleTypeRoot", true)
    oneInt := AdversarialDirectCallOneType(typeof(int))
    SourceCallPublicStatic(owner, "Run", oneInt, typeof(int))

    tree := DirectCallQualifiedTree("AdversarialVisibleTypeRoot", "Run", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))
    visibleTypeParameters := new string[](1)
    visibleTypeParameters[0] = "AdversarialVisibleTypeRoot"
    ExternalStampScopeFull(tree, tree.Source, "", visibleTypeParameters, ExternalEmptyStructs(), null)

    bindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(bindings, "value", 0, typeof(int))
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning := true
    DirectCallRejected(tree, bindings, out ownership, out legacyWholeSubtreePlanning)

    assert ownership == ColumnarDirectCallOwnership.OwnedRejected
    assert !legacyWholeSubtreePlanning
}

test "direct-call planner requests legacy children for missing and excluded source receiver calls" {
    owner := SourceCallDefinition("AdversarialSourceReceiver", true)
    excluded := SourceCallPublicInstance(owner, "Excluded", new Type[](0), typeof(int))
    SourceCallMakeGeneric(excluded.Builder)

    bindings := DirectCallSingleDefinitionBindings(owner)
    ColumnarRangePlannerAddParameter(bindings, "receiver", 0, owner.Builder)

    missingTree := DirectCallInstanceTree("receiver", "PotentialExtension", DirectCallEmptyTexts(), DirectCallEmptyKinds())
    missingOwnership := ColumnarDirectCallOwnership.OwnedRejected
    missingLegacy := false
    DirectCallRejected(missingTree, bindings, out missingOwnership, out missingLegacy)

    assert missingOwnership == ColumnarDirectCallOwnership.NotOwned
    assert missingLegacy

    excludedTree := DirectCallInstanceTree("receiver", "Excluded", DirectCallEmptyTexts(), DirectCallEmptyKinds())
    excludedOwnership := ColumnarDirectCallOwnership.OwnedRejected
    excludedLegacy := false
    DirectCallRejected(excludedTree, bindings, out excludedOwnership, out excludedLegacy)

    assert excludedOwnership == ColumnarDirectCallOwnership.NotOwned
    assert excludedLegacy
}

test "direct-call planner owns ordinary runtime static and instance methods with exact dispatch" {
    mathType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.Math")
    mathTree := DirectCallQualifiedTree("Math", "Abs", DirectCallOneText("value"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))
    ExternalStampScope(mathTree, "import System")
    mathBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(mathBindings, "value", 0, typeof(int))

    mathPlan := DirectCallPlan(mathTree, mathBindings)
    mathMethodIndex := mathPlan.OperandIndices[mathPlan.OperationCount - 1]

    assert mathPlan.OpCodeValues[mathPlan.OperationCount - 1] == ColumnarCodePlanContract.Call()
    assert mathPlan.Methods[mathMethodIndex].get_Name() == "Abs"
    assert mathPlan.MethodDeclaringTypes[mathMethodIndex] == mathType
    assert mathPlan.MethodParameterTypes[mathMethodIndex].Length == 1
    assert mathPlan.MethodParameterTypes[mathMethodIndex][0] == typeof(int)
    assert mathPlan.MethodIsStatic[mathMethodIndex]

    objectTree := DirectCallInstanceTree("value", "ToString", DirectCallEmptyTexts(), DirectCallEmptyKinds())
    objectBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(objectBindings, "value", 0, typeof(object))

    objectPlan := DirectCallPlan(objectTree, objectBindings)
    objectMethodIndex := objectPlan.OperandIndices[objectPlan.OperationCount - 1]

    assert objectPlan.OpCodeValues[objectPlan.OperationCount - 1] == ColumnarCodePlanContract.Callvirt()
    assert objectPlan.Methods[objectMethodIndex].get_Name() == "ToString"
    assert objectPlan.MethodDeclaringTypes[objectMethodIndex] == typeof(object)
    assert objectPlan.MethodParameterTypes[objectMethodIndex].Length == 0
    assert !objectPlan.MethodIsStatic[objectMethodIndex]

    fileStreamType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.IO.FileStream")
    fileTree := DirectCallQualifiedTree("File", "OpenRead", DirectCallOneText("path"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))
    ExternalStampScope(fileTree, "import System.IO")
    fileBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(fileBindings, "path", 0, typeof(string))

    filePlan := DirectCallPlan(fileTree, fileBindings)
    fileMethodIndex := filePlan.OperandIndices[filePlan.OperationCount - 1]

    assert filePlan.OpCodeValues[filePlan.OperationCount - 1] == ColumnarCodePlanContract.Call()
    assert filePlan.Methods[fileMethodIndex].get_Name() == "OpenRead"
    assert filePlan.MethodReturnTypes[fileMethodIndex] == fileStreamType
    assert filePlan.ResultType == fileStreamType
    assert ColumnarRuntimeTypeFacts.IsSupportedDirectCallInteropType(fileStreamType)

    readArguments := new Type[](3)
    readArguments[0] = typeof(byte[])
    readArguments[1] = typeof(int)
    readArguments[2] = typeof(int)
    readSelection := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(fileStreamType, "Read", readArguments, false)

    if readSelection.IsExcluded {
        throw new InvalidOperationException("FileStream.Read was classified as excluded.")
    }

    if readSelection.IsOwnedRejected {
        throw new InvalidOperationException("FileStream.Read was classified as rejected.")
    }

    if readSelection.IsNotFound {
        throw new InvalidOperationException("FileStream.Read was classified as missing.")
    }

    assert readSelection.ReturnType == typeof(int)
    assert readSelection.DeclaringType == fileStreamType

    readTexts := new string[](3)
    readTexts[0] = "buffer"
    readTexts[1] = "offset"
    readTexts[2] = "count"
    readKinds := new int[](3)
    readKinds[0] = ColumnarExpressionNodeKind.IdentifierExpression()
    readKinds[1] = ColumnarExpressionNodeKind.IdentifierExpression()
    readKinds[2] = ColumnarExpressionNodeKind.IdentifierExpression()
    readTree := DirectCallInstanceTree("stream", "Read", readTexts, readKinds)
    readBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(readBindings, "stream", 0, fileStreamType)
    ColumnarRangePlannerAddParameter(readBindings, "buffer", 1, typeof(byte[]))
    ColumnarRangePlannerAddParameter(readBindings, "offset", 2, typeof(int))
    ColumnarRangePlannerAddParameter(readBindings, "count", 3, typeof(int))

    readPlan := DirectCallPlan(readTree, readBindings)
    readMethodIndex := readPlan.OperandIndices[readPlan.OperationCount - 1]

    assert readPlan.OpCodeValues[readPlan.OperationCount - 1] == ColumnarCodePlanContract.Callvirt()
    assert readPlan.MethodDeclaringTypes[readMethodIndex] == fileStreamType
    assert readPlan.ResultType == typeof(int)

    nestedBuilder := new ColumnarRangePlannerNodeBuilder()
    nestedStream := nestedBuilder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "stream")
    nestedRead := DirectCallAppendMember(nestedBuilder, nestedStream, "Read")
    nestedBuffer := nestedBuilder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "buffer")
    nestedOffset := nestedBuilder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "0")
    nestedLengthReceiver := nestedBuilder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), "buffer")
    nestedLength := DirectCallAppendMember(nestedBuilder, nestedLengthReceiver, "Length")
    nestedArguments := new int[](3)
    nestedArguments[0] = nestedBuffer
    nestedArguments[1] = nestedOffset
    nestedArguments[2] = nestedLength
    nestedCall := DirectCallAppendCall(nestedBuilder, nestedRead, nestedArguments)
    nestedTree := nestedBuilder.Build(nestedCall)
    nestedBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(nestedBindings, "stream", 0, fileStreamType)
    ColumnarRangePlannerAddParameter(nestedBindings, "buffer", 1, typeof(byte[]))

    nestedPlan := DirectCallPlan(nestedTree, nestedBindings)

    assert nestedPlan.ResultType == typeof(int)

    directoryInfoType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.IO.DirectoryInfo")

    directoryTree := DirectCallQualifiedTree("Directory", "CreateDirectory", DirectCallOneText("path"), DirectCallOneKind(ColumnarExpressionNodeKind.IdentifierExpression()))

    ExternalStampScope(directoryTree, "import System.IO")
    directoryPlan := DirectCallPlan(directoryTree, fileBindings)
    directoryMethodIndex := directoryPlan.OperandIndices[directoryPlan.OperationCount - 1]

    assert directoryPlan.OpCodeValues[directoryPlan.OperationCount - 1] == ColumnarCodePlanContract.Call()

    assert directoryPlan.MethodReturnTypes[directoryMethodIndex] == directoryInfoType

    assert directoryPlan.ResultType == directoryInfoType
    assert ColumnarRuntimeTypeFacts.IsSupportedDirectCallInteropType(directoryInfoType)
}

test "runtime direct-call candidates require the planned member identity" {
    mathType := TypeOfRequiredRuntimeType(typeof(MethodInfo), "System.Math")
    intParameters := new Type[](1)
    intParameters[0] = typeof(int)
    plan := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, mathType, "Abs", intParameters, typeof(int))

    wrongMethod := RequiredRuntimeDirectCallMethod(mathType, "Sign", intParameters)

    candidates := new MethodInfo[](1)
    candidates[0] = wrongMethod
    selection := ColumnarRuntimeDirectCallSelection.Empty()

    assert !ColumnarRuntimeDirectCallResolver.TrySelectFromCandidates(plan, mathType, true, candidates, out selection)
}

test "runtime direct-call plans require callvirt for reference receivers" {
    noParameters := new Type[](0)
    directReference := RuntimeDirectCallPlan(ColumnarExternalCallKind.Call, typeof(object), "ToString", noParameters, typeof(string))

    selection := ColumnarRuntimeDirectCallSelection.Empty()

    assert !ColumnarRuntimeDirectCallResolver.TrySelect(directReference, typeof(object), false, out selection)
}
