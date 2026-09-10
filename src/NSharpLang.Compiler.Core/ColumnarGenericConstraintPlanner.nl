namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler.Columnar


// WHAT A `where` CLAUSE BECOMES IN METADATA, DECIDED ONCE FOR BOTH GENERIC-PARAMETER OWNERS.
//
// A generic METHOD and a generic TYPE carry the same three CLR facts on each of their parameters —
// an attribute word, at most one base-type constraint, and a set of interface constraints — and the
// rules for deriving them from a `where` clause are identical. They lived inline in the emitter's
// FUNCTION arm and nowhere else, which is why a `class Box<T> where T: struct` emitted a type
// parameter with `attrs=None`: the five `TypeBuilder.DefineGenericParameters` sites had no rules to
// apply. N# now owns both those decisions and their CLR application, called directly at all six sites.
class ColumnarGenericConstraintPlanner {
    static readonly emptyTypeConstraints: string[] = createEmptyTypeConstraints()

    static func createEmptyTypeConstraints(): string[] {
        return new string[](0)
    }

    // Preserve the caller's exact shared empty map when no row contributes a constraint. Allocation
    // is delayed until the first non-empty row, and every reached array read stays in the same order
    // as the historical producer: row length, map allocation, key, then the row value read again.
    static func BuildGenericInterfaceConstraintMap(
        typeParams: Type[],
        interfaceConstraints: Type[][],
        empty: IReadOnlyDictionary<Type, Type[]>
    ): IReadOnlyDictionary<Type, Type[]> {
        if typeParams.Length == 0 || interfaceConstraints.Length == 0 {
            return empty
        }

        map: Dictionary<Type, Type[]>? = null
        count := Math.Min(typeParams.Length, interfaceConstraints.Length)
        index := 0
        while index < count {
            if interfaceConstraints[index].Length == 0 {
                index = index + 1
                continue
            }

            if map == null {
                map = new Dictionary<Type, Type[]>()
            }
            key := typeParams[index]
            value := interfaceConstraints[index]
            map[key] = value
            index = index + 1
        }

        if map == null {
            return empty
        }
        return map
    }

    // Apply one owner's complete `where` declaration directly to its live CLR generic parameters.
    // Outputs are allocated before any per-parameter work and intentionally retain partial writes when
    // resolution declines or reflection throws. Circularity is checked only after every metadata write,
    // matching the historical mutation boundary.
    static func TryApplyGenericParameterConstraints(
        gpBuilders: GenericTypeParameterBuilder[],
        specialRows: int[],
        typeConstraintRows: string[][],
        typeParamMap: Dictionary<string, Type>,
        ownerTypeParams: Type[],
        typeResolution: ColumnarSemanticTypeResolution,
        out specials: int[],
        out baseConstraints: Type[],
        out interfaceConstraints: Type[][]
    ): bool {
        specials = new int[](gpBuilders.Length)
        baseConstraints = new Type[](gpBuilders.Length)
        interfaceConstraints = new Type[][](gpBuilders.Length)
        baseParamIndices := new int[](gpBuilders.Length)
        parameterIndex := 0
        while parameterIndex < gpBuilders.Length {
            baseParamIndices[parameterIndex] = -1
            specials[parameterIndex] = SpecialAt(specialRows, parameterIndex)
            bits := AttributeBitsFor(specials[parameterIndex])
            if bits != 0 {
                attributeBuilder := gpBuilders[parameterIndex]
                attributes := (GenericParameterAttributes)bits
                attributeBuilder.SetGenericParameterAttributes(attributes)
            }

            interfaces := new List<Type>()
            constraintTexts := TypeConstraintsAt(typeConstraintRows, parameterIndex)
            constraintIndex := 0
            while constraintIndex < constraintTexts.Length {
                text := constraintTexts[constraintIndex]
                constraintType: Type = null
                if !ColumnarCanonicalTypeResolver.TryResolveTypeWithTypeParams(
                    text,
                    typeParamMap,
                    typeResolution.Enums,
                    typeResolution.Structs,
                    typeResolution.Unions,
                    out constraintType
                ) {
                    return false
                }

                isParameter := constraintType.get_IsGenericParameter()
                ignoredInterface: ColumnarStructDef? = null
                isSourceInterface := false
                isRuntimeInterface := false
                isBuilder := false
                isValueType := false
                isAssemblyBuilderBacked := false
                isSzArray := false
                isClass := false
                if !isParameter {
                    isSourceInterface = ColumnarSourceDefinitionResolver.TryResolveInterface(
                        constraintType,
                        typeResolution.Structs.Values,
                        out ignoredInterface
                    )
                    isRuntimeInterface = ColumnarBaseTypePlanner.IsRuntimeInterfaceType(constraintType)
                    isBuilder = constraintType is TypeBuilder
                    isValueType = constraintType.get_IsValueType()
                    isAssemblyBuilderBacked = constraintType.get_Assembly() is AssemblyBuilder
                    isSzArray = ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(constraintType)
                    isClass = constraintType.get_IsClass()
                }
                kind := ClassifyConstraint(
                    isParameter,
                    isSourceInterface,
                    isRuntimeInterface,
                    isBuilder,
                    isValueType,
                    isAssemblyBuilderBacked,
                    isSzArray,
                    isClass
                )
                if kind == ConstraintKindInterface() {
                    interfaces.Add(constraintType)
                    constraintIndex = constraintIndex + 1
                    continue
                }
                if kind == ConstraintKindRefused() || baseConstraints[parameterIndex] != null {
                    return false
                }
                if isParameter {
                    ownerIndex := 0
                    while ownerIndex < ownerTypeParams.Length {
                        if Object.ReferenceEquals(ownerTypeParams[ownerIndex], constraintType) {
                            baseParamIndices[parameterIndex] = ownerIndex
                            break
                        }
                        ownerIndex = ownerIndex + 1
                    }
                    if baseParamIndices[parameterIndex] < 0 {
                        return false
                    }
                }
                baseBuilder := gpBuilders[parameterIndex]
                baseBuilder.SetBaseTypeConstraint(constraintType)
                baseConstraints[parameterIndex] = constraintType
                constraintIndex = constraintIndex + 1
            }

            interfaceConstraints[parameterIndex] = interfaces.ToArray()
            if interfaces.Count > 0 {
                interfaceBuilder := gpBuilders[parameterIndex]
                interfaceBuilder.SetInterfaceConstraints(interfaceConstraints[parameterIndex])
            }
            parameterIndex = parameterIndex + 1
        }
        return !HasCircularConstraint(baseParamIndices)
    }

