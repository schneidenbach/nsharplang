namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Semantic type selection belongs to N#. The C# assembly owner consumes only the exact live
// handles selected here and never reconstructs imports, aliases, or source-name precedence.
class ColumnarSemanticTypeRegistryBridge {
    static func TypeParametersOwnedByType(visibleTypeParameters: Dictionary<string, Type>, declaringType: TypeBuilder): Dictionary<string, Type>? {
        owned: Dictionary<string, Type>? = null
        for pair in visibleTypeParameters {
            typeParameter := pair.Value
            if !typeParameter.get_IsGenericParameter() || typeParameter.get_DeclaringMethod() != null || !Object.ReferenceEquals(typeParameter.get_DeclaringType(), declaringType) {
                continue
            }
            if owned == null {
                owned = new Dictionary<string, Type>(StringComparer.Ordinal)
            }
            owned[pair.Key] = typeParameter
        }
        return owned
    }

    static func IsValidSynthesizedMethodSignatureType(valueType: Type, declaringType: TypeBuilder): bool {
        if valueType.get_IsGenericParameter() {
            return valueType.get_DeclaringMethod() == null && Object.ReferenceEquals(valueType.get_DeclaringType(), declaringType)
        }
        if valueType.get_HasElementType() {
            elementType := valueType.GetElementType()
            return elementType != null && IsValidSynthesizedMethodSignatureType(elementType, declaringType)
        }
        if !valueType.get_IsGenericType() {
            return true
        }
        for argument in valueType.GetGenericArguments() {
            if !IsValidSynthesizedMethodSignatureType(argument, declaringType) {
                return false
            }
        }
        return true
    }

    static func IsValidSynthesizedMethodSignature(returnType: Type, parameterTypes: Type[], declaringType: TypeBuilder): bool {
        if !IsValidSynthesizedMethodSignatureType(returnType, declaringType) {
            return false
        }
        for parameterType in parameterTypes {
            if !IsValidSynthesizedMethodSignatureType(parameterType, declaringType) {
                return false
            }
        }
        return true
    }

    static func BindMethodToDeclaringTypeGenericContext(declaringType: TypeBuilder, method: MethodInfo): MethodInfo {
        typeParameters := declaringType.GetGenericArguments()
        if typeParameters.Length == 0 {
            return method
        }
        definition: Type = declaringType
        closedDeclaringType := definition.MakeGenericType(typeParameters)
        rebound := TypeBuilder.GetMethod(closedDeclaringType, method)
        return rebound
    }
}

class ColumnarExactTypeResolutionCacheEntry {
    Resolved: bool
    Claimed: bool
    Selected: ColumnarSelectedTypeReference

    constructor(resolved: bool, claimed: bool, selected: ColumnarSelectedTypeReference) {
        Resolved = resolved
        Claimed = claimed
        Selected = selected
    }
}

class ColumnarSourceNameResolutionCacheEntry {
    Resolved: bool
    Claimed: bool
    ExactName: string

    constructor(resolved: bool, claimed: bool, exactName: string) {
        Resolved = resolved
        Claimed = claimed
        ExactName = exactName
    }
}

class ColumnarExactTypeResolver {
    program: ColumnarProgramInput
    sourceFileId: int
    bindings: ColumnarFragmentBindings
    sourceDefinitionTypes: List<Type>
    exactSourceTypes: Dictionary<string, Type>
    typeParameters: Dictionary<string, Type>
    blockedTypeParameterNames: HashSet<string>
    enclosingSourceDeclarationName: string
    structuralTypeReferences: ColumnarStructuralTypeReferenceTable
    cache: Dictionary<string, ColumnarExactTypeResolutionCacheEntry>
    sourceNameCache: Dictionary<string, ColumnarSourceNameResolutionCacheEntry>

    ExactSourceTypes: Dictionary<string, Type> => exactSourceTypes
    StructuralTypeReferences: ColumnarStructuralTypeReferenceTable => structuralTypeReferences

    constructor(program: ColumnarProgramInput, sourceFileId: int, bindings: ColumnarFragmentBindings, sourceDefinitionTypes: List<Type>, exactSourceTypes: Dictionary<string, Type>, typeParameters: Dictionary<string, Type>, blockedTypeParameterNames: IEnumerable<string>?, enclosingSourceDeclarationName: string?, structuralTypeReferences: ColumnarStructuralTypeReferenceTable) {
        this.program = program
        this.sourceFileId = sourceFileId
        this.bindings = bindings
        this.sourceDefinitionTypes = sourceDefinitionTypes
        this.exactSourceTypes = exactSourceTypes
        this.typeParameters = typeParameters
        this.enclosingSourceDeclarationName = enclosingSourceDeclarationName ?? ""
        this.structuralTypeReferences = structuralTypeReferences
        this.blockedTypeParameterNames = new HashSet<string>(StringComparer.Ordinal)
        if blockedTypeParameterNames != null {
            for name in blockedTypeParameterNames {
                this.blockedTypeParameterNames.Add(name)
            }
        }
        cache = new Dictionary<string, ColumnarExactTypeResolutionCacheEntry>(StringComparer.Ordinal)
        sourceNameCache = new Dictionary<string, ColumnarSourceNameResolutionCacheEntry>(StringComparer.Ordinal)
    }

    func TryResolve(canonical: string, out selectedType: Type, out claimed: bool): bool {
        selected := ColumnarSelectedTypeReference.Missing(structuralTypeReferences)
        resolved := TryResolveSelected(canonical, out selected, out claimed)
        selectedType = selected.RuntimeType
        return resolved
    }

