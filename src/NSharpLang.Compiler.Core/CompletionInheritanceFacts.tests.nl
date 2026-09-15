namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

func CifEmptyMembers(): DeclaredMemberInfo[] {
    return new DeclaredMemberInfo[](0)
}

func CifEmptyReferences(): TypeReference[] {
    return new TypeReference[](0)
}

func CifEmptyParameters(): TypeParameter[] {
    return new TypeParameter[](0)
}

func CifProperty(name: string): DeclaredMemberInfo {
    typeReference: TypeReference = new SimpleTypeReference("int")
    return new DeclaredMemberInfo(
        name,
        "Owner",
        DeclaredMemberKind.Property,
        "property",
        typeReference,
        false,
        false,
        false,
        true,
        0,
        new string[](0),
        new TypeReference[](0),
        new ParameterModifier[](0),
        0,
        false,
        false,
        typeReference,
        0,
        new TypeParameter[](0),
        new GenericConstraint[](0),
        0,
        false,
        false,
        false,
        false,
        "",
        false,
        false,
        1,
        1
    )
}

func CifClass(name: string, members: DeclaredMemberInfo[], baseReference: TypeReference?): TypeInfo {
    return new ClassTypeInfo(name, 1, 1, false, baseReference, CifEmptyReferences(), CifEmptyParameters(), new ParameterDeclarationInfo[](0), members, new NestedTypeInfo[](0), true)
}

func CifContainsItem(items: List<CompletionItem>, name: string): bool {
    index := 0
    while index < items.Count {
        if items[index].Name == name {
            return true
        }

        index = index + 1
    }

    return false
}

func CifNestedOwner(name: string, baseReference: TypeReference): TypeInfo {
    bases := new TypeReference[](1)
    bases[0] = baseReference
    return new InterfaceTypeInfo(name, 1, 1, false, bases, CifEmptyParameters(), CifEmptyMembers(), new NestedTypeInfo[](0))
}

func CifOuterWithNested(name: string, nested: TypeInfo): TypeInfo {
    nestedTypes := new NestedTypeInfo[](1)
    nestedTypes[0] = new NestedTypeInfo("Inner", nested)
    return new ClassTypeInfo(name, 1, 1, false, null, CifEmptyReferences(), CifEmptyParameters(), new ParameterDeclarationInfo[](0), CifEmptyMembers(), nestedTypes, true)
}

func CifGenericOuterWithNested(name: string, nested: TypeInfo): TypeInfo {
    parameters := new TypeParameter[](1)
    parameters[0] = new TypeParameter("T")
    nestedTypes := new NestedTypeInfo[](1)
    nestedTypes[0] = new NestedTypeInfo("Inner", nested)
    return new ClassTypeInfo(name, 1, 1, false, null, CifEmptyReferences(), parameters, new ParameterDeclarationInfo[](0), CifEmptyMembers(), nestedTypes, true)
}

// Spans identify positions only within one file. A known declaration owner therefore has to answer
// from its model alone, and nested source declarations must still identify that model through their
// outer declaration tree.
test "recorded references stay with the owning model and recognize nested declarations" {
    resolvedReference: TypeReference = new SimpleTypeReference("IBase", 71, 7)
    missingReference: TypeReference = new SimpleTypeReference("IBase", 72, 7)
    nestedOwner := CifNestedOwner("Inner", resolvedReference)
    outer := CifGenericOuterWithNested("Outer", nestedOwner)

    owningModel := new SemanticModel()
    owningModel.RecordType("Outer`1", outer)
    owningModel.RecordType("Outer", CifClass("Outer", CifEmptyMembers(), null))
    owningModel.RecordTypeReference(71, 7, BuiltInTypes.Int)

    otherModel := new SemanticModel()
    otherModel.Types["Elsewhere"] = CifOuterWithNested("Elsewhere", CifNestedOwner("OtherInner", resolvedReference))
    otherModel.RecordTypeReference(71, 7, BuiltInTypes.String)
    otherModel.RecordTypeReference(72, 7, BuiltInTypes.String)

    models := new List<SemanticModel>()
    models.Add(owningModel)
    models.Add(otherModel)

    assert CompletionInheritanceFacts.SemanticModelOwnsDeclaration(owningModel, nestedOwner)
    resolved := CompletionInheritanceFacts.RecordedTypeReferenceType(resolvedReference, models, nestedOwner)
    assert TypeInfoIdentityFacts.AreEqual(must resolved, BuiltInTypes.Int)

    // The same source position appears in another file, but the owner model has no record for it.
    // Completion must leave that edge unresolved rather than read the other file's String record.
    assert CompletionInheritanceFacts.RecordedTypeReferenceType(missingReference, models, nestedOwner) == null
}

