namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit


// Reflection.Emit cannot answer IsAssignableFrom for every closed BCL wrapper while one of
// its generic arguments is still an unbaked TypeBuilder. Keep the exact CLR interface edges
// that N# admits in one place so overload selection and sealed-plan validation cannot drift.
class ColumnarReferenceConversionFacts {

    // The emitter's complete reference-conversion decision. Reflection.Emit cannot answer
    // IsAssignableFrom for every closed shell that still contains an unbaked source builder, so the
    // guarded runtime question is followed by the exact collection edges already owned by emission.
    // Keep TypesEquivalent here: emission historically accepts its richer builder-aware equivalence,
    // while IsExactKnownUpcast below deliberately uses the stricter structural identity predicate.
    static func TryEmitReferenceConversion(sourceType: Type, targetType: Type): bool {
        if sourceType == ColumnarTypeOfPlanner.RequiredVoidType() || sourceType.get_IsValueType() || targetType.get_IsValueType() {
            return false
        }
        try {
            if targetType.IsAssignableFrom(sourceType) {
                return true
            }
        } catch ex: NotSupportedException {
        }

        if sourceType.get_IsSZArray() && targetType.get_IsGenericType() && !targetType.get_IsGenericTypeDefinition() {
            targetDefinition := targetType.GetGenericTypeDefinition()
            if (targetDefinition == typeof(IReadOnlyList<int>).GetGenericTypeDefinition() || targetDefinition == typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition() || targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition()) && ColumnarTypeEquivalenceFacts.TypesEquivalent(sourceType.GetElementType(), targetType.GetGenericArguments()[0]) {
                return true
            }
        }

        if sourceType.get_IsGenericType() && !sourceType.get_IsGenericTypeDefinition() && targetType.get_IsGenericType() && !targetType.get_IsGenericTypeDefinition() {
            sourceDefinition := sourceType.GetGenericTypeDefinition()
            targetDefinition := targetType.GetGenericTypeDefinition()
            sourceArguments := sourceType.GetGenericArguments()
            targetArguments := targetType.GetGenericArguments()
            if targetArguments.Length == 1 && sourceArguments.Length >= 1 && ColumnarTypeEquivalenceFacts.TypesEquivalent(sourceArguments[0], targetArguments[0]) && ((sourceDefinition == typeof(List<int>).GetGenericTypeDefinition() && (targetDefinition == typeof(IReadOnlyList<int>).GetGenericTypeDefinition() || targetDefinition == typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition() || targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition())) || (sourceDefinition == typeof(HashSet<int>).GetGenericTypeDefinition() && (targetDefinition == typeof(IReadOnlySet<int>).GetGenericTypeDefinition() || targetDefinition == typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition() || targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition())) || (sourceDefinition == typeof(SortedSet<int>).GetGenericTypeDefinition() && targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition()) || (sourceDefinition == typeof(Stack<int>).GetGenericTypeDefinition() && targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition())) {
                return true
            }
            // Dictionary<TKey, TValue>.ValueCollection retains both declaring-type arguments while
            // IEnumerable<T> carries only TValue. Compare the second source slot at the same phase as
            // the other closed-generic emission conversions.
            if targetArguments.Length == 1 && sourceArguments.Length == 2 && ColumnarTypeEquivalenceFacts.TypesEquivalent(sourceArguments[1], targetArguments[0]) && sourceDefinition == ColumnarTypeOfPlanner.RequiredDictionaryValueCollectionDefinition() && targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition() {
                return true
            }
            // Dictionary<TKey, TValue>.KeyCollection likewise retains both declaring arguments,
            // while its enumerable element is the first slot.
            if targetArguments.Length == 1 && sourceArguments.Length == 2 && ColumnarTypeEquivalenceFacts.TypesEquivalent(sourceArguments[0], targetArguments[0]) && sourceDefinition == ColumnarTypeOfPlanner.RequiredDictionaryKeyCollectionDefinition() && targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition() {
                return true
            }
            // IReadOnlyDictionary<TKey, TValue> inherits IEnumerable<KeyValuePair<TKey, TValue>>.
            // Reflection cannot inspect that inherited interface when TValue is an unbaked source
            // TypeBuilder, so preserve the complete nested key/value identity explicitly.
            if sourceArguments.Length == 2 && targetArguments.Length == 1 && IsReadOnlyDictionaryEnumerableShell(sourceDefinition, targetDefinition, targetArguments[0]) {
                pairArguments := targetArguments[0].GetGenericArguments()
                if pairArguments.Length == 2 && ColumnarTypeEquivalenceFacts.TypesEquivalent(sourceArguments[0], pairArguments[0]) && ColumnarTypeEquivalenceFacts.TypesEquivalent(sourceArguments[1], pairArguments[1]) {
                    return true
                }
            }
            if targetArguments.Length == 2 && sourceArguments.Length == 2 && ColumnarTypeEquivalenceFacts.TypesEquivalent(sourceArguments[0], targetArguments[0]) && ColumnarTypeEquivalenceFacts.TypesEquivalent(sourceArguments[1], targetArguments[1]) && ColumnarGenericCallBindingPlanner.IsReadOnlyDictionaryCollectionDefinition(targetDefinition) && ColumnarGenericCallBindingPlanner.IsDictionaryLikeCollectionDefinition(sourceDefinition) {
                return true
            }
        }

        return false
    }