    func TryResolveSelected(canonical: string, out selectedReference: ColumnarSelectedTypeReference, out claimed: bool): bool {
        cached := new ColumnarExactTypeResolutionCacheEntry(false, false, ColumnarSelectedTypeReference.Missing(structuralTypeReferences))
        if !cache.TryGetValue(canonical, out cached) {
            selected := ColumnarSelectedTypeReference.Missing(structuralTypeReferences)
            resolved := false
            claimed = false
            syntaxTerminal := false
            if ContainsBlockedTypeParameter(canonical) {
                claimed = true
            } else if canonical.EndsWith("[]", StringComparison.Ordinal) {
                element := ColumnarSelectedTypeReference.Missing(structuralTypeReferences)
                resolved = TryResolveSelected(canonical.Substring(0, canonical.Length - 2), out element, out claimed)
                if resolved {
                    runtimeArray := typeof(object)
                    try {
                        runtimeArray = element.RuntimeType.MakeArrayType()
                    } catch {
                        resolved = false
                        selected = ColumnarSelectedTypeReference.Missing(structuralTypeReferences)
                    }
                    if resolved {
                        selected = structuralTypeReferences.SelectSzArray(runtimeArray, element)
                    }
                }
            } else if TryClassifySyntaxOwnedShape(canonical, out syntaxTerminal) {
                claimed = syntaxTerminal
            } else {
                typeParameter := typeof(object)
                if typeParameters.TryGetValue(canonical, out typeParameter) {
                    claimed = true
                    selected = structuralTypeReferences.SelectRuntimeType(typeParameter)
                    resolved = true
                } else if HasVisibleTypeParameterRoot(canonical) {
                    claimed = true
                } else {
                    exactSourceName := ""
                    sourceClaimed := false
                    if TryResolveSourceDeclarationName(canonical, out exactSourceName, out sourceClaimed) {
                        claimed = true
                        // Alias expansion owns constructed shapes. The exact live source handle is
                        // the authoritative identity bridge for erased, non-generic source
                        // declarations. Select it before asking the file resolver to reinterpret
                        // the original spelling; a competing file-level short name must not
                        // replace a lexically selected nested declaration.
                        sourceType := typeof(object)
                        if exactSourceTypes.TryGetValue(exactSourceName, out sourceType) && !sourceType.get_IsGenericTypeDefinition() {
                            selected = structuralTypeReferences.SelectSourceDefinition(exactSourceName, sourceType)
                            resolved = true
                        } else {
                            ignoredClaim := false
                            selectedType := typeof(object)
                            resolved = TryResolveExactExplicitType(canonical, out selectedType, out ignoredClaim)
                            if resolved {
                                selected = structuralTypeReferences.SelectRuntimeType(selectedType)
                            } else if selectedType != null && !Object.ReferenceEquals(selectedType, typeof(object)) {
                                selected = ColumnarSelectedTypeReference.RejectedWithRuntime(structuralTypeReferences, selectedType)
                            }
                        }
                    } else {
                        selectedType := typeof(object)
                        resolved = TryResolveExactExplicitType(canonical, out selectedType, out claimed)
                        if resolved {
                            selected = structuralTypeReferences.SelectRuntimeType(selectedType)
                        } else if selectedType != null && !Object.ReferenceEquals(selectedType, typeof(object)) {
                            selected = ColumnarSelectedTypeReference.RejectedWithRuntime(structuralTypeReferences, selectedType)
                        }
                    }
                }
            }
            cached = new ColumnarExactTypeResolutionCacheEntry(resolved, claimed, selected)
            cache[canonical] = cached
        }

        selectedReference = cached.Selected
        claimed = cached.Claimed
        return cached.Resolved
    }

    func IsSourceDefinition(valueType: Type): bool {
        if ContainsSourceDefinitionIdentity(valueType) {
            return true
        }
        return valueType.get_IsGenericType() && !valueType.get_IsGenericTypeDefinition() && ContainsSourceDefinitionIdentity(valueType.GetGenericTypeDefinition())
    }

    func ContainsSourceDefinitionIdentity(valueType: Type): bool {
        for sourceDefinitionType in sourceDefinitionTypes {
            if Object.ReferenceEquals(sourceDefinitionType, valueType) {
                return true
            }
        }
        return false
    }

    func ForSynthesizedMethod(declaringType: TypeBuilder): ColumnarExactTypeResolver {
        owned := ColumnarSemanticTypeRegistryBridge.TypeParametersOwnedByType(typeParameters, declaringType)
        if owned == null {
            owned = new Dictionary<string, Type>(StringComparer.Ordinal)
        }
        blocked := new HashSet<string>(StringComparer.Ordinal)
        for name in blockedTypeParameterNames {
            blocked.Add(name)
        }
        for pair in typeParameters {
            if !owned.ContainsKey(pair.Key) {
                blocked.Add(pair.Key)
            }
        }
        narrowedBindings := ColumnarFragmentBindings.CreateTypeResolutionBindings(bindings.Enums, bindings.SourceTypeDefinitions, bindings.SourceUnionDefinitions, owned)
        narrowedBindings.ExactSourceTypes = exactSourceTypes
        return new ColumnarExactTypeResolver(program, sourceFileId, narrowedBindings, sourceDefinitionTypes, exactSourceTypes, owned, blocked, enclosingSourceDeclarationName, structuralTypeReferences)
    }

    func ClaimsTypeParameterShape(canonical: string): bool {
        if ContainsBlockedTypeParameter(canonical) {
            return true
        }
        for pair in typeParameters {
            if ContainsTypeParameter(canonical, pair.Key) {
                return true
            }
        }
        return false
    }

    // Some canonical shapes have syntax-owned meaning before ordinary named-type resolution:
    // `Func<...>` is parser sugar even when a source declaration is named Func, while a source
    // declaration/alias claiming a BCL collection head makes that collection spelling terminally
    // invalid for the retained emitter. Inspect the complete shape so an outer array, nullable,
    // tuple, union, or generic cannot hide either rule from the exact resolver.
    func TryClassifySyntaxOwnedShape(canonical: string, out terminalRejection: bool): bool {
        terminalRejection = false
        remaining := canonical
        deferToRetainedShape := false
        changed := true
        while changed {
            changed = false
            while remaining.EndsWith("[]", StringComparison.Ordinal) && remaining.Length > 2 {
                remaining = remaining.Substring(0, remaining.Length - 2)
                deferToRetainedShape = true
                changed = true
            }
            if remaining.EndsWith("?", StringComparison.Ordinal) && remaining.Length > 1 {
                remaining = remaining.Substring(0, remaining.Length - 1)
                deferToRetainedShape = true
                changed = true
            }
            if remaining.StartsWith("&", StringComparison.Ordinal) && remaining.Length > 1 {
                remaining = remaining.Substring(1)
                deferToRetainedShape = true
                changed = true
            }
        }

        unionParts := SplitTopLevelPipes(remaining)
        if unionParts.Count > 0 {
            for part in unionParts {
                nestedTerminal := false
                if TryClassifySyntaxOwnedShape(part, out nestedTerminal) && nestedTerminal {
                    terminalRejection = true
                    return true
                }
            }
            return true
        }

        if remaining.Length >= 2 && remaining[0] == '(' && remaining[remaining.Length - 1] == ')' {
            tupleCanonical := ColumnarTypeCanonicalizer.StripTupleElementNames(remaining).Canonical
            elements := ColumnarTypeCanonicalizer.SplitTopLevelCommas(tupleCanonical.Substring(1, tupleCanonical.Length - 2))
            for element in elements {
                nestedTerminal := false
                if TryClassifySyntaxOwnedShape(element, out nestedTerminal) && nestedTerminal {
                    terminalRejection = true
                    return true
                }
            }
            return true
        }

        genericOpen := remaining.IndexOf('<')
        if genericOpen > 0 && remaining.EndsWith(">", StringComparison.Ordinal) {
            head := remaining.Substring(0, genericOpen)
            arguments := ColumnarTypeCanonicalizer.SplitTopLevelCommas(remaining.Substring(genericOpen + 1, remaining.Length - genericOpen - 2))
            // A terminal source collision in any argument dominates a retained outer shape.
            // Inspect every argument before accepting a modeled or exact-only runtime family so
            // an earlier non-terminal Func/tuple/union arm cannot hide a later source collection.
            for argument in arguments {
                nestedTerminal := false
                if TryClassifySyntaxOwnedShape(argument, out nestedTerminal) && nestedTerminal {
                    terminalRejection = true
                    return true
                }
            }
            if head == "Func" {
                return true
            }
            exactHeadName := ""
            sourceClaimed := false
            sourceResolved := TryResolveSourceDeclarationName(head, out exactHeadName, out sourceClaimed)
            if IsCollectionSyntaxHead(head) {
                if sourceResolved || sourceClaimed {
                    terminalRejection = true
                    return true
                }
            }
            // Modeled runtime families must flow through their retained admissibility checks.
            // Exact-only runtime families stay exact, then use the retained support predicate;
            // only an exact source generic may be assembled without either validation path.
            if !sourceResolved {
                exactRuntimeType := typeof(object)
                exactRuntimeClaimed := false
                if TryResolveExactExplicitType(remaining, out exactRuntimeType, out exactRuntimeClaimed) {
                    validationCanonical := RuntimeGenericValidationCanonical(exactRuntimeType)
                    if validationCanonical == "*" {
                        return false
                    }
                    if validationCanonical != null && validationCanonical.Length > 0 {
                        return true
                    }
                    terminalRejection = true
                    return true
                }
                if head.IndexOf('.') < 0 && IsModeledRuntimeGenericHeadName(head) {
                    return true
                }
                terminalRejection = true
                return true
            }
            for argument in arguments {
                nestedTerminal := false
                if TryClassifySyntaxOwnedShape(argument, out nestedTerminal) {
                    terminalRejection = nestedTerminal
                    return true
                }
            }
        }
        return deferToRetainedShape
    }

