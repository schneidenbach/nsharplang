namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the analyzer's assignability SHAPE decisions. Every member of this family was
// `private` in Analyzer.cs, so no test named any of them: their behaviour was pinned only
// indirectly, through end-to-end analyzer diagnostics. This is their first DIRECT pinning.
//
// The known-generic and function-type decisions answer with the PENDING-PAIR protocol, so these
// contracts assert on the protocol itself — a decided verdict, or the exact pairs handed back — and
// never on a recursive assignability answer, which is not this owner's to give.

func AssignabilityContext(path: string): AnalyzerDeclarationContext {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    declarations := new List<object>()
    declarations.Add(new NSharpLang.Compiler.TestStubs.ClassDeclaration("Widget", null))
    context.Reset("/tmp", assemblies)
    context.AddCompilationUnit(path, new AnalyzerContextTestUnit(declarations))
    return context
}

func AssignabilityOwner(path: string): AnalyzerAssignabilityFacts {
    return new AnalyzerAssignabilityFacts(AssignabilityContext(path), null)
}

func AssignabilityArgs(first: TypeInfo): List<TypeInfo> {
    result := new List<TypeInfo>()
    result.Add(first)
    return result
}

func AssignabilityArgs2(first: TypeInfo, second: TypeInfo): List<TypeInfo> {
    result := AssignabilityArgs(first)
    result.Add(second)
    return result
}

// A generic instantiation carrying the REAL runtime definition, which is what
// HasKnownRuntimeGenericDefinition demands of both sides of a known conversion.
func AssignabilityKnownGeneric(
    name: string,
    definition: Type,
    argument: TypeInfo): GenericTypeInfo {
    return new GenericTypeInfo(
        name,
        AssignabilityArgs(argument),
        new ReflectionTypeInfo(definition))
}

// The same spelling with NO definition — a source-declared type that merely shares the name.
func AssignabilitySpelledGeneric(name: string, argument: TypeInfo): GenericTypeInfo {
    return new GenericTypeInfo(name, AssignabilityArgs(argument), null)
}

func AssignabilityFunction(
    returnType: TypeInfo?,
    parameters: List<TypeInfo>): FunctionTypeInfo {
    functionType := new FunctionTypeInfo()
    functionType.ParameterTypes = parameters
    functionType.ReturnType = returnType
    return functionType
}

func AssignabilityNoParameters(): List<TypeInfo> {
    return new List<TypeInfo>()
}

// The runtime open generic definitions, resolved by CANONICAL IDENTITY rather than by `typeof`.
// HasKnownRuntimeGenericDefinition compares against exactly these identities, and the columnar
// `typeof` surface does not carry most of the collection types.
func AssignabilityOpen(identity: string): Type {
    resolved := Type.GetType(identity)
    if resolved == null {
        // Answering `object` rather than throwing keeps a missing identity a LOUD contract failure
        // at the assertion instead of an obscure one here.
        return typeof(object)
    }

    return resolved
}

func AssignabilityClosed(openDefinition: Type, argument: Type): Type {
    arguments := new Type[](1)
    arguments[0] = argument
    return openDefinition.MakeGenericType(arguments)
}

func AssignabilityListOpen(): Type {
    return AssignabilityOpen("System.Collections.Generic.List`1, System.Private.CoreLib")
}

func AssignabilityEnumerableOpen(): Type {
    return AssignabilityOpen("System.Collections.Generic.IEnumerable`1, System.Private.CoreLib")
}

func AssignabilityCollectionInterfaceOpen(): Type {
    return AssignabilityOpen("System.Collections.Generic.ICollection`1, System.Private.CoreLib")
}

func AssignabilityListInterfaceOpen(): Type {
    return AssignabilityOpen("System.Collections.Generic.IList`1, System.Private.CoreLib")
}

func AssignabilityHashSetOpen(): Type {
    return AssignabilityOpen("System.Collections.Generic.HashSet`1, System.Private.CoreLib")
}

