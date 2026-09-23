namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit
import System.Threading.Tasks


// Canonical declaration/body signature resolution owns the same shape policy as the historical
// emitter, but selects a structural reference together with its live reflection companion. The
// Type-out entry points below are intentionally thin compatibility surfaces: callers that still
// consume Type receive the companion selected here, rather than a Type selected elsewhere and
// decorated after the fact.
class ColumnarCanonicalTypeResolver {

    // Every non-generic public exception the RUNTIME's own assembly declares, indexed by simple name.
    // Names two different namespaces share are dropped rather than resolved to one of them.
    static readonly RuntimeExceptionsBySimpleName: Dictionary<string, Type> = BuildRuntimeExceptionIndex()

    static func TryResolveType(
        canonical: string,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out resolvedType: Type
    ): bool {
        table := structRegistry.StructuralTypeReferences
        selected := ColumnarSelectedTypeReference.Missing(table)
        resolved := TrySelectRuntimeType(
            canonical,
            enumRegistry,
            structRegistry,
            unionRegistry,
            out selected
        )
        if selected.HasRuntimeType {
            resolvedType = selected.RuntimeType
        } else {
            resolvedType = null
        }
        return resolved
    }

    static func TryResolveTypeWithTypeParams(
        canonical: string,
        typeParams: IReadOnlyDictionary<string, Type>,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out resolvedType: Type
    ): bool {
        table := structRegistry.StructuralTypeReferences
        selected := ColumnarSelectedTypeReference.Missing(table)
        resolved := TrySelectRuntimeTypeWithTypeParams(
            canonical,
            typeParams,
            enumRegistry,
            structRegistry,
            unionRegistry,
            out selected
        )
        if selected.HasRuntimeType {
            resolvedType = selected.RuntimeType
        } else {
            resolvedType = null
        }
        return resolved
    }

    static func TryResolveMemberType(
        canonical: string,
        def: ColumnarStructDef,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out resolvedType: Type
    ): bool {
        typeParameters := def.GenericParameters
        if typeParameters != null {
            return TryResolveTypeWithTypeParams(
                canonical,
                typeParameters,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out resolvedType
            )
        }
        return TryResolveType(
            canonical,
            enumRegistry,
            structRegistry,
            unionRegistry,
            out resolvedType
        )
    }

    static func TrySelectMemberType(
        canonical: string,
        def: ColumnarStructDef,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out selected: ColumnarSelectedTypeReference
    ): bool {
        typeParameters := def.GenericParameters
        if typeParameters != null {
            return TrySelectRuntimeTypeWithTypeParams(
                canonical,
                typeParameters,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out selected
            )
        }
        return TrySelectRuntimeType(
            canonical,
            enumRegistry,
            structRegistry,
            unionRegistry,
            out selected
        )
    }

    static func TryResolveExactRuntimeType(
        fullName: string,
        out resolvedType: Type
    ): bool {
        resolvedType = Type.GetType(fullName)
        return resolvedType != null
    }

    static func TrySelectRuntimeType(
        canonical: string,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out selected: ColumnarSelectedTypeReference
    ): bool {
        table := structRegistry.StructuralTypeReferences
        selected = ColumnarSelectedTypeReference.Missing(table)

        claimed := false
        if structRegistry.Resolver.TryResolveSelected(canonical, out selected, out claimed) {
            if IsOpenGenericUnionDefinition(selected.RuntimeType, unionRegistry) {
                selected = ColumnarSelectedTypeReference.Missing(table)
                return false
            }

            validationCanonical := structRegistry.Resolver.RuntimeGenericValidationCanonical(selected.RuntimeType)
            if validationCanonical == null {
                return true
            }
            if validationCanonical == "*" {
                if ColumnarTypeOfPlanner.IsSupportedType(selected.RuntimeType) {
                    return true
                }
                selected = ColumnarSelectedTypeReference.RejectedWithRuntime(table, selected.RuntimeType)
                return false
            }
            return TrySelectRuntimeType(
                validationCanonical,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out selected
            )
        }
        if claimed {
            selected = ColumnarSelectedTypeReference.Missing(table)
            return false
        }

        if canonical.StartsWith("&", StringComparison.Ordinal) {
            element := ColumnarSelectedTypeReference.Missing(table)
            if canonical.Length > 1 && TrySelectRuntimeType(
                canonical.Substring(1),
                enumRegistry,
                structRegistry,
                unionRegistry,
                out element
            ) && IsSupportedByRefElementType(element.RuntimeType) {
                runtimeType := element.RuntimeType.MakeByRefType()
                selected = table.SelectByRef(runtimeType, element)
                return true
            }
            selected = ColumnarSelectedTypeReference.Missing(table)
            return false
        }

        unionArms := ColumnarTypeOfPlanner.SplitTopLevelPipes(canonical)
        if unionArms.Count == 2 {
            firstArm := ColumnarSelectedTypeReference.Missing(table)
            secondArm := ColumnarSelectedTypeReference.Missing(table)
            if TrySelectRuntimeType(
                unionArms[0],
                enumRegistry,
                structRegistry,
                unionRegistry,
                out firstArm
            ) && TrySelectRuntimeType(
                unionArms[1],
                enumRegistry,
                structRegistry,
                unionRegistry,
                out secondArm
            ) && ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(firstArm.RuntimeType) && ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(secondArm.RuntimeType) && !ColumnarTypeEquivalenceFacts.TypesEquivalent(firstArm.RuntimeType, secondArm.RuntimeType) {
                unionDefinition := typeof(object)
                if ColumnarTypeOfPlanner.TryResolveRuntimeGenericDefinition(
                    "NSharpLang.Runtime.Union`2",
                    "NSharpLang.Runtime",
                    out unionDefinition
                ) {
                    runtimeArguments := RuntimeTypes(firstArm, secondArm)
                    runtimeType := unionDefinition.MakeGenericType(runtimeArguments)
                    selected = ConstructedSelection(table, runtimeType, unionDefinition, SelectedPair(firstArm, secondArm))
                    return true
                }
            }
            selected = ColumnarSelectedTypeReference.Missing(table)
            return false
        }
        if unionArms.Count > 0 {
            selected = ColumnarSelectedTypeReference.Missing(table)
            return false
        }

        if canonical.EndsWith("[]", StringComparison.Ordinal) {
            element := ColumnarSelectedTypeReference.Missing(table)
            if TrySelectRuntimeType(
                canonical.Substring(0, canonical.Length - 2),
                enumRegistry,
                structRegistry,
                unionRegistry,
                out element
            ) && ColumnarTypeOfPlanner.IsSupportedElementType(element.RuntimeType) {
                runtimeType := element.RuntimeType.MakeArrayType()
                selected = table.SelectSzArray(runtimeType, element)
                return true
            }
            selected = ColumnarSelectedTypeReference.Missing(table)
            return false
        }

        if canonical.EndsWith("?", StringComparison.Ordinal) {
            element := ColumnarSelectedTypeReference.Missing(table)
            if TrySelectRuntimeType(
                canonical.Substring(0, canonical.Length - 1),
                enumRegistry,
                structRegistry,
                unionRegistry,
                out element
            ) {
                if !element.RuntimeType.get_IsValueType() {
                    selected = element
                    return true
                }
                if ColumnarTypeOfPlanner.IsLiftableNullableElement(element.RuntimeType) {
                    nullableDefinition := ColumnarTypeOfPlanner.RequiredNullableDefinition()
                    runtimeArguments := SelectedRuntimeTypes(SelectedSingle(element))
                    runtimeType := nullableDefinition.MakeGenericType(runtimeArguments)
                    selected = ConstructedSelection(table, runtimeType, nullableDefinition, SelectedSingle(element))
                    return true
                }
            }
            selected = ColumnarSelectedTypeReference.Missing(table)
            return false
        }

        specialType := typeof(object)
        if WellKnownTypeCatalog.TryResolveSpecialKnownType(canonical, out specialType) {
            selected = table.SelectRuntimeType(specialType)
            return true
        }

        runtimeIdentity := ""
        if ColumnarExternalBindingPlans.TryGetRuntimeTypeName(canonical, out runtimeIdentity) {
            runtimeType := Type.GetType(runtimeIdentity)
            if runtimeType != null {
                selected = table.SelectRuntimeType(runtimeType)
                return true
            }
        }

        knownExternal := typeof(object)
        if ColumnarTypeOfPlanner.TryResolveKnownExternalType(canonical, out knownExternal) {
            selected = table.SelectRuntimeType(knownExternal)
            return true
        }

        exceptionType := typeof(object)
        if TryResolveBclExceptionType(canonical, out exceptionType) {
            selected = table.SelectRuntimeType(exceptionType)
            return true
        }

        if canonical.Length >= 2 && canonical[0] == '(' && canonical[canonical.Length - 1] == ')' {
            tupleCanonical := ColumnarTypeCanonicalizer.StripTupleElementNames(canonical).Canonical
            elementCanonicals := ColumnarTypeCanonicalizer.SplitTopLevelCommas(
                tupleCanonical.Substring(1, tupleCanonical.Length - 2)
            )
            tupleDefinition := ColumnarTypeOfPlanner.OpenValueTupleType(elementCanonicals.Count)
            if tupleDefinition != null {
                tupleElements := new ColumnarSelectedTypeReference[](elementCanonicals.Count)
                i := 0
                while i < tupleElements.Length {
                    element := ColumnarSelectedTypeReference.Missing(table)
                    if !TrySelectRuntimeType(
                        elementCanonicals[i],
                        enumRegistry,
                        structRegistry,
                        unionRegistry,
                        out element
                    ) {
                        selected = ColumnarSelectedTypeReference.Missing(table)
                        return false
                    }
                    tupleElements[i] = element
                    i += 1
                }
                runtimeType := tupleDefinition.MakeGenericType(SelectedRuntimeTypes(tupleElements))
                selected = ConstructedSelection(table, runtimeType, tupleDefinition, tupleElements)
                return true
            }
            selected = ColumnarSelectedTypeReference.Missing(table)
            return false
        }

        if canonical.StartsWith("Func<", StringComparison.Ordinal) && canonical[canonical.Length - 1] == '>' {
            return TrySelectDelegateCanonical(
                canonical.Substring(5, canonical.Length - 6),
                true,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out selected
            )
        }

        genericOpen := canonical.IndexOf('<')
        if genericOpen > 0 && canonical[canonical.Length - 1] == '>' {
            unqualifiedGeneric := UnqualifyGenericHead(canonical, genericOpen)
            if unqualifiedGeneric != canonical {
                terminalRejection := false
                preserveExactHead := ShouldPreserveSemanticGenericHead(
                    canonical,
                    genericOpen,
                    structRegistry,
                    out terminalRejection
                )
                if terminalRejection {
                    selected = ColumnarSelectedTypeReference.Missing(table)
                    return false
                }
                if !preserveExactHead {
                    return TrySelectRuntimeType(
                        unqualifiedGeneric,
                        enumRegistry,
                        structRegistry,
                        unionRegistry,
                        out selected
                    )
                }
            }

            if IsCollectionHeadShadowedByUserType(
                canonical.Substring(0, genericOpen),
                enumRegistry,
                structRegistry,
                unionRegistry
            ) {
                selected = ColumnarSelectedTypeReference.Missing(table)
                return false
            }

            if TrySelectClosedUserGeneric(
                canonical,
                genericOpen,
                null,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out selected
            ) {
                return true
            }

            return TrySelectOrdinaryGenericFamily(
                canonical,
                genericOpen,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out selected
            )
        }

        enumDefinition: ColumnarEnumDef = null
        if enumRegistry.TryGetValue(canonical, out enumDefinition) && enumDefinition != null {
            if enumDefinition.IsStringBacked {
                selected = table.SelectSourceDefinition(
                    enumDefinition.DeclaredTypeName,
                    typeof(string)
                )
            } else {
                selected = table.SelectSourceDefinition(
                    enumDefinition.DeclaredTypeName,
                    enumDefinition.EnumType
                )
            }
            return true
        }

        structDefinition: ColumnarStructDef = null
        if structRegistry.TryGetValue(canonical, out structDefinition) && structDefinition != null {
            selected = table.SelectSourceDefinition(
                structDefinition.DeclaredTypeName,
                structDefinition.Builder
            )
            return true
        }

        unionDefinition: ColumnarUnionDef = null
        if unionRegistry.TryGetValue(canonical, out unionDefinition) && unionDefinition != null {
            if unionDefinition.Base.get_IsGenericTypeDefinition() {
                selected = ColumnarSelectedTypeReference.Missing(table)
                return false
            }
            selected = table.SelectSourceDefinition(
                unionDefinition.DeclaredTypeName,
                unionDefinition.Base
            )
            return true
        }

        if canonical == "Action" {
            selected = table.SelectRuntimeType(typeof(Action))
            return true
        }

        builtinType := typeof(object)
        if WellKnownTypeCatalog.TryResolveBuiltinType(canonical, out builtinType) {
            selected = table.SelectRuntimeType(builtinType)
            return true
        }

        selected = ColumnarSelectedTypeReference.Missing(table)
        return false
    }