    // Type declarations carry their generic builders in a name map. Preserve the early null return,
    // then lift every parameter in declared order before entering the shared application path.
    static func TryApplyDeclaredTypeConstraints(
        typeParamNames: string[],
        genericParams: Dictionary<string, Type>?,
        specials: int[],
        typeConstraints: string[][],
        typeResolution: ColumnarSemanticTypeResolution
    ): bool {
        if genericParams == null {
            return true
        }

        builders := new GenericTypeParameterBuilder[](typeParamNames.Length)
        index := 0
        while index < builders.Length {
            parameterName := typeParamNames[index]
            parameterType: object = genericParams[parameterName]
            builder := (GenericTypeParameterBuilder)parameterType
            builders[index] = builder
            index = index + 1
        }

        appliedSpecials: int[] = null
        appliedBases: Type[] = null
        appliedInterfaces: Type[][] = null
        return TryApplyGenericParameterConstraints(
            builders,
            specials,
            typeConstraints,
            genericParams,
            builders,
            typeResolution,
            out appliedSpecials,
            out appliedBases,
            out appliedInterfaces
        )
    }

    // Reflection.Emit does not validate constraints when MakeGenericMethod closes an unbaked sibling
    // MethodBuilder. Validate the carried declaration facts before the call is emitted. The bound-argument
    // length remains the controlling length, and each parameter reads special, base, then interface facts
    // before deciding whether the bound itself needs to be observed.
    static func TryValidateGenericSiblingConstraints(
        typeParams: Type[],
        specialConstraints: int[],
        baseConstraints: Type[],
        interfaceConstraintRows: Type[][],
        binding: Type[],
        boundArgs: Type[],
        structRegistry: IReadOnlyDictionary<string, ColumnarStructDef>
    ): bool {
        parameterIndex := 0
        while parameterIndex < boundArgs.Length {
            special := 0
            if specialConstraints.Length > parameterIndex {
                special = specialConstraints[parameterIndex]
            }
            baseConstraint: Type = null
            if baseConstraints.Length > parameterIndex {
                baseConstraint = baseConstraints[parameterIndex]
            }
            interfaceConstraints: Type[] = null
            if interfaceConstraintRows.Length > parameterIndex {
                interfaceConstraints = interfaceConstraintRows[parameterIndex]
            } else {
                interfaceConstraints = System.Type.EmptyTypes
            }
            if special == 0 && baseConstraint == null && interfaceConstraints.Length == 0 {
                parameterIndex = parameterIndex + 1
                continue
            }

            bound := boundArgs[parameterIndex]
            if bound.get_IsGenericParameter() {
                return false
            }
            if (special & 1) != 0 && bound.get_IsValueType() {
                return false
            }
            if (special & 2) != 0 && (!bound.get_IsValueType() || Nullable.GetUnderlyingType(bound) != null) {
                return false
            }
            if (special & 4) != 0 && !HasPublicParameterlessConstructorForConstraint(bound, structRegistry) {
                return false
            }

            if baseConstraint != null && !BoundSatisfiesBaseConstraint(typeParams, boundArgs, bound, baseConstraint) {
                return false
            }
            constraintIndex := 0
            while constraintIndex < interfaceConstraints.Length {
                closedInterfaceConstraint: Type = null
                if !TrySubstituteGenericTypeArguments(
                    typeParams,
                    binding,
                    interfaceConstraints[constraintIndex],
                    out closedInterfaceConstraint
                ) || !BoundSatisfiesInterfaceConstraint(bound, closedInterfaceConstraint, structRegistry) {
                    return false
                }
                constraintIndex = constraintIndex + 1
            }
            parameterIndex = parameterIndex + 1
        }

        return true
    }

