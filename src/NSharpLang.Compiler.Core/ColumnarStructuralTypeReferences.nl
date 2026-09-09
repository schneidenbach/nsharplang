namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection

enum ColumnarStructuralTypeReferenceKind {
    Primitive = 0,
    SourceDefinition = 1,
    ExternalNamedDefinition = 2,
    ConstructedGeneric = 3,
    SzArray = 4,
    ByRef = 5,
    TypeGenericParameter = 6,
    MethodGenericParameter = 7,
    SynthesizedDefinition = 8
}

enum ColumnarStructuralGenericOwnerKind {
    SourceType = 0,
    SourceMethod = 1,
    SourceUnionCase = 2,
    SynthesizedType = 3,
    ExternalType = 4,
    ExternalMethod = 5
}

// Reference identity is intentional. One parsed ColumnarProgramInput may be emitted more than once,
// so each emission catalog owns a fresh token and a key from one emission cannot validate in another.
class ColumnarStructuralTypeEmissionIdentity {
}

class ColumnarStructuralGenericOwnerIdentity {
    readonly kindValue: ColumnarStructuralGenericOwnerKind
    readonly sourceFileIdValue: int
    readonly declaringTypeNameValue: string
    readonly memberOrdinalValue: int

    Kind: ColumnarStructuralGenericOwnerKind => kindValue
    SourceFileId: int => sourceFileIdValue
    DeclaringTypeName: string => declaringTypeNameValue
    MemberOrdinal: int => memberOrdinalValue

    constructor(kind: ColumnarStructuralGenericOwnerKind, sourceFileId: int, declaringTypeName: string, memberOrdinal: int) {
        kindValue = kind
        sourceFileIdValue = sourceFileId
        declaringTypeNameValue = declaringTypeName
        memberOrdinalValue = memberOrdinal
    }

    static func SourceType(sourceFileId: int, declarationName: string): ColumnarStructuralGenericOwnerIdentity {
        return new ColumnarStructuralGenericOwnerIdentity(ColumnarStructuralGenericOwnerKind.SourceType, sourceFileId, declarationName, -1)
    }

    static func SourceMethod(sourceFileId: int, methodOrdinal: int): ColumnarStructuralGenericOwnerIdentity {
        return new ColumnarStructuralGenericOwnerIdentity(ColumnarStructuralGenericOwnerKind.SourceMethod, sourceFileId, "", methodOrdinal)
    }

    static func SourceUnionCase(sourceFileId: int, unionName: string, caseOrdinal: int): ColumnarStructuralGenericOwnerIdentity {
        return new ColumnarStructuralGenericOwnerIdentity(ColumnarStructuralGenericOwnerKind.SourceUnionCase, sourceFileId, unionName, caseOrdinal)
    }

    static func SynthesizedType(sourceFileId: int, stableOwnerName: string, memberOrdinal: int): ColumnarStructuralGenericOwnerIdentity {
        return new ColumnarStructuralGenericOwnerIdentity(ColumnarStructuralGenericOwnerKind.SynthesizedType, sourceFileId, stableOwnerName, memberOrdinal)
    }
}

class ColumnarStructuralGenericParameterIdentity {
    readonly ownerValue: ColumnarStructuralGenericOwnerIdentity
    readonly parameterOrdinalValue: int

    Owner: ColumnarStructuralGenericOwnerIdentity => ownerValue
    ParameterOrdinal: int => parameterOrdinalValue

    constructor(owner: ColumnarStructuralGenericOwnerIdentity, parameterOrdinal: int) {
        ownerValue = owner
        parameterOrdinalValue = parameterOrdinal
    }
}

// External generic parameters are owned by portable CLR metadata identity rather than an emission
// registration. A VAR names its exact open declaring definition. An MVAR additionally names its
// MethodDef within that definition; the token is retained together with the module, name, arity and
// calling-convention facts rather than being treated as a substitute for the method signature.
class ColumnarStructuralExternalGenericOwnerIdentity {
    readonly kindValue: ColumnarStructuralGenericOwnerKind
    readonly declaringTypeValue: ColumnarStructuralTypeKey
    readonly moduleVersionIdValue: string
    readonly methodMetadataTokenValue: int
    readonly methodNameValue: string
    readonly methodGenericArityValue: int
    readonly methodCallingConventionValue: int
    readonly methodIsStaticValue: bool

    Kind: ColumnarStructuralGenericOwnerKind => kindValue
    DeclaringType: ColumnarStructuralTypeKey => declaringTypeValue
    ModuleVersionId: string => moduleVersionIdValue
    MethodMetadataToken: int => methodMetadataTokenValue
    MethodName: string => methodNameValue
    MethodGenericArity: int => methodGenericArityValue
    MethodCallingConvention: int => methodCallingConventionValue
    MethodIsStatic: bool => methodIsStaticValue

    constructor(
        kind: ColumnarStructuralGenericOwnerKind,
        declaringType: ColumnarStructuralTypeKey,
        moduleVersionId: string,
        methodMetadataToken: int,
        methodName: string,
        methodGenericArity: int,
        methodCallingConvention: int,
        methodIsStatic: bool
    ) {
        if declaringType == null || moduleVersionId == null || methodName == null {
            throw new InvalidOperationException("External generic-owner identity values cannot be null.")
        }
        kindValue = kind
        declaringTypeValue = declaringType
        moduleVersionIdValue = moduleVersionId
        methodMetadataTokenValue = methodMetadataToken
        methodNameValue = methodName
        methodGenericArityValue = methodGenericArity
        methodCallingConventionValue = methodCallingConvention
        methodIsStaticValue = methodIsStatic
    }
}

// The key contains metadata identity only. Constructor inputs are copied into BCL read-only
// collections whose mutable List backing is never retained by a caller.
class ColumnarStructuralTypeKey {
    readonly kindValue: ColumnarStructuralTypeReferenceKind
    readonly emissionIdentityValue: ColumnarStructuralTypeEmissionIdentity?
    readonly primitiveNameValue: string
    readonly sourceDeclarationNameValue: string
    readonly assemblyIdentityValue: string
    readonly namespaceNameValue: string
    readonly nestedNamesValue: IReadOnlyList<string>
    readonly nestedNameCountValue: int
    readonly isValueTypeValue: bool
    readonly genericOwnerKindValue: ColumnarStructuralGenericOwnerKind
    readonly genericOwnerSourceFileIdValue: int
    readonly genericOwnerDeclaringTypeNameValue: string
    readonly genericOwnerMemberOrdinalValue: int
    readonly genericParameterOrdinalValue: int
    readonly externalGenericOwnerValue: ColumnarStructuralExternalGenericOwnerIdentity?
    readonly childrenValue: IReadOnlyList<object>
    readonly childCountValue: int