func AssignabilityQueueOpen(): Type {
    return AssignabilityOpen("System.Collections.Generic.Queue`1, System.Private.CoreLib")
}

func AssignabilityReadOnlyListOpen(): Type {
    return AssignabilityOpen("System.Collections.Generic.IReadOnlyList`1, System.Private.CoreLib")
}

func AssignabilityReadOnlyCollectionOpen(): Type {
    return AssignabilityOpen(
        "System.Collections.Generic.IReadOnlyCollection`1, System.Private.CoreLib")
}

func AssignabilitySortedSetOpen(): Type {
    return AssignabilityOpen("System.Collections.Generic.SortedSet`1, System.Collections")
}

func AssignabilityDictionaryOpen(): Type {
    return AssignabilityOpen("System.Collections.Generic.Dictionary`2, System.Private.CoreLib")
}

func AssignabilitySpanOpen(): Type {
    return AssignabilityOpen("System.Span`1, System.Private.CoreLib")
}

func AssignabilityReadOnlySpanOpen(): Type {
    return AssignabilityOpen("System.ReadOnlySpan`1, System.Private.CoreLib")
}

func AssignabilityDictionaryClosed(): Type {
    arguments := new Type[](2)
    arguments[0] = typeof(string)
    arguments[1] = typeof(int)
    dictionaryOpen := AssignabilityDictionaryOpen()
    return dictionaryOpen.MakeGenericType(arguments)
}

func AssignabilityActionType(): Type {
    return AssignabilityOpen("System.Action, System.Private.CoreLib")
}

func AssignabilityFuncClosed(): Type {
    arguments := new Type[](2)
    arguments[0] = typeof(int)
    arguments[1] = typeof(string)
    funcOpen := AssignabilityOpen("System.Func`2, System.Private.CoreLib")
    return funcOpen.MakeGenericType(arguments)
}

// Renders a decision so a contract can name the whole protocol answer in one string.
func AssignabilityDecisionShape(decision: AnalyzerAssignabilityDecision): string {
    if decision.Decided {
        if decision.Result {
            return "decided:true"
        }

        return "decided:false"
    }

    rendered := "pending"
    index := 0
    while index < decision.PendingTargets.Count {
        target := decision.PendingTargets[index]
        source := decision.PendingSources[index]
        rendered = rendered + " [" + AssignabilityTypeName(target)
            + "<-" + AssignabilityTypeName(source) + "]"
        index = index + 1
    }

    return rendered
}

func AssignabilityTypeName(candidate: TypeInfo): string {
    simple := candidate as SimpleTypeInfo
    if simple != null {
        return simple.Name
    }

    array := candidate as ArrayTypeInfo
    if array != null {
        return AssignabilityTypeName(array.ElementType) + "[]"
    }

    generic := candidate as GenericTypeInfo
    if generic != null {
        return generic.Name + "<" + AssignabilityTypeName(generic.TypeArguments[0]) + ">"
    }

    reflection := candidate as ReflectionTypeInfo
    if reflection != null {
        reflected := reflection.Type
        reflectedName: string? = reflected.get_FullName()
        if reflectedName == null {
            return reflected.get_Name()
        }

        return reflectedName
    }

    // No contract here renders any other family; a pair that reached this arm would be a shape the
    // decision protocol is not supposed to hand back.
    return "other"
}