    // A `new()` constraint asks whether the bound argument can be constructed with no arguments.
    // A SOURCE type is answered from its own declaration table and never by reflection: an unbaked
    // `TypeBuilder` — and a constructed generic over one — throws
    // "The invoked member is not supported before the type is created" from `GetConstructor`, so a
    // source argument that declares its own parameterless constructor would crash the emission
    // instead of answering.
    static func HasPublicParameterlessConstructorForConstraint(
        bound: Type,
        structRegistry: IReadOnlyDictionary<string, ColumnarStructDef>
    ): bool {
        if bound.get_IsValueType() {
            return true
        }

        sourceDefinition := TryResolveSourceDefinitionForConstraint(bound, structRegistry)
        if sourceDefinition != null {
            if sourceDefinition.DefaultCtor != null {
                return true
            }
            for candidate in sourceDefinition.Constructors {
                if candidate.ParamTypes.Length == 0 {
                    return true
                }
            }
            return false
        }

        if ColumnarTypeOfPlanner.ContainsBuilderBoundType(bound) {
            return false
        }

        return bound.GetConstructor(System.Type.EmptyTypes) != null
    }

    // The source declaration behind a bound argument, whether the argument is the open builder
    // itself or a constructed instantiation of it.
    static func TryResolveSourceDefinitionForConstraint(
        bound: Type,
        structRegistry: IReadOnlyDictionary<string, ColumnarStructDef>
    ): ColumnarStructDef? {
        builder := bound as TypeBuilder
        if builder != null {
            return ColumnarSourceDefinitionResolver.FindByBuilderIdentity(structRegistry.get_Values(), builder)
        }

        if ColumnarTypeOfPlanner.IsClosedSourceGeneric(bound) {
            definitionBuilder := bound.GetGenericTypeDefinition() as TypeBuilder
            if definitionBuilder != null {
                return ColumnarSourceDefinitionResolver.FindByBuilderIdentity(structRegistry.get_Values(), definitionBuilder)
            }
        }

        return null
    }

    static func BoundSatisfiesBaseConstraint(
        typeParams: Type[],
        boundArgs: Type[],
        bound: Type,
        baseConstraint: Type
    ): bool {
        if baseConstraint.get_IsGenericParameter() {
            otherPosition := -1
            parameterIndex := 0
            while parameterIndex < typeParams.Length {
                if Object.ReferenceEquals(typeParams[parameterIndex], baseConstraint) {
                    otherPosition = parameterIndex
                    break
                }
                parameterIndex = parameterIndex + 1
            }
            if otherPosition < 0 {
                return false
            }

            otherBound := boundArgs[otherPosition]
            if otherBound.get_IsGenericParameter() {
                return false
            }
            if otherBound.get_Assembly() is AssemblyBuilder {
                return false
            }
            return otherBound.IsAssignableFrom(bound)
        }

        if baseConstraint.get_Assembly() is AssemblyBuilder {
            return false
        }
        if bound.get_IsGenericParameter() {
            return false
        }
        if bound.get_Assembly() is AssemblyBuilder {
            return false
        }
        return baseConstraint.IsAssignableFrom(bound)
    }