    Kind: ColumnarStructuralTypeReferenceKind => kindValue
    EmissionIdentity: ColumnarStructuralTypeEmissionIdentity? => emissionIdentityValue
    PrimitiveName: string => primitiveNameValue
    SourceDeclarationName: string => sourceDeclarationNameValue
    AssemblyIdentity: string => assemblyIdentityValue
    NamespaceName: string => namespaceNameValue
    IsValueType: bool => isValueTypeValue
    GenericOwnerKind: ColumnarStructuralGenericOwnerKind => genericOwnerKindValue
    GenericOwnerSourceFileId: int => genericOwnerSourceFileIdValue
    GenericOwnerDeclaringTypeName: string => genericOwnerDeclaringTypeNameValue
    GenericOwnerMemberOrdinal: int => genericOwnerMemberOrdinalValue
    GenericParameterOrdinal: int => genericParameterOrdinalValue
    ExternalGenericOwner: ColumnarStructuralExternalGenericOwnerIdentity? => externalGenericOwnerValue
    NestedNameCount: int => nestedNameCountValue
    ChildCount: int => childCountValue

    constructor(
        kind: ColumnarStructuralTypeReferenceKind,
        emissionIdentity: ColumnarStructuralTypeEmissionIdentity?,
        primitiveName: string,
        sourceDeclarationName: string,
        assemblyIdentity: string,
        namespaceName: string,
        nestedNames: string[],
        isValueType: bool,
        genericOwnerKind: ColumnarStructuralGenericOwnerKind,
        genericOwnerSourceFileId: int,
        genericOwnerDeclaringTypeName: string,
        genericOwnerMemberOrdinal: int,
        genericParameterOrdinal: int,
        externalGenericOwner: ColumnarStructuralExternalGenericOwnerIdentity?,
        children: ColumnarStructuralTypeKey[]
    ) {
        if primitiveName == null || sourceDeclarationName == null || assemblyIdentity == null || namespaceName == null || genericOwnerDeclaringTypeName == null || nestedNames == null || children == null {
            throw new InvalidOperationException("Structural key identity values cannot be null.")
        }
        kindValue = kind
        emissionIdentityValue = emissionIdentity
        primitiveNameValue = primitiveName
        sourceDeclarationNameValue = sourceDeclarationName
        assemblyIdentityValue = assemblyIdentity
        namespaceNameValue = namespaceName
        nestedNamesCopy := new List<string>()
        i := 0
        while i < nestedNames.Length {
            if nestedNames[i] == null {
                throw new InvalidOperationException("Structural key names cannot contain null entries.")
            }
            nestedNamesCopy.Add(nestedNames[i])
            i += 1
        }
        nestedNamesValue = nestedNamesCopy.AsReadOnly()
        nestedNameCountValue = nestedNames.Length
        isValueTypeValue = isValueType
        genericOwnerKindValue = genericOwnerKind
        genericOwnerSourceFileIdValue = genericOwnerSourceFileId
        genericOwnerDeclaringTypeNameValue = genericOwnerDeclaringTypeName
        genericOwnerMemberOrdinalValue = genericOwnerMemberOrdinal
        genericParameterOrdinalValue = genericParameterOrdinal
        externalGenericOwnerValue = externalGenericOwner
        childrenCopy := new List<object>()
        i = 0
        while i < children.Length {
            if children[i] == null {
                throw new InvalidOperationException("Structural key children cannot contain null entries.")
            }
            childrenCopy.Add(children[i])
            i += 1
        }
        childrenValue = childrenCopy.AsReadOnly()
        childCountValue = children.Length
    }

    func NestedName(index: int): string {
        return nestedNamesValue.get_Item(index)
    }

    func Child(index: int): ColumnarStructuralTypeKey {
        child := childrenValue.get_Item(index) as ColumnarStructuralTypeKey
        if child == null {
            throw new InvalidOperationException("Structural key child storage is invalid.")
        }
        return child
    }
}

class ColumnarSelectedTypeReference {
    readonly emissionIdentityValue: ColumnarStructuralTypeEmissionIdentity
    readonly keyValue: ColumnarStructuralTypeKey?
    readonly runtimeTypeValue: Type
    readonly hasRuntimeTypeValue: bool
    readonly sourceProvenanceEmissionValue: ColumnarStructuralTypeEmissionIdentity?
    readonly sourceProvenanceNameValue: string

    EmissionIdentity: ColumnarStructuralTypeEmissionIdentity => emissionIdentityValue
    Key: ColumnarStructuralTypeKey? => keyValue
    RuntimeType: Type => runtimeTypeValue
    HasRuntimeType: bool => hasRuntimeTypeValue
    SourceProvenanceEmission: ColumnarStructuralTypeEmissionIdentity? => sourceProvenanceEmissionValue
    SourceProvenanceName: string => sourceProvenanceNameValue

    constructor(emissionIdentity: ColumnarStructuralTypeEmissionIdentity, key: ColumnarStructuralTypeKey?, runtimeType: Type, hasRuntimeType: bool, sourceProvenanceEmission: ColumnarStructuralTypeEmissionIdentity?, sourceProvenanceName: string) {
        if emissionIdentity == null || sourceProvenanceName == null {
            throw new InvalidOperationException("A selected structural reference requires non-null identity values.")
        }
        emissionIdentityValue = emissionIdentity
        keyValue = key
        runtimeTypeValue = runtimeType
        hasRuntimeTypeValue = hasRuntimeType
        sourceProvenanceEmissionValue = sourceProvenanceEmission
        sourceProvenanceNameValue = sourceProvenanceName
    }

    static func Missing(table: ColumnarStructuralTypeReferenceTable): ColumnarSelectedTypeReference {
        return new ColumnarSelectedTypeReference(table.Identity, null, typeof(object), false, null, "")
    }

    // Some legacy resolution failures intentionally retain an unsupported non-null Type. They carry
    // no key: failed values are observable to callers but never admissible in a keyed metadata pool.
    static func RejectedWithRuntime(table: ColumnarStructuralTypeReferenceTable, runtimeType: Type): ColumnarSelectedTypeReference {
        return new ColumnarSelectedTypeReference(table.Identity, null, runtimeType, true, null, "")
    }
}

// A pool row keeps the selecting table beside the immutable selected reference. The executor uses
// this object to revalidate the key/runtime pair before any ILGenerator mutation.
class ColumnarStructuralTypePoolEntry {
    readonly tableValue: ColumnarStructuralTypeReferenceTable
    readonly selectedValue: ColumnarSelectedTypeReference

    Table: ColumnarStructuralTypeReferenceTable => tableValue
    Selected: ColumnarSelectedTypeReference => selectedValue

    constructor(table: ColumnarStructuralTypeReferenceTable, selected: ColumnarSelectedTypeReference) {
        if table == null || selected == null {
            throw new InvalidOperationException("A structural type-pool entry requires a table and selected reference.")
        }
        tableValue = table
        selectedValue = selected
    }

    func MatchesRuntime(runtimeType: Type): bool {
        return tableValue.ValidatePair(selectedValue, runtimeType)
    }
}

