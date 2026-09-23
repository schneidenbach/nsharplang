namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Columnar


// HOW `for x in e` LOWERS, decided once and handed to the emitter as four handles and two small
// integers.
//
// THE SHAPE IS THE C# ONE (Roslyn's `ForEachLoopBinder` and its lowering), and the order is the
// language rule rather than a preference:
//
//   ARRAY   an index loop over `ldlen` — no enumerator, no disposal;
//   STRING  an index loop over `get_Length` / `get_Chars` — the language special-cases `string`
//           because its `CharEnumerator` is a heap allocation nobody asked for;
//   PATTERN an accessible parameterless `GetEnumerator()` whose result carries a readable `Current`
//           and a parameterless `bool MoveNext()` — the shape that makes `List<T>`, `Dictionary<K,V>`,
//           `Span<T>` and every user type with a struct enumerator iterate WITHOUT a boxing
//           interface call, and without any of them being NAMED here;
//   INTERFACE `IEnumerable<T>` and then the non-generic `IEnumerable`, for a collection that carries
//           no pattern of its own.
//
// A CONSTRUCTION OVER A SOURCE TYPE IS RESOLVED ON ITS OPEN DEFINITION AND REBOUND. Reflecting on a
// closed construction over a source `TypeBuilder` is not possible — `GetMethods` on a
// `TypeBuilderInstantiation` throws — so for those the pattern is found on `List<>` and every handle
// it yields is rebound onto `List<Widget>` through the one closed-generic member owner the rest of
// the emitter uses, with the ELEMENT type substituted by POSITION: `Dictionary<string, Widget>`
// iterates `KeyValuePair<string, Widget>` over a `Widget` whose type does not exist yet. A
// construction with no builder-bound argument is reflected on DIRECTLY, because its own members are
// the handles the emitter wants and rebinding them would only be a detour.
//
// DISPOSAL HAS FOUR ANSWERS AND THE CHOICE IS THE C# ONE:
//   * a VALUE-TYPE enumerator implementing `IDisposable` is disposed through a `constrained.` call —
//     no box, and the `Dispose` runs on the enumerator's own storage rather than on a copy;
//   * a REFERENCE enumerator implementing `IDisposable` is null-checked and disposed;
//   * a non-sealed reference enumerator that does NOT implement it is tested at runtime;
//   * a BY-REF-LIKE enumerator cannot implement an interface at all, so it is disposed only through
//     a pattern `void Dispose()` — and `Span<T>.Enumerator` has none, which is why a loop over a span
//     has no protected region.
// A sealed or value-type enumerator with no disposal answers NONE, and the emitted loop then carries
// no `try`/`finally` at all.
class ColumnarForeachPlan {

    // 1 = array index loop, 2 = string index loop, 3 = enumerator.
    Kind: int
    ElementType: Type

    // Enumerator shapes only.
    GetEnumeratorMethod: MethodInfo?
    EnumeratorType: Type?
    MoveNextMethod: MethodInfo?
    CurrentGetter: MethodInfo?
    CurrentIsByRef: bool

    // Index-loop shapes only: the `int Length` a by-ref-like collection is walked by, and the
    // element read its `ref readonly` indexer cannot express.
    LengthGetter: MethodInfo?
    ElementRead: ColumnarReadOnlySpanElementRead?

    // 0 = none, 1 = constrained call on a value-type enumerator, 2 = null check then interface call,
    // 3 = runtime `isinst` test then interface call, 4 = direct call on a by-ref-like enumerator.
    DisposeKind: int
    DisposeMethod: MethodInfo?

    constructor(kind: int, elementType: Type) {
        if elementType == null {
            throw new InvalidOperationException("A foreach plan cannot be built without an element type.")
        }

        Kind = kind
        ElementType = elementType
        GetEnumeratorMethod = null
        EnumeratorType = null
        MoveNextMethod = null
        CurrentGetter = null
        CurrentIsByRef = false
        LengthGetter = null
        ElementRead = null
        DisposeKind = 0
        DisposeMethod = null
    }
}

class ColumnarForeachLoopPlanner {