test "the known-generic relation is a closed table over the runtime collection types" {
    owner := AssignabilityOwner("/tmp/assign-known.nl")
    listOpen := AssignabilityListOpen()
    enumerableOpen := AssignabilityEnumerableOpen()
    collectionOpen := AssignabilityCollectionInterfaceOpen()
    listInterfaceOpen := AssignabilityListInterfaceOpen()
    hashSetOpen := AssignabilityHashSetOpen()
    queueOpen := AssignabilityQueueOpen()
    readOnlyListOpen := AssignabilityReadOnlyListOpen()
    readOnlyCollectionOpen := AssignabilityReadOnlyCollectionOpen()

    // Every accepted pair, with identical arguments, is decided TRUE with nothing pending.
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("IEnumerable", enumerableOpen, BuiltInTypes.Int),
        AssignabilityKnownGeneric("List", listOpen, BuiltInTypes.Int))) == "decided:true"
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("IEnumerable", enumerableOpen, BuiltInTypes.Int),
        AssignabilityKnownGeneric("HashSet", hashSetOpen, BuiltInTypes.Int))) == "decided:true"
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("IEnumerable", enumerableOpen, BuiltInTypes.Int),
        AssignabilityKnownGeneric("Queue", queueOpen, BuiltInTypes.Int))) == "decided:true"
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("ICollection", collectionOpen, BuiltInTypes.Int),
        AssignabilityKnownGeneric("List", listOpen, BuiltInTypes.Int))) == "decided:true"
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("IList", listInterfaceOpen, BuiltInTypes.Int),
        AssignabilityKnownGeneric("List", listOpen, BuiltInTypes.Int))) == "decided:true"
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("IReadOnlyList", readOnlyListOpen, BuiltInTypes.Int),
        AssignabilityKnownGeneric("List", listOpen, BuiltInTypes.Int))) == "decided:true"
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("IReadOnlyCollection", readOnlyCollectionOpen, BuiltInTypes.Int),
        AssignabilityKnownGeneric("IReadOnlyList", readOnlyListOpen, BuiltInTypes.Int)))
        == "decided:true"

    // The table is CLOSED: the relation does not run backwards, and it does not invent pairs.
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("List", listOpen, BuiltInTypes.Int),
        AssignabilityKnownGeneric("IEnumerable", enumerableOpen, BuiltInTypes.Int)))
        == "decided:false"
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("IList", listInterfaceOpen, BuiltInTypes.Int),
        AssignabilityKnownGeneric("HashSet", hashSetOpen, BuiltInTypes.Int))) == "decided:false"
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("ICollection", collectionOpen, BuiltInTypes.Int),
        AssignabilityKnownGeneric("Queue", queueOpen, BuiltInTypes.Int))) == "decided:false"

    // Both sides must carry the REAL runtime definition. A same-spelled source type does not
    // acquire the relation, in either position.
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilitySpelledGeneric("IEnumerable", BuiltInTypes.Int),
        AssignabilityKnownGeneric("List", listOpen, BuiltInTypes.Int))) == "decided:false"
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("IEnumerable", enumerableOpen, BuiltInTypes.Int),
        AssignabilitySpelledGeneric("List", BuiltInTypes.Int))) == "decided:false"

    // Nothing but a generic instantiation can stand in the relation at all.
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        BuiltInTypes.Object,
        AssignabilityKnownGeneric("List", listOpen, BuiltInTypes.Int))) == "decided:false"
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("IEnumerable", enumerableOpen, BuiltInTypes.Int),
        new ArrayTypeInfo(BuiltInTypes.Int))) == "decided:false"
}

test "known-generic arity must agree and the covariant targets hand back their argument pairs" {
    owner := AssignabilityOwner("/tmp/assign-variance.nl")
    listOpen := AssignabilityListOpen()
    enumerableOpen := AssignabilityEnumerableOpen()
    collectionOpen := AssignabilityCollectionInterfaceOpen()
    dictionaryOpen := AssignabilityDictionaryOpen()

    // Arity is compared BEFORE the table, so a two-argument target is rejected outright.
    twoArgument := new GenericTypeInfo(
        "IEnumerable",
        AssignabilityArgs2(BuiltInTypes.Int, BuiltInTypes.String),
        new ReflectionTypeInfo(dictionaryOpen))
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        twoArgument,
        AssignabilityKnownGeneric("List", listOpen, BuiltInTypes.Int))) == "decided:false"

    // A COVARIANT target with differing reference-like arguments hands back exactly that pair.
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("IEnumerable", enumerableOpen, BuiltInTypes.Object),
        AssignabilityKnownGeneric("List", listOpen, BuiltInTypes.String)))
        == "pending [object<-string]"
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("IReadOnlyList", AssignabilityReadOnlyListOpen(), new ArrayTypeInfo(BuiltInTypes.Object)),
        AssignabilityKnownGeneric("List", listOpen, new ArrayTypeInfo(BuiltInTypes.String))))
        == "pending [object[]<-string[]]"

    // A covariant target whose arguments are VALUE types is decided false without any pair: an
    // `IEnumerable<int>` is not an `IEnumerable<long>`, and no recursion could make it one.
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("IEnumerable", enumerableOpen, BuiltInTypes.Long),
        AssignabilityKnownGeneric("List", listOpen, BuiltInTypes.Int))) == "decided:false"

    // A MUTABLE target is invariant: differing arguments are rejected outright, reference-like or
    // not, because a caller holding the target could insert the wrong element.
    assert AssignabilityDecisionShape(owner.ClassifyKnownGenericAssignability(
        AssignabilityKnownGeneric("ICollection", collectionOpen, BuiltInTypes.Object),
        AssignabilityKnownGeneric("List", listOpen, BuiltInTypes.String))) == "decided:false"
}