// One table belongs to one semantic resolution catalog and therefore to one emission. Runtime
// companions remain local to this table and are never recovered from a process-wide Type lookup.
class ColumnarStructuralTypeReferenceTable {
    readonly identityValue: ColumnarStructuralTypeEmissionIdentity
    readonly rowsValue: List<ColumnarStructuralTypeKey>
    readonly sourceTypesByName: Dictionary<string, Type>
    readonly synthesizedTypeNames: HashSet<string>
    readonly uniqueSourceNamesByType: Dictionary<Type, string>
    readonly ambiguousSourceTypes: HashSet<Type>
    readonly genericParameters: Dictionary<Type, ColumnarStructuralGenericParameterIdentity>

    Identity: ColumnarStructuralTypeEmissionIdentity => identityValue
    RowCount: int => rowsValue.Count

    constructor() {
        identityValue = new ColumnarStructuralTypeEmissionIdentity()
        rowsValue = new List<ColumnarStructuralTypeKey>()
        sourceTypesByName = new Dictionary<string, Type>(StringComparer.Ordinal)
        synthesizedTypeNames = new HashSet<string>(StringComparer.Ordinal)
        uniqueSourceNamesByType = new Dictionary<Type, string>()
        ambiguousSourceTypes = new HashSet<Type>()
        genericParameters = new Dictionary<Type, ColumnarStructuralGenericParameterIdentity>()
    }

    func RegisterSourceDefinition(exactName: string, runtimeType: Type, erasedToRuntimeIdentity: bool) {
        if exactName == null || exactName.Length == 0 || runtimeType == null {
            throw new InvalidOperationException("Structural source identities require an exact name and runtime companion.")
        }
        existing := typeof(object)
        if sourceTypesByName.TryGetValue(exactName, out existing) {
            if !Object.ReferenceEquals(existing, runtimeType) {
                throw new InvalidOperationException("A structural source identity cannot change runtime companion within one emission.")
            }
            return
        }
        sourceTypesByName.Add(exactName, runtimeType)
        if erasedToRuntimeIdentity {
            return
        }
        priorName := ""
        if uniqueSourceNamesByType.TryGetValue(runtimeType, out priorName) {
            if priorName != exactName {
                uniqueSourceNamesByType.Remove(runtimeType)
                ambiguousSourceTypes.Add(runtimeType)
            }
        } else if !ambiguousSourceTypes.Contains(runtimeType) {
            uniqueSourceNamesByType.Add(runtimeType, exactName)
        }
    }

    func RegisterSynthesizedDefinition(stableIdentity: string, runtimeType: Type) {
        if stableIdentity == null || stableIdentity.Length == 0 || runtimeType == null || sourceTypesByName.ContainsKey(stableIdentity) {
            throw new InvalidOperationException("A synthesized structural definition requires a new stable emission identity and runtime companion.")
        }
        sourceTypesByName.Add(stableIdentity, runtimeType)
        synthesizedTypeNames.Add(stableIdentity)
        priorName := ""
        if uniqueSourceNamesByType.TryGetValue(runtimeType, out priorName) {
            if priorName != stableIdentity {
                uniqueSourceNamesByType.Remove(runtimeType)
                ambiguousSourceTypes.Add(runtimeType)
            }
        } else if !ambiguousSourceTypes.Contains(runtimeType) {
            uniqueSourceNamesByType.Add(runtimeType, stableIdentity)
        }
    }

    // Registration happens at the declaration that created these parameters. Scoped views only read
    // the registration; they never relabel a supplied substitution as their own generic parameter.
    func RegisterGenericParameters(parameters: Dictionary<string, Type>?, owner: ColumnarStructuralGenericOwnerIdentity?) {
        if parameters == null || parameters.Count == 0 {
            return
        }
        if owner == null {
            throw new InvalidOperationException("Structural generic parameters require a known owner identity.")
        }
        if owner.Kind == ColumnarStructuralGenericOwnerKind.ExternalType || owner.Kind == ColumnarStructuralGenericOwnerKind.ExternalMethod {
            throw new InvalidOperationException("External generic-parameter owners are derived from their runtime metadata identity.")
        }
        for pair in parameters {
            parameter := pair.Value
            if !parameter.get_IsGenericParameter() {
                throw new InvalidOperationException("A structural generic-parameter registration must carry a generic parameter Type.")
            }
            ownerIsMethod := owner.Kind == ColumnarStructuralGenericOwnerKind.SourceMethod
            parameterIsMethod := parameter.get_IsGenericMethodParameter()
            parameterIsType := parameter.get_IsGenericTypeParameter()
            if parameterIsMethod == parameterIsType || ownerIsMethod != parameterIsMethod {
                throw new InvalidOperationException("A structural generic parameter owner must match its declaring type or method.")
            }
            identity := new ColumnarStructuralGenericParameterIdentity(owner, parameter.get_GenericParameterPosition())
            existing := identity
            if genericParameters.TryGetValue(parameter, out existing) {
                if !ColumnarStructuralTypeKeyFacts.GenericParameterIdentitiesEqual(existing, identity) {
                    throw new InvalidOperationException("A generic parameter cannot acquire two structural owners in one emission.")
                }
            } else {
                genericParameters.Add(parameter, identity)
            }
        }
    }

    func RegisterTypeGenericParameters(sourceFileId: int, exactName: string, parameterNames: string[], runtimeDefinition: Type) {
        parameters := runtimeDefinition.GetGenericArguments()
        if parameters.Length != parameterNames.Length {
            throw new InvalidOperationException("A structural source type's declared names must match its generic parameters.")
        }
        parameterMap := new Dictionary<string, Type>(StringComparer.Ordinal)
        i := 0
        while i < parameters.Length {
            parameterMap[parameterNames[i]] = parameters[i]
            i += 1
        }
        RegisterGenericParameters(parameterMap, ColumnarStructuralGenericOwnerIdentity.SourceType(sourceFileId, exactName))
    }

    func RegisterSynthesizedType(sourceFileId: int, stableIdentity: string, memberOrdinal: int, runtimeDefinition: Type, parameters: Dictionary<string, Type>?) {
        RegisterSynthesizedDefinition(stableIdentity, runtimeDefinition)
        RegisterGenericParameters(parameters, ColumnarStructuralGenericOwnerIdentity.SynthesizedType(sourceFileId, stableIdentity, memberOrdinal))
    }

    func RegisterIteratorType(sourceFileId: int, functionOrdinal: int, generatedTypeName: string, runtimeDefinition: Type, parameters: Dictionary<string, Type>?) {
        stableIdentity := "iterator:" + sourceFileId.ToString() + ":" + functionOrdinal.ToString() + ":" + generatedTypeName
        RegisterSynthesizedType(sourceFileId, stableIdentity, functionOrdinal, runtimeDefinition, parameters)
    }