    // Source interface identity lives in the declaration registry while its TypeBuilders are
    // still unbaked. Reflection.Emit assignability is not a reliable semantic oracle there:
    // use only the exact source definitions populated by the explicit/duck-interface pass.
    // External CLR interface edges are likewise admitted only from ExternalInterfaces facts;
    // a same-spelled source declaration or an unrelated runtime interface is never enough.
    // This deliberately preserves the existing non-constructed TypeBuilder product boundary;
    // closed source/interface TypeBuilderInstantiation flows need their own substituted
    // implemented-interface facts before they can be admitted. The returned reference fact is
    // also the authoritative boxing decision for value implementers, so overload selection and
    // argument-plan emission cannot disagree.
    static func TryClassifyExactSourceInterfaceUpcast(sourceType: Type, targetType: Type, sourceDefinitions: IEnumerable<ColumnarStructDef>, out sourceIsReference: bool): bool {
        if sourceType == null || targetType == null || sourceDefinitions == null {
            throw new InvalidOperationException("Source interface conversion facts cannot be null.")
        }

        sourceIsReference = false
        sourceBuilder := sourceType as TypeBuilder
        targetBuilder := targetType as TypeBuilder
        if sourceBuilder == null {
            return false
        }

        sourceDefinition: ColumnarStructDef? = null
        targetDefinition: ColumnarStructDef? = null
        for candidate in sourceDefinitions {
            if candidate == null || candidate.Builder == null {
                throw new InvalidOperationException("Source interface conversion definitions cannot be null.")
            }

            if Object.ReferenceEquals(candidate.Builder, sourceBuilder) {
                if sourceDefinition != null && !Object.ReferenceEquals(sourceDefinition, candidate) {
                    throw new InvalidOperationException("One source interface conversion type cannot map to two definitions.")
                }
                sourceDefinition = candidate
            }

            if targetBuilder != null && Object.ReferenceEquals(candidate.Builder, targetBuilder) {
                if targetDefinition != null && !Object.ReferenceEquals(targetDefinition, candidate) {
                    throw new InvalidOperationException("One target interface conversion type cannot map to two definitions.")
                }
                targetDefinition = candidate
            }
        }

        if sourceDefinition == null {
            return false
        }
        if sourceDefinition.Builder.get_IsValueType() == sourceDefinition.IsReference {
            throw new InvalidOperationException("Source interface conversion shape facts do not match their builders.")
        }

        matched := false
        if targetBuilder != null {
            if targetDefinition == null || !targetDefinition.IsInterface {
                return false
            }
            if targetDefinition.Builder.get_IsInterface() != targetDefinition.IsInterface {
                throw new InvalidOperationException("Source interface conversion shape facts do not match their builders.")
            }
            matched = SourceDefinitionImplementsInterface(sourceDefinition, targetDefinition, new HashSet<object>())
        } else {
            if targetType.get_IsByRef() || targetType.get_IsPointer() || targetType.get_IsGenericParameter() || !targetType.get_IsInterface() || IsDynamicDeclarationType(targetType) {
                return false
            }
            matched = SourceDefinitionImplementsExternalInterface(sourceDefinition, targetType, new HashSet<object>())
        }

        if matched {
            sourceIsReference = sourceDefinition.IsReference
            return true
        }

        return false
    }