    // THE PLAN FOR ITERATING THIS TYPE, or null when nothing here iterates it and the loop declines.
    static func Plan(collectionType: Type, definitions: IReadOnlyDictionary<string, ColumnarStructDef>): ColumnarForeachPlan? {
        if collectionType == null {
            return null
        }

        if ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(collectionType) {
            elementType := collectionType.GetElementType()
            if elementType == null {
                return null
            }

            return new ColumnarForeachPlan(1, elementType)
        }

        if collectionType == typeof(string) {
            return new ColumnarForeachPlan(2, typeof(char))
        }

        sourceDefinition := ColumnarSourceDefinitionResolver.FindDirectType(definitions, collectionType)
        if sourceDefinition != null {
            return PlanSourceCollection(sourceDefinition, collectionType, definitions)
        }

        if RuntimeTypeShapeFacts.ContainsBuilderBoundType(collectionType) && !collectionType.get_IsGenericType() {
            return null
        }

        return PlanExternalCollection(collectionType, definitions)
    }

    // A SOURCE COLLECTION ANSWERS FROM ITS OWN DEFINITION. Its members are `MethodBuilder`s, which
    // ARE `MethodInfo`s, so the plan the emitter consumes is the same shape either way — only the
    // lookup differs, because a `TypeBuilder` cannot be reflected on before it is baked.
    static func PlanSourceCollection(definition: ColumnarStructDef, collectionType: Type, definitions: IReadOnlyDictionary<string, ColumnarStructDef>): ColumnarForeachPlan? {
        getEnumerator := FindSourceParameterlessMethod(definition, "GetEnumerator")
        if getEnumerator != null {
            enumeratorType := getEnumerator.ReturnType
            plan := BuildEnumeratorPlan(getEnumerator.Builder, enumeratorType, definitions)
            if plan != null {
                return plan
            }
        }

        return PlanThroughDeclaredInterfaces(definition, definitions)
    }

    // A SOURCE TYPE WITH NO PATTERN OF ITS OWN STILL ITERATES THROUGH THE SEQUENCE INTERFACE IT
    // NAMES. The interface is an ordinary runtime type, so the external walk owns it from here.
    static func PlanThroughDeclaredInterfaces(definition: ColumnarStructDef, definitions: IReadOnlyDictionary<string, ColumnarStructDef>): ColumnarForeachPlan? {
        index := 0
        while index < definition.ExternalInterfaces.Count {
            candidate := definition.ExternalInterfaces[index]
            if ForeachPatternFacts.MatchesConstructedDefinition(candidate, ForeachPatternFacts.SequenceInterfaceName()) || candidate.FullName == ForeachPatternFacts.NonGenericSequenceName() {
                plan := PlanExternalCollection(candidate, definitions)
                if plan != null {
                    return plan
                }
            }

            index = index + 1
        }

        return null
    }

    static func FindSourceParameterlessMethod(definition: ColumnarStructDef, name: string): ColumnarInstanceMethodDef? {
        overloads: List<ColumnarInstanceMethodDef>? = null
        if definition.MethodOverloads.TryGetValue(name, out overloads) {
            if overloads != null {
                index := 0
                while index < overloads.Count {
                    candidate := overloads[index]
                    if candidate.ParamTypes.Length == 0 {
                        return candidate
                    }

                    index = index + 1
                }
            }
        }

        single: ColumnarInstanceMethodDef? = null
        if definition.Methods.TryGetValue(name, out single) {
            if single != null && single.ParamTypes.Length == 0 {
                return single
            }
        }

        return null
    }

    // THE EXTERNAL WALK, in the language's own order: the pattern, then an index loop for a
    // collection whose pattern cannot be NAMED in emitted IL, then `IEnumerable<T>`, then the
    // non-generic `IEnumerable`. A construction over a source `TypeBuilder` is resolved on its open
    // definition and rebound; every other type answers from itself.
    static func PlanExternalCollection(collectionType: Type, definitions: IReadOnlyDictionary<string, ColumnarStructDef>): ColumnarForeachPlan? {
        definition := collectionType
        if RuntimeTypeShapeFacts.ContainsBuilderBoundType(collectionType) {
            definition = OpenDefinitionOf(collectionType)
        }

        pattern := ForeachPatternFacts.FindPattern(definition)
        if pattern != null && IsReferenceablePattern(pattern) {
            plan := BuildEnumeratorPlan(
                RebindMember(pattern.GetEnumeratorMethod, collectionType),
                Substitute(pattern.EnumeratorType, collectionType),
                definitions
            )
            if plan != null {
                return plan
            }
        }

        indexedPlan := PlanIndexedCollection(collectionType)
        if indexedPlan != null {
            return indexedPlan
        }

        sequenceInterface := ForeachPatternFacts.FindSequenceInterface(definition)
        if sequenceInterface != null {
            closedInterface := Substitute(sequenceInterface, collectionType)
            interfacePlan := PlanThroughSequenceInterface(closedInterface, definitions)
            if interfacePlan != null {
                return interfacePlan
            }
        }

        if ForeachPatternFacts.ImplementsNonGenericSequence(definition) {
            return PlanThroughSequenceInterface(RequiredNonGenericSequenceType(), definitions)
        }

        return null
    }