    func SelectSourceDefinition(exactName: string, runtimeType: Type): ColumnarSelectedTypeReference {
        expected := typeof(object)
        if synthesizedTypeNames.Contains(exactName) || !sourceTypesByName.TryGetValue(exactName, out expected) || !Object.ReferenceEquals(expected, runtimeType) {
            throw new InvalidOperationException("The selected source type is not registered in this emission.")
        }
        uniqueName := ""
        if !uniqueSourceNamesByType.TryGetValue(runtimeType, out uniqueName) || uniqueName != exactName {
            selected := SelectRuntimeType(runtimeType)
            return new ColumnarSelectedTypeReference(identityValue, selected.Key, selected.RuntimeType, true, identityValue, exactName)
        }
        key := Intern(ColumnarStructuralTypeKeyFacts.SourceDefinitionKey(identityValue, exactName))
        return new ColumnarSelectedTypeReference(identityValue, key, runtimeType, true, identityValue, exactName)
    }

    func SelectSynthesizedDefinition(stableIdentity: string, runtimeType: Type): ColumnarSelectedTypeReference {
        expected := typeof(object)
        if !synthesizedTypeNames.Contains(stableIdentity) || !sourceTypesByName.TryGetValue(stableIdentity, out expected) || !Object.ReferenceEquals(expected, runtimeType) {
            throw new InvalidOperationException("The selected synthesized type is not registered in this emission.")
        }
        key := Intern(ColumnarStructuralTypeKeyFacts.SynthesizedDefinitionKey(identityValue, stableIdentity))
        return new ColumnarSelectedTypeReference(identityValue, key, runtimeType, true, null, "")
    }

    func SelectResolvedRuntimeType(runtimeType: Type, exactSourceName: string): ColumnarSelectedTypeReference {
        sourceType := typeof(object)
        if exactSourceName != null && exactSourceName.Length > 0 && sourceTypesByName.TryGetValue(exactSourceName, out sourceType) && Object.ReferenceEquals(sourceType, runtimeType) {
            return SelectSourceDefinition(exactSourceName, runtimeType)
        }
        return SelectRuntimeType(runtimeType)
    }

    func SelectRuntimeType(runtimeType: Type): ColumnarSelectedTypeReference {
        if runtimeType == null {
            throw new InvalidOperationException("A structural type reference requires a runtime companion.")
        }
        parameterIdentity := new ColumnarStructuralGenericParameterIdentity(ColumnarStructuralGenericOwnerIdentity.SourceMethod(-1, -1), -1)
        if runtimeType.get_IsGenericParameter() {
            if genericParameters.TryGetValue(runtimeType, out parameterIdentity) {
                return Selected(ColumnarStructuralTypeKeyFacts.GenericParameterKey(identityValue, parameterIdentity), runtimeType)
            }
            return Selected(ColumnarStructuralTypeKeyFacts.ExternalGenericParameterKey(runtimeType), runtimeType)
        }
        sourceName := ""
        if uniqueSourceNamesByType.TryGetValue(runtimeType, out sourceName) && !ambiguousSourceTypes.Contains(runtimeType) {
            if synthesizedTypeNames.Contains(sourceName) {
                return SelectSynthesizedDefinition(sourceName, runtimeType)
            }
            return SelectSourceDefinition(sourceName, runtimeType)
        }
        primitiveName := ColumnarStructuralTypeKeyFacts.PrimitiveIdentity(runtimeType)
        if primitiveName.Length > 0 {
            return Selected(ColumnarStructuralTypeKeyFacts.PrimitiveKey(primitiveName), runtimeType)
        }
        if ColumnarTypeEquivalenceFacts.IsSzArrayType(runtimeType) {
            elementType := ColumnarTypeEquivalenceFacts.TryGetElementType(runtimeType)
            if elementType == null {
                throw new InvalidOperationException("An SZ-array structural reference has no element type.")
            }
            return SelectSzArray(runtimeType, SelectRuntimeType(elementType))
        }
        if ColumnarTypeEquivalenceFacts.IsByRefType(runtimeType) {
            elementType := ColumnarTypeEquivalenceFacts.TryGetElementType(runtimeType)
            if elementType == null {
                throw new InvalidOperationException("A byref structural reference has no element type.")
            }
            return SelectByRef(runtimeType, SelectRuntimeType(elementType))
        }
        if runtimeType.get_IsGenericType() && !runtimeType.get_IsGenericTypeDefinition() {
            definition := SelectRuntimeType(runtimeType.GetGenericTypeDefinition())
            argumentTypes := runtimeType.GetGenericArguments()
            arguments := new ColumnarSelectedTypeReference[](argumentTypes.Length)
            i := 0
            while i < argumentTypes.Length {
                arguments[i] = SelectRuntimeType(argumentTypes[i])
                i += 1
            }
            return SelectConstructedGeneric(runtimeType, definition, arguments)
        }
        if ColumnarTypeEquivalenceFacts.TryGetElementType(runtimeType) != null {
            throw new InvalidOperationException("This element-bearing runtime type has no structural identity in the current schema.")
        }
        if ColumnarTypeOfPlanner.IsAssemblyBuilderBacked(runtimeType) {
            throw new InvalidOperationException("An unregistered AssemblyBuilder-backed type cannot be classified as an external metadata identity.")
        }
        return Selected(ColumnarStructuralTypeKeyFacts.ExternalNamedKey(runtimeType), runtimeType)
    }

    // Open external member signatures derive VAR/MVAR ownership from the metadata parameter itself,
    // even if a caller has separately registered that Type under a source-fixture owner. Composite
    // open-signature shapes recurse through this door; effective/context shapes use SelectRuntimeType
    // so real source generic arguments retain their registered emission owners.
    func SelectExternalSignatureType(runtimeType: Type): ColumnarSelectedTypeReference {
        if runtimeType == null {
            throw new InvalidOperationException("An external signature type requires a runtime companion.")
        }
        if runtimeType.get_IsGenericParameter() {
            return Selected(ColumnarStructuralTypeKeyFacts.ExternalGenericParameterKey(runtimeType), runtimeType)
        }
        if ColumnarTypeEquivalenceFacts.IsSzArrayType(runtimeType) {
            elementType := ColumnarTypeEquivalenceFacts.TryGetElementType(runtimeType)
            if elementType == null {
                throw new InvalidOperationException("An external signature SZ-array has no element type.")
            }
            return SelectSzArray(runtimeType, SelectExternalSignatureType(elementType))
        }
        if ColumnarTypeEquivalenceFacts.IsByRefType(runtimeType) {
            elementType := ColumnarTypeEquivalenceFacts.TryGetElementType(runtimeType)
            if elementType == null {
                throw new InvalidOperationException("An external signature byref has no element type.")
            }
            return SelectByRef(runtimeType, SelectExternalSignatureType(elementType))
        }
        if runtimeType.get_IsGenericType() && !runtimeType.get_IsGenericTypeDefinition() {
            definition := SelectRuntimeType(runtimeType.GetGenericTypeDefinition())
            argumentTypes := runtimeType.GetGenericArguments()
            arguments := new ColumnarSelectedTypeReference[](argumentTypes.Length)
            index := 0
            while index < argumentTypes.Length {
                arguments[index] = SelectExternalSignatureType(argumentTypes[index])
                index += 1
            }
            return SelectConstructedGeneric(runtimeType, definition, arguments)
        }
        return SelectRuntimeType(runtimeType)
    }