// An ownerless caller cannot tell which file owns a line/column pair. It may use an independently
// recorded equivalent type, but different semantic types at the same position are ambiguous.
test "ownerless recorded references require one semantic answer" {
    reference: TypeReference = new SimpleTypeReference("Item", 81, 5)

    first := new SemanticModel()
    first.RecordTypeReference(81, 5, BuiltInTypes.Int)
    second := new SemanticModel()
    second.RecordTypeReference(81, 5, BuiltInTypes.String)
    ambiguous := new List<SemanticModel>()
    ambiguous.Add(first)
    ambiguous.Add(second)
    assert CompletionInheritanceFacts.RecordedTypeReferenceType(reference, ambiguous, null) == null

    sameFirst := new SemanticModel()
    sameFirst.RecordTypeReference(81, 5, BuiltInTypes.String)
    sameSecond := new SemanticModel()
    sameSecond.RecordTypeReference(81, 5, new SimpleTypeInfo("string"))
    matching := new List<SemanticModel>()
    matching.Add(sameFirst)
    matching.Add(sameSecond)
    answer := CompletionInheritanceFacts.RecordedTypeReferenceType(reference, matching, null)
    assert answer != null
    assert TypeInfoIdentityFacts.AreEqual(answer, BuiltInTypes.String)
}

// A closed source receiver can carry a type parameter below any normal composite shape. Rebuild
// each inner node so completion prints the closed signature while retaining tuple labels and the
// function declaration facts that later completion code reads.
test "completion substitution closes tuple and function type trees" {
    substitution := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
    substitution["T"] = BuiltInTypes.String

    tupleElements := new List<TupleTypeElementInfo>()
    tupleElements.Add(new TupleTypeElementInfo("first", new SimpleTypeInfo("T")))
    tupleElements.Add(new TupleTypeElementInfo("second", new SimpleTypeInfo("T")))
    tuple: TypeInfo = new TupleTypeInfo(tupleElements)
    substitutedTuple := CompletionInheritanceFacts.ApplySubstitution(tuple, substitution) as TupleTypeInfo
    assert substitutedTuple != null
    if substitutedTuple != null {
        assert substitutedTuple.Elements[0].Name == "first"
        assert substitutedTuple.Elements[1].Name == "second"
        assert TypeInfoIdentityFacts.AreEqual(substitutedTuple.Elements[0].Type, BuiltInTypes.String)
        assert TypeInfoIdentityFacts.AreEqual(substitutedTuple.Elements[1].Type, BuiltInTypes.String)
        assert NullabilityMetadataReflection.FormatTypeInfo(substitutedTuple) == "(first: string, second: string)"
    }

    function := new FunctionTypeInfo()
    function.SyntheticName = "Map"
    function.SourceName = "Map"
    function.SourceLine = 9
    function.SourceColumn = 5
    function.ParameterNames = new List<string>()
    function.ParameterNames.Add("value")
    function.ParameterTypes = new List<TypeInfo>()
    function.ParameterTypes.Add(new SimpleTypeInfo("T"))
    function.ParameterModifiers = new List<ParameterModifier>()
    function.ParameterModifiers.Add(ParameterModifier.Ref)
    function.RequiredParameterCount = 1
    function.ReturnType = new SimpleTypeInfo("T")

    substitutedFunction := CompletionInheritanceFacts.ApplySubstitution(function, substitution) as FunctionTypeInfo
    assert substitutedFunction != null
    if substitutedFunction != null {
        assert substitutedFunction.SourceName == "Map"
        assert substitutedFunction.SourceLine == 9
        assert substitutedFunction.SourceColumn == 5
        assert substitutedFunction.ParameterNames != null
        assert substitutedFunction.ParameterNames[0] == "value"
        assert substitutedFunction.ParameterModifiers != null
        assert substitutedFunction.ParameterModifiers[0] == ParameterModifier.Ref
        assert substitutedFunction.ParameterTypes != null
        assert TypeInfoIdentityFacts.AreEqual(substitutedFunction.ParameterTypes[0], BuiltInTypes.String)
        assert TypeInfoIdentityFacts.AreEqual(must substitutedFunction.ReturnType, BuiltInTypes.String)
        assert NullabilityMetadataReflection.FormatTypeInfo(substitutedFunction) == "(string) -> string"
    }
}