    static func SourceDefinitionImplementsInterface(source: ColumnarStructDef, target: ColumnarStructDef, active: HashSet<object>): bool {
        if source == null || target == null || active == null || source.Builder == null || target.Builder == null || source.ImplementedInterfaces == null {
            throw new InvalidOperationException("Source implemented-interface facts cannot be null.")
        }

        if source.IsInterface {
            return SourceInterfaceEqualsOrExtends(source, target, new HashSet<object>())
        }

        if !active.Add(source) {
            throw new InvalidOperationException("Source class hierarchy contains a cycle.")
        }

        for implemented in source.ImplementedInterfaces {
            if SourceInterfaceEqualsOrExtends(implemented, target, new HashSet<object>()) {
                active.Remove(source)
                return true
            }
        }

        baseDefinition := source.BaseDef
        if baseDefinition != null {
            if !source.IsReference || !baseDefinition.IsReference || baseDefinition.IsInterface {
                throw new InvalidOperationException("Source class hierarchy facts do not identify reference classes.")
            }
            if SourceDefinitionImplementsInterface(baseDefinition, target, active) {
                active.Remove(source)
                return true
            }
        }

        active.Remove(source)
        return false
    }

    static func SourceInterfaceEqualsOrExtends(candidate: ColumnarStructDef, target: ColumnarStructDef, active: HashSet<object>): bool {
        if candidate == null || target == null || active == null || candidate.Builder == null || target.Builder == null || candidate.InterfaceBases == null {
            throw new InvalidOperationException("Source interface hierarchy facts cannot be null.")
        }
        if !candidate.IsInterface || !target.IsInterface {
            throw new InvalidOperationException("Source interface hierarchy facts must identify interfaces.")
        }
        if Object.ReferenceEquals(candidate, target) {
            return true
        }
        if !active.Add(candidate) {
            throw new InvalidOperationException("Source interface conversion hierarchy contains a cycle.")
        }

        for baseInterface in candidate.InterfaceBases {
            if SourceInterfaceEqualsOrExtends(baseInterface, target, active) {
                active.Remove(candidate)
                return true
            }
        }

        active.Remove(candidate)
        return false
    }

    static func SourceDefinitionImplementsExternalInterface(source: ColumnarStructDef, target: Type, active: HashSet<object>): bool {
        if source == null || target == null || active == null || source.Builder == null || source.InterfaceBases == null || source.ImplementedInterfaces == null || source.ExternalInterfaces == null {
            throw new InvalidOperationException("Source external-interface facts cannot be null.")
        }
        if !target.get_IsInterface() {
            throw new InvalidOperationException("A source external-interface conversion target must be an interface.")
        }
        if !active.Add(source) {
            throw new InvalidOperationException("Source external-interface hierarchy contains a cycle.")
        }

        for externalInterface in source.ExternalInterfaces {
            if externalInterface == null || !externalInterface.get_IsInterface() {
                throw new InvalidOperationException("Source external-interface facts must identify exact interfaces.")
            }
            if RuntimeInterfaceEqualsOrExtends(externalInterface, target) {
                active.Remove(source)
                return true
            }
        }

        if source.IsInterface {
            for baseInterface in source.InterfaceBases {
                if baseInterface == null || !baseInterface.IsInterface {
                    throw new InvalidOperationException("Source interface-base facts must identify interfaces.")
                }
                if SourceDefinitionImplementsExternalInterface(baseInterface, target, active) {
                    active.Remove(source)
                    return true
                }
            }
        } else {
            for implementedInterface in source.ImplementedInterfaces {
                if implementedInterface == null || !implementedInterface.IsInterface {
                    throw new InvalidOperationException("Source implemented-interface facts must identify interfaces.")
                }
                if SourceDefinitionImplementsExternalInterface(implementedInterface, target, active) {
                    active.Remove(source)
                    return true
                }
            }

            baseDefinition := source.BaseDef
            if baseDefinition != null {
                if !source.IsReference || !baseDefinition.IsReference || baseDefinition.IsInterface {
                    throw new InvalidOperationException("Source class hierarchy facts do not identify reference classes.")
                }
                if SourceDefinitionImplementsExternalInterface(baseDefinition, target, active) {
                    active.Remove(source)
                    return true
                }
            }
        }

        active.Remove(source)
        return false
    }

    static func RuntimeInterfaceEqualsOrExtends(candidate: Type, target: Type): bool {
        if ExactTypeShapeMatches(candidate, target) {
            return true
        }

        runtimeAssignable := false
        try {
            runtimeAssignable = target.IsAssignableFrom(candidate)
        } catch ex: NotSupportedException {
            runtimeAssignable = false
        } catch ex: NotImplementedException {
            runtimeAssignable = false
        }
        if runtimeAssignable {
            return true
        }

        return IsExactKnownUpcast(candidate, target)
    }