    static func PlanThroughSequenceInterface(closedInterface: Type, definitions: IReadOnlyDictionary<string, ColumnarStructDef>): ColumnarForeachPlan? {
        openInterface := closedInterface
        if RuntimeTypeShapeFacts.ContainsBuilderBoundType(closedInterface) {
            openInterface = OpenDefinitionOf(closedInterface)
        }
        getEnumerator := ForeachPatternFacts.FindParameterlessInstanceMethod(openInterface, "GetEnumerator")
        if getEnumerator == null {
            return null
        }

        return BuildEnumeratorPlan(
            RebindMember(getEnumerator, closedInterface),
            Substitute(getEnumerator.get_ReturnType(), closedInterface),
            definitions
        )
    }

    // THE ENUMERATOR HALF OF EVERY PATTERN PLAN. The enumerator may be a source `TypeBuilder`, a
    // closed construction over one, or an ordinary runtime type; the three differ only in where
    // `MoveNext` and `Current` are looked up.
    static func BuildEnumeratorPlan(getEnumerator: MethodInfo, enumeratorType: Type, definitions: IReadOnlyDictionary<string, ColumnarStructDef>): ColumnarForeachPlan? {
        if getEnumerator == null || enumeratorType == null {
            return null
        }

        sourceEnumerator := ColumnarSourceDefinitionResolver.FindDirectType(definitions, enumeratorType)
        if sourceEnumerator != null {
            return BuildSourceEnumeratorPlan(getEnumerator, enumeratorType, sourceEnumerator)
        }

        if RuntimeTypeShapeFacts.ContainsBuilderBoundType(enumeratorType) && !enumeratorType.get_IsGenericType() {
            return null
        }

        openEnumerator := enumeratorType
        if RuntimeTypeShapeFacts.ContainsBuilderBoundType(enumeratorType) {
            openEnumerator = OpenDefinitionOf(enumeratorType)
        }
        moveNext := ForeachPatternFacts.FindParameterlessInstanceMethod(openEnumerator, "MoveNext")
        if moveNext == null || !ForeachPatternFacts.IsBoolean(moveNext.get_ReturnType()) {
            return null
        }

        currentGetter := ForeachPatternFacts.FindCurrentGetter(openEnumerator)
        if currentGetter == null {
            return null
        }

        currentType := Substitute(currentGetter.get_ReturnType(), enumeratorType)
        elementType := currentType
        currentIsByRef := currentType.get_IsByRef()
        if currentIsByRef {
            elementType = currentType.GetElementType()
            if elementType == null {
                return null
            }
        }

        plan := new ColumnarForeachPlan(3, elementType)
        plan.GetEnumeratorMethod = getEnumerator
        plan.EnumeratorType = enumeratorType
        plan.MoveNextMethod = RebindMember(moveNext, enumeratorType)
        plan.CurrentGetter = RebindMember(currentGetter, enumeratorType)
        plan.CurrentIsByRef = currentIsByRef
        ApplyExternalDisposal(plan, openEnumerator, enumeratorType)
        return plan
    }

    static func BuildSourceEnumeratorPlan(getEnumerator: MethodInfo, enumeratorType: Type, enumeratorDefinition: ColumnarStructDef): ColumnarForeachPlan? {
        moveNext := FindSourceParameterlessMethod(enumeratorDefinition, "MoveNext")
        if moveNext == null || moveNext.ReturnType != typeof(bool) {
            return null
        }

        currentProperty: ColumnarPropertyDef? = null
        if !enumeratorDefinition.Properties.TryGetValue("Current", out currentProperty) {
            return null
        }

        if currentProperty == null || currentProperty.GetterParameterCount != 0 {
            return null
        }

        plan := new ColumnarForeachPlan(3, currentProperty.PropertyType)
        plan.GetEnumeratorMethod = getEnumerator
        plan.EnumeratorType = enumeratorType
        plan.MoveNextMethod = moveNext.Builder
        plan.CurrentGetter = currentProperty.Getter
        plan.CurrentIsByRef = false
        ApplySourceDisposal(plan, enumeratorDefinition)
        return plan
    }