    // Contract for a resolved type: null needs no runtime-generic validation; empty means it is
    // open or its arguments cannot be represented and must be rejected; "*" delegates a family
    // to the retained support predicate; every other value is a canonical routed back through
    // the retained resolver's existing family-specific admissibility predicates.
    func RuntimeGenericValidationCanonical(valueType: Type): string? {
        if !valueType.get_IsGenericType() || IsSourceDefinition(valueType) {
            return null
        }
        if valueType.get_IsGenericTypeDefinition() {
            return ""
        }
        definition := valueType.GetGenericTypeDefinition()
        head := RuntimeGenericValidationHead(definition)
        if head.Length == 0 {
            // The retained IsSupportedType predicate is the existing owner for explicitly
            // supported exact-only families (pools/memory and external reference types).
            return "*"
        }
        arguments := valueType.GetGenericArguments()
        canonicals := new string[](arguments.Length)
        i := 0
        while i < arguments.Length {
            argumentCanonical := ""
            if !TryBuildValidationArgumentCanonical(arguments[i], out argumentCanonical) {
                return ""
            }
            canonicals[i] = argumentCanonical
            i += 1
        }
        if head == "Nullable" {
            return canonicals[0] + "?"
        }
        return head + "<" + string.Join(",", canonicals) + ">"
    }

    func TryBuildValidationArgumentCanonical(valueType: Type, out canonical: string): bool {
        canonical = ""
        primitiveCanonical := ValidationPrimitiveCanonical(valueType)
        if primitiveCanonical != null {
            canonical = primitiveCanonical
            return true
        }
        if valueType.get_IsGenericParameter() {
            canonical = valueType.get_Name()
            return true
        }
        if valueType.get_IsSZArray() {
            elementCanonical := ""
            elementType := valueType.GetElementType()
            if elementType == null {
                return false
            }
            if !TryBuildValidationArgumentCanonical(elementType, out elementCanonical) {
                return false
            }
            canonical = elementCanonical + "[]"
            return true
        }
        sourceType := valueType
        sourceArguments := new Type[](0)
        if valueType.get_IsGenericType() && !valueType.get_IsGenericTypeDefinition() && IsSourceDefinition(valueType) {
            sourceType = valueType.GetGenericTypeDefinition()
            sourceArguments = valueType.GetGenericArguments()
        }
        for pair in exactSourceTypes {
            if Object.ReferenceEquals(pair.Value, sourceType) {
                canonical = pair.Key
                if sourceArguments.Length > 0 {
                    argumentCanonicals := new string[](sourceArguments.Length)
                    i := 0
                    while i < sourceArguments.Length {
                        sourceArgumentCanonical := ""
                        if !TryBuildValidationArgumentCanonical(sourceArguments[i], out sourceArgumentCanonical) {
                            canonical = ""
                            return false
                        }
                        argumentCanonicals[i] = sourceArgumentCanonical
                        i += 1
                    }
                    canonical = canonical + "<" + string.Join(",", argumentCanonicals) + ">"
                }
                return true
            }
        }
        nested := RuntimeGenericValidationCanonical(valueType)
        if nested != null {
            if nested == "*" {
                return TryBuildExactRuntimeGenericCanonical(valueType, out canonical)
            }
            canonical = nested
            return canonical.Length > 0
        }
        fullName := valueType.get_FullName()
        if fullName == null || fullName.Length == 0 {
            return false
        }
        canonical = fullName
        return true
    }

    static func ValidationPrimitiveCanonical(valueType: Type): string? {
        if valueType == typeof(int) {
            return "int"
        }
        if valueType == typeof(long) {
            return "long"
        }
        if valueType == typeof(ulong) {
            return "ulong"
        }
        if valueType == typeof(uint) {
            return "uint"
        }
        if valueType == typeof(short) {
            return "short"
        }
        if valueType == typeof(ushort) {
            return "ushort"
        }
        if valueType == typeof(byte) {
            return "byte"
        }
        if valueType == typeof(sbyte) {
            return "sbyte"
        }
        if valueType == typeof(bool) {
            return "bool"
        }
        if valueType == typeof(char) {
            return "char"
        }
        if valueType == typeof(double) {
            return "double"
        }
        if valueType == typeof(float) {
            return "float"
        }
        if valueType == typeof(decimal) {
            return "decimal"
        }
        if valueType == typeof(string) {
            return "string"
        }
        if valueType == typeof(object) {
            return "object"
        }
        return null
    }