    func SelectConstructedGeneric(runtimeType: Type, definition: ColumnarSelectedTypeReference, arguments: ColumnarSelectedTypeReference[]): ColumnarSelectedTypeReference {
        children := new ColumnarStructuralTypeKey[](arguments.Length + 1)
        children[0] = ColumnarStructuralTypeKeyFacts.RequiredKey(identityValue, definition)
        i := 0
        while i < arguments.Length {
            children[i + 1] = ColumnarStructuralTypeKeyFacts.RequiredKey(identityValue, arguments[i])
            i += 1
        }
        return Selected(ColumnarStructuralTypeKeyFacts.CompositeKey(ColumnarStructuralTypeReferenceKind.ConstructedGeneric, children), runtimeType)
    }

    func SelectSzArray(runtimeType: Type, element: ColumnarSelectedTypeReference): ColumnarSelectedTypeReference {
        children := new ColumnarStructuralTypeKey[](1)
        children[0] = ColumnarStructuralTypeKeyFacts.RequiredKey(identityValue, element)
        return Selected(ColumnarStructuralTypeKeyFacts.CompositeKey(ColumnarStructuralTypeReferenceKind.SzArray, children), runtimeType)
    }

    func SelectByRef(runtimeType: Type, element: ColumnarSelectedTypeReference): ColumnarSelectedTypeReference {
        children := new ColumnarStructuralTypeKey[](1)
        children[0] = ColumnarStructuralTypeKeyFacts.RequiredKey(identityValue, element)
        return Selected(ColumnarStructuralTypeKeyFacts.CompositeKey(ColumnarStructuralTypeReferenceKind.ByRef, children), runtimeType)
    }

    func ValidatePair(selected: ColumnarSelectedTypeReference, runtimeType: Type): bool {
        if selected == null || runtimeType == null || !Object.ReferenceEquals(selected.EmissionIdentity, identityValue) || !selected.HasRuntimeType || !Object.ReferenceEquals(selected.RuntimeType, runtimeType) || selected.Key == null {
            return false
        }
        if selected.SourceProvenanceEmission == null {
            if selected.SourceProvenanceName.Length != 0 || selected.Key.Kind == ColumnarStructuralTypeReferenceKind.SourceDefinition {
                return false
            }
        } else {
            sourceType := typeof(object)
            if !Object.ReferenceEquals(selected.SourceProvenanceEmission, identityValue) || selected.SourceProvenanceName.Length == 0 || synthesizedTypeNames.Contains(selected.SourceProvenanceName) || !sourceTypesByName.TryGetValue(selected.SourceProvenanceName, out sourceType) || !Object.ReferenceEquals(sourceType, runtimeType) {
                return false
            }
            if selected.Key.Kind == ColumnarStructuralTypeReferenceKind.SourceDefinition && selected.Key.SourceDeclarationName != selected.SourceProvenanceName {
                return false
            }
        }
        return ColumnarStructuralTypeKeyFacts.KeyMatchesRuntime(identityValue, sourceTypesByName, synthesizedTypeNames, genericParameters, selected.Key, runtimeType)
    }

    func Selected(key: ColumnarStructuralTypeKey, runtimeType: Type): ColumnarSelectedTypeReference {
        return new ColumnarSelectedTypeReference(identityValue, Intern(key), runtimeType, true, null, "")
    }

    func Intern(candidate: ColumnarStructuralTypeKey): ColumnarStructuralTypeKey {
        for existing in rowsValue {
            if ColumnarStructuralTypeKeyFacts.KeysEqual(existing, candidate) {
                return existing
            }
        }
        rowsValue.Add(candidate)
        return candidate
    }
}