    // A SOURCE ENUMERATOR DISPOSES THROUGH THE INTERFACE IT NAMES. `IDisposable` is an external
    // interface even when the enumerator is not, so the reference-vs-value choice is the same one
    // the external walk makes.
    static func ApplySourceDisposal(plan: ColumnarForeachPlan, enumeratorDefinition: ColumnarStructDef) {
        if !NamesExternalDisposable(enumeratorDefinition) {
            return
        }

        dispose := RequiredDisposeMethod()
        plan.DisposeMethod = dispose
        if enumeratorDefinition.IsReference {
            plan.DisposeKind = 2
            return
        }

        plan.DisposeKind = 1
    }

    static func NamesExternalDisposable(definition: ColumnarStructDef): bool {
        index := 0
        while index < definition.ExternalInterfaces.Count {
            if definition.ExternalInterfaces[index].FullName == ForeachPatternFacts.DisposableName() {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func ApplyExternalDisposal(plan: ColumnarForeachPlan, openEnumerator: Type, enumeratorType: Type) {
        if openEnumerator.get_IsByRefLike() {
            patternDispose := ForeachPatternFacts.FindPatternDispose(openEnumerator)
            if patternDispose != null {
                plan.DisposeKind = 4
                plan.DisposeMethod = RebindMember(patternDispose, enumeratorType)
            }

            return
        }

        if ForeachPatternFacts.ImplementsDisposable(openEnumerator) {
            plan.DisposeMethod = RequiredDisposeMethod()
            if openEnumerator.get_IsValueType() {
                plan.DisposeKind = 1
                return
            }

            plan.DisposeKind = 2
            return
        }

        if openEnumerator.get_IsValueType() || openEnumerator.get_IsSealed() {
            return
        }

        plan.DisposeMethod = RequiredDisposeMethod()
        plan.DisposeKind = 3
    }

    // A MEMBER THE EMITTED ASSEMBLY CANNOT NAME IS NOT A USABLE PATTERN. A signature carrying
    // REQUIRED CUSTOM MODIFIERS — `ref readonly T` is `T&` with `modreq(InAttribute)` — loses them
    // when the metadata writer emits a `MemberRef`, and the resulting reference resolves to nothing
    // at run time ("Method not found: '!0 ByRef Enumerator.get_Current()'"). `ReadOnlySpan<T>` is
    // exactly that shape, so its pattern is refused HERE rather than emitted and discovered broken;
    // the index arm below is what carries it instead.
    static func IsReferenceablePattern(pattern: ForeachEnumeratorPattern): bool {
        return !HasRequiredModifiers(pattern.GetEnumeratorMethod) && !HasRequiredModifiers(pattern.MoveNextMethod) && !HasRequiredModifiers(pattern.CurrentGetter)
    }

    static func HasRequiredModifiers(method: MethodInfo): bool {
        try {
            returnParameter := method.get_ReturnParameter()
            if returnParameter != null && returnParameter.GetRequiredCustomModifiers().Length != 0 {
                return true
            }
        } catch {
            return true
        }

        return false
    }

    // THE INDEX LOOP FOR A COLLECTION WHOSE ELEMENTS THE EMITTER CAN READ BY POSITION. This is the
    // arm a by-ref-like collection reaches when its enumerator cannot be named: C# lowers a `foreach`
    // over a span to an index loop for its own reasons, and the same loop is the only one that can be
    // emitted here. The element read itself is owned by `ColumnarReadOnlySpanElementRead`, which is
    // the same door the index EXPRESSION goes through — a `ref readonly` indexer cannot be called
    // either, and there is exactly one workaround, not two.
    static func PlanIndexedCollection(collectionType: Type): ColumnarForeachPlan? {
        elementRead := ColumnarReadOnlySpanElementRead.Resolve(collectionType)
        if elementRead == null {
            return null
        }

        lengthProperty := collectionType.GetProperty("Length", BindingFlags.Public | BindingFlags.Instance)
        if lengthProperty == null {
            return null
        }

        lengthGetter := lengthProperty.get_GetMethod()
        if lengthGetter == null || lengthGetter.get_ReturnType() != typeof(int) {
            return null
        }

        plan := new ColumnarForeachPlan(4, elementRead.ElementType)
        plan.LengthGetter = lengthGetter
        plan.ElementRead = elementRead
        return plan
    }

    // ---- the closed-generic mechanics ---------------------------------------------------------

    static func OpenDefinitionOf(candidate: Type): Type {
        if !candidate.get_IsGenericType() || candidate.get_IsGenericTypeDefinition() {
            return candidate
        }

        try {
            return candidate.GetGenericTypeDefinition()
        } catch {
            return candidate
        }
    }

    static func Substitute(openType: Type, closedOwner: Type): Type {
        return ColumnarClosedGenericMemberResolver.SubstituteInterfaceMemberType(openType, closedOwner)
    }

    static func RebindMember(openMethod: MethodInfo, closedOwner: Type): MethodInfo {
        return ColumnarClosedGenericMemberResolver.RebindOntoClosedOwner(openMethod, closedOwner)
    }

    static func RequiredDisposeMethod(): MethodInfo {
        dispose := typeof(IDisposable).GetMethod("Dispose")
        if dispose == null {
            throw new InvalidOperationException("The foreach lowering requires System.IDisposable.Dispose.")
        }

        return dispose
    }

    static func RequiredNonGenericSequenceType(): Type {
        sequence := Type.GetType(ForeachPatternFacts.NonGenericSequenceName())
        if sequence == null {
            throw new InvalidOperationException("The foreach lowering requires System.Collections.IEnumerable.")
        }

        return sequence
    }
}

// READING ONE ELEMENT OF A `ReadOnlySpan<T>` AT A POSITION, without calling its indexer.
//
// `ReadOnlySpan<T>.this[int]` returns `ref readonly T`, whose signature carries
// `modreq(InAttribute)`; the metadata writer drops required modifiers when it emits a `MemberRef`,
// so a call to it resolves to nothing at run time. `Slice(start, 1)` → `MemoryMarshal.AsBytes` →
// `MemoryMarshal.Read<T>` reads the same element through three signatures that carry none, and it is
// what both the index EXPRESSION and the `foreach` INDEX LOOP go through — one workaround, resolved
// once, rather than the same three lookups written twice.
class ColumnarReadOnlySpanElementRead {
    ElementType: Type
    SliceMethod: MethodInfo
    AsBytesMethod: MethodInfo
    ReadMethod: MethodInfo

    constructor(elementType: Type, sliceMethod: MethodInfo, asBytesMethod: MethodInfo, readMethod: MethodInfo) {
        if elementType == null || sliceMethod == null || asBytesMethod == null || readMethod == null {
            throw new InvalidOperationException("A read-only span element read cannot be built from missing members.")
        }

        ElementType = elementType
        SliceMethod = sliceMethod
        AsBytesMethod = asBytesMethod
        ReadMethod = readMethod
    }

    static func Resolve(spanType: Type): ColumnarReadOnlySpanElementRead? {
        if !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(spanType) {
            return null
        }

        elementType := spanType.GetGenericArguments()[0]
        slice := spanType.GetMethod("Slice", [typeof(int), typeof(int)])
        asBytes := FindMarshalMethod("AsBytes", true)
        read := FindMarshalMethod("Read", false)
        if slice == null || asBytes == null || read == null {
            return null
        }

        return new ColumnarReadOnlySpanElementRead(elementType, slice, asBytes.MakeGenericMethod([elementType]), read.MakeGenericMethod([elementType]))
    }

    // `AsBytes` takes an OPEN `ReadOnlySpan<T>`; `Read` takes the CLOSED `ReadOnlySpan<byte>`. The two
    // overload sets differ only in that, which is why one finder answers both.
    static func FindMarshalMethod(name: string, openSpanParameter: bool): MethodInfo? {
        candidates := typeof(System.Runtime.InteropServices.MemoryMarshal).GetMethods(BindingFlags.Public | BindingFlags.Static)
        index := 0
        while index < candidates.Length {
            candidate := candidates[index]
            if candidate.get_Name() == name && candidate.get_IsGenericMethodDefinition() {
                parameters := candidate.GetParameters()
                if parameters.Length == 1 {
                    parameterType := parameters[0].get_ParameterType()
                    if openSpanParameter {
                        if parameterType.get_IsGenericType() && parameterType.GetGenericTypeDefinition() == typeof(ReadOnlySpan<int>).GetGenericTypeDefinition() {
                            return candidate
                        }
                    } else {
                        if parameterType == typeof(ReadOnlySpan<byte>) {
                            return candidate
                        }
                    }
                }
            }

            index = index + 1
        }

        return null
    }
}