    // THE MODELED ROWS FIRST, THEN THE GENERAL ARM. Each row below states a narrower ELEMENT policy
    // for a family whose lowerings care about it — span elements, collection elements, dictionary
    // keys — and those policies are why the rows exist. What the rows are NOT is the list of BCL
    // generics a source file may write over its own type parameters: when a row declines, or names a
    // head no row covers, `TrySelectExternalGenericConstruction` resolves the definition and closes
    // it the way the CLR does. A rejection the modeled row recorded with its exact runtime shape
    // survives a general-arm decline, so the caller still sees the row's diagnosis.
    static func TrySelectTypeParameterGenericFamily(
        canonical: string,
        genericOpen: int,
        typeParams: IReadOnlyDictionary<string, Type>,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out selected: ColumnarSelectedTypeReference
    ): bool {
        claimedHead := false
        if TrySelectTypeParameterModeledFamily(
            canonical,
            genericOpen,
            typeParams,
            enumRegistry,
            structRegistry,
            unionRegistry,
            out claimedHead,
            out selected
        ) {
            return true
        }

        // A ROW THAT OWNS THIS HEAD HAS ALREADY ANSWERED. Its element policy — a dictionary
        // key must be hashable, a span element must be blittable, a collection element must be
        // storable — is the entire reason the row exists, so its decline is TERMINAL and the
        // general arm never reinterprets it. The general arm is for heads no row covers.
        if claimedHead {
            return false
        }

        modeledSelection := selected
        if TrySelectExternalGenericConstruction(
            canonical,
            genericOpen,
            typeParams,
            enumRegistry,
            structRegistry,
            unionRegistry,
            out selected
        ) {
            return true
        }

        if modeledSelection.HasRuntimeType {
            selected = modeledSelection
        }
        return false
    }