    func TryBuildExactRuntimeGenericCanonical(valueType: Type, out canonical: string): bool {
        canonical = ""
        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }
        definitionName := valueType.GetGenericTypeDefinition().get_FullName()
        if definitionName == null || definitionName.Length == 0 {
            return false
        }
        arityIndex := definitionName.IndexOf('`')
        if arityIndex >= 0 {
            definitionName = definitionName.Substring(0, arityIndex)
        }
        definitionName = definitionName.Replace('+', '.')
        arguments := valueType.GetGenericArguments()
        argumentCanonicals := new string[](arguments.Length)
        i := 0
        while i < arguments.Length {
            argumentCanonical := ""
            if !TryBuildValidationArgumentCanonical(arguments[i], out argumentCanonical) {
                return false
            }
            argumentCanonicals[i] = argumentCanonical
            i += 1
        }
        canonical = definitionName + "<" + string.Join(",", argumentCanonicals) + ">"
        return true
    }

    static func RuntimeGenericValidationHead(definition: Type): string {
        core := "System.Private.CoreLib"
        collections := "System.Collections"
        if RuntimeDefinitionMatches(definition, "System.Nullable`1", core) {
            return "Nullable"
        }
        if RuntimeDefinitionMatches(definition, "System.Span`1", core) {
            return "Span"
        }
        if RuntimeDefinitionMatches(definition, "System.ReadOnlySpan`1", core) {
            return "ReadOnlySpan"
        }
        if RuntimeDefinitionMatches(definition, "System.ValueTuple`2", core) || RuntimeDefinitionMatches(definition, "System.ValueTuple`3", core) || RuntimeDefinitionMatches(definition, "System.ValueTuple`4", core) || RuntimeDefinitionMatches(definition, "System.ValueTuple`5", core) || RuntimeDefinitionMatches(definition, "System.ValueTuple`6", core) || RuntimeDefinitionMatches(definition, "System.ValueTuple`7", core) {
            return "ValueTuple"
        }
        if RuntimeDefinitionMatches(definition, "System.Threading.Tasks.Task`1", core) {
            return "Task"
        }
        if RuntimeDefinitionMatches(definition, "System.Threading.Tasks.ValueTask`1", core) {
            return "ValueTask"
        }
        if RuntimeDefinitionMatches(definition, "NSharpLang.Runtime.Result`2", "NSharpLang.Runtime") {
            return "Result"
        }
        if RuntimeDefinitionMatches(definition, "System.Collections.Generic.List`1", core) {
            return "List"
        }
        if RuntimeDefinitionMatches(definition, "System.Collections.Generic.HashSet`1", core) {
            return "HashSet"
        }
        if RuntimeDefinitionMatches(definition, "System.Collections.Generic.Stack`1", collections) {
            return "Stack"
        }
        if RuntimeDefinitionMatches(definition, "System.Collections.Generic.IReadOnlyList`1", core) {
            return "IReadOnlyList"
        }
        if RuntimeDefinitionMatches(definition, "System.Collections.Generic.IReadOnlyCollection`1", core) {
            return "IReadOnlyCollection"
        }
        if RuntimeDefinitionMatches(definition, "System.Collections.Generic.IReadOnlySet`1", core) {
            return "IReadOnlySet"
        }
        if RuntimeDefinitionMatches(definition, "System.Collections.Generic.IEnumerable`1", core) {
            return "IEnumerable"
        }
        if RuntimeDefinitionMatches(definition, "System.Collections.Generic.Dictionary`2", core) {
            return "Dictionary"
        }
        if RuntimeDefinitionMatches(definition, "System.Collections.Generic.SortedDictionary`2", collections) {
            return "SortedDictionary"
        }
        if RuntimeDefinitionMatches(definition, "System.Collections.Generic.IReadOnlyDictionary`2", core) {
            return "IReadOnlyDictionary"
        }
        if RuntimeDefinitionMatches(definition, "System.Action`1", core) || RuntimeDefinitionMatches(definition, "System.Action`2", core) || RuntimeDefinitionMatches(definition, "System.Action`3", core) || RuntimeDefinitionMatches(definition, "System.Action`4", core) {
            return "Action"
        }
        if RuntimeDefinitionMatches(definition, "System.Func`1", core) || RuntimeDefinitionMatches(definition, "System.Func`2", core) || RuntimeDefinitionMatches(definition, "System.Func`3", core) || RuntimeDefinitionMatches(definition, "System.Func`4", core) || RuntimeDefinitionMatches(definition, "System.Func`5", core) {
            return "Func"
        }
        return ""
    }

    static func RuntimeDefinitionMatches(definition: Type, fullName: string, assemblyName: string): bool {
        if definition.get_FullName() != fullName {
            return false
        }
        assembly := definition.get_Assembly()
        identity := assembly.GetName()
        return identity.get_Name() == assemblyName
    }

    static func IsModeledRuntimeGenericHeadName(name: string): bool {
        return name == "Nullable" || name == "Span" || name == "ReadOnlySpan" || name == "ValueTuple" || name == "Task" || name == "ValueTask" || name == "Result" || name == "List" || name == "HashSet" || name == "Stack" || name == "IReadOnlyList" || name == "IReadOnlyCollection" || name == "IReadOnlySet" || name == "IEnumerable" || name == "Dictionary" || name == "SortedDictionary" || name == "IReadOnlyDictionary" || name == "Action" || name == "Func"
    }

    func TryResolveSourceDeclarationName(canonical: string, out exactName: string, out claimed: bool): bool {
        cached := new ColumnarSourceNameResolutionCacheEntry(false, false, "")
        if !sourceNameCache.TryGetValue(canonical, out cached) {
            selectedName := ""
            resolved := TryResolveLexicalSourceDeclarationName(canonical, out selectedName)
            claimed = resolved
            if !resolved {
                resolved = program.TryResolveExactSourceDeclarationNameForFile(sourceFileId, canonical, out selectedName, out claimed)
            }
            cached = new ColumnarSourceNameResolutionCacheEntry(resolved, claimed, selectedName)
            sourceNameCache[canonical] = cached
        }
        exactName = cached.ExactName
        claimed = cached.Claimed
        return cached.Resolved
    }

    // Resolve a source type spelling relative to the exact declaration that owns the metadata or
    // body being emitted. A resolver instance has one immutable owner, so the ordinary spelling
    // caches above remain correct. Only actual source declarations form the parent walk: once the
    // next prefix is a namespace rather than a type, ordinary per-file/import lookup takes over.
    func TryResolveLexicalSourceDeclarationName(canonical: string, out exactName: string): bool {
        exactName = ""
        if canonical == null || canonical.Length == 0 || enclosingSourceDeclarationName.Length == 0 {
            return false
        }

        ownerName := enclosingSourceDeclarationName
        while ownerName.Length > 0 {
            if (ownerName == canonical || ownerName.EndsWith("." + canonical, StringComparison.Ordinal)) && exactSourceTypes.ContainsKey(ownerName) {
                exactName = ownerName
                return true
            }

            candidateName := ownerName + "." + canonical
            if exactSourceTypes.ContainsKey(candidateName) {
                exactName = candidateName
                return true
            }

            separator := ownerName.LastIndexOf('.')
            if separator < 0 {
                return false
            }
            parentName := ownerName.Substring(0, separator)
            if !exactSourceTypes.ContainsKey(parentName) {
                return false
            }
            ownerName = parentName
        }
        return false
    }

    // Constructed lexical source types still flow through the binding scope's CLR-shape owner.
    // Replace only the source head with its exact dotted identity, then let the existing recursive
    // resolver assemble and validate arguments. File aliases/imports remain unchanged fallbacks.
    func TryResolveExactExplicitType(canonical: string, out selectedType: Type, out claimed: bool): bool {
        contextualCanonical := ""
        if TryBuildLexicalExplicitCanonical(canonical, out contextualCanonical) {
            contextualClaimed := false
            if program.TryResolveExactExplicitTypeForFile(sourceFileId, contextualCanonical, bindings, out selectedType, out contextualClaimed) {
                claimed = true
                return true
            }
            if contextualClaimed {
                claimed = true
                return false
            }
        }
        return program.TryResolveExactExplicitTypeForFile(sourceFileId, canonical, bindings, out selectedType, out claimed)
    }

    func TryBuildLexicalExplicitCanonical(canonical: string, out contextualCanonical: string): bool {
        contextualCanonical = ""
        if canonical == null || canonical.Length == 0 {
            return false
        }
        head := canonical
        suffix := ""
        genericOpen := canonical.IndexOf('<')
        if genericOpen > 0 && canonical.EndsWith(">", StringComparison.Ordinal) {
            head = canonical.Substring(0, genericOpen)
            suffix = canonical.Substring(genericOpen)
        }
        exactHead := ""
        if !TryResolveLexicalSourceDeclarationName(head, out exactHead) {
            return false
        }
        contextualCanonical = exactHead + suffix
        return true
    }

    func HasVisibleTypeParameterRoot(canonical: string): bool {
        for pair in typeParameters {
            if canonical.StartsWith(pair.Key + ".", StringComparison.Ordinal) || canonical.StartsWith(pair.Key + "<", StringComparison.Ordinal) {
                return true
            }
        }
        return false
    }

    func ContainsBlockedTypeParameter(canonical: string): bool {
        for name in blockedTypeParameterNames {
            if ContainsTypeParameter(canonical, name) {
                return true
            }
        }
        return false
    }

    static func ContainsTypeParameter(canonical: string, name: string): bool {
        remaining := canonical
        changed := true
        while changed {
            changed = false
            while remaining.EndsWith("[]", StringComparison.Ordinal) && remaining.Length > 2 {
                remaining = remaining.Substring(0, remaining.Length - 2)
                changed = true
            }
            if remaining.EndsWith("?", StringComparison.Ordinal) && remaining.Length > 1 {
                remaining = remaining.Substring(0, remaining.Length - 1)
                changed = true
            }
            if remaining.StartsWith("&", StringComparison.Ordinal) && remaining.Length > 1 {
                remaining = remaining.Substring(1)
                changed = true
            }
        }
        unionParts := SplitTopLevelPipes(remaining)
        if unionParts.Count > 0 {
            for part in unionParts {
                if ContainsTypeParameter(part, name) {
                    return true
                }
            }
            return false
        }
        if remaining.Length >= 2 && remaining[0] == '(' && remaining[remaining.Length - 1] == ')' {
            tupleCanonical := ColumnarTypeCanonicalizer.StripTupleElementNames(remaining).Canonical
            elements := ColumnarTypeCanonicalizer.SplitTopLevelCommas(tupleCanonical.Substring(1, tupleCanonical.Length - 2))
            for element in elements {
                if ContainsTypeParameter(element, name) {
                    return true
                }
            }
            return false
        }
        genericOpen := remaining.IndexOf('<')
        if genericOpen > 0 && remaining.EndsWith(">", StringComparison.Ordinal) {
            if IsTypeParameterRoot(remaining.Substring(0, genericOpen), name) {
                return true
            }
            arguments := ColumnarTypeCanonicalizer.SplitTopLevelCommas(remaining.Substring(genericOpen + 1, remaining.Length - genericOpen - 2))
            for argument in arguments {
                if ContainsTypeParameter(argument, name) {
                    return true
                }
            }
            return false
        }
        return IsTypeParameterRoot(remaining, name)
    }

    static func IsCollectionSyntaxHead(name: string): bool {
        return name == "List" || name == "Dictionary" || name == "SortedDictionary" || name == "HashSet" || name == "Stack"
    }

    static func SplitTopLevelPipes(canonical: string): List<string> {
        parts := new List<string>()
        start := 0
        angleDepth := 0
        parenDepth := 0
        bracketDepth := 0
        i := 0
        while i < canonical.Length {
            c := canonical[i]
            if c == '<' {
                angleDepth += 1
            } else if c == '>' && angleDepth > 0 {
                angleDepth -= 1
            } else if c == '(' {
                parenDepth += 1
            } else if c == ')' && parenDepth > 0 {
                parenDepth -= 1
            } else if c == '[' {
                bracketDepth += 1
            } else if c == ']' && bracketDepth > 0 {
                bracketDepth -= 1
            } else if c == '|' && angleDepth == 0 && parenDepth == 0 && bracketDepth == 0 {
                parts.Add(canonical.Substring(start, i - start))
                start = i + 1
            }
            i += 1
        }
        if parts.Count > 0 {
            parts.Add(canonical.Substring(start))
        }
        return parts
    }

    static func IsTypeParameterRoot(canonical: string, name: string): bool {
        return canonical == name || canonical.StartsWith(name + ".", StringComparison.Ordinal)
    }
}