// There is no language limit on a valid chain's length. The old numeric cutoff silently omitted
// this leaf; the walk now reaches it while the exact-type set still removes diamonds.
test "completion inheritance reaches a source chain beyond sixty four edges" {
    tailMembers := new DeclaredMemberInfo[](1)
    tailMembers[0] = CifProperty("Tail")
    current := CifClass("Depth0", tailMembers, null)

    model := new SemanticModel()
    model.Types["Depth0"] = current
    index := 1
    while index <= 65 {
        line := 100 + index
        baseReference: TypeReference = new SimpleTypeReference("Depth" + (index - 1).ToString(), line, 5)
        next := CifClass("Depth" + index.ToString(), CifEmptyMembers(), baseReference)
        model.Types["Depth" + index.ToString()] = next
        model.RecordTypeReference(line, 5, current)
        current = next
        index = index + 1
    }

    models := new List<SemanticModel>()
    models.Add(model)
    items := new List<CompletionItem>()
    CompletionReceiverFacts.AppendInheritedMemberItems(current, models, CompletionMemberFilter.InstanceOnly, new List<CompilationUnit>(), "", items)
    assert CifContainsItem(items, "Tail")
}

// A malformed generic declaration can produce a fresh closed type at every edge, so exact closed
// identity alone cannot stop it. Re-entering the same source declaration on one path is the cycle.
test "completion inheritance stops a growing source generic cycle by declaration path" {
    parameters := new TypeParameter[](1)
    parameters[0] = new TypeParameter("T")

    argumentReferences := new List<TypeReference>()
    argumentReferences.Add(new SimpleTypeReference("T", 201, 14))
    baseReference: TypeReference = new GenericTypeReference("ICycle", argumentReferences, 201, 5)
    bases := new TypeReference[](1)
    bases[0] = baseReference
    definition: TypeInfo = new InterfaceTypeInfo("ICycle", 1, 1, false, bases, parameters, CifEmptyMembers(), new NestedTypeInfo[](0))

    recursiveArguments := new List<TypeInfo>()
    listArguments := new List<TypeInfo>()
    listArguments.Add(new SimpleTypeInfo("T"))
    recursiveArguments.Add(new GenericTypeInfo("List", listArguments))
    recursive: TypeInfo = new GenericTypeInfo("ICycle", recursiveArguments, definition)

    receiverArguments := new List<TypeInfo>()
    receiverArguments.Add(BuiltInTypes.Int)
    receiver: TypeInfo = new GenericTypeInfo("ICycle", receiverArguments, definition)

    model := new SemanticModel()
    model.Types["ICycle"] = definition
    model.RecordTypeReference(201, 5, recursive)
    models := new List<SemanticModel>()
    models.Add(model)
    items := new List<CompletionItem>()

    CompletionReceiverFacts.AppendInheritedMemberItems(receiver, models, CompletionMemberFilter.InstanceOnly, new List<CompilationUnit>(), "", items)
    assert items.Count == 0
}