test "an alias is resolved before variance is judged" {
    path := "/tmp/assign-alias.nl"
    declarationContext := AssignabilityContext(path)
    owner := new AnalyzerAssignabilityFacts(declarationContext, null)
    meters := new AliasTypeInfo(new SimpleTypeReference("int"))
    declarationContext.RegisterDeclaredAlias(path, meters)
    alias := meters as TypeInfo
    names := new AliasTypeInfo(new SimpleTypeReference("string"))
    declarationContext.RegisterDeclaredAlias(path, names)
    stringAlias := names as TypeInfo

    // `type Meters = int` is a value type, so it is not reference-like and cannot vary.
    assert !owner.IsReferenceLikeForVariance(alias)
    assert !owner.MayUseDelegateReferenceConversion(alias)

    // `type Names = string` is, and so is an array of the value alias.
    assert owner.IsReferenceLikeForVariance(stringAlias)
    assert owner.IsReferenceLikeForVariance(new ArrayTypeInfo(alias))

    // An alias this context does not own stays OPAQUE: it resolves to itself, and an alias is not
    // a shape the reference-type rule recognizes, so it answers false — not the answer its aliased
    // reference would have given. Registration is what makes an alias transparent.
    unowned := new AliasTypeInfo(new SimpleTypeReference("string")) as TypeInfo
    assert !owner.IsReferenceLikeForVariance(unowned)
    assert !owner.MayUseDelegateReferenceConversion(unowned)
}

test "reference-likeness is transparent through the nullable and oblivious shells" {
    owner := AssignabilityOwner("/tmp/assign-shells.nl")

    assert owner.IsReferenceLikeForVariance(BuiltInTypes.String)
    assert owner.IsReferenceLikeForVariance(BuiltInTypes.Object)
    assert owner.IsReferenceLikeForVariance(new ArrayTypeInfo(BuiltInTypes.Int))
    assert !owner.IsReferenceLikeForVariance(BuiltInTypes.Int)
    assert !owner.IsReferenceLikeForVariance(BuiltInTypes.Bool)
    assert !owner.IsReferenceLikeForVariance(BuiltInTypes.Char)

    // The shells do not change the answer; they are unwrapped and the inner type decides.
    assert owner.IsReferenceLikeForVariance(new NullableTypeInfo(BuiltInTypes.String))
    assert !owner.IsReferenceLikeForVariance(new NullableTypeInfo(BuiltInTypes.Int))
    assert owner.IsReferenceLikeForVariance(new ObliviousTypeInfo(BuiltInTypes.String))
    assert !owner.IsReferenceLikeForVariance(new ObliviousTypeInfo(BuiltInTypes.Int))
    assert owner.IsReferenceLikeForVariance(
        new NullableTypeInfo(new ArrayTypeInfo(BuiltInTypes.Int)))

    // A generic instantiation may carry a reference conversion — unless it is the one value-typed
    // shape spelled generically. That rule is the whole difference between the two predicates:
    // `MayUseDelegateReferenceConversion` sees `Nullable<T>` itself, while
    // `IsReferenceLikeForVariance` never does, because the shell is unwrapped first.
    assert owner.MayUseDelegateReferenceConversion(
        AssignabilitySpelledGeneric("List", BuiltInTypes.Int))
    assert !owner.MayUseDelegateReferenceConversion(
        AssignabilitySpelledGeneric("Nullable", BuiltInTypes.Int))
    assert owner.MayUseDelegateReferenceConversion(
        AssignabilitySpelledGeneric("Widget", BuiltInTypes.Int))
}