    static func BoundSatisfiesInterfaceConstraint(
        bound: Type,
        interfaceConstraint: Type,
        structRegistry: IReadOnlyDictionary<string, ColumnarStructDef>
    ): bool {
        boundBuilder := bound as TypeBuilder
        if boundBuilder != null {
            boundDefinition := ColumnarSourceDefinitionResolver.FindByBuilderIdentity(
                structRegistry.get_Values(),
                boundBuilder
            )
            if boundDefinition != null {
                implementedEnumerator := boundDefinition.ImplementedInterfaceTypes.GetEnumerator()
                try {
                    while implementedEnumerator.MoveNext() {
                        implemented := implementedEnumerator.get_Current()
                        if ColumnarTypeEquivalenceFacts.TypesEquivalent(implemented, interfaceConstraint) {
                            return true
                        }
                    }
                } finally {
                    implementedEnumerator.Dispose()
                }

                interfaceBuilder := interfaceConstraint as TypeBuilder
                if interfaceBuilder == null {
                    return false
                }
                return AnyInterfaceEqualsOrExtends(
                    boundDefinition.ImplementedInterfaces,
                    interfaceBuilder
                )
            }
        }

        if bound.get_Assembly() is AssemblyBuilder {
            return false
        }
        return ColumnarBaseTypePlanner.IsRuntimeInterfaceType(interfaceConstraint) && interfaceConstraint.IsAssignableFrom(bound)
    }

    static func InterfaceEqualsOrExtends(
        interfaceDefinition: ColumnarStructDef,
        targetBuilder: TypeBuilder
    ): bool {
        candidates := new List<ColumnarStructDef>()
        ColumnarBaseTypePlanner.EnumerateInterfaceAndBases(interfaceDefinition, candidates)
        candidateEnumerator := candidates.GetEnumerator()
        try {
            while candidateEnumerator.MoveNext() {
                candidate := candidateEnumerator.get_Current()
                if Object.ReferenceEquals(candidate.Builder, targetBuilder) {
                    return true
                }
            }
        } finally {
            candidateEnumerator.Dispose()
        }
        return false
    }

