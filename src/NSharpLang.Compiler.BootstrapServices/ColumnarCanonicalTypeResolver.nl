namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Reflection
import System.Reflection.Emit
import System.Text
import System.Threading
import System.Threading.Tasks


// Canonical declaration/body signature resolution owns the same shape policy as the historical
// emitter, but selects a structural reference together with its live reflection companion. The
// Type-out entry points below are intentionally thin compatibility surfaces: callers that still
// consume Type receive the companion selected here, rather than a Type selected elsewhere and
// decorated after the fact.
class ColumnarCanonicalTypeResolver {
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
        if TryResolveSpecialKnownType(canonical, out specialType) {
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
        if TryResolveBuiltin(canonical, out builtinType) {
            selected = table.SelectRuntimeType(builtinType)
            return true
        }

        selected = ColumnarSelectedTypeReference.Missing(table)
        return false
    }

    // This deliberately differs from the ordinary family. The historical generic-signature path
    // permits only the BCL heads whose type-parameter closure it can emit; in particular it does
    // not admit the read-only collection interfaces merely because an empty map was supplied.
    static func TrySelectTypeParameterGenericFamily(
        canonical: string,
        genericOpen: int,
        typeParams: IReadOnlyDictionary<string, Type>,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out selected: ColumnarSelectedTypeReference
    ): bool {
        table := structRegistry.StructuralTypeReferences
        selected = ColumnarSelectedTypeReference.Missing(table)

        if genericOpen == 4 && canonical.StartsWith("Span<", StringComparison.Ordinal) {
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
            ) && !ColumnarTypeOfPlanner.IsByRefLike(arguments[0].RuntimeType) && !ColumnarTypeOfPlanner.IsByRefLike(arguments[1].RuntimeType) && ColumnarTypeOfPlanner.IsSupportedType(arguments[0].RuntimeType) && ColumnarTypeOfPlanner.IsSupportedType(arguments[1].RuntimeType) {
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
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(canonical.Substring(8, canonical.Length - 9), 1, typeParams, enumRegistry, structRegistry, unionRegistry, out arguments) && (arguments[0].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(arguments[0].RuntimeType)) {
                definition := typeof(HashSet<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 5 && canonical.StartsWith("Stack<", StringComparison.Ordinal) {
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(canonical.Substring(6, canonical.Length - 7), 1, typeParams, enumRegistry, structRegistry, unionRegistry, out arguments) && (arguments[0].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[0].RuntimeType)) {
                definition := typeof(Stack<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 10 && canonical.StartsWith("Dictionary<", StringComparison.Ordinal) {
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(canonical.Substring(11, canonical.Length - 12), 2, typeParams, enumRegistry, structRegistry, unionRegistry, out arguments) && !ColumnarTypeOfPlanner.ContainsBuilderBoundType(arguments[0].RuntimeType) && (arguments[1].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[1].RuntimeType)) {
                definition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 16 && canonical.StartsWith("SortedDictionary<", StringComparison.Ordinal) {
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectTypeParameterArguments(canonical.Substring(17, canonical.Length - 18), 2, typeParams, enumRegistry, structRegistry, unionRegistry, out arguments) && !ColumnarTypeOfPlanner.ContainsBuilderBoundType(arguments[0].RuntimeType) && (arguments[1].RuntimeType is GenericTypeParameterBuilder || ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[1].RuntimeType)) {
                definition := typeof(SortedDictionary<int, int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
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

        parameterType := typeof(object)
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

        if canonical.StartsWith("Func<", StringComparison.Ordinal) || canonical.StartsWith("Action<", StringComparison.Ordinal) {
            delegateSelected := ColumnarSelectedTypeReference.Missing(table)
            if TrySelectRuntimeType(
                canonical,
                enumRegistry,
                structRegistry,
                unionRegistry,
                out delegateSelected
            ) {
                selected = delegateSelected
                return true
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
        openDefinition: Type? = null
        exactSourceName := ""

        structDefinition: ColumnarStructDef = null
        if structRegistry.TryGetValue(headName, out structDefinition) && structDefinition != null && structDefinition.Builder.get_IsGenericTypeDefinition() {
            openDefinition = structDefinition.Builder
            exactSourceName = structDefinition.DeclaredTypeName
        } else {
            unionDefinition: ColumnarUnionDef = null
            if unionRegistry.TryGetValue(headName, out unionDefinition) && unionDefinition != null && unionDefinition.Base.get_IsGenericTypeDefinition() {
                openDefinition = unionDefinition.Base
                exactSourceName = unionDefinition.DeclaredTypeName
            }
        }

        if openDefinition == null {
            return false
        }

        argumentCanonicals := ColumnarTypeCanonicalizer.SplitTopLevelCommas(
            canonical.Substring(genericOpen + 1, canonical.Length - genericOpen - 2)
        )
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

    static func TrySelectOrdinaryGenericFamily(
        canonical: string,
        genericOpen: int,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        structRegistry: ColumnarSemanticRegistry<ColumnarStructDef>,
        unionRegistry: ColumnarSemanticRegistry<ColumnarUnionDef>,
        out selected: ColumnarSelectedTypeReference
    ): bool {
        table := structRegistry.StructuralTypeReferences
        selected = ColumnarSelectedTypeReference.Missing(table)

        if genericOpen == 4 && canonical.StartsWith("Span<", StringComparison.Ordinal) {
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
            ) && !ColumnarTypeOfPlanner.IsByRefLike(arguments[0].RuntimeType) && !ColumnarTypeOfPlanner.IsByRefLike(arguments[1].RuntimeType) && ColumnarTypeOfPlanner.IsSupportedType(arguments[0].RuntimeType) && ColumnarTypeOfPlanner.IsSupportedType(arguments[1].RuntimeType) {
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
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(canonical.Substring(8, canonical.Length - 9), 1, enumRegistry, structRegistry, unionRegistry, out arguments) && ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(arguments[0].RuntimeType) {
                definition := typeof(HashSet<int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 5 && canonical.StartsWith("Stack<", StringComparison.Ordinal) {
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
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(canonical.Substring(11, canonical.Length - 12), 2, enumRegistry, structRegistry, unionRegistry, out arguments) && !ColumnarTypeOfPlanner.ContainsNonEnumBuilderBoundType(arguments[0].RuntimeType) && ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[1].RuntimeType) {
                definition := typeof(Dictionary<int, int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 19 && canonical.StartsWith("IReadOnlyDictionary<", StringComparison.Ordinal) {
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(canonical.Substring(20, canonical.Length - 21), 2, enumRegistry, structRegistry, unionRegistry, out arguments) && !ColumnarTypeOfPlanner.ContainsNonEnumBuilderBoundType(arguments[0].RuntimeType) && ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[1].RuntimeType) {
                definition := ColumnarTypeOfPlanner.RequiredReadOnlyDictionaryDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        if genericOpen == 16 && canonical.StartsWith("SortedDictionary<", StringComparison.Ordinal) {
            arguments := new ColumnarSelectedTypeReference[](0)
            if TrySelectOrdinaryArguments(canonical.Substring(17, canonical.Length - 18), 2, enumRegistry, structRegistry, unionRegistry, out arguments) && !ColumnarTypeOfPlanner.ContainsBuilderBoundType(arguments[0].RuntimeType) && ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(arguments[1].RuntimeType) {
                definition := typeof(SortedDictionary<int, int>).GetGenericTypeDefinition()
                runtimeType := definition.MakeGenericType(SelectedRuntimeTypes(arguments))
                selected = ConstructedSelection(table, runtimeType, definition, arguments)
                return true
            }
            return false
        }

        return false
    }

    // Delegate selection intentionally uses the ordinary resolver, even when invoked from a
    // generic-aware entry point. This preserves the legacy order: resolve the Func return first,
    // then reject arity, then resolve parameters.
    static func TrySelectDelegateCanonical(
        argumentText: string,
        hasReturnSlot: bool,
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

        parameterCount := parts.Count
        voidType := ColumnarTypeOfPlanner.RequiredVoidType()
        returnType := voidType
        returnSelected := ColumnarSelectedTypeReference.Missing(table)
        if hasReturnSlot {
            parameterCount = parameterCount - 1
            returnCanonical := parts[parameterCount]
            if returnCanonical != "void" {
                if !TrySelectRuntimeType(
                    returnCanonical,
                    enumRegistry,
                    structRegistry,
                    unionRegistry,
                    out returnSelected
                ) || returnSelected.RuntimeType.get_Assembly() is AssemblyBuilder {
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
            if parts[i] == "void" || !TrySelectRuntimeType(
                parts[i],
                enumRegistry,
                structRegistry,
                unionRegistry,
                out parameter
            ) || parameter.RuntimeType.get_Assembly() is AssemblyBuilder {
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
        if headName != "List" && headName != "Dictionary" && headName != "SortedDictionary" && headName != "HashSet" && headName != "Stack" {
            return false
        }
        return enumRegistry.ContainsKey(headName) || structRegistry.ContainsKey(headName) || unionRegistry.ContainsKey(headName)
    }

    static func TryResolveSpecialKnownType(canonical: string, out result: Type): bool {
        result = null
        if canonical == "StringBuilder" {
            result = typeof(StringBuilder)
        } else if canonical == "object" {
            result = typeof(object)
        } else if canonical == "StringComparer" {
            result = typeof(StringComparer)
        } else if canonical == "SearchOption" {
            result = typeof(SearchOption)
        } else if canonical == "IList" {
            result = typeof(IList)
        } else if canonical == "Type" {
            result = typeof(Type)
        } else if canonical == "Version" {
            result = typeof(Version)
        } else if canonical == "TimeSpan" {
            result = typeof(TimeSpan)
        } else if canonical == "Random" {
            result = typeof(Random)
        } else if canonical == "Process" {
            result = typeof(Process)
        } else if canonical == "ProcessStartInfo" {
            result = typeof(ProcessStartInfo)
        } else if canonical == "StreamReader" {
            result = typeof(StreamReader)
        } else if canonical == "Stream" {
            result = typeof(Stream)
        } else if canonical == "CancellationToken" {
            result = typeof(CancellationToken)
        } else if canonical == "Task" {
            result = typeof(Task)
        } else if canonical == "ValueTask" {
            result = typeof(ValueTask)
        } else if canonical == "Assembly" {
            result = typeof(Assembly)
        } else {
            return false
        }
        return true
    }

    // Keep the C# helper's false/null leaf contract instead of exposing the planner helper's
    // false/object sentinel. The resolver's Type-out compatibility surface observes this value.
    static func TryResolveBuiltin(canonical: string, out result: Type): bool {
        result = null
        if canonical == "int" {
            result = typeof(int)
        } else if canonical == "long" {
            result = typeof(long)
        } else if canonical == "uint" {
            result = typeof(uint)
        } else if canonical == "ulong" {
            result = typeof(ulong)
        } else if canonical == "short" {
            result = typeof(short)
        } else if canonical == "ushort" {
            result = typeof(ushort)
        } else if canonical == "byte" {
            result = typeof(byte)
        } else if canonical == "sbyte" {
            result = typeof(sbyte)
        } else if canonical == "bool" {
            result = typeof(bool)
        } else if canonical == "char" {
            result = typeof(char)
        } else if canonical == "double" {
            result = typeof(double)
        } else if canonical == "float" {
            result = typeof(float)
        } else if canonical == "decimal" {
            result = typeof(decimal)
        } else if canonical == "string" {
            result = typeof(string)
        } else if canonical == "IntPtr" || canonical == "nint" {
            result = typeof(IntPtr)
        } else if canonical == "UIntPtr" || canonical == "nuint" {
            result = typeof(UIntPtr)
        } else if canonical == "DateTime" {
            result = typeof(DateTime)
        } else if canonical == "Index" {
            result = typeof(Index)
        } else if canonical == "Range" {
            result = typeof(Range)
        } else {
            return false
        }
        return true
    }

    static func TryResolveBclExceptionType(canonical: string, out result: Type): bool {
        result = null
        if canonical == "Exception" || canonical == "System.Exception" {
            result = typeof(Exception)
        } else if canonical == "InvalidOperationException" || canonical == "System.InvalidOperationException" {
            result = typeof(InvalidOperationException)
        } else if canonical == "ArgumentException" || canonical == "System.ArgumentException" {
            result = typeof(ArgumentException)
        } else if canonical == "ArgumentNullException" || canonical == "System.ArgumentNullException" {
            result = typeof(ArgumentNullException)
        } else if canonical == "ArgumentOutOfRangeException" || canonical == "System.ArgumentOutOfRangeException" {
            result = typeof(ArgumentOutOfRangeException)
        } else if canonical == "FormatException" || canonical == "System.FormatException" {
            result = typeof(FormatException)
        } else if canonical == "NotSupportedException" || canonical == "System.NotSupportedException" {
            result = typeof(NotSupportedException)
        } else if canonical == "NotImplementedException" || canonical == "System.NotImplementedException" {
            result = typeof(NotImplementedException)
        } else if canonical == "TimeoutException" || canonical == "System.TimeoutException" {
            result = typeof(TimeoutException)
        } else if canonical == "DivideByZeroException" || canonical == "System.DivideByZeroException" {
            result = typeof(DivideByZeroException)
        } else if canonical == "ArithmeticException" || canonical == "System.ArithmeticException" {
            result = typeof(ArithmeticException)
        } else if canonical == "OverflowException" || canonical == "System.OverflowException" {
            result = typeof(OverflowException)
        } else if canonical == "NullReferenceException" || canonical == "System.NullReferenceException" {
            result = typeof(NullReferenceException)
        } else if canonical == "IndexOutOfRangeException" || canonical == "System.IndexOutOfRangeException" {
            result = typeof(IndexOutOfRangeException)
        } else if canonical == "InvalidCastException" || canonical == "System.InvalidCastException" {
            result = typeof(InvalidCastException)
        } else if canonical == "FileNotFoundException" || canonical == "System.IO.FileNotFoundException" {
            result = typeof(FileNotFoundException)
        } else if canonical == "YamlException" || canonical == "YamlDotNet.Core.YamlException" {
            yamlException := typeof(object)
            if ColumnarTypeOfPlanner.TryResolveKnownExternalType(canonical, out yamlException) {
                result = yamlException
                return true
            }
            return false
        } else {
            return false
        }
        return true
    }
}