test "a collection expression targets the runtime collections and names their element type" {
    owner := AssignabilityOwner("/tmp/assign-collections.nl")
    element := BuiltInTypes.Unknown as TypeInfo

    // The generic arm accepts fifteen spellings, and every one must carry the runtime definition.
    assert owner.TryGetCollectionElementType(
        AssignabilityKnownGeneric("List", AssignabilityListOpen(), BuiltInTypes.Int),
        out element)
    assert AssignabilityTypeName(element) == "int"
    assert owner.TryGetCollectionElementType(
        AssignabilityKnownGeneric("SortedSet", AssignabilitySortedSetOpen(), BuiltInTypes.String),
        out element)
    assert AssignabilityTypeName(element) == "string"
    assert owner.TryGetCollectionElementType(
        AssignabilityKnownGeneric("IReadOnlyCollection", AssignabilityReadOnlyCollectionOpen(), new ArrayTypeInfo(BuiltInTypes.Int)),
        out element)
    assert AssignabilityTypeName(element) == "int[]"

    // Not carrying the runtime definition is a decline, and the element type is left unknown.
    assert !owner.TryGetCollectionElementType(
        AssignabilitySpelledGeneric("List", BuiltInTypes.Int),
        out element)
    assert BuiltInTypes.IsUnknown(element)

    // A runtime collection NOT in the table declines even though it is a real generic.
    assert !owner.TryGetCollectionElementType(
        AssignabilityKnownGeneric("Dictionary", AssignabilityDictionaryOpen(), BuiltInTypes.Int),
        out element)
    assert !owner.TryGetCollectionElementType(new ArrayTypeInfo(BuiltInTypes.Int), out element)
    assert !owner.TryGetCollectionElementType(BuiltInTypes.String, out element)
}

test "the reflection collection arm matches metadata names and refuses an open definition" {
    owner := AssignabilityOwner("/tmp/assign-collections-refl.nl")
    element := BuiltInTypes.Unknown as TypeInfo

    assert owner.TryGetCollectionElementType(
        new ReflectionTypeInfo(AssignabilityClosed(AssignabilityListOpen(), typeof(int))),
        out element)
    assert AssignabilityTypeName(element) == "System.Int32"
    assert owner.TryGetCollectionElementType(
        new ReflectionTypeInfo(AssignabilityClosed(AssignabilityHashSetOpen(), typeof(string))),
        out element)
    assert AssignabilityTypeName(element) == "System.String"
    assert owner.TryGetCollectionElementType(
        new ReflectionTypeInfo(AssignabilityClosed(AssignabilityEnumerableOpen(), typeof(int))),
        out element)
    assert AssignabilityTypeName(element) == "System.Int32"

    // An OPEN definition names no element type. This is the one place the reflection arm differs
    // from a naive "is it generic" test, and it is load-bearing: answering with the type PARAMETER
    // would hand a caller a `T` as if it were the element.
    assert !owner.TryGetCollectionElementType(
        new ReflectionTypeInfo(AssignabilityListOpen()),
        out element)
    assert BuiltInTypes.IsUnknown(element)

    // The reflection arm is deliberately NARROWER than the generic one: the three read-only and
    // sorted spellings the generic arm accepts have no counterpart here.
    assert !owner.TryGetCollectionElementType(
        new ReflectionTypeInfo(AssignabilityClosed(AssignabilitySortedSetOpen(), typeof(int))),
        out element)
    assert !owner.TryGetCollectionElementType(
        new ReflectionTypeInfo(AssignabilityClosed(AssignabilityReadOnlyListOpen(), typeof(int))),
        out element)
    assert !owner.TryGetCollectionElementType(
        new ReflectionTypeInfo(AssignabilityClosed(AssignabilityReadOnlyCollectionOpen(), typeof(int))),
        out element)
    assert !owner.TryGetCollectionElementType(
        new ReflectionTypeInfo(AssignabilityDictionaryClosed()),
        out element)
    assert !owner.TryGetCollectionElementType(new ReflectionTypeInfo(typeof(string)), out element)
}