class ColumnarSemanticDefinitionIndexes {
    static func Enums(source: Dictionary<string, ColumnarEnumDef>): ColumnarSemanticDefinitionIndex<ColumnarEnumDef> {
        definitions := new List<ColumnarEnumDef>()
        names := new List<string>()
        runtimeTypes := new List<Type>()
        for pair in source {
            definition := pair.Value
            definitions.Add(definition)
            names.Add(definition.DeclaredTypeName)
            runtimeType := definition.EnumType
            if definition.IsStringBacked {
                runtimeType = typeof(object)
            }
            runtimeTypes.Add(runtimeType)
        }
        return new ColumnarSemanticDefinitionIndex<ColumnarEnumDef>(definitions.ToArray(), names.ToArray(), runtimeTypes.ToArray())
    }

    static func Structs(source: Dictionary<string, ColumnarStructDef>): ColumnarSemanticDefinitionIndex<ColumnarStructDef> {
        definitions := new List<ColumnarStructDef>()
        names := new List<string>()
        runtimeTypes := new List<Type>()
        for pair in source {
            definition := pair.Value
            definitions.Add(definition)
            names.Add(definition.DeclaredTypeName)
            runtimeTypes.Add(definition.Builder)
        }
        return new ColumnarSemanticDefinitionIndex<ColumnarStructDef>(definitions.ToArray(), names.ToArray(), runtimeTypes.ToArray())
    }