    static func IsExactKnownUpcast(sourceType: Type, targetType: Type): bool {
        if IsExactDynamicBaseUpcast(sourceType, targetType) {
            return true
        }

        if targetType.get_IsGenericType() && !targetType.get_IsGenericTypeDefinition() && sourceType.get_IsSZArray() {
            sourceElement := sourceType.GetElementType()
            targetArguments := targetType.GetGenericArguments()
            if sourceElement == null || targetArguments.Length != 1 || !ExactTypeShapeMatches(sourceElement, targetArguments[0]) {
                return false
            }

            targetDefinition := targetType.GetGenericTypeDefinition()
            return targetDefinition == typeof(IReadOnlyList<int>).GetGenericTypeDefinition() || targetDefinition == typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition() || targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition()
        }

        if !sourceType.get_IsGenericType() || sourceType.get_IsGenericTypeDefinition() || !targetType.get_IsGenericType() || targetType.get_IsGenericTypeDefinition() {
            return false
        }

        sourceArguments := sourceType.GetGenericArguments()
        targetArguments := targetType.GetGenericArguments()
        // Dictionary<K,V>.ValueCollection is a live IEnumerable<V>. The nested view keeps both
        // declaring-type arguments, so compare its VALUE slot to the target's sole element slot.
        if sourceArguments.Length == 2 && targetArguments.Length == 1 && ExactTypeShapeMatches(sourceArguments[1], targetArguments[0]) {
            sourceDefinition := sourceType.GetGenericTypeDefinition()
            targetDefinition := targetType.GetGenericTypeDefinition()
            if sourceDefinition == ColumnarTypeOfPlanner.RequiredDictionaryValueCollectionDefinition() && targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition() {
                return true
            }
        }
        // Dictionary<K,V>.KeyCollection is the corresponding live IEnumerable<K>; its second
        // generic slot is retained only because the nested CLR type closes over its owner.
        if sourceArguments.Length == 2 && targetArguments.Length == 1 && ExactTypeShapeMatches(sourceArguments[0], targetArguments[0]) {
            sourceDefinition := sourceType.GetGenericTypeDefinition()
            targetDefinition := targetType.GetGenericTypeDefinition()
            if sourceDefinition == ColumnarTypeOfPlanner.RequiredDictionaryKeyCollectionDefinition() && targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition() {
                return true
            }
        }
        // The inherited IReadOnlyDictionary<TKey, TValue> enumerator interface closes over a
        // KeyValuePair containing both source arguments. Keep the strict validator's structural
        // identity rule: neither key nor value may be replaced by an assignable near miss.
        dictionarySourceDefinition := sourceType.GetGenericTypeDefinition()
        enumerableTargetDefinition := targetType.GetGenericTypeDefinition()
        if sourceArguments.Length == 2 && targetArguments.Length == 1 && IsReadOnlyDictionaryEnumerableShell(dictionarySourceDefinition, enumerableTargetDefinition, targetArguments[0]) {
            pairArguments := targetArguments[0].GetGenericArguments()
            if pairArguments.Length == 2 && ExactTypeShapeMatches(sourceArguments[0], pairArguments[0]) && ExactTypeShapeMatches(sourceArguments[1], pairArguments[1]) {
                return true
            }
        }
        // The one two-argument upcast: Dictionary<K,V>/SortedDictionary<K,V> -> IReadOnlyDictionary<K,V>,
        // the two-argument mirror of List<T> -> IReadOnlyList<T> below. Both arguments must match exactly.
        if targetArguments.Length == 2 && sourceArguments.Length == 2 && (targetType.GetGenericTypeDefinition().FullName ?? "") == "System.Collections.Generic.IReadOnlyDictionary`2" && ExactTypeShapeMatches(sourceArguments[0], targetArguments[0]) && ExactTypeShapeMatches(sourceArguments[1], targetArguments[1]) {
            sourceDictionaryDefinition := sourceType.GetGenericTypeDefinition()
            return sourceDictionaryDefinition == typeof(Dictionary<int, int>).GetGenericTypeDefinition() || sourceDictionaryDefinition == typeof(SortedDictionary<int, int>).GetGenericTypeDefinition()
        }
        if sourceArguments.Length < 1 || targetArguments.Length != 1 || !ExactTypeShapeMatches(sourceArguments[0], targetArguments[0]) {
            return false
        }

        sourceDefinition := sourceType.GetGenericTypeDefinition()
        targetDefinition := targetType.GetGenericTypeDefinition()
        if targetDefinition == typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition() && (sourceDefinition == typeof(IReadOnlyList<int>).GetGenericTypeDefinition() || sourceDefinition == typeof(IReadOnlySet<int>).GetGenericTypeDefinition()) {
            return true
        }

        if targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition() && (sourceDefinition == typeof(IReadOnlyList<int>).GetGenericTypeDefinition() || sourceDefinition == typeof(IReadOnlySet<int>).GetGenericTypeDefinition() || sourceDefinition == typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition()) {
            return true
        }

        if sourceDefinition == typeof(List<int>).GetGenericTypeDefinition() {
            return targetDefinition == typeof(IReadOnlyList<int>).GetGenericTypeDefinition() || targetDefinition == typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition() || targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition()
        }

        if sourceDefinition == typeof(HashSet<int>).GetGenericTypeDefinition() {
            return targetDefinition == typeof(IReadOnlySet<int>).GetGenericTypeDefinition() || targetDefinition == typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition() || targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition()
        }

        if sourceDefinition == typeof(SortedSet<int>).GetGenericTypeDefinition() {
            return targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition()
        }

        return sourceDefinition == typeof(Stack<int>).GetGenericTypeDefinition() && (targetDefinition == typeof(IReadOnlyCollection<int>).GetGenericTypeDefinition() || targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition())
    }