test "an array widens to a span only nominally and only on the exact element type" {
    path := "/tmp/assign-span.nl"
    declarationContext := AssignabilityContext(path)
    owner := new AnalyzerAssignabilityFacts(declarationContext, null)
    spanOpen := AssignabilitySpanOpen()
    readOnlySpanOpen := AssignabilityReadOnlySpanOpen()

    assert owner.IsArrayToSpanAssignable(
        AssignabilityKnownGeneric("Span", spanOpen, BuiltInTypes.Int),
        new ArrayTypeInfo(BuiltInTypes.Int))
    assert owner.IsArrayToSpanAssignable(
        AssignabilityKnownGeneric("ReadOnlySpan", readOnlySpanOpen, BuiltInTypes.Int),
        new ArrayTypeInfo(BuiltInTypes.Int))

    // The element type must be IDENTICAL — a span is not variant and not numerically widening.
    assert !owner.IsArrayToSpanAssignable(
        AssignabilityKnownGeneric("Span", spanOpen, BuiltInTypes.Long),
        new ArrayTypeInfo(BuiltInTypes.Int))
    assert !owner.IsArrayToSpanAssignable(
        AssignabilityKnownGeneric("Span", spanOpen, BuiltInTypes.Object),
        new ArrayTypeInfo(BuiltInTypes.String))

    // An alias is resolved on BOTH halves before the identity comparison.
    meters := new AliasTypeInfo(new SimpleTypeReference("int"))
    declarationContext.RegisterDeclaredAlias(path, meters)
    alias := meters as TypeInfo
    assert owner.IsArrayToSpanAssignable(
        AssignabilityKnownGeneric("Span", spanOpen, alias),
        new ArrayTypeInfo(BuiltInTypes.Int))
    assert owner.IsArrayToSpanAssignable(
        AssignabilityKnownGeneric("Span", spanOpen, BuiltInTypes.Int),
        new ArrayTypeInfo(alias))

    // NOMINAL on the target: a source-declared `Span<T>` of the program's own does not acquire the
    // conversion, and neither does another runtime generic that merely takes one argument.
    assert !owner.IsArrayToSpanAssignable(
        AssignabilitySpelledGeneric("Span", BuiltInTypes.Int),
        new ArrayTypeInfo(BuiltInTypes.Int))
    assert !owner.IsArrayToSpanAssignable(
        AssignabilityKnownGeneric("List", AssignabilityListOpen(), BuiltInTypes.Int),
        new ArrayTypeInfo(BuiltInTypes.Int))

    // And the source must be an array: a list of the element type is not a span source.
    assert !owner.IsArrayToSpanAssignable(
        AssignabilityKnownGeneric("Span", spanOpen, BuiltInTypes.Int),
        AssignabilityKnownGeneric("List", AssignabilityListOpen(), BuiltInTypes.Int))
}