class ColumnarStructuralTypeKeyFacts {
    static func KeyMatchesRuntime(emissionIdentity: ColumnarStructuralTypeEmissionIdentity, sourceTypesByName: Dictionary<string, Type>, synthesizedTypeNames: HashSet<string>, genericParameters: Dictionary<Type, ColumnarStructuralGenericParameterIdentity>, key: ColumnarStructuralTypeKey, runtimeType: Type): bool {
        blankNamedIdentity := key.PrimitiveName == "" && key.SourceDeclarationName == "" && key.AssemblyIdentity == "" && key.NamespaceName == "" && key.NestedNameCount == 0
        blankGenericIdentity := key.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.SourceType && key.GenericOwnerSourceFileId == -1 && key.GenericOwnerDeclaringTypeName == "" && key.GenericOwnerMemberOrdinal == -1 && key.GenericParameterOrdinal == -1 && key.ExternalGenericOwner == null
        if key.Kind == ColumnarStructuralTypeReferenceKind.Primitive {
            return key.EmissionIdentity == null && key.PrimitiveName.Length > 0 && key.SourceDeclarationName == "" && key.AssemblyIdentity == "" && key.NamespaceName == "" && key.NestedNameCount == 0 && !key.IsValueType && blankGenericIdentity && key.ChildCount == 0 && key.PrimitiveName == PrimitiveIdentity(runtimeType)
        }
        if key.Kind == ColumnarStructuralTypeReferenceKind.SourceDefinition || key.Kind == ColumnarStructuralTypeReferenceKind.SynthesizedDefinition {
            if !Object.ReferenceEquals(key.EmissionIdentity, emissionIdentity) || key.PrimitiveName != "" || key.SourceDeclarationName.Length == 0 || key.AssemblyIdentity != "" || key.NamespaceName != "" || key.NestedNameCount != 0 || key.IsValueType || !blankGenericIdentity || key.ChildCount != 0 {
                return false
            }
            selected := typeof(object)
            expectedSynthesized := key.Kind == ColumnarStructuralTypeReferenceKind.SynthesizedDefinition
            return synthesizedTypeNames.Contains(key.SourceDeclarationName) == expectedSynthesized && sourceTypesByName.TryGetValue(key.SourceDeclarationName, out selected) && Object.ReferenceEquals(selected, runtimeType)
        }
        if key.Kind == ColumnarStructuralTypeReferenceKind.ExternalNamedDefinition {
            if key.EmissionIdentity != null || key.PrimitiveName != "" || key.SourceDeclarationName != "" || key.AssemblyIdentity.Length == 0 || key.NestedNameCount == 0 || !blankGenericIdentity || key.ChildCount != 0 || runtimeType.get_IsGenericParameter() || (runtimeType.get_IsGenericType() && !runtimeType.get_IsGenericTypeDefinition()) || ColumnarTypeEquivalenceFacts.TryGetElementType(runtimeType) != null || ColumnarTypeOfPlanner.IsAssemblyBuilderBacked(runtimeType) {
                return false
            }
            return ExternalIdentityMatches(key, runtimeType)
        }
        if key.Kind == ColumnarStructuralTypeReferenceKind.ConstructedGeneric {
            if key.EmissionIdentity != null || !blankNamedIdentity || key.IsValueType || !blankGenericIdentity || key.ChildCount < 1 || !runtimeType.get_IsGenericType() || runtimeType.get_IsGenericTypeDefinition() {
                return false
            }
            arguments := runtimeType.GetGenericArguments()
            if key.ChildCount != arguments.Length + 1 || !KeyMatchesRuntime(emissionIdentity, sourceTypesByName, synthesizedTypeNames, genericParameters, key.Child(0), runtimeType.GetGenericTypeDefinition()) {
                return false
            }
            i := 0
            while i < arguments.Length {
                if !KeyMatchesRuntime(emissionIdentity, sourceTypesByName, synthesizedTypeNames, genericParameters, key.Child(i + 1), arguments[i]) {
                    return false
                }
                i += 1
            }
            return true
        }
        if key.Kind == ColumnarStructuralTypeReferenceKind.SzArray || key.Kind == ColumnarStructuralTypeReferenceKind.ByRef {
            expectedShape := key.Kind == ColumnarStructuralTypeReferenceKind.SzArray ? ColumnarTypeEquivalenceFacts.IsSzArrayType(runtimeType) : ColumnarTypeEquivalenceFacts.IsByRefType(runtimeType)
            element := ColumnarTypeEquivalenceFacts.TryGetElementType(runtimeType)
            return key.EmissionIdentity == null && blankNamedIdentity && !key.IsValueType && blankGenericIdentity && expectedShape && key.ChildCount == 1 && element != null && KeyMatchesRuntime(emissionIdentity, sourceTypesByName, synthesizedTypeNames, genericParameters, key.Child(0), element)
        }
        if key.Kind == ColumnarStructuralTypeReferenceKind.TypeGenericParameter || key.Kind == ColumnarStructuralTypeReferenceKind.MethodGenericParameter {
            if !runtimeType.get_IsGenericParameter() || !blankNamedIdentity || key.IsValueType || key.ChildCount != 0 {
                return false
            }
            runtimeIsMethod := runtimeType.get_IsGenericMethodParameter()
            runtimeIsType := runtimeType.get_IsGenericTypeParameter()
            if runtimeIsMethod == runtimeIsType || (key.Kind == ColumnarStructuralTypeReferenceKind.MethodGenericParameter) != runtimeIsMethod || runtimeType.get_GenericParameterPosition() != key.GenericParameterOrdinal {
                return false
            }

            keyHasExternalOwner := key.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.ExternalType || key.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.ExternalMethod
            if keyHasExternalOwner {
                if key.EmissionIdentity != null || key.GenericOwnerSourceFileId != -1 || key.GenericOwnerDeclaringTypeName != "" || key.GenericOwnerMemberOrdinal != -1 || key.ExternalGenericOwner == null {
                    return false
                }
                expectedOwnerKind := runtimeIsMethod ? ColumnarStructuralGenericOwnerKind.ExternalMethod : ColumnarStructuralGenericOwnerKind.ExternalType
                return key.GenericOwnerKind == expectedOwnerKind && ExternalGenericOwnerMatchesRuntime(key.ExternalGenericOwner, runtimeType)
            }

            registered := new ColumnarStructuralGenericParameterIdentity(ColumnarStructuralGenericOwnerIdentity.SourceMethod(-1, -1), -1)
            if key.ExternalGenericOwner != null || !Object.ReferenceEquals(key.EmissionIdentity, emissionIdentity) || !genericParameters.TryGetValue(runtimeType, out registered) {
                return false
            }
            return GenericParameterKeyMatches(key, registered)
        }
        return false
    }

    static func KeysEqual(left: ColumnarStructuralTypeKey, right: ColumnarStructuralTypeKey): bool {
        if left == null || right == null || left.Kind != right.Kind || !Object.ReferenceEquals(left.EmissionIdentity, right.EmissionIdentity) || left.PrimitiveName != right.PrimitiveName || left.SourceDeclarationName != right.SourceDeclarationName || left.AssemblyIdentity != right.AssemblyIdentity || left.NamespaceName != right.NamespaceName || left.IsValueType != right.IsValueType || left.GenericOwnerKind != right.GenericOwnerKind || left.GenericOwnerSourceFileId != right.GenericOwnerSourceFileId || left.GenericOwnerDeclaringTypeName != right.GenericOwnerDeclaringTypeName || left.GenericOwnerMemberOrdinal != right.GenericOwnerMemberOrdinal || left.GenericParameterOrdinal != right.GenericParameterOrdinal || !ExternalGenericOwnersEqual(left.ExternalGenericOwner, right.ExternalGenericOwner) || left.NestedNameCount != right.NestedNameCount || left.ChildCount != right.ChildCount {
            return false
        }
        i := 0
        while i < left.NestedNameCount {
            if left.NestedName(i) != right.NestedName(i) {
                return false
            }
            i += 1
        }
        i = 0
        while i < left.ChildCount {
            if !KeysEqual(left.Child(i), right.Child(i)) {
                return false
            }
            i += 1
        }
        return true
    }

    static func RequiredKey(emissionIdentity: ColumnarStructuralTypeEmissionIdentity, selected: ColumnarSelectedTypeReference): ColumnarStructuralTypeKey {
        if selected == null || !selected.HasRuntimeType || selected.Key == null || !Object.ReferenceEquals(selected.EmissionIdentity, emissionIdentity) {
            throw new InvalidOperationException("A structural composite requires selected child keys from the same emission.")
        }
        return selected.Key
    }

    static func PrimitiveKey(name: string): ColumnarStructuralTypeKey {
        return EmptyKey(ColumnarStructuralTypeReferenceKind.Primitive, null, name, "")
    }

    static func SourceDefinitionKey(identity: ColumnarStructuralTypeEmissionIdentity, name: string): ColumnarStructuralTypeKey {
        return EmptyKey(ColumnarStructuralTypeReferenceKind.SourceDefinition, identity, "", name)
    }

    static func SynthesizedDefinitionKey(identity: ColumnarStructuralTypeEmissionIdentity, name: string): ColumnarStructuralTypeKey {
        return EmptyKey(ColumnarStructuralTypeReferenceKind.SynthesizedDefinition, identity, "", name)
    }

    static func CompositeKey(kind: ColumnarStructuralTypeReferenceKind, children: ColumnarStructuralTypeKey[]): ColumnarStructuralTypeKey {
        return new ColumnarStructuralTypeKey(kind, null, "", "", "", "", new string[](0), false, ColumnarStructuralGenericOwnerKind.SourceType, -1, "", -1, -1, null, children)
    }