    static func TrySelectTypeParameterModeledFamily(
        canonical: string,
        genericOpen: int,
        typeParams: IReadOnlyDictionary<string, Type>,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out claimedHead: bool,
        out selected: ColumnarSelectedTypeReference
    ): bool {
        table := structRegistry.StructuralTypeReferences
        selected = ColumnarSelectedTypeReference.Missing(table)
        claimedHead = false

        if genericOpen == 4 && canonical.StartsWith("Span<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(
                canonical.Substring(5, canonical.Length - 6),
                1,
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out arguments
            ) && ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(arguments[0].RuntimeType) {
                definition := typeof(Span<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 12 && canonical.StartsWith("ReadOnlySpan<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(
                canonical.Substring(13, canonical.Length - 14),
                1,
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out arguments
            ) && ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(arguments[0].RuntimeType) {
                definition := typeof(ReadOnlySpan<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 10 && canonical.StartsWith("ValueTuple<", StringComparison.Ordinal) {
            claimedHead = true
            argumentCanonicals := ColumnarTypeCanonicalizer.SplitTopLevelCommas(
                canonical.Substring(11, canonical.Length - 12)
            )
            definition := ColumnarTypeOfPlanner.OpenValueTupleType(argumentCanonicals.Count)
            if definition == null {
                return false
            }
            arguments := new ColumnarSelectedTypeReference[](0)
            if !TrySelectTypeParameterCanonicalList(
                argumentCanonicals,
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out arguments
            ) {
                return false
            }
            runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
            if !ColumnarTypeOfPlanner.IsSupportedValueTuple(runtimeType) {
                selected = ColumnarSelectedTypeReference.RejectedWithRuntime(table, runtimeType)
                return false
            }
            selected = ConstructedSelection(table, runtimeType, definition, arguments)
            return true
        }

        if genericOpen == 4 && canonical.StartsWith("Task<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(
                canonical.Substring(5, canonical.Length - 6),
                1,
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out arguments
            ) && ColumnarTypeOfPlanner.IsSupportedType(arguments[0].RuntimeType) {
                definition := typeof(Task<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 9 && canonical.StartsWith("ValueTask<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(
                canonical.Substring(10, canonical.Length - 11),
                1,
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out arguments
            ) && ColumnarTypeOfPlanner.IsSupportedType(arguments[0].RuntimeType) {
                definition := typeof(ValueTask<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 6 && canonical.StartsWith("Result<", StringComparison.Ordinal) {
            claimedHead = true
            argumentCanonicals := ColumnarTypeCanonicalizer.SplitTopLevelCommas(
                canonical.Substring(7, canonical.Length - 8)
            )
            if argumentCanonicals.Count != 2 {
                return false
            }
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterCanonicalList(
                argumentCanonicals,
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out arguments
            ) && !RuntimeTypeShapeFacts.IsByRefLike(arguments[0].RuntimeType) && !RuntimeTypeShapeFacts.IsByRefLike(arguments[1].RuntimeType) && ColumnarTypeOfPlanner.IsSupportedType(arguments[0].RuntimeType) && ColumnarTypeOfPlanner.IsSupportedType(arguments[1].RuntimeType) {
                definition := typeof(object)
                if ColumnarTypeOfPlanner.TryResolveRuntimeGenericDefinition(
                    "NSharpLang.Runtime.Result`2",
                    "NSharpLang.Runtime",
                    out definition
                ) {
                    runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                    selected = ConstructedSelection(table, runtimeType, definition, arguments)
                    return true
                }
            }
            return false
        }

        if genericOpen == 4 && canonical.StartsWith("List<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(canonical.Substring(5, canonical.Length - 6), 1, typeParams, enumRegistry, structRegistry, unionRegistry, out arguments) && (arguments[0].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[0].RuntimeType)) {
                definition := typeof(List<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 7 && canonical.StartsWith("HashSet<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(canonical.Substring(8, canonical.Length - 9), 1, typeParams, enumRegistry, structRegistry, unionRegistry, out arguments) && (arguments[0].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(arguments[0].RuntimeType)) {
                definition := typeof(HashSet<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 9 && canonical.StartsWith("SortedSet<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(canonical.Substring(10, canonical.Length - 11), 1, typeParams, enumRegistry, structRegistry, unionRegistry, out arguments) && (arguments[0].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[0].RuntimeType)) {
                definition := typeof(SortedSet<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 5 && canonical.StartsWith("Stack<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(canonical.Substring(6, canonical.Length - 7), 1, typeParams, enumRegistry, structRegistry, unionRegistry, out arguments) && (arguments[0].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[0].RuntimeType)) {
                definition := typeof(Stack<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        // ONE ELEMENT POLICY PER FAMILY, WHICHEVER WALK ASKS. A body local typed `IEnumerable<int>`
        // is the same sequence a signature spells, and the two walks disagreeing about it was an
        // accident of which resolver a body reaches, not a rule: the ordinary collection-element
        // policy is the rule, and the two exact shapes below (the Analyzer's inherited string
        // dictionary-entry view, the SDK task's Cecil sequences) are ADDITIONS to it, not a
        // replacement for it.
        if genericOpen == 11 && canonical.StartsWith("IEnumerable<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(canonical.Substring(12, canonical.Length - 13), 1, typeParams, enumRegistry, structRegistry, unionRegistry, out arguments) {
                definition := typeof(IEnumerable<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                if arguments[0].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[0].RuntimeType) || IsExactStringDictionaryEntryElement(arguments[0].RuntimeType) || ColumnarTypeOfPlanner.IsSupportedCecilSequenceType(runtimeType) {
                    selected = ConstructedSelection(table, runtimeType, definition, arguments)
                    return true
                }
            }
            return false
        }

        // THE READ-ONLY COLLECTION VIEWS, WITH THE SAME ELEMENT AND KEY POLICIES THE ORDINARY WALK
        // APPLIES. They had no row on this walk at all, which meant a body local spelling one
        // reached the general arm and its `IReadOnlySet` element or `IReadOnlyDictionary` key was
        // never asked the hashability question a signature would have asked it.
        if genericOpen == 13 && canonical.StartsWith("IReadOnlyList<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(canonical.Substring(14, canonical.Length - 15), 1, typeParams, enumRegistry, structRegistry, unionRegistry, out arguments) && (arguments[0].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[0].RuntimeType)) {
                definition := typeof(IReadOnlyList<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 19 && canonical.StartsWith("IReadOnlyCollection<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(canonical.Substring(20, canonical.Length - 21), 1, typeParams, enumRegistry, structRegistry, unionRegistry, out arguments) && (arguments[0].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[0].RuntimeType)) {
                definition := typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 12 && canonical.StartsWith("IReadOnlySet<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(canonical.Substring(13, canonical.Length - 14), 1, typeParams, enumRegistry, structRegistry, unionRegistry, out arguments) && (arguments[0].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(arguments[0].RuntimeType)) {
                definition := typeof(IReadOnlySet<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 19 && canonical.StartsWith("IReadOnlyDictionary<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(canonical.Substring(20, canonical.Length - 21), 2, typeParams, enumRegistry, structRegistry, unionRegistry, out arguments) && (arguments[0].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleSourceDeclarationKey(arguments[0].RuntimeType) || !RuntimeTypeShapeFacts.ContainsBuilderBoundType(arguments[0].RuntimeType)) && (arguments[1].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[1].RuntimeType)) {
                definition := ColumnarTypeOfPlanner.RequiredReadOnlyDictionaryDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 10 && canonical.StartsWith("Dictionary<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(canonical.Substring(11, canonical.Length - 12), 2, typeParams, enumRegistry, structRegistry, unionRegistry, out arguments) && (arguments[0].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleSourceDeclarationKey(arguments[0].RuntimeType) || !RuntimeTypeShapeFacts.ContainsBuilderBoundType(arguments[0].RuntimeType)) && (arguments[1].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[1].RuntimeType)) {
                definition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 16 && canonical.StartsWith("SortedDictionary<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(canonical.Substring(17, canonical.Length - 18), 2, typeParams, enumRegistry, structRegistry, unionRegistry, out arguments) && (arguments[0].RuntimeType is GenericTypeParameterBuilder || !RuntimeTypeShapeFacts.ContainsBuilderBoundType(arguments[0].RuntimeType)) && (arguments[1].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[1].RuntimeType)) {
                definition := typeof(SortedDictionary<int, int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        return false
    }

    // THE GENERAL ARM BEHIND THE FAMILY ROWS ABOVE, and the reason a new row is never needed for a
    // BCL generic a source file writes. The rows above state narrower ELEMENT policies for the
    // families whose lowerings care (spans, collection elements, dictionary keys); when a row
    // declines, or names a head nobody wrote a row for, the ordinary answer is the CLR's own:
    // resolve the open definition through ordinary scoped type resolution at the written arity,
    // resolve each argument the same way this function resolves any other, and close it with
    // `MakeGenericType`. Nothing here consults a name.
    //
    // It serves BOTH walks. `typeParams` is the enclosing declaration's visible type parameters when
    // there are any, and null on the ordinary walk; the arguments are resolved by whichever walk the
    // caller is on, so `IComparer<T>` inside a generic declaration and `IEquatable<Plain>` at file
    // scope reach the same construction. Admissibility of the closed shape is then
    // `ColumnarTypeOfPlanner.IsSupportedType`'s single answer, and a rejection a modeled row already
    // recorded with its exact runtime shape survives a decline here.
    static func TrySelectExternalGenericConstruction(
        canonical: string,
        genericOpen: int,
        typeParams: IReadOnlyDictionary<string, Type>?,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out selected: ColumnarSelectedTypeReference
    ): bool {
        table := structRegistry.StructuralTypeReferences
        selected = ColumnarSelectedTypeReference.Missing(table)

        headName := canonical.Substring(0, genericOpen)
        if headName.Length == 0 {
            return false
        }
        argumentCanonicals := ColumnarTypeCanonicalizer.SplitTopLevelCommas(
            canonical.Substring(genericOpen + 1, canonical.Length - genericOpen - 2)
        )
        if argumentCanonicals.Count == 0 {
            return false
        }

        definition := typeof(object)
        definitionClaimed := false
        if !structRegistry.Resolver.TryResolveExactExplicitType(
            TypeArityNames.Key(headName, argumentCanonicals.Count),
            out definition,
            out definitionClaimed
        ) {
            return false
        }
        if definition == null || !definition.get_IsGenericTypeDefinition() || definition is TypeBuilder || definition.GetGenericArguments().Length != argumentCanonicals.Count {
            return false
        }

        arguments := new ColumnarSelectedTypeReference[](0)
        if typeParams != null {
            if !TrySelectTypeParameterCanonicalList(
                argumentCanonicals,
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out arguments
            ) {
                return false
            }
        } else if !TrySelectOrdinaryCanonicalList(
            argumentCanonicals,
            enumRegistry,
            structRegistry,
            unionRegistry,
            out arguments
        ) {
            return false
        }

        runtimeType := typeof(object)
        try {
            runtimeType = definition.MakeGenericType(SelectedRuntimeTypes(arguments))
        } catch ex: ArgumentException {
            return false
        }
        if !ColumnarTypeOfPlanner.IsSupportedType(runtimeType) {
            selected = ColumnarSelectedTypeReference.RejectedWithRuntime(table, runtimeType)
            return false
        }
        selected = ConstructedSelection(table, runtimeType, definition, arguments)
        return true
    }

    static func MentionsVisibleTypeParameter(canonical: string, typeParams: IReadOnlyDictionary<string, Type>): bool {
        for pair in typeParams {
            if ColumnarExactTypeResolver.ContainsTypeParameter(canonical, pair.Key) {
                return true
            }
        }
        return false
    }

    static func TrySelectRuntimeTypeWithTypeParams(
        canonical: string,
        typeParams: IReadOnlyDictionary<string, Type>,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out selected: ColumnarSelectedTypeReference
    ): bool {
        table := structRegistry.StructuralTypeReferences
        selected = ColumnarSelectedTypeReference.Missing(table)

        // A generic parameter in the explicitly supplied scope belongs to the innermost generic
        // declaration. A synthesized local may copy an enclosing parameter onto a new owner, so its
        // `T` must win over the resolver view that still contains the enclosing method's `T`. A
        // concrete map entry retains the ordinary exact-declaration precedence below.
        parameterType := typeof(object)
        if typeParams.TryGetValue(canonical, out parameterType) && parameterType.get_IsGenericParameter() {
            selected = table.SelectRuntimeType(parameterType)
            return true
        }

        claimed := false
        if structRegistry.Resolver.TryResolveSelected(canonical, out selected, out claimed) {
            if IsOpenGenericUnionDefinition(selected.RuntimeType, unionRegistry) {
                selected = ColumnarSelectedTypeReference.Missing(table)
                return false
            }

            validationCanonical := structRegistry.Resolver.RuntimeGenericValidationCanonical(selected.RuntimeType)
            if validationCanonical == null {
                return true
            }
            if validationCanonical == "*" {
                if ColumnarTypeOfPlanner.IsSupportedType(selected.RuntimeType) {
                    return true
                }
                selected = ColumnarSelectedTypeReference.RejectedWithRuntime(table, selected.RuntimeType)
                return false
            }
            return TrySelectRuntimeTypeWithTypeParams(
                validationCanonical,
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out selected
            )
        }
        if claimed {
            selected = ColumnarSelectedTypeReference.Missing(table)
            return false
        }

        if canonical.StartsWith("&", StringComparison.Ordinal) {
            element := ColumnarSelectedTypeReference.Missing(table)
            if canonical.Length > 1 && TrySelectRuntimeTypeWithTypeParams(
                canonical.Substring(1),
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out element
            ) && IsSupportedByRefElementType(element.RuntimeType) {
                runtimeType := element.RuntimeType.MakeByRefType()
                selected = table.SelectByRef(runtimeType, element)
                return true
            }
            selected = ColumnarSelectedTypeReference.Missing(table)
            return false
        }

        if typeParams.TryGetValue(canonical, out parameterType) {
            selected = table.SelectRuntimeType(parameterType)
            return true
        }

        elementParameter := typeof(object)
        if canonical.EndsWith("[]", StringComparison.Ordinal) && typeParams.TryGetValue(
            canonical.Substring(0, canonical.Length - 2),
            out elementParameter
        ) {
            element := table.SelectRuntimeType(elementParameter)
            runtimeType := elementParameter.MakeArrayType()
            selected = table.SelectSzArray(runtimeType, element)
            return true
        }

        // The DELEGATE FAMILIES, resolved on this walk rather than the ordinary one so that a type
        // parameter in scope is a name they can see. `Action<T>` and `Func<T, bool>` are ordinary
        // constructed external generics; they were the only such family that could not name a type
        // parameter, and only because this arm handed them to the wrong resolver.
        genericHeadOpen := canonical.IndexOf('<')
        if genericHeadOpen > 0 && canonical[canonical.Length - 1] == '>' && (canonical.StartsWith("Func<", StringComparison.Ordinal) || canonical.StartsWith("Action<", StringComparison.Ordinal)) {
            delegateSelected := ColumnarSelectedTypeReference.Missing(table)
            if TrySelectDelegateCanonical(
                canonical.Substring(genericHeadOpen + 1, canonical.Length - genericHeadOpen - 2),
                canonical[0] == 'F',
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out delegateSelected
            ) {
                selected = delegateSelected
                return true
            }

            // A delegate written over the ENCLOSING SCOPE'S TYPE PARAMETERS — `Func<T, TResult>` in a
            // generic member's signature. The plain reader cannot see them, so the arguments are read
            // under the binding here and the open `Func`/`Action` definition of the matching arity is
            // constructed over them.
            openDelegateSelected := ColumnarSelectedTypeReference.Missing(table)
            if TrySelectDelegateWithTypeParams(
                canonical,
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out openDelegateSelected
            ) {
                selected = openDelegateSelected
                return true
            }
            selected = ColumnarSelectedTypeReference.Missing(table)
        }

        // ARRAY AND NULLABLE SUFFIXES OVER A TYPE-PARAMETER SHAPE. The ordinary resolver below owns
        // both suffixes, but it strips them and re-enters ITSELF, which cannot see this declaration's
        // type parameters — so `Func<T, bool>?` and `Dictionary<string, T>[]` lost their parameters at
        // the suffix. These two arms strip the same suffix and re-enter THIS resolver, applying the
        // same element and liftability rules. A spelling that mentions no type parameter never
        // reaches them and keeps the ordinary path exactly.
        if MentionsVisibleTypeParameter(canonical, typeParams) {
            if canonical.EndsWith("[]", StringComparison.Ordinal) && canonical.Length > 2 {
                element := ColumnarSelectedTypeReference.Missing(table)
                if TrySelectRuntimeTypeWithTypeParams(
                    canonical.Substring(0, canonical.Length - 2),
                    typeParams,
                    enumRegistry,
                    structRegistry,
                    unionRegistry,
                    out element
                ) && ColumnarTypeOfPlanner.IsSupportedElementType(element.RuntimeType) {
                    runtimeType := element.RuntimeType.MakeArrayType()
                    selected = table.SelectSzArray(runtimeType, element)
                    return true
                }
                selected = ColumnarSelectedTypeReference.Missing(table)
                return false
            }

            if canonical.EndsWith("?", StringComparison.Ordinal) && canonical.Length > 1 {
                element := ColumnarSelectedTypeReference.Missing(table)
                if TrySelectRuntimeTypeWithTypeParams(
                    canonical.Substring(0, canonical.Length - 1),
                    typeParams,
                    enumRegistry,
                    structRegistry,
                    unionRegistry,
                    out element
                ) {
                    // THE LIFT IS ASKED FIRST, because it is the only question that can tell the two
                    // readings of a TYPE PARAMETER's `T?` apart. A parameter is not a "value-type
                    // shape" — reflection cannot say what it will be — so asking that first read
                    // `where T : struct`'s `T?` as the bare annotated `T`, which is the UNCONSTRAINED
                    // reading. For every other element the order changes nothing: a reference type is
                    // never liftable, and a value type always is.
                    if ColumnarTypeOfPlanner.IsLiftableNullableElement(element.RuntimeType) {
                        nullableDefinition := ColumnarTypeOfPlanner.RequiredNullableDefinition()
                        runtimeArguments := SelectedRuntimeTypes(SelectedSingle(element))
                        runtimeType := nullableDefinition.MakeGenericType(runtimeArguments)
                        selected = ConstructedSelection(table, runtimeType, nullableDefinition, SelectedSingle(element))
                        return true
                    }
                    if !ColumnarTypeOfPlanner.IsValueTypeShape(element.RuntimeType) {
                        selected = element
                        return true
                    }
                }
                selected = ColumnarSelectedTypeReference.Missing(table)
                return false
            }
        }

        genericOpen := canonical.IndexOf('<')
        if genericOpen > 0 && canonical[canonical.Length - 1] == '>' && canonical[0] != '(' {
            unqualifiedGeneric := UnqualifyGenericHead(canonical, genericOpen)
            if unqualifiedGeneric != canonical {
                terminalRejection := false
                preserveExactHead := ShouldPreserveSemanticGenericHead(
                    canonical,
                    genericOpen,
                    structRegistry,
                    out terminalRejection
                )
                if terminalRejection {
                    selected = ColumnarSelectedTypeReference.Missing(table)
                    return false
                }
                if !preserveExactHead {
                    return TrySelectRuntimeTypeWithTypeParams(
                        unqualifiedGeneric,
                        typeParams,
                        enumRegistry,
                        structRegistry,
                        unionRegistry,
                        out selected
                    )
                }
            }

            if IsCollectionHeadShadowedByUserType(
                canonical.Substring(0, genericOpen),
                enumRegistry,
                structRegistry,
                unionRegistry
            ) {
                selected = ColumnarSelectedTypeReference.Missing(table)
                return false
            }

            if TrySelectClosedUserGeneric(
                canonical,
                genericOpen,
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out selected
            ) {
                return true
            }

            return TrySelectTypeParameterGenericFamily(
                canonical,
                genericOpen,
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out selected
            )
        }

        return TrySelectRuntimeType(
            canonical,
            enumRegistry,
            structRegistry,
            unionRegistry,
            out selected
        )
    }

    // The open `Func`/`Action` definition of a given arity. `Func` reads its LAST type argument as the
    // result and `Action` reads them all as parameters, which is the same reading every other
    // delegate surface in this compiler gives those two names.
    static func OpenDelegateDefinition(isFunc: bool, arity: int): Type? {
        if arity <= 0 {
            return null
        }
        family := isFunc ? "System.Func`" : "System.Action`"
        definition := Type.GetType(family + arity.ToString())
        if definition == null || !definition.get_IsGenericTypeDefinition() {
            return null
        }
        return definition
    }

    static func SupportsInferredDelegateParameterCount(parameterCount: int): bool {
        if parameterCount < 0 {
            return false
        }
        if parameterCount == 0 {
            return true
        }
        return OpenDelegateDefinition(false, parameterCount) != null && OpenDelegateDefinition(true, parameterCount + 1) != null
    }

    static func TryConstructInferredDelegate(parameterTypes: Type[], returnType: Type, out delegateType: Type): bool {
        delegateType = null
        if parameterTypes == null || returnType == null || !SupportsInferredDelegateParameterCount(parameterTypes.Length) {
            return false
        }
        if returnType == ColumnarTypeOfPlanner.RequiredVoidType() {
            if parameterTypes.Length == 0 {
                delegateType = typeof(Action)
                return true
            }
            actionDefinition := OpenDelegateDefinition(false, parameterTypes.Length)
            if actionDefinition == null {
                return false
            }
            delegateType = actionDefinition.MakeGenericType(parameterTypes)
            return true
        }
        funcDefinition := OpenDelegateDefinition(true, parameterTypes.Length + 1)
        if funcDefinition == null {
            return false
        }
        arguments := new Type[](parameterTypes.Length + 1)
        i := 0
        while i < parameterTypes.Length {
            arguments[i] = parameterTypes[i]
            i += 1
        }
        arguments[parameterTypes.Length] = returnType
        delegateType = funcDefinition.MakeGenericType(arguments)
        return true
    }

    static func TrySelectDelegateWithTypeParams(
        canonical: string,
        typeParams: IReadOnlyDictionary<string, Type>,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out selected: ColumnarSelectedTypeReference
    ): bool {
        table := structRegistry.StructuralTypeReferences
        selected = ColumnarSelectedTypeReference.Missing(table)
        genericOpen := canonical.IndexOf('<')
        if genericOpen <= 0 || canonical[canonical.Length - 1] != '>' {
            return false
        }

        headName := canonical.Substring(0, genericOpen)
        isFunc := headName == "Func"
        if !isFunc && headName != "Action" {
            return false
        }

        argumentCanonicals := ColumnarTypeCanonicalizer.SplitTopLevelCommas(
            canonical.Substring(genericOpen + 1, canonical.Length - genericOpen - 2)
        )
        definition := OpenDelegateDefinition(isFunc, argumentCanonicals.Count)
        if definition == null {
            return false
        }

        arguments := new ColumnarSelectedTypeReference[](argumentCanonicals.Count)
        i := 0
        while i < arguments.Length {
            argument := ColumnarSelectedTypeReference.Missing(table)
            if !TrySelectRuntimeTypeWithTypeParams(
                argumentCanonicals[i],
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out argument
            ) {
                selected = ColumnarSelectedTypeReference.Missing(table)
                return false
            }
            arguments[i] = argument
            i += 1
        }

        runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
        selected = ConstructedSelection(table, runtimeType, definition, arguments)
        return true
    }

    static func TrySelectClosedUserGeneric(
        canonical: string,
        genericOpen: int,
        typeParams: IReadOnlyDictionary<string, Type>?,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out selected: ColumnarSelectedTypeReference
    ): bool {
        table := structRegistry.StructuralTypeReferences
        selected = ColumnarSelectedTypeReference.Missing(table)
        headName := canonical.Substring(0, genericOpen)
        argumentCanonicals := ColumnarTypeCanonicalizer.SplitTopLevelCommas(
            canonical.Substring(genericOpen + 1, canonical.Length - genericOpen - 2)
        )
        lookupHeadName := TypeArityNames.Key(headName, argumentCanonicals.Count)
        openDefinition: Type? = null
        exactSourceName := ""

        structDefinition: ColumnarStructDef = null
        if structRegistry.TryGetValue(lookupHeadName, out structDefinition) && structDefinition != null && structDefinition.Builder.get_IsGenericTypeDefinition() {
            openDefinition = structDefinition.Builder
            exactSourceName = structDefinition.DeclaredTypeName
        } else {
            unionDefinition: ColumnarUnionDef = null
            if unionRegistry.TryGetValue(lookupHeadName, out unionDefinition) && unionDefinition != null && unionDefinition.Base.get_IsGenericTypeDefinition() {
                openDefinition = unionDefinition.Base
                exactSourceName = unionDefinition.DeclaredTypeName
            }
        }

        if openDefinition == null {
            return false
        }

        if argumentCanonicals.Count != openDefinition.GetGenericArguments().Length {
            return false
        }

        arguments := new ColumnarSelectedTypeReference[](argumentCanonicals.Count)
        i := 0
        while i < arguments.Length {
            argument := ColumnarSelectedTypeReference.Missing(table)
            resolved := false
            if typeParams != null {
                resolved = TrySelectRuntimeTypeWithTypeParams(
                    argumentCanonicals[i],
                    typeParams,
                    enumRegistry,
                    structRegistry,
                    unionRegistry,
                    out argument
                )
            } else {
                resolved = TrySelectRuntimeType(
                    argumentCanonicals[i],
                    enumRegistry,
                    structRegistry,
                    unionRegistry,
                    out argument
                )
            }
            if !resolved {
                selected = ColumnarSelectedTypeReference.Missing(table)
                return false
            }
            arguments[i] = argument
            i += 1
        }

        runtimeType := openDefinition.MakeGenericType(SelectedRuntimeTypes(arguments))
        definition := table.SelectSourceDefinition(exactSourceName, openDefinition)
        selected = table.SelectConstructedGeneric(runtimeType, definition, arguments)
        return true
    }

    // THE MODELED ROWS FIRST, THEN THE GENERAL ARM — the ordinary walk's half of the same rule the
    // type-parameter walk follows. A modeled row keeps its narrower element policy and its recorded
    // rejection; a head no row covers, or a row that declined, falls through to the CLR's own answer
    // in `TrySelectExternalGenericConstruction`.
    static func TrySelectOrdinaryGenericFamily(
        canonical: string,
        genericOpen: int,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out selected: ColumnarSelectedTypeReference
    ): bool {
        claimedHead := false
        if TrySelectOrdinaryModeledFamily(
            canonical,
            genericOpen,
            enumRegistry,
            structRegistry,
            unionRegistry,
            out claimedHead,
            out selected
        ) {
            return true
        }

        // A ROW THAT OWNS THIS HEAD HAS ALREADY ANSWERED. Its element policy — a dictionary
        // key must be hashable, a span element must be blittable, a collection element must be
        // storable — is the entire reason the row exists, so its decline is TERMINAL and the
        // general arm never reinterprets it. The general arm is for heads no row covers.
        if claimedHead {
            return false
        }

        modeledSelection := selected
        if TrySelectExternalGenericConstruction(
            canonical,
            genericOpen,
            null,
            enumRegistry,
            structRegistry,
            unionRegistry,
            out selected
        ) {
            return true
        }

        if modeledSelection.HasRuntimeType {
            selected = modeledSelection
        }
        return false
    }

    static func TrySelectOrdinaryModeledFamily(
        canonical: string,
        genericOpen: int,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out claimedHead: bool,
        out selected: ColumnarSelectedTypeReference
    ): bool {
        table := structRegistry.StructuralTypeReferences
        selected = ColumnarSelectedTypeReference.Missing(table)
        claimedHead = false

        if genericOpen == 4 && canonical.StartsWith("Span<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(
                canonical.Substring(5, canonical.Length - 6),
                1,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out arguments
            ) && ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(arguments[0].RuntimeType) {
                definition := typeof(Span<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 12 && canonical.StartsWith("ReadOnlySpan<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(
                canonical.Substring(13, canonical.Length - 14),
                1,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out arguments
            ) && ColumnarTypeOfPlanner.IsSupportedReadOnlySpanElement(arguments[0].RuntimeType) {
                definition := typeof(ReadOnlySpan<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 10 && canonical.StartsWith("ValueTuple<", StringComparison.Ordinal) {
            claimedHead = true
            argumentCanonicals := ColumnarTypeCanonicalizer.SplitTopLevelCommas(
                canonical.Substring(11, canonical.Length - 12)
            )
            definition := ColumnarTypeOfPlanner.OpenValueTupleType(argumentCanonicals.Count)
            if definition == null {
                return false
            }
            arguments := new ColumnarSelectedTypeReference[](0)
            if !TrySelectOrdinaryCanonicalList(
                argumentCanonicals,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out arguments
            ) {
                return false
            }
            runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
            if !ColumnarTypeOfPlanner.IsSupportedValueTuple(runtimeType) {
                selected = ColumnarSelectedTypeReference.RejectedWithRuntime(table, runtimeType)
                return false
            }
            selected = ConstructedSelection(table, runtimeType, definition, arguments)
            return true
        }

        if genericOpen == 6 && canonical.StartsWith("Action<", StringComparison.Ordinal) {
            claimedHead = true
            return TrySelectDelegateCanonical(
                canonical.Substring(7, canonical.Length - 8),
                false,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out selected
            )
        }

        if genericOpen == 4 && canonical.StartsWith("Task<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(
                canonical.Substring(5, canonical.Length - 6),
                1,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out arguments
            ) && ColumnarTypeOfPlanner.IsSupportedType(arguments[0].RuntimeType) {
                definition := typeof(Task<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 9 && canonical.StartsWith("ValueTask<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(
                canonical.Substring(10, canonical.Length - 11),
                1,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out arguments
            ) && ColumnarTypeOfPlanner.IsSupportedType(arguments[0].RuntimeType) {
                definition := typeof(ValueTask<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 6 && canonical.StartsWith("Result<", StringComparison.Ordinal) {
            claimedHead = true
            argumentCanonicals := ColumnarTypeCanonicalizer.SplitTopLevelCommas(
                canonical.Substring(7, canonical.Length - 8)
            )
            if argumentCanonicals.Count != 2 {
                return false
            }
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryCanonicalList(
                argumentCanonicals,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out arguments
            ) && !RuntimeTypeShapeFacts.IsByRefLike(arguments[0].RuntimeType) && !RuntimeTypeShapeFacts.IsByRefLike(arguments[1].RuntimeType) && ColumnarTypeOfPlanner.IsSupportedType(arguments[0].RuntimeType) && ColumnarTypeOfPlanner.IsSupportedType(arguments[1].RuntimeType) {
                definition := typeof(object)
                if ColumnarTypeOfPlanner.TryResolveRuntimeGenericDefinition(
                    "NSharpLang.Runtime.Result`2",
                    "NSharpLang.Runtime",
                    out definition
                ) {
                    runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                    selected = ConstructedSelection(table, runtimeType, definition, arguments)
                    return true
                }
            }
            return false
        }

        if genericOpen == 4 && canonical.StartsWith("List<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(canonical.Substring(5, canonical.Length - 6), 1, enumRegistry, structRegistry, unionRegistry, out arguments) && ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[0].RuntimeType) {
                definition := typeof(List<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 7 && canonical.StartsWith("HashSet<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(canonical.Substring(8, canonical.Length - 9), 1, enumRegistry, structRegistry, unionRegistry, out arguments) && ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(arguments[0].RuntimeType) {
                definition := typeof(HashSet<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 9 && canonical.StartsWith("SortedSet<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(canonical.Substring(10, canonical.Length - 11), 1, enumRegistry, structRegistry, unionRegistry, out arguments) && ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[0].RuntimeType) {
                definition := typeof(SortedSet<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 5 && canonical.StartsWith("Stack<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(canonical.Substring(6, canonical.Length - 7), 1, enumRegistry, structRegistry, unionRegistry, out arguments) && ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[0].RuntimeType) {
                definition := typeof(Stack<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 13 && canonical.StartsWith("IReadOnlyList<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(canonical.Substring(14, canonical.Length - 15), 1, enumRegistry, structRegistry, unionRegistry, out arguments) && ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[0].RuntimeType) {
                definition := typeof(IReadOnlyList<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 19 && canonical.StartsWith("IReadOnlyCollection<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(canonical.Substring(20, canonical.Length - 21), 1, enumRegistry, structRegistry, unionRegistry, out arguments) && ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[0].RuntimeType) {
                definition := typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 12 && canonical.StartsWith("IReadOnlySet<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(canonical.Substring(13, canonical.Length - 14), 1, enumRegistry, structRegistry, unionRegistry, out arguments) && ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(arguments[0].RuntimeType) {
                definition := typeof(IReadOnlySet<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 11 && canonical.StartsWith("IEnumerable<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(canonical.Substring(12, canonical.Length - 13), 1, enumRegistry, structRegistry, unionRegistry, out arguments) && ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[0].RuntimeType) {
                definition := typeof(IEnumerable<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 10 && canonical.StartsWith("Dictionary<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(canonical.Substring(11, canonical.Length - 12), 2, enumRegistry, structRegistry, unionRegistry, out arguments) && ColumnarTypeOfPlanner.IsAdmissibleDictionaryKey(arguments[0].RuntimeType) && ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[1].RuntimeType) {
                definition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 19 && canonical.StartsWith("IReadOnlyDictionary<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(canonical.Substring(20, canonical.Length - 21), 2, enumRegistry, structRegistry, unionRegistry, out arguments) && ColumnarTypeOfPlanner.IsAdmissibleDictionaryKey(arguments[0].RuntimeType) && ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[1].RuntimeType) {
                definition := ColumnarTypeOfPlanner.RequiredReadOnlyDictionaryDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 16 && canonical.StartsWith("SortedDictionary<", StringComparison.Ordinal) {
            claimedHead = true
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(canonical.Substring(17, canonical.Length - 18), 2, enumRegistry, structRegistry, unionRegistry, out arguments) && !RuntimeTypeShapeFacts.ContainsBuilderBoundType(arguments[0].RuntimeType) && ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[1].RuntimeType) {
                definition := typeof(SortedDictionary<int, int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        return false
    }

    // ONE delegate argument, resolved by whichever walk the caller is on. The only thing the two
    // walks disagree about is what a bare name may mean, and the admissibility rule below is the
    // same either way: a delegate is constructed from complete identities, and the ONE builder-bound
    // shape it accepts is a generic PARAMETER — the same shape `List<T>` and `Dictionary<string, T>`
    // already accept. A source class or struct is still refused, because `Action<MyClass>` would
    // have to name a type that does not exist yet at the moment the delegate is constructed.
    static func TrySelectDelegateArgument(
        canonical: string,
        typeParams: IReadOnlyDictionary<string, Type>?,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out selected: ColumnarSelectedTypeReference
    ): bool {
        table := structRegistry.StructuralTypeReferences
        selected = ColumnarSelectedTypeReference.Missing(table)
        resolved := ColumnarSelectedTypeReference.Missing(table)
        if typeParams == null {
            if !TrySelectRuntimeType(canonical, enumRegistry, structRegistry, unionRegistry, out resolved) {
                return false
            }
        } else if !TrySelectRuntimeTypeWithTypeParams(canonical, typeParams, enumRegistry, structRegistry, unionRegistry, out resolved) {
            return false
        }

        if resolved.RuntimeType.get_IsGenericParameter() {
            selected = resolved
            return true
        }

        // A DELEGATE ARGUMENT IS AN ORDINARY STORABLE TYPE, and that is the whole rule. It used to
        // refuse anything belonging to the assembly being emitted, on the grounds that
        // `Action<MyClass>` would name a type that does not exist yet — but `MakeGenericType` over a
        // `TypeBuilder` answers a real handle, and a `Func<Plain, bool>` field, parameter, local or
        // return is an ordinary delegate reference. What a generic argument may still never be is
        // BY-REF-LIKE: the CLR refuses that instantiation outright, and asking for it would throw
        // where this resolver must decline.
        if RuntimeTypeShapeFacts.IsByRefLike(resolved.RuntimeType) || !ColumnarTypeOfPlanner.IsSupportedType(resolved.RuntimeType) {
            return false
        }

        selected = resolved
        return true
    }

    // The ordinary entry point: no type parameters are in scope, so every argument must be a
    // complete external or source identity.
    static func TrySelectDelegateCanonical(
        argumentText: string,
        hasReturnSlot: bool,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out selected: ColumnarSelectedTypeReference
    ): bool {
        noTypeParams: IReadOnlyDictionary<string, Type>? = null
        return TrySelectDelegateCanonical(
            argumentText,
            hasReturnSlot,
            noTypeParams,
            enumRegistry,
            structRegistry,
            unionRegistry,
            out selected
        )
    }

    // `Action<T>` / `Func<T, bool>` WHERE `T` IS THE DECLARING TYPE'S OWN TYPE PARAMETER.
    //
    // A delegate argument used to be resolved by the ordinary walk even when this was reached from a
    // generic-aware entry point, so a type parameter was simply an unknown name and every field,
    // parameter or local spelled over one declined. `List<T>` and `Dictionary<string, T>` already
    // resolved; the delegate families did not, for no reason other than which resolver they called.
    // They now call the same one their callers do, and the ORDER is unchanged: the `Func` return
    // first, then arity, then the parameters.
    static func TrySelectDelegateCanonical(
        argumentText: string,
        hasReturnSlot: bool,
        typeParams: IReadOnlyDictionary<string, Type>?,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out selected: ColumnarSelectedTypeReference
    ): bool {
        table := structRegistry.StructuralTypeReferences
        selected = ColumnarSelectedTypeReference.Missing(table)
        parts := ColumnarTypeCanonicalizer.SplitTopLevelCommas(argumentText)
        if parts.Count == 0 {
            return false
        }

        // THE SPLIT KEEPS THE SPACE THE AUTHOR WROTE. `Func<int, int>` is the ordinary spelling, and
        // it split into `int` and ` int` — a name no registry has — so every delegate written with a
        // space after its comma failed to resolve while the same type written without one succeeded.
        // Whitespace around a type canonical never carries meaning, so it is removed here.
        trimmed := 0
        while trimmed < parts.Count {
            parts[trimmed] = parts[trimmed].Trim()
            trimmed = trimmed + 1
        }

        parameterCount := parts.Count
        voidType := ColumnarTypeOfPlanner.RequiredVoidType()
        returnType := voidType
        returnSelected := ColumnarSelectedTypeReference.Missing(table)
        if hasReturnSlot {
            parameterCount = parameterCount - 1
            returnCanonical := parts[parameterCount]
            if returnCanonical != "void" {
                if !TrySelectDelegateArgument(
                    returnCanonical,
                    typeParams,
                    enumRegistry,
                    structRegistry,
                    unionRegistry,
                    out returnSelected
                ) {
                    selected = ColumnarSelectedTypeReference.Missing(table)
                    return false
                }
                returnType = returnSelected.RuntimeType
            }
        }

        if parameterCount > 4 {
            return false
        }

        parameters := new ColumnarSelectedTypeReference[](parameterCount)
        i := 0
        while i < parameterCount {
            parameter := ColumnarSelectedTypeReference.Missing(table)
            if parts[i] == "void" || !TrySelectDelegateArgument(
                parts[i],
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out parameter
            ) {
                selected = ColumnarSelectedTypeReference.Missing(table)
                return false
            }
            parameters[i] = parameter
            i += 1
        }

        if returnType == voidType {
            if parameterCount == 0 {
                selected = table.SelectRuntimeType(typeof(Action))
                return true
            }

            actionDefinition := typeof(Action<int>).GetGenericTypeDefinition()
            if parameterCount == 2 {
                actionDefinition = typeof(Action<int, int>).GetGenericTypeDefinition()
            } else if parameterCount == 3 {
                actionDefinition = typeof(Action<int, int, int>).GetGenericTypeDefinition()
            } else if parameterCount == 4 {
                actionDefinition = typeof(Action<int, int, int, int>).GetGenericTypeDefinition()
            }
            runtimeType := actionDefinition.MakeGenericType(SelectedRuntimeTypes(parameters))
            selected = ConstructedSelection(table, runtimeType, actionDefinition, parameters)
            return true
        }

        funcDefinition := typeof(Func<int>).GetGenericTypeDefinition()
        if parameterCount == 1 {
            funcDefinition = typeof(Func<int, int>).GetGenericTypeDefinition()
        } else if parameterCount == 2 {
            funcDefinition = typeof(Func<int, int, int>).GetGenericTypeDefinition()
        } else if parameterCount == 3 {
            funcDefinition = typeof(Func<int, int, int, int>).GetGenericTypeDefinition()
        } else if parameterCount == 4 {
            funcDefinition = typeof(Func<int, int, int, int, int>).GetGenericTypeDefinition()
        }

        arguments := new ColumnarSelectedTypeReference[](parameterCount + 1)
        i = 0
        while i < parameterCount {
            arguments[i] = parameters[i]
            i += 1
        }
        arguments[parameterCount] = returnSelected
        runtimeType := funcDefinition.MakeGenericType(SelectedRuntimeTypes(arguments))
        selected = ConstructedSelection(table, runtimeType, funcDefinition, arguments)
        return true
    }

    // Fixed arity is verified before any recursive selection. Several invalid shapes contain a
    // nested tuple that would throw during MakeGenericType, whereas the legacy resolver declines
    // a wrong outer arity before it ever reaches that nested shape.
    static func TrySelectOrdinaryArguments(
        argumentText: string,
        expectedCount: int,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out arguments: ColumnarSelectedTypeReference[]
    ): bool {
        argumentCanonicals := ColumnarTypeCanonicalizer.SplitTopLevelCommas(argumentText)
        if argumentCanonicals.Count != expectedCount {
            arguments = new ColumnarSelectedTypeReference[](0)
            return false
        }
        return TrySelectOrdinaryCanonicalList(
            argumentCanonicals,
            enumRegistry,
            structRegistry,
            unionRegistry,
            out arguments
        )
    }

    static func TrySelectOrdinaryCanonicalList(
        argumentCanonicals: List<string>,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out arguments: ColumnarSelectedTypeReference[]
    ): bool {
        table := structRegistry.StructuralTypeReferences
        arguments = new ColumnarSelectedTypeReference[](argumentCanonicals.Count)
        i := 0
        while i < arguments.Length {
            argument := ColumnarSelectedTypeReference.Missing(table)
            if !TrySelectRuntimeType(
                argumentCanonicals[i],
                enumRegistry,
                structRegistry,
                unionRegistry,
                out argument
            ) {
                arguments = new ColumnarSelectedTypeReference[](0)
                return false
            }
            arguments[i] = argument
            i += 1
        }
        return true
    }

    static func TrySelectTypeParameterArguments(
        argumentText: string,
        expectedCount: int,
        typeParams: IReadOnlyDictionary<string, Type>,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out arguments: ColumnarSelectedTypeReference[]
    ): bool {
        argumentCanonicals := ColumnarTypeCanonicalizer.SplitTopLevelCommas(argumentText)
        if argumentCanonicals.Count != expectedCount {
            arguments = new ColumnarSelectedTypeReference[](0)
            return false
        }
        return TrySelectTypeParameterCanonicalList(
            argumentCanonicals,
            typeParams,
            enumRegistry,
            structRegistry,
            unionRegistry,
            out arguments
        )
    }

    static func TrySelectTypeParameterCanonicalList(
        argumentCanonicals: List<string>,
        typeParams: IReadOnlyDictionary<string, Type>,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out arguments: ColumnarSelectedTypeReference[]
    ): bool {
        table := structRegistry.StructuralTypeReferences
        arguments = new ColumnarSelectedTypeReference[](argumentCanonicals.Count)
        i := 0
        while i < arguments.Length {
            argument := ColumnarSelectedTypeReference.Missing(table)
            if !TrySelectRuntimeTypeWithTypeParams(
                argumentCanonicals[i],
                typeParams,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out argument
            ) {
                arguments = new ColumnarSelectedTypeReference[](0)
                return false
            }
            arguments[i] = argument
            i += 1
        }
        return true
    }

    static func SelectedSingle(value: ColumnarSelectedTypeReference): ColumnarSelectedTypeReference[] {
        result := new ColumnarSelectedTypeReference[](1)
        result[0] = value
        return result
    }

    static func SelectedPair(first: ColumnarSelectedTypeReference, second: ColumnarSelectedTypeReference): ColumnarSelectedTypeReference[] {
        result := new ColumnarSelectedTypeReference[](2)
        result[0] = first
        result[1] = second
        return result
    }

    static func SelectedRuntimeTypes(selectedTypes: ColumnarSelectedTypeReference[]): Type[] {
        runtimeTypes := new Type[](selectedTypes.Length)
        i := 0
        while i < selectedTypes.Length {
            runtimeTypes[i] = selectedTypes[i].RuntimeType
            i += 1
        }
        return runtimeTypes
    }

    static func RuntimeTypes(first: ColumnarSelectedTypeReference, second: ColumnarSelectedTypeReference): Type[] {
        runtimeTypes := new Type[](2)
        runtimeTypes[0] = first.RuntimeType
        runtimeTypes[1] = second.RuntimeType
        return runtimeTypes
    }

    static func ConstructedSelection(
        table: ColumnarStructuralTypeReferenceTable,
        runtimeType: Type,
        definition: Type,
        arguments: ColumnarSelectedTypeReference[]
    ): ColumnarSelectedTypeReference {
        definitionSelected := table.SelectRuntimeType(definition)
        return table.SelectConstructedGeneric(runtimeType, definitionSelected, arguments)
    }

    static func IsOpenGenericUnionDefinition(
        runtimeType: Type,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>
    ): bool {
        if !runtimeType.get_IsGenericTypeDefinition() {
            return false
        }
        for definition in unionRegistry.Values {
            if Object.ReferenceEquals(definition.Base, runtimeType) {
                return true
            }
        }
        return false
    }

    static func ShouldPreserveSemanticGenericHead(
        canonical: string,
        genericOpen: int,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        out terminalRejection: bool
    ): bool {
        terminalRejection = false
        head := canonical.Substring(0, genericOpen)
        selected := ColumnarSelectedTypeReference.Missing(structRegistry.StructuralTypeReferences)
        claimed := false
        if structRegistry.Resolver.TryResolveSelected(head, out selected, out claimed) {
            return structRegistry.Resolver.IsSourceDefinition(selected.RuntimeType)
        }
        terminalRejection = claimed
        return false
    }

    static func UnqualifyGenericHead(canonical: string, genericOpen: int): string {
        head := canonical.Substring(0, genericOpen)
        shortHead := ColumnarTypeCanonicalizer.UnqualifiedTypeName(head)
        if head == shortHead {
            return canonical
        }
        return shortHead + canonical.Substring(genericOpen)
    }

    static func IsSupportedByRefElementType(runtimeType: Type): bool {
        return !runtimeType.get_IsByRef() && ColumnarTypeOfPlanner.IsSupportedType(runtimeType)
    }

    static func IsCollectionHeadShadowedByUserType(
        headName: string,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>
    ): bool {
        if headName != "List" && headName != "Dictionary" && headName != "SortedDictionary" && headName != "HashSet" && headName != "SortedSet" && headName != "Stack" && headName != "IReadOnlyList" {
            return false
        }
        return enumRegistry.ContainsKey(headName) || structRegistry.ContainsKey(headName) || unionRegistry.ContainsKey(headName)
    }

    static func IsExactStringDictionaryEntryElement(runtimeType: Type): bool {
        if !ColumnarTypeOfPlanner.IsSupportedKeyValuePairType(runtimeType) {
            return false
        }
        arguments := runtimeType.GetGenericArguments()
        return arguments.Length == 2 && arguments[0] == typeof(string) && arguments[1] == typeof(string)
    }

    // Keep the C# helper's false/null leaf contract instead of exposing the planner helper's
    // false/object sentinel. The resolver's Type-out compatibility surface observes this value.
    // THE EXCEPTION A `catch` CLAUSE OR A `throw` NAMES — RESOLVED, NOT LISTED.
    //
    // There is no allowlist of admitted exception names, and there are no longer TWO of them. A
    // spelling resolves by ordinary CLR name lookup: a qualified name directly, a bare simple name
    // against the runtime's own exception hierarchy. The only admission rule is the one the CLR itself
    // enforces on a handler type — it must derive from `System.Exception`.
    //
    // That is what makes `System.ArrayTypeMismatchException` and `ArrayTypeMismatchException` the SAME
    // type instead of two rows that can disagree: the qualified spelling used to be absent from one
    // table and present in the other, so the same program compiled or declined depending on how its
    // catch clause was written.
    //
    // SOURCE DECLARATIONS ARE RESOLVED FIRST BY THE CALLER (`TrySelectRuntimeType` asks the struct
    // registry before it reaches here), so a user type whose name collides with a BCL exception still
    // wins. An AMBIGUOUS simple name — two exceptions in different namespaces of the same assembly —
    // resolves to neither, because choosing one would be a guess.
    static func TryResolveBclExceptionType(canonical: string, out result: Type): bool {
        result = null
        if canonical == null || canonical.Length == 0 {
            return false
        }

        exceptionBase := typeof(Exception)
        if IsPlainTypeNameSpelling(canonical) {
            qualified := Type.GetType(canonical)
            if IsCatchableExceptionType(qualified, exceptionBase) {
                result = qualified
                return true
            }
            if IndexOfDot(canonical) < 0 {
                index := RuntimeExceptionsBySimpleName
                if index.ContainsKey(canonical) {
                    result = index[canonical]
                    return true
                }
            }
        }

        // A referenced (non-runtime) assembly's exception still comes from the external-type owner.
        external := typeof(object)
        if ColumnarTypeOfPlanner.TryResolveKnownExternalType(canonical, out external) && IsCatchableExceptionType(external, exceptionBase) {
            result = external
            return true
        }
        return false
    }

    static func BuildRuntimeExceptionIndex(): Dictionary<string, Type> {
        index := new Dictionary<string, Type>(StringComparer.Ordinal)
        ambiguous := new List<string>()
        exceptionBase := typeof(Exception)
        for candidate in exceptionBase.get_Assembly().GetExportedTypes() {
            if !IsCatchableExceptionType(candidate, exceptionBase) {
                continue
            }
            name := candidate.Name
            if index.ContainsKey(name) {
                ambiguous.Add(name)
                continue
            }
            index[name] = candidate
        }
        for name in ambiguous {
            index.Remove(name)
        }
        return index
    }

    static func IsCatchableExceptionType(candidate: Type?, exceptionBase: Type): bool {
        if candidate == null || candidate.get_IsGenericTypeDefinition() || candidate.get_IsGenericParameter() || candidate.get_IsByRef() || candidate.get_IsPointer() {
            return false
        }
        return exceptionBase.IsAssignableFrom(candidate)
    }

    // A dotted identifier and nothing else. `Type.GetType` reads an assembly-qualified type GRAMMAR —
    // brackets, commas, `&`, `*` and `+` all mean something in it — so a canonical carrying any of them
    // is not a plain name and must not be handed to it.
    static func IsPlainTypeNameSpelling(canonical: string): bool {
        i := 0
        while i < canonical.Length {
            c := canonical[i]
            if !char.IsLetterOrDigit(c) && c != '_' && c != '.' {
                return false
            }
            i = i + 1
        }
        return canonical[0] != '.' && canonical[canonical.Length - 1] != '.'
    }

    static func IndexOfDot(value: string): int {
        i := 0
        while i < value.Length {
            if value[i] == '.' {
                return i
            }
            i = i + 1
        }
        return -1
    }

    // A bare catch is the CLI catch-all region: the CLR handler type is System.Object. Typed catches
    // retain the existing exception allowlist and the source text is read only for a typed clause.
    static func TryResolveCatchType(
        nodes: ColumnarNodeTable,
        source: string,
        clause: int,
        out result: Type
    ): bool {
        if nodes.ValueStart(clause) < 0 {
            result = typeof(object)
            return true
        }

        return TryResolveBclExceptionType(ColumnarNodeTextFacts.Text(nodes, source, clause), out result)
    }
}