    static func IsReadOnlyDictionaryEnumerableShell(sourceDefinition: Type, targetDefinition: Type, targetElement: Type): bool {
        return sourceDefinition == ColumnarTypeOfPlanner.RequiredReadOnlyDictionaryDefinition() && targetDefinition == typeof(IEnumerable<int>).GetGenericTypeDefinition() && targetElement.get_IsGenericType() && !targetElement.get_IsGenericTypeDefinition() && targetElement.GetGenericTypeDefinition() == typeof(KeyValuePair<int, int>).GetGenericTypeDefinition()
    }

    // Runtime Type.IsAssignableFrom cannot inspect a TypeBuilderInstantiation whose generic
    // definition has not been baked. Reflection.Emit does preserve its substituted BaseType,
    // so follow only that exact dynamic declaration chain. Ordinary CLR types remain with the
    // runtime assignability fallback, and every generic shell/argument must match exactly.
    static func IsExactDynamicBaseUpcast(sourceType: Type, targetType: Type): bool {
        if !IsDynamicDeclarationType(sourceType) || sourceType.get_IsValueType() || targetType.get_IsValueType() || sourceType.get_IsGenericParameter() || targetType.get_IsGenericParameter() {
            return false
        }

        current: Type? = sourceType
        depth := 0
        while current != null && depth < 200 {
            candidate := current
            baseType: Type? = null
            try {
                baseType = candidate.get_BaseType()
            } catch ex: NotSupportedException {
                return false
            } catch ex: NotImplementedException {
                return false
            }
            if baseType == null {
                return false
            }
            if ExactTypeShapeMatches(baseType, targetType) {
                return true
            }
            if ExactTypeShapeMatches(baseType, candidate) {
                return false
            }
            current = baseType
            depth += 1
        }
        return false
    }

    static func IsDynamicDeclarationType(valueType: Type): bool {
        if valueType is TypeBuilder {
            return true
        }
        return valueType.get_IsGenericType() && !valueType.get_IsGenericTypeDefinition() && valueType.GetGenericTypeDefinition() is TypeBuilder
    }

    static func ExactTypeShapeMatches(left: Type, right: Type): bool {
        if left == right {
            return true
        }

        if left.get_IsSZArray() || right.get_IsSZArray() {
            if !left.get_IsSZArray() || !right.get_IsSZArray() {
                return false
            }

            leftElement := left.GetElementType()
            rightElement := right.GetElementType()
            return leftElement != null && rightElement != null && ExactTypeShapeMatches(leftElement, rightElement)
        }

        if !left.get_IsGenericType() || !right.get_IsGenericType() || left.get_IsGenericTypeDefinition() || right.get_IsGenericTypeDefinition() || left.GetGenericTypeDefinition() != right.GetGenericTypeDefinition() {
            return false
        }

        leftArguments := left.GetGenericArguments()
        rightArguments := right.GetGenericArguments()
        if leftArguments.Length != rightArguments.Length {
            return false
        }

        index := 0
        while index < leftArguments.Length {
            if !ExactTypeShapeMatches(leftArguments[index], rightArguments[index]) {
                return false
            }

            index += 1
        }

        return true
    }
}