    static func GenericParameterKey(emissionIdentity: ColumnarStructuralTypeEmissionIdentity, identity: ColumnarStructuralGenericParameterIdentity): ColumnarStructuralTypeKey {
        owner := identity.Owner
        kind := owner.Kind == ColumnarStructuralGenericOwnerKind.SourceMethod ? ColumnarStructuralTypeReferenceKind.MethodGenericParameter : ColumnarStructuralTypeReferenceKind.TypeGenericParameter
        return new ColumnarStructuralTypeKey(kind, emissionIdentity, "", "", "", "", new string[](0), false, owner.Kind, owner.SourceFileId, owner.DeclaringTypeName, owner.MemberOrdinal, identity.ParameterOrdinal, null, new ColumnarStructuralTypeKey[](0))
    }

    static func ExternalGenericParameterKey(runtimeType: Type): ColumnarStructuralTypeKey {
        if runtimeType == null || !runtimeType.get_IsGenericParameter() {
            throw new InvalidOperationException("An external generic-parameter key requires an actual generic parameter.")
        }
        runtimeIsMethod := runtimeType.get_IsGenericMethodParameter()
        runtimeIsType := runtimeType.get_IsGenericTypeParameter()
        if runtimeIsMethod == runtimeIsType {
            throw new InvalidOperationException("An external generic parameter must identify either a declaring type or method.")
        }
        owner := ExternalGenericOwner(runtimeType)
        kind := runtimeIsMethod ? ColumnarStructuralTypeReferenceKind.MethodGenericParameter : ColumnarStructuralTypeReferenceKind.TypeGenericParameter
        return new ColumnarStructuralTypeKey(kind, null, "", "", "", "", new string[](0), false, owner.Kind, -1, "", -1, runtimeType.get_GenericParameterPosition(), owner, new ColumnarStructuralTypeKey[](0))
    }

    static func ExternalNamedKey(runtimeType: Type): ColumnarStructuralTypeKey {
        assemblyIdentity := runtimeType.get_Assembly().GetName().get_FullName()
        if assemblyIdentity == null || assemblyIdentity.Length == 0 {
            throw new InvalidOperationException("An external structural type requires an exact assembly identity.")
        }
        names := ExternalNestedNames(runtimeType)
        return new ColumnarStructuralTypeKey(ColumnarStructuralTypeReferenceKind.ExternalNamedDefinition, null, "", "", assemblyIdentity, runtimeType.get_Namespace() ?? "", names, runtimeType.get_IsValueType(), ColumnarStructuralGenericOwnerKind.SourceType, -1, "", -1, -1, null, new ColumnarStructuralTypeKey[](0))
    }

    static func ExternalGenericOwner(runtimeType: Type): ColumnarStructuralExternalGenericOwnerIdentity {
        if runtimeType.get_IsGenericMethodParameter() {
            declaringMethodBase := runtimeType.get_DeclaringMethod()
            if declaringMethodBase == null {
                throw new InvalidOperationException("A generic parameter reached structural selection without a registered source owner.")
            }
            declaringMethodObject: object? = declaringMethodBase
            declaringMethod := (MethodInfo)declaringMethodObject
            declaringType := declaringMethod.get_DeclaringType()
            if declaringType == null {
                throw new InvalidOperationException("A generic parameter reached structural selection without a registered source owner.")
            }
            declaringTypeObject: object? = declaringType
            openDeclaringType := OpenExternalDefinition((Type)declaringTypeObject)
            EnsureExternalGenericOwner(openDeclaringType)
            module := declaringMethod.get_Module()
            moduleVersionId := module.get_ModuleVersionId().ToString()
            return new ColumnarStructuralExternalGenericOwnerIdentity(
                ColumnarStructuralGenericOwnerKind.ExternalMethod,
                ExternalNamedKey(openDeclaringType),
                moduleVersionId,
                declaringMethod.get_MetadataToken(),
                declaringMethod.get_Name(),
                declaringMethod.GetGenericArguments().Length,
                Convert.ToInt32(declaringMethod.get_CallingConvention()),
                declaringMethod.get_IsStatic()
            )
        }

        declaringType := runtimeType.get_DeclaringType()
        if declaringType == null {
            throw new InvalidOperationException("A generic parameter reached structural selection without a registered source owner.")
        }
        declaringTypeObject: object? = declaringType
        openDeclaringType := OpenExternalDefinition((Type)declaringTypeObject)
        EnsureExternalGenericOwner(openDeclaringType)
        return new ColumnarStructuralExternalGenericOwnerIdentity(
            ColumnarStructuralGenericOwnerKind.ExternalType,
            ExternalNamedKey(openDeclaringType),
            "",
            -1,
            "",
            -1,
            -1,
            false
        )
    }

    static func OpenExternalDefinition(declaringType: Type): Type {
        if declaringType.get_IsGenericType() && !declaringType.get_IsGenericTypeDefinition() {
            return declaringType.GetGenericTypeDefinition()
        }
        return declaringType
    }

    static func EnsureExternalGenericOwner(declaringType: Type) {
        if declaringType == null || ColumnarTypeOfPlanner.IsAssemblyBuilderBacked(declaringType) {
            throw new InvalidOperationException("A generic parameter reached structural selection without a registered source owner.")
        }
    }