    static func Unions(source: Dictionary<string, ColumnarUnionDef>): ColumnarSemanticDefinitionIndex<ColumnarUnionDef> {
        definitions := new List<ColumnarUnionDef>()
        names := new List<string>()
        runtimeTypes := new List<Type>()
        for pair in source {
            definition := pair.Value
            definitions.Add(definition)
            names.Add(definition.DeclaredTypeName)
            runtimeTypes.Add(definition.Base)
        }
        return new ColumnarSemanticDefinitionIndex<ColumnarUnionDef>(definitions.ToArray(), names.ToArray(), runtimeTypes.ToArray())
    }
}

class ColumnarSemanticDefinitionIndex<TDefinition> {
    exact: Dictionary<string, TDefinition>
    exactNames: List<string>
    definitions: List<TDefinition>
    uniqueRuntimeDefinitions: Dictionary<Type, TDefinition>
    ambiguousRuntimeTypes: HashSet<Type>

    Keys: List<string> => exactNames
    Values: List<TDefinition> => definitions
    Count: int => definitions.Count
    ExactPairs: Dictionary<string, TDefinition> => exact

    constructor(sourceDefinitions: TDefinition[], declaredNames: string[], runtimeTypes: Type[]) {
        if sourceDefinitions.Length != declaredNames.Length || sourceDefinitions.Length != runtimeTypes.Length {
            throw new InvalidOperationException("Semantic definition index columns must have identical lengths.")
        }
        exact = new Dictionary<string, TDefinition>(StringComparer.Ordinal)
        exactNames = new List<string>()
        definitions = new List<TDefinition>()
        uniqueRuntimeDefinitions = new Dictionary<Type, TDefinition>()
        ambiguousRuntimeTypes = new HashSet<Type>()
        seen := new HashSet<TDefinition>()
        sourceIndex := 0
        while sourceIndex < sourceDefinitions.Length {
            definition := sourceDefinitions[sourceIndex]
            if !seen.Add(definition) {
                sourceIndex += 1
                continue
            }
            definitions.Add(definition)
            exactName := declaredNames[sourceIndex]
            if !string.IsNullOrEmpty(exactName) && !exact.ContainsKey(exactName) {
                exact.Add(exactName, definition)
                exactNames.Add(exactName)
            }

            emittedType := runtimeTypes[sourceIndex]
            if emittedType != typeof(object) {
                existing := definition
                if uniqueRuntimeDefinitions.TryGetValue(emittedType, out existing) {
                    uniqueRuntimeDefinitions.Remove(emittedType)
                    ambiguousRuntimeTypes.Add(emittedType)
                } else if !ambiguousRuntimeTypes.Contains(emittedType) {
                    uniqueRuntimeDefinitions.Add(emittedType, definition)
                }
            }
            sourceIndex += 1
        }
    }

    func TryGetExact(name: string, out definition: TDefinition): bool {
        return exact.TryGetValue(name, out definition)
    }

    func ContainsExact(name: string): bool {
        return exact.ContainsKey(name)
    }

    func TryGetExactConstructed(name: string, out definition: TDefinition): bool {
        if exact.TryGetValue(name, out definition) {
            return true
        }
        genericOpen := name.IndexOf('<')
        return genericOpen > 0 && name.EndsWith(">", StringComparison.Ordinal) && exact.TryGetValue(name.Substring(0, genericOpen), out definition)
    }

    func ContainsExactConstructed(name: string): bool {
        if exact.ContainsKey(name) {
            return true
        }
        genericOpen := name.IndexOf('<')
        return genericOpen > 0 && name.EndsWith(">", StringComparison.Ordinal) && exact.ContainsKey(name.Substring(0, genericOpen))
    }

    func TryGetUniqueRuntime(valueType: Type, out definition: TDefinition): bool {
        lookupType := valueType
        if lookupType.get_IsGenericType() && !lookupType.get_IsGenericTypeDefinition() {
            lookupType = lookupType.GetGenericTypeDefinition()
        }
        found := uniqueRuntimeDefinitions.TryGetValue(lookupType, out definition)
        return !ambiguousRuntimeTypes.Contains(lookupType) && found
    }

    func ContainsUniqueRuntime(valueType: Type): bool {
        lookupType := valueType
        if lookupType.get_IsGenericType() && !lookupType.get_IsGenericTypeDefinition() {
            lookupType = lookupType.GetGenericTypeDefinition()
        }
        return !ambiguousRuntimeTypes.Contains(lookupType) && uniqueRuntimeDefinitions.ContainsKey(lookupType)
    }
}

class ColumnarSemanticRegistry<TDefinition> {
    index: ColumnarSemanticDefinitionIndex<TDefinition>
    resolver: ColumnarExactTypeResolver
    resolvedLookupCache: Dictionary<string, TDefinition>
    rejectedLookupCache: HashSet<string>

    Resolver: ColumnarExactTypeResolver => resolver
    StructuralTypeReferences: ColumnarStructuralTypeReferenceTable => resolver.StructuralTypeReferences
    Keys: List<string> => index.Keys
    Values: List<TDefinition> => index.Values
    Count: int => index.Count

    constructor(index: ColumnarSemanticDefinitionIndex<TDefinition>, resolver: ColumnarExactTypeResolver) {
        this.index = index
        this.resolver = resolver
        resolvedLookupCache = new Dictionary<string, TDefinition>(StringComparer.Ordinal)
        rejectedLookupCache = new HashSet<string>(StringComparer.Ordinal)
    }

    func ContainsSourceDeclaration(name: string): bool {
        exactSourceName := ""
        claimed := false
        return resolver.TryResolveSourceDeclarationName(name, out exactSourceName, out claimed) && index.ContainsExactConstructed(exactSourceName)
    }

    func ContainsKey(key: string): bool {
        if resolvedLookupCache.ContainsKey(key) {
            return true
        }
        if rejectedLookupCache.Contains(key) || resolver.ClaimsTypeParameterShape(key) {
            rejectedLookupCache.Add(key)
            return false
        }

        exactSourceName := ""
        sourceClaimed := false
        if resolver.TryResolveSourceDeclarationName(key, out exactSourceName, out sourceClaimed) {
            foundSource := index.ContainsExactConstructed(exactSourceName)
            if !foundSource {
                rejectedLookupCache.Add(key)
            }
            return foundSource
        }

        selectedType := typeof(object)
        claimed := false
        if resolver.TryResolve(key, out selectedType, out claimed) {
            foundRuntime := index.ContainsUniqueRuntime(selectedType)
            if !foundRuntime {
                rejectedLookupCache.Add(key)
            }
            return foundRuntime
        }
        if claimed {
            rejectedLookupCache.Add(key)
            return false
        }

        foundExact := index.ContainsExact(key)
        if !foundExact {
            rejectedLookupCache.Add(key)
        }
        return foundExact
    }