    static func AnyInterfaceEqualsOrExtends(
        interfaceDefinitions: IEnumerable<ColumnarStructDef>,
        targetBuilder: TypeBuilder
    ): bool {
        enumerator := interfaceDefinitions.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            if movement == null {
                throw new NullReferenceException()
            }
            while movement.MoveNext() {
                interfaceDefinition := enumerator.get_Current()
                if InterfaceEqualsOrExtends(interfaceDefinition, targetBuilder) {
                    return true
                }
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return false
    }

    // Substitute every occurrence of one of the callee's parameters through arrays, managed
    // references, and closed generic shapes. A miss or any still-open leaf declines after clearing
    // the out slot; reflection failures and partially-created local arrays remain observable.
    static func TrySubstituteGenericTypeArguments(
        typeParams: Type[],
        binding: Type[],
        sourceType: Type,
        out substituted: Type
    ): bool {
        substituted = null
        if sourceType.get_IsGenericParameter() {
            parameterIndex := 0
            while parameterIndex < typeParams.Length {
                if Object.ReferenceEquals(typeParams[parameterIndex], sourceType) {
                    if binding[parameterIndex] == null {
                        return false
                    }
                    substituted = binding[parameterIndex]
                    return true
                }
                parameterIndex = parameterIndex + 1
            }
            return false
        }

        if sourceType.get_IsSZArray() {
            element: Type = null
            if !TrySubstituteGenericTypeArguments(
                typeParams,
                binding,
                sourceType.GetElementType(),
                out element
            ) {
                return false
            }
            substituted = element.MakeArrayType()
            return true
        }

        if sourceType.get_IsByRef() {
            element: Type = null
            if !TrySubstituteGenericTypeArguments(
                typeParams,
                binding,
                sourceType.GetElementType(),
                out element
            ) {
                return false
            }
            substituted = element.MakeByRefType()
            return true
        }

        if sourceType.get_IsGenericType() && !sourceType.get_IsGenericTypeDefinition() {
            arguments := sourceType.GetGenericArguments()
            substitutedArguments := new Type[](arguments.Length)
            argumentIndex := 0
            while argumentIndex < arguments.Length {
                substitutedArgument: Type = null
                if !TrySubstituteGenericTypeArguments(
                    typeParams,
                    binding,
                    arguments[argumentIndex],
                    out substitutedArgument
                ) {
                    return false
                }
                substitutedArguments[argumentIndex] = substitutedArgument
                argumentIndex = argumentIndex + 1
            }
            definition := sourceType.GetGenericTypeDefinition()
            substituted = definition.MakeGenericType(substitutedArguments)
            return true
        }

        if sourceType.get_ContainsGenericParameters() {
            return false
        }
        substituted = sourceType
        return true
    }

    // Resolve the constraints used by a constrained receiver without rebuilding the declaration
    // map. An exact dictionary hit retains the supplied map's comparer and exact array value. The
    // weak fallback deliberately compares only a live parameter name and ordinal, matching the
    // historical lookup across distinct Reflection.Emit handles.
    static func ResolveCallConstraints(
        map: IReadOnlyDictionary<Type, Type[]>,
        requested: Type
    ): Type[] {
        exact: Type[] = null
        if map.TryGetValue(requested, out exact) {
            return exact
        }

        weak: Type[] = null
        if TryFindWeakCallConstraints(map, requested, out weak) {
            return weak
        }

        try {
            return requested.GetGenericParameterConstraints()
        } catch ex: NotSupportedException {
            return System.Type.EmptyTypes
        } catch ex: NotImplementedException {
            return System.Type.EmptyTypes
        }
    }

    // The IReadOnlyDictionary's inherited enumerable view is passed directly by the caller. This
    // keeps the exact IEnumerator<KeyValuePair<Type, Type[]>> Current slot while permitting explicit
    // disposal around an early first-match return.
    static func TryFindWeakCallConstraints(
        entries: IEnumerable<KeyValuePair<Type, Type[]>>,
        requested: Type,
        out constraints: Type[]
    ): bool {
        enumerator := entries.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            if movement == null {
                throw new NullReferenceException()
            }

            while movement.MoveNext() {
                pair := enumerator.get_Current()
                left := pair.get_Key()
                if GenericParameterIdentityMatches(left, requested) {
                    constraints = pair.get_Value()
                    return true
                }
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }

        constraints = null
        return false
    }

    static func GenericParameterIdentityMatches(left: Type, right: Type): bool {
        if !left.get_IsGenericParameter() || !right.get_IsGenericParameter() || left.get_Name() != right.get_Name() {
            return false
        }

        try {
            return left.get_GenericParameterPosition() == right.get_GenericParameterPosition()
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }
    }

    // `GenericParameterAttributes` (ECMA-335 II.23.1.7), as integers because the emitter's own bits are
    // CLR-side: ReferenceTypeConstraint 4, NotNullableValueTypeConstraint 8, DefaultConstructorConstraint 16.
    static func ReferenceTypeConstraintBit(): int {
        return 4
    }

    static func NotNullableValueTypeConstraintBit(): int {
        return 8
    }

    static func DefaultConstructorConstraintBit(): int {
        return 16
    }

    // THE TWO BOUNDS GUARDS AT THE `where` SITE, AND WHY THEY ARE NOT BELT-AND-BRACES.
    //
    // `ColumnarConstraintColumns.SpecialsOrEmpty` / `TypesOrEmpty` are named as if they normalise, and
    // they DO -- but only for NULL. A non-null array SHORTER than the type-parameter count is returned
    // UNCHANGED, `typeParamCount` unused, so an owner declaring three parameters can reach emit with a
    // two-entry specials row. Reading it unguarded would throw on a shape the emitter accepts today,
    // which is the same class of trap as the field family's readonly flags. The guards are therefore
    // rules with contracts, not defensive noise at a call site.
    //
    // A parameter past the end has NO special constraint (0) and NO type constraints (an empty row) --
    // never a missing row the caller must test for.
    static func SpecialAt(specialRows: int[], index: int): int {
        if specialRows != null && index < specialRows.Length {
            return specialRows[index]
        }
        return 0
    }

    static func TypeConstraintsAt(typeConstraintRows: string[][], index: int): string[] {
        if typeConstraintRows != null && index < typeConstraintRows.Length {
            return typeConstraintRows[index]
        }
        // Preserve the host's shared empty answer without allocating for each missing row.
        return ColumnarGenericConstraintPlanner.emptyTypeConstraints
    }

    // `SpecialConstraintKind` (Class 1, Struct 2, New 4) to the CLR's attribute word.
    //
    // `struct` IMPLIES the default-constructor bit and the `new()` bit is then redundant — every value
    // type has a parameterless constructor — which is what the CLR itself records and what the legacy
    // emitter set. The `else if` matters: `where T: struct, new()` must not set the ctor bit twice by
    // two routes and must not be refused for saying the same thing twice.
    static func AttributeBitsFor(special: int): int {
        bits := 0
        if (special & 1) != 0 {
            bits = bits | ReferenceTypeConstraintBit()
        }

        if (special & 2) != 0 {
            bits = bits | NotNullableValueTypeConstraintBit() | DefaultConstructorConstraintBit()
        } else if (special & 4) != 0 {
            bits = bits | DefaultConstructorConstraintBit()
        }

        return bits
    }

    // Whether a resolved constraint type is admissible as a BASE-TYPE constraint.
    //
    // The caller answers the four CLR questions (it holds the `Type`); this holds the rule. A type
    // PARAMETER is always admissible — `where T: U` is a real constraint. An emitted user type is
    // admissible only with REFERENCE layout, because a value struct cannot be a base. Everything else
    // must be a plain runtime class: an `AssemblyBuilder` shape (EnumBuilder, TypeBuilderInstantiation),
    // a value type, an array and a non-class are all unmodeled targets.
    static func IsAdmissibleBaseConstraint(isGenericParameter: bool, isTypeBuilder: bool, isValueType: bool, isFromAssemblyBuilder: bool, isSzArray: bool, isClass: bool): bool {
        if isGenericParameter {
            return true
        }

        if isTypeBuilder {
            return !isValueType
        }

        return !isFromAssemblyBuilder && !isValueType && !isSzArray && isClass
    }

    // WHAT ONE RESOLVED CONSTRAINT IS: an interface to add to the set, the single base-type constraint,
    // or a shape the emitter does not model. The caller answers the CLR questions because it holds the
    // `Type`; the DECISION is here, so both generic-parameter owners reach it the same way.
    //
    // A type PARAMETER is a BASE constraint (`where T: U`), never an interface — it is not known to be
    // one, and the CLR records it in the base slot. The caller must pass `false` for the four
    // shape questions when the constraint IS a parameter: `Type.IsSZArray` throws on a bare parameter
    // under persisted emit, so those answers must never be computed for one.
    static func ConstraintKindInterface(): int {
        return 0
    }

    static func ConstraintKindBase(): int {
        return 1
    }

    static func ConstraintKindRefused(): int {
        return -1
    }

    static func ClassifyConstraint(isGenericParameter: bool, isUserInterface: bool, isRuntimeInterface: bool, isTypeBuilder: bool, isValueType: bool, isFromAssemblyBuilder: bool, isSzArray: bool, isClass: bool): int {
        if isGenericParameter {
            return ConstraintKindBase()
        }

        if isUserInterface || isRuntimeInterface {
            return ConstraintKindInterface()
        }

        if IsAdmissibleBaseConstraint(false, isTypeBuilder, isValueType, isFromAssemblyBuilder, isSzArray, isClass) {
            return ConstraintKindBase()
        }

        return ConstraintKindRefused()
    }

    // CIRCULAR type-parameter constraints (`where T: T`, `where T: U where U: T`) emit metadata the CLR
    // REJECTS at load with a TypeLoadException — probe-proven over-accept, so the emitter must decline
    // rather than write it.
    //
    // `baseParamIndices[g]` is the index of the type parameter that g's base constraint names, or -1 when
    // g has no base constraint or names something that is not one of this owner's parameters. Walking
    // more steps than there are parameters means the chain re-entered itself.
    static func HasCircularConstraint(baseParamIndices: int[]): bool {
        g := 0
        while g < baseParamIndices.Length {
            steps := 0
            cursor := g
            while cursor >= 0 && baseParamIndices[cursor] >= 0 {
                cursor = baseParamIndices[cursor]
                steps = steps + 1
                if steps > baseParamIndices.Length {
                    return true
                }
            }

            g = g + 1
        }

        return false
    }

    // A constraint row set is well-formed only when every parameter that carries one is a parameter this
    // owner declared. A non-generic owner with constraint rows is malformed outright.
    static func HasConstraintsWithoutTypeParameters(typeParamCount: int, specialCount: int, typeConstraintCount: int): bool {
        return typeParamCount == 0 && (specialCount > 0 || typeConstraintCount > 0)
    }
}