    static func ExternalGenericOwnerMatchesRuntime(owner: ColumnarStructuralExternalGenericOwnerIdentity, runtimeType: Type): bool {
        if owner == null || runtimeType == null || !runtimeType.get_IsGenericParameter() {
            return false
        }
        runtimeIsMethod := runtimeType.get_IsGenericMethodParameter()
        runtimeIsType := runtimeType.get_IsGenericTypeParameter()
        if runtimeIsMethod == runtimeIsType {
            return false
        }

        declaringType: Type? = null
        declaringMethod: MethodInfo? = null
        if runtimeIsMethod {
            declaringMethodBase := runtimeType.get_DeclaringMethod()
            if declaringMethodBase == null {
                return false
            }
            declaringMethodObject: object? = declaringMethodBase
            declaringMethod = (MethodInfo)declaringMethodObject
            declaringType = declaringMethod.get_DeclaringType()
        } else {
            declaringType = runtimeType.get_DeclaringType()
        }
        if declaringType == null {
            return false
        }
        declaringTypeObject: object? = declaringType
        openDeclaringType := OpenExternalDefinition((Type)declaringTypeObject)
        declaringKey := owner.DeclaringType
        canonicalDeclaringKey := declaringKey.Kind == ColumnarStructuralTypeReferenceKind.ExternalNamedDefinition && declaringKey.EmissionIdentity == null && declaringKey.PrimitiveName == "" && declaringKey.SourceDeclarationName == "" && declaringKey.AssemblyIdentity.Length > 0 && declaringKey.NestedNameCount > 0 && declaringKey.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.SourceType && declaringKey.GenericOwnerSourceFileId == -1 && declaringKey.GenericOwnerDeclaringTypeName == "" && declaringKey.GenericOwnerMemberOrdinal == -1 && declaringKey.GenericParameterOrdinal == -1 && declaringKey.ExternalGenericOwner == null && declaringKey.ChildCount == 0
        if !canonicalDeclaringKey || ColumnarTypeOfPlanner.IsAssemblyBuilderBacked(openDeclaringType) || !ExternalIdentityMatches(declaringKey, openDeclaringType) {
            return false
        }

        if runtimeIsType {
            return owner.Kind == ColumnarStructuralGenericOwnerKind.ExternalType && owner.ModuleVersionId == "" && owner.MethodMetadataToken == -1 && owner.MethodName == "" && owner.MethodGenericArity == -1 && owner.MethodCallingConvention == -1 && !owner.MethodIsStatic
        }
        if declaringMethod == null {
            return false
        }
        module := declaringMethod.get_Module()
        moduleVersionId := module.get_ModuleVersionId().ToString()
        return owner.Kind == ColumnarStructuralGenericOwnerKind.ExternalMethod && owner.ModuleVersionId == moduleVersionId && owner.MethodMetadataToken == declaringMethod.get_MetadataToken() && owner.MethodName == declaringMethod.get_Name() && owner.MethodGenericArity == declaringMethod.GetGenericArguments().Length && owner.MethodCallingConvention == Convert.ToInt32(declaringMethod.get_CallingConvention()) && owner.MethodIsStatic == declaringMethod.get_IsStatic()
    }

    static func ExternalGenericOwnersEqual(left: ColumnarStructuralExternalGenericOwnerIdentity?, right: ColumnarStructuralExternalGenericOwnerIdentity?): bool {
        if left == null || right == null {
            return left == null && right == null
        }
        return left.Kind == right.Kind && KeysEqual(left.DeclaringType, right.DeclaringType) && left.ModuleVersionId == right.ModuleVersionId && left.MethodMetadataToken == right.MethodMetadataToken && left.MethodName == right.MethodName && left.MethodGenericArity == right.MethodGenericArity && left.MethodCallingConvention == right.MethodCallingConvention && left.MethodIsStatic == right.MethodIsStatic
    }

    static func EmptyKey(kind: ColumnarStructuralTypeReferenceKind, emission: ColumnarStructuralTypeEmissionIdentity?, primitiveName: string, sourceName: string): ColumnarStructuralTypeKey {
        return new ColumnarStructuralTypeKey(kind, emission, primitiveName, sourceName, "", "", new string[](0), false, ColumnarStructuralGenericOwnerKind.SourceType, -1, "", -1, -1, null, new ColumnarStructuralTypeKey[](0))
    }

    static func ExternalNestedNames(runtimeType: Type): string[] {
        reversed := new List<string>()
        current: Type? = runtimeType
        while current != null {
            reversed.Add(current.get_Name())
            current = current.get_DeclaringType()
        }
        result := new string[](reversed.Count)
        i := 0
        while i < reversed.Count {
            result[i] = reversed[reversed.Count - i - 1]
            i += 1
        }
        return result
    }

    static func ExternalIdentityMatches(key: ColumnarStructuralTypeKey, runtimeType: Type): bool {
        assemblyIdentity := runtimeType.get_Assembly().GetName().get_FullName()
        if assemblyIdentity == null || assemblyIdentity != key.AssemblyIdentity || (runtimeType.get_Namespace() ?? "") != key.NamespaceName || runtimeType.get_IsValueType() != key.IsValueType {
            return false
        }
        names := ExternalNestedNames(runtimeType)
        if names.Length != key.NestedNameCount {
            return false
        }
        i := 0
        while i < names.Length {
            if names[i] != key.NestedName(i) {
                return false
            }
            i += 1
        }
        return true
    }

    static func GenericParameterIdentitiesEqual(left: ColumnarStructuralGenericParameterIdentity, right: ColumnarStructuralGenericParameterIdentity): bool {
        return left.ParameterOrdinal == right.ParameterOrdinal && left.Owner.Kind == right.Owner.Kind && left.Owner.SourceFileId == right.Owner.SourceFileId && left.Owner.DeclaringTypeName == right.Owner.DeclaringTypeName && left.Owner.MemberOrdinal == right.Owner.MemberOrdinal
    }

    static func GenericParameterKeyMatches(key: ColumnarStructuralTypeKey, identity: ColumnarStructuralGenericParameterIdentity): bool {
        owner := identity.Owner
        expectedKind := owner.Kind == ColumnarStructuralGenericOwnerKind.SourceMethod ? ColumnarStructuralTypeReferenceKind.MethodGenericParameter : ColumnarStructuralTypeReferenceKind.TypeGenericParameter
        return key.Kind == expectedKind && key.GenericOwnerKind == owner.Kind && key.GenericOwnerSourceFileId == owner.SourceFileId && key.GenericOwnerDeclaringTypeName == owner.DeclaringTypeName && key.GenericOwnerMemberOrdinal == owner.MemberOrdinal && key.GenericParameterOrdinal == identity.ParameterOrdinal
    }

    // Signature primitives are identified by exact core-library metadata identity so runtime and
    // MetadataLoadContext handles converge without allowing a foreign System.Int32/System.Void name.
    static func PrimitiveIdentity(runtimeType: Type): string {
        fullName := runtimeType.get_FullName()
        actualAssembly := runtimeType.get_Assembly().GetName().get_FullName()
        coreAssembly := typeof(int).get_Assembly().GetName().get_FullName()
        if fullName == null || actualAssembly == null || coreAssembly == null || actualAssembly != coreAssembly {
            return ""
        }
        if fullName == "System.Boolean" {
            return "bool"
        }
        if fullName == "System.Byte" {
            return "uint8"
        }
        if fullName == "System.SByte" {
            return "int8"
        }
        if fullName == "System.Int16" {
            return "int16"
        }
        if fullName == "System.UInt16" {
            return "uint16"
        }
        if fullName == "System.Int32" {
            return "int32"
        }
        if fullName == "System.UInt32" {
            return "uint32"
        }
        if fullName == "System.Int64" {
            return "int64"
        }
        if fullName == "System.UInt64" {
            return "uint64"
        }
        if fullName == "System.Char" {
            return "char"
        }
        if fullName == "System.Single" {
            return "float32"
        }
        if fullName == "System.Double" {
            return "float64"
        }
        if fullName == "System.String" {
            return "string"
        }
        if fullName == "System.Object" {
            return "object"
        }
        if fullName == "System.IntPtr" {
            return "native-int"
        }
        if fullName == "System.UIntPtr" {
            return "native-uint"
        }
        if fullName == "System.Void" {
            return "void"
        }
        return ""
    }
}