    func TryGetValue(key: string, out value: TDefinition): bool {
        if resolvedLookupCache.TryGetValue(key, out value) {
            return true
        }
        if rejectedLookupCache.Contains(key) {
            return false
        }
        if resolver.ClaimsTypeParameterShape(key) {
            rejectedLookupCache.Add(key)
            return false
        }

        exactSourceName := ""
        sourceClaimed := false
        if resolver.TryResolveSourceDeclarationName(key, out exactSourceName, out sourceClaimed) {
            sourceDefinition := value
            if index.TryGetExactConstructed(exactSourceName, out sourceDefinition) {
                resolvedLookupCache[key] = sourceDefinition
                value = sourceDefinition
                return true
            }
            rejectedLookupCache.Add(key)
            return false
        }

        selectedType := typeof(object)
        claimed := false
        if resolver.TryResolve(key, out selectedType, out claimed) {
            runtimeDefinition := value
            if index.TryGetUniqueRuntime(selectedType, out runtimeDefinition) {
                resolvedLookupCache[key] = runtimeDefinition
                value = runtimeDefinition
                return true
            }
            rejectedLookupCache.Add(key)
            return false
        }
        if claimed {
            rejectedLookupCache.Add(key)
            return false
        }

        exactDefinition := value
        if index.TryGetExact(key, out exactDefinition) {
            resolvedLookupCache[key] = exactDefinition
            value = exactDefinition
            return true
        }
        rejectedLookupCache.Add(key)
        return false
    }

    func ForSynthesizedMethod(declaringType: TypeBuilder): ColumnarSemanticRegistry<TDefinition> {
        selectedIndex := index
        selectedResolver := resolver.ForSynthesizedMethod(declaringType)
        return new ColumnarSemanticRegistry<TDefinition>(selectedIndex, selectedResolver)
    }
}

class ColumnarSemanticTypeResolution {
    Enums: ColumnarSemanticRegistry<ColumnarEnumDef>
    Structs: ColumnarSemanticRegistry<ColumnarStructDef>
    Unions: ColumnarSemanticRegistry<ColumnarUnionDef>
    StructuralTypeReferences: ColumnarStructuralTypeReferenceTable

    constructor(program: ColumnarProgramInput, sourceFileId: int, enums: Dictionary<string, ColumnarEnumDef>, structs: Dictionary<string, ColumnarStructDef>, unions: Dictionary<string, ColumnarUnionDef>, enumIndex: ColumnarSemanticDefinitionIndex<ColumnarEnumDef>, structIndex: ColumnarSemanticDefinitionIndex<ColumnarStructDef>, unionIndex: ColumnarSemanticDefinitionIndex<ColumnarUnionDef>, sourceDefinitionTypes: List<Type>, exactSourceTypes: Dictionary<string, Type>, suppliedTypeParameters: Dictionary<string, Type>?, enclosingSourceDeclarationName: string?, structuralTypeReferences: ColumnarStructuralTypeReferenceTable) {
        typeParameters := suppliedTypeParameters
        if typeParameters == null {
            typeParameters = new Dictionary<string, Type>(StringComparer.Ordinal)
        }
        bindings := ColumnarFragmentBindings.CreateTypeResolutionBindings(enums, structs, unions, typeParameters)
        bindings.ExactSourceTypes = exactSourceTypes
        exactResolver := new ColumnarExactTypeResolver(program, sourceFileId, bindings, sourceDefinitionTypes, exactSourceTypes, typeParameters, null, enclosingSourceDeclarationName, structuralTypeReferences)
        Enums = new ColumnarSemanticRegistry<ColumnarEnumDef>(enumIndex, exactResolver)
        Structs = new ColumnarSemanticRegistry<ColumnarStructDef>(structIndex, exactResolver)
        Unions = new ColumnarSemanticRegistry<ColumnarUnionDef>(unionIndex, exactResolver)
        StructuralTypeReferences = structuralTypeReferences
    }
}

class ColumnarSemanticTypeResolutionCatalogEntry {
    TypeParameters: Dictionary<string, Type>
    Resolution: ColumnarSemanticTypeResolution

    constructor(typeParameters: Dictionary<string, Type>, resolution: ColumnarSemanticTypeResolution) {
        TypeParameters = typeParameters
        Resolution = resolution
    }

    func Matches(typeParameters: Dictionary<string, Type>): bool {
        return Object.ReferenceEquals(TypeParameters, typeParameters)
    }
}

// One emission owns one immutable definition catalog. Definition indexes and exact live source
// handles are built once, while the spelling caches inside each resolution remain scoped to the
// source file, lexical owner, and exact type-parameter map that can affect their answers.
class ColumnarSemanticTypeResolutionCatalog {
    program: ColumnarProgramInput
    enums: Dictionary<string, ColumnarEnumDef>
    structs: Dictionary<string, ColumnarStructDef>
    unions: Dictionary<string, ColumnarUnionDef>
    enumIndex: ColumnarSemanticDefinitionIndex<ColumnarEnumDef>
    structIndex: ColumnarSemanticDefinitionIndex<ColumnarStructDef>
    unionIndex: ColumnarSemanticDefinitionIndex<ColumnarUnionDef>
    sourceDefinitionTypes: List<Type>
    exactSourceTypes: Dictionary<string, Type>
    nongenericViews: Dictionary<int, Dictionary<string, ColumnarSemanticTypeResolution>>
    genericViews: Dictionary<int, Dictionary<string, List<ColumnarSemanticTypeResolutionCatalogEntry>>>
    structuralTypeReferences: ColumnarStructuralTypeReferenceTable

    StructuralTypeReferences: ColumnarStructuralTypeReferenceTable => structuralTypeReferences