test "function-type assignability compares arity, skips inferred parameters and reverses direction" {
    owner := AssignabilityOwner("/tmp/assign-functions.nl")

    // Identical signatures need no recursion at all beyond the pairs themselves.
    assert AssignabilityDecisionShape(owner.ClassifyFunctionTypeAssignability(
        AssignabilityFunction(BuiltInTypes.Void, AssignabilityNoParameters()),
        AssignabilityFunction(BuiltInTypes.Void, AssignabilityNoParameters())))
        == "pending [void<-void]"

    // Arity disagreement is decided immediately.
    assert AssignabilityDecisionShape(owner.ClassifyFunctionTypeAssignability(
        AssignabilityFunction(BuiltInTypes.Void, AssignabilityArgs(BuiltInTypes.Int)),
        AssignabilityFunction(BuiltInTypes.Void, AssignabilityNoParameters())))
        == "decided:false"
    assert AssignabilityDecisionShape(owner.ClassifyFunctionTypeAssignability(
        AssignabilityFunction(BuiltInTypes.Void, AssignabilityNoParameters()),
        AssignabilityFunction(BuiltInTypes.Void, AssignabilityArgs(BuiltInTypes.Int))))
        == "decided:false"

    // THE DIRECTIONS. A parameter pair is handed back source ← target; the return pair is handed
    // back target ← source. Getting this backwards would silently invert variance.
    assert AssignabilityDecisionShape(owner.ClassifyFunctionTypeAssignability(
        AssignabilityFunction(BuiltInTypes.String, AssignabilityArgs(BuiltInTypes.Int)),
        AssignabilityFunction(BuiltInTypes.Object, AssignabilityArgs(BuiltInTypes.Long))))
        == "pending [int<-long] [object<-string]"

    // An INFERRED source parameter is accepted without a pair rather than rejected, because a
    // lambda still being inferred must not be pre-judged.
    assert AssignabilityDecisionShape(owner.ClassifyFunctionTypeAssignability(
        AssignabilityFunction(BuiltInTypes.Void, AssignabilityArgs(BuiltInTypes.Unknown)),
        AssignabilityFunction(BuiltInTypes.Void, AssignabilityArgs(BuiltInTypes.Int))))
        == "pending [void<-void]"

    // An unknown or absent RETURN drops the return pair entirely, and with no parameters left the
    // whole relation is decided true.
    assert AssignabilityDecisionShape(owner.ClassifyFunctionTypeAssignability(
        AssignabilityFunction(BuiltInTypes.Unknown, AssignabilityNoParameters()),
        AssignabilityFunction(BuiltInTypes.Void, AssignabilityNoParameters())))
        == "decided:true"
    assert AssignabilityDecisionShape(owner.ClassifyFunctionTypeAssignability(
        AssignabilityFunction(null, AssignabilityNoParameters()),
        AssignabilityFunction(BuiltInTypes.Void, AssignabilityNoParameters())))
        == "decided:true"
    assert AssignabilityDecisionShape(owner.ClassifyFunctionTypeAssignability(
        AssignabilityFunction(BuiltInTypes.Void, AssignabilityNoParameters()),
        AssignabilityFunction(null, AssignabilityNoParameters())))
        == "decided:true"

    // A NULL parameter list counts as zero parameters on either side.
    nullParameters := new FunctionTypeInfo()
    nullParameters.ReturnType = BuiltInTypes.Void
    assert AssignabilityDecisionShape(owner.ClassifyFunctionTypeAssignability(
        nullParameters,
        AssignabilityFunction(BuiltInTypes.Void, AssignabilityNoParameters())))
        == "pending [void<-void]"
    assert AssignabilityDecisionShape(owner.ClassifyFunctionTypeAssignability(
        nullParameters,
        AssignabilityFunction(BuiltInTypes.Void, AssignabilityArgs(BuiltInTypes.Int))))
        == "decided:false"
}