    constructor(program: ColumnarProgramInput, enums: Dictionary<string, ColumnarEnumDef>, structs: Dictionary<string, ColumnarStructDef>, unions: Dictionary<string, ColumnarUnionDef>) {
        this.program = program
        this.enums = enums
        this.structs = structs
        this.unions = unions
        enumIndex = ColumnarSemanticDefinitionIndexes.Enums(enums)
        structIndex = ColumnarSemanticDefinitionIndexes.Structs(structs)
        unionIndex = ColumnarSemanticDefinitionIndexes.Unions(unions)
        structuralTypeReferences = new ColumnarStructuralTypeReferenceTable()
        sourceDefinitionTypes = new List<Type>()
        for definition in enumIndex.Values {
            sourceDefinitionTypes.Add(definition.EnumType)
        }
        for definition in structIndex.Values {
            sourceDefinitionTypes.Add(definition.Builder)
        }
        for definition in unionIndex.Values {
            sourceDefinitionTypes.Add(definition.Base)
        }
        exactSourceTypes = new Dictionary<string, Type>(StringComparer.Ordinal)
        for pair in enumIndex.ExactPairs {
            exactSourceTypes[pair.Key] = pair.Value.EnumType
            structuralTypeReferences.RegisterSourceDefinition(pair.Key, pair.Value.EnumType, pair.Value.IsStringBacked)
        }
        for pair in structIndex.ExactPairs {
            exactSourceTypes[pair.Key] = pair.Value.Builder
            structuralTypeReferences.RegisterSourceDefinition(pair.Key, pair.Value.Builder, false)
        }
        for pair in unionIndex.ExactPairs {
            exactSourceTypes[pair.Key] = pair.Value.Base
            structuralTypeReferences.RegisterSourceDefinition(pair.Key, pair.Value.Base, false)
        }
        RegisterDeclaredTypeParameters()
        nongenericViews = new Dictionary<int, Dictionary<string, ColumnarSemanticTypeResolution>>()
        genericViews = new Dictionary<int, Dictionary<string, List<ColumnarSemanticTypeResolutionCatalogEntry>>>()
    }

    func For(sourceFileId: int, typeParameters: Dictionary<string, Type>? = null, enclosingSourceDeclarationName: string? = null): ColumnarSemanticTypeResolution {
        enclosingDeclaration := enclosingSourceDeclarationName ?? ""
        if typeParameters == null {
            viewsByOwner := new Dictionary<string, ColumnarSemanticTypeResolution>(StringComparer.Ordinal)
            if nongenericViews.ContainsKey(sourceFileId) {
                viewsByOwner = nongenericViews[sourceFileId]
            } else {
                nongenericViews[sourceFileId] = viewsByOwner
            }
            if viewsByOwner.ContainsKey(enclosingDeclaration) {
                return viewsByOwner[enclosingDeclaration]
            }
            created := Create(sourceFileId, null, enclosingDeclaration)
            viewsByOwner[enclosingDeclaration] = created
            return created
        }

        genericViewsByOwner := new Dictionary<string, List<ColumnarSemanticTypeResolutionCatalogEntry>>(StringComparer.Ordinal)
        if genericViews.ContainsKey(sourceFileId) {
            genericViewsByOwner = genericViews[sourceFileId]
        } else {
            genericViews[sourceFileId] = genericViewsByOwner
        }
        ownerViews := new List<ColumnarSemanticTypeResolutionCatalogEntry>()
        if genericViewsByOwner.ContainsKey(enclosingDeclaration) {
            ownerViews = genericViewsByOwner[enclosingDeclaration]
        } else {
            genericViewsByOwner[enclosingDeclaration] = ownerViews
        }
        for entry in ownerViews {
            if entry.Matches(typeParameters) {
                return entry.Resolution
            }
        }
        createdGeneric := Create(sourceFileId, typeParameters, enclosingDeclaration)
        ownerViews.Add(new ColumnarSemanticTypeResolutionCatalogEntry(typeParameters, createdGeneric))
        return createdGeneric
    }

    func ForSourceMethod(sourceFileId: int, typeParameters: Dictionary<string, Type>, methodOrdinal: int): ColumnarSemanticTypeResolution {
        structuralTypeReferences.RegisterGenericParameters(typeParameters, ColumnarStructuralGenericOwnerIdentity.SourceMethod(sourceFileId, methodOrdinal))
        return For(sourceFileId, typeParameters, null)
    }

    func RegisterUnionCase(sourceFileId: int, unionName: string, caseName: string, caseOrdinal: int, caseType: Type, typeParameters: Dictionary<string, Type>?): ColumnarSemanticTypeResolution {
        exactCaseName := unionName + "." + caseName
        structuralTypeReferences.RegisterSourceDefinition(exactCaseName, caseType, false)
        structuralTypeReferences.RegisterGenericParameters(typeParameters, ColumnarStructuralGenericOwnerIdentity.SourceUnionCase(sourceFileId, unionName, caseOrdinal))
        return For(sourceFileId, typeParameters, unionName)
    }

    func Create(sourceFileId: int, typeParameters: Dictionary<string, Type>?, enclosingDeclaration: string): ColumnarSemanticTypeResolution {
        return new ColumnarSemanticTypeResolution(program, sourceFileId, enums, structs, unions, enumIndex, structIndex, unionIndex, sourceDefinitionTypes, exactSourceTypes, typeParameters, enclosingDeclaration, structuralTypeReferences)
    }

    func RegisterDeclaredTypeParameters() {
        sourceOwnerFiles := new Dictionary<string, int>(StringComparer.Ordinal)
        unionParameterNames := new Dictionary<string, string[]>(StringComparer.Ordinal)
        for iface in program.Interfaces {
            exactName := program.ExactTypeNameForFile(iface.Name, iface.SourceFileId)
            if !sourceOwnerFiles.ContainsKey(exactName) {
                sourceOwnerFiles.Add(exactName, iface.SourceFileId)
            }
        }
        for input in program.Structs {
            exactName := program.ExactStructTypeName(input)
            if !sourceOwnerFiles.ContainsKey(exactName) {
                sourceOwnerFiles.Add(exactName, input.SourceFileId)
            }
        }
        for input in program.Unions {
            exactName := program.ExactTypeNameForFile(input.Name, input.SourceFileId)
            if !sourceOwnerFiles.ContainsKey(exactName) {
                sourceOwnerFiles.Add(exactName, input.SourceFileId)
                unionParameterNames.Add(exactName, input.TypeParamNames)
            }
        }

        for pair in structIndex.ExactPairs {
            sourceFileId := -1
            if sourceOwnerFiles.TryGetValue(pair.Key, out sourceFileId) {
                structuralTypeReferences.RegisterGenericParameters(pair.Value.GenericParameters, ColumnarStructuralGenericOwnerIdentity.SourceType(sourceFileId, pair.Key))
            }
        }
        for pair in unionIndex.ExactPairs {
            sourceFileId := -1
            parameterNames := new string[](0)
            if sourceOwnerFiles.TryGetValue(pair.Key, out sourceFileId) && unionParameterNames.TryGetValue(pair.Key, out parameterNames) && parameterNames.Length > 0 {
                structuralTypeReferences.RegisterTypeGenericParameters(sourceFileId, pair.Key, parameterNames, pair.Value.Base)
            }
        }
    }
}