test "a callable reference binds only to a function, the two delegate generics, or a real delegate" {
    owner := AssignabilityOwner("/tmp/assign-callable.nl")

    assert owner.CanBindCallableReferenceToExpectedType(
        AssignabilityFunction(BuiltInTypes.Void, AssignabilityNoParameters()))
    assert owner.CanBindCallableReferenceToExpectedType(
        AssignabilitySpelledGeneric("Func", BuiltInTypes.Int))
    assert owner.CanBindCallableReferenceToExpectedType(
        AssignabilitySpelledGeneric("Action", BuiltInTypes.Int))

    // The two names are exact; nothing else spelled generically binds a callable reference.
    assert !owner.CanBindCallableReferenceToExpectedType(
        AssignabilitySpelledGeneric("List", BuiltInTypes.Int))
    assert !owner.CanBindCallableReferenceToExpectedType(
        AssignabilitySpelledGeneric("func", BuiltInTypes.Int))
    assert !owner.CanBindCallableReferenceToExpectedType(BuiltInTypes.Object)
    assert !owner.CanBindCallableReferenceToExpectedType(BuiltInTypes.String)
    assert !owner.CanBindCallableReferenceToExpectedType(new ArrayTypeInfo(BuiltInTypes.Int))

    // The shells are transparent, so `Func<int>?` still binds.
    assert owner.CanBindCallableReferenceToExpectedType(
        new NullableTypeInfo(AssignabilitySpelledGeneric("Func", BuiltInTypes.Int)))
    assert owner.CanBindCallableReferenceToExpectedType(
        new ObliviousTypeInfo(AssignabilitySpelledGeneric("Action", BuiltInTypes.Int)))
    assert !owner.CanBindCallableReferenceToExpectedType(
        new NullableTypeInfo(BuiltInTypes.String))

    // A runtime delegate TYPE is recognized through the callable-reference facts even with no
    // metadata bag at all, because that classification reads the CLR base identity.
    assert owner.CanBindCallableReferenceToExpectedType(
        new ReflectionTypeInfo(AssignabilityActionType()))
    assert owner.CanBindCallableReferenceToExpectedType(
        new ReflectionTypeInfo(AssignabilityFuncClosed()))
    assert !owner.CanBindCallableReferenceToExpectedType(
        new ReflectionTypeInfo(typeof(string)))
    assert !owner.CanBindCallableReferenceToExpectedType(
        new ReflectionTypeInfo(AssignabilityClosed(AssignabilityListOpen(), typeof(int))))
}

test "without metadata facts nothing is a delegate type" {
    owner := AssignabilityOwner("/tmp/assign-delegate-nofacts.nl")

    // The delegate test reads the well-known bag, so with no bag it answers false for everything —
    // including the types that plainly ARE delegates. That state is live, not defensive: it is what
    // an analyzer looks like before it has loaded its MetadataLoadContext.
    assert !owner.IsDelegateType(AssignabilityActionType())
    assert !owner.IsDelegateType(AssignabilityFuncClosed())
    assert !owner.IsDelegateType(typeof(string))
    assert !owner.IsDelegateType(AssignabilityOpen("System.Delegate, System.Private.CoreLib"))
}

test "with metadata facts a concrete delegate is one and the two abstract roots are not" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        core := context.LoadFromAssemblyName("System.Runtime")
        facts := new AnalyzerWellKnownTypes(context, core)
        owner := new AnalyzerAssignabilityFacts(
            AssignabilityContext("/tmp/assign-delegate-facts.nl"),
            facts)

        action := core.GetType("System.Action")
        assert action != null
        assert owner.IsDelegateType(action)

        eventHandler := core.GetType("System.EventHandler")
        assert eventHandler != null
        assert owner.IsDelegateType(eventHandler)

        funcOpen := core.GetType("System.Func`2")
        assert funcOpen != null
        assert owner.IsDelegateType(funcOpen)

        // The two ROOTS are excluded by name: neither names a callable signature, so binding a
        // method group to one has to fail rather than silently succeed.
        delegateRoot := core.GetType("System.Delegate")
        assert delegateRoot != null
        assert !owner.IsDelegateType(delegateRoot)

        multicastRoot := core.GetType("System.MulticastDelegate")
        assert multicastRoot != null
        assert !owner.IsDelegateType(multicastRoot)

        // And a non-delegate is not one, however ordinary.
        stringType := core.GetType("System.String")
        assert stringType != null
        assert !owner.IsDelegateType(stringType)

        // The bag's types come from the load context, so a HOST-RUNTIME delegate is not assignable
        // to the metadata `System.Delegate` and answers false. Callers pass load-context types.
        assert !owner.IsDelegateType(AssignabilityActionType())
    } finally {
        scan.Dispose()
    }
}
