namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler


// One exact runtime extension-method candidate: a public static method that carries
// [System.Runtime.CompilerServices.ExtensionAttribute] and whose first parameter is the extension
// receiver. ParameterTypes is the FULL declared list, so ParameterTypes[0] is the receiver slot and
// an ordinary `StaticClass.Method(receiver, args...)` call row reproduces the extension invocation.
// Generic methods are indexed as OPEN definitions; selection closes them by receiver/argument
// inference so the selected candidate always carries an exact closed handle and signature.
class ColumnarExtensionMethodCandidate {
    Method: MethodInfo
    DeclaringType: Type
    ParameterTypes: Type[]
    ReturnType: Type

    ReceiverParameterType: Type => ParameterTypes[0]

    constructor(method: MethodInfo, declaringType: Type, parameterTypes: Type[], returnType: Type) {
        if method == null || declaringType == null || parameterTypes == null || returnType == null || parameterTypes.Length < 1 {
            throw new InvalidOperationException("Extension-method candidate facts cannot be null.")
        }

        Method = method
        DeclaringType = declaringType
        ParameterTypes = parameterTypes
        ReturnType = returnType
    }
}

// A name-keyed index of the extension methods exported by the referenced-assembly scan. Built once
// per compilation and cached on the external-type catalog: later member-call resolution consults it
// without re-opening the scan or extending a per-feature whitelist.
class ColumnarExtensionMethodIndex {
    byName: Dictionary<string, List<ColumnarExtensionMethodCandidate>>

    constructor() {
        byName = new Dictionary<string, List<ColumnarExtensionMethodCandidate>>(StringComparer.Ordinal)
    }

    func Add(name: string, candidate: ColumnarExtensionMethodCandidate) {
        bucket := new List<ColumnarExtensionMethodCandidate>()
        if !byName.TryGetValue(name, out bucket) || bucket == null {
            bucket = new List<ColumnarExtensionMethodCandidate>()
            byName[name] = bucket
        }

        bucket.Add(candidate)
    }

    func TryGet(name: string, out candidates: List<ColumnarExtensionMethodCandidate>): bool {
        candidates = new List<ColumnarExtensionMethodCandidate>()
        return byName.TryGetValue(name, out candidates) && candidates != null
    }
}

// A selected extension binding for emission. ParameterTypes is the full declared list including the
// receiver at [0]; ExplicitArgumentCount is the number of supplied call arguments (never the
// receiver). Parameters beyond `1 + ExplicitArgumentCount` are filled from their metadata defaults.
class ColumnarExtensionMethodSelection {
    IsSelected: bool
    Method: MethodInfo?
    DeclaringType: Type
    ParameterTypes: Type[]
    ReturnType: Type
    ExplicitArgumentCount: int

    // NON-NULL WHEN THE CALL SITE PACKS ITS TAIL. The declared list above is unchanged — it is what
    // the method's signature says and what the call instruction must agree with — so the element
    // type is the one extra fact emission needs: every supplied argument from the fixed count on is
    // stored into a fresh array of this type rather than pushed as its own parameter. Null is the
    // ordinary call, including one that hands an already-built array to a `params` slot.
    ParamsElementType: Type?

    constructor(isSelected: bool, method: MethodInfo?, declaringType: Type, parameterTypes: Type[], returnType: Type, explicitArgumentCount: int, paramsElementType: Type? = null) {
        if declaringType == null || parameterTypes == null || returnType == null {
            throw new InvalidOperationException("Extension-method selection facts cannot be null.")
        }

        if isSelected && (method == null || parameterTypes.Length < 1 || explicitArgumentCount < 0) {
            throw new InvalidOperationException("A selected extension method requires an exact static handle and a valid explicit-argument count.")
        }

        // An expanded call supplies one argument per PACKED value, so it may legitimately carry more
        // arguments than the signature has slots; a normal one may never.
        if isSelected && paramsElementType == null && explicitArgumentCount > parameterTypes.Length - 1 {
            throw new InvalidOperationException("A selected extension method requires an exact static handle and a valid explicit-argument count.")
        }

        // It may also supply FEWER than the fixed slots, when each one it omits fills from its metadata
        // default — `route.Produces<Todo>()` over `(int statusCode = 200, string? contentType = null,
        // params string[] additionalContentTypes)` — so an expanded count is bounded only below.
        if isSelected && paramsElementType != null && parameterTypes.Length < 2 {
            throw new InvalidOperationException("An expanded extension call requires a signature with a params slot after its receiver.")
        }

        IsSelected = isSelected
        Method = method
        DeclaringType = declaringType
        ParameterTypes = parameterTypes
        ReturnType = returnType
        ExplicitArgumentCount = explicitArgumentCount
        ParamsElementType = paramsElementType
    }

    static func None(): ColumnarExtensionMethodSelection {
        return new ColumnarExtensionMethodSelection(false, null, typeof(object), new Type[](0), typeof(object), 0, null)
    }
}

// Extension-method binding for member-style calls whose receiver type declares no matching instance
// method. Candidate discovery is metadata-exact ([ExtensionAttribute] on a public static method of a
// static class) over the referenced-assembly runtime scan; selection reuses the shared direct-call
// argument scoring so an extension and an ordinary call never disagree about conversion preference.
//
// This owner is intentionally narrow: reference-type receivers only, exact fixed arity, a trailing run
// of optional parameters whose metadata default is fillable, or a `params` tail. Generic candidates
// close by input inference from the receiver's matching base/interface instantiation and the SUPPLIED
// argument types (`List<int>` -> `IEnumerable<int>` -> `Enumerable.Take<int>`; `DbSet<Person>` ->
// `FromSqlRaw<Person>`); optional arguments do not bind a type parameter. A closure the declared
// constraints refuse and anything outside the admitted surface leaves the call to its later owner.
class ColumnarExtensionMethodResolver {

    // ATTRIBUTES ARE MATCHED BY FULL NAME, NEVER BY TYPE IDENTITY, and the two `Type.GetType` lookups
    // that used to supply the identities are gone with the identities. `IsDefined(attributeType, ...)`
    // cannot answer over a `MetadataLoadContext` at all -- it throws
    // `The requested operation cannot be used on objects loaded by a MetadataLoadContext. Use
    // CustomAttributeData instead.` -- and every one of these call sites swallowed that throw in a
    // `catch` returning false, so a metadata-sourced catalog would have produced an EMPTY extension
    // index in silence. The analyzer already learned this rule (`AnalyzerOverloadScoring`'s
    // `HasExtensionAttribute`/`IsParamsParameter`, whose comment states it); the columnar side now
    // shares those owners instead of keeping a second, identity-based copy.
    static func BuildIndex(scan: ExternalAssemblyScanResult): ColumnarExtensionMethodIndex {
        index := new ColumnarExtensionMethodIndex()
        if scan == null || scan.Entries == null {
            return index
        }

        for entry in scan.Entries {
            if entry != null && entry.RuntimeAssembly != null {
                AddAssembly(index, entry.RuntimeAssembly)
            }
        }

        return index
    }

    static func AddAssembly(index: ColumnarExtensionMethodIndex, assembly: Assembly) {
        types := HostTypesOrEmpty(assembly)
        for candidateType in types {
            if IsStaticExtensionHost(candidateType) {
                AddType(index, candidateType)
            }
        }
    }

    // A REFERENCED ASSEMBLY IS NOT A PROMISE THAT ITS WHOLE CLOSURE IS PRESENT, and the index build
    // is the one walk that touches EVERY extension method of EVERY referenced assembly rather than
    // only the ones a call names. `System.Reactive` declares extensions over WPF types, so its
    // `WindowsBase` reference is real; on macOS that assembly does not exist, and materialising such
    // a signature throws `FileNotFoundException` out of `GetParameters`. That is a fact about the
    // reference set and not about the program being compiled, so the method contributes nothing and
    // the scan continues — an exception here ended the whole compilation with a sentence about an
    // assembly the user never named.
    //
    // Every per-method read is therefore guarded, not just the enumeration: the parameter ROWS exist
    // in metadata whatever their types resolve to, so `GetParameters`, each parameter's type, the
    // return type and the attribute reads each reach the missing assembly on their own.
    static func AddType(index: ColumnarExtensionMethodIndex, hostType: Type) {
        methods := MethodsOrEmpty(hostType)
        for method in methods {
            if IsExtensionMethodCandidate(method) {
                parameters := ParametersOrNull(method)
                if parameters != null && parameters.Length >= 1 && !HasExcludedParameterShape(parameters) {
                    parameterTypes := ParameterTypesOrNull(parameters)
                    returnType := ReturnTypeOrNull(method)
                    if parameterTypes != null && returnType != null && IsSupportedReceiverParameter(parameterTypes[0]) {
                        index.Add(method.Name, new ColumnarExtensionMethodCandidate(method, hostType, parameterTypes, returnType))
                    }
                }
            }
        }
    }

    static func ParametersOrNull(method: MethodInfo): ParameterInfo[]? {
        try {
            return method.GetParameters()
        } catch {
            return null
        }
    }

    static func ReturnTypeOrNull(method: MethodInfo): Type? {
        try {
            return method.ReturnType
        } catch {
            return null
        }
    }

    static func ParameterTypeOrNull(parameter: ParameterInfo): Type? {
        try {
            return parameter.ParameterType
        } catch {
            return null
        }
    }

    static func IsStaticExtensionHost(candidateType: Type): bool {
        if candidateType == null {
            return false
        }

        try {
            if !candidateType.IsClass || !candidateType.IsSealed || !candidateType.IsAbstract || candidateType.IsGenericType {
                return false
            }
        } catch {
            return false
        }

        return HasExtensionAttribute(candidateType)
    }

    // The scan is spelled HERE rather than shared with `AnalyzerOverloadScoring`'s identical one: a
    // static call into that class from a `NSharpLang.Compiler.Columnar` owner declines at
    // `emit.return.expression` whatever the argument type, so the columnar surface cannot reach it.
    // The count goes through `object` for the recorded reason -- a generic `IList<T>` does not cast to
    // the non-generic `IList` on this surface, but an `object` does.
    static func HasAttributeNamed(attributes: IList<CustomAttributeData>, fullName: string): bool {
        count := AttributeSequenceCount(attributes)
        index := 0
        while index < count {
            attribute := attributes.get_Item(index)
            attributeType := attribute.AttributeType
            if attributeType.FullName == fullName {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func AttributeSequenceCount(sequence: object): int {
        list := (IList)sequence
        return list.Count
    }

    // An attribute list whose ARGUMENT types cannot be resolved throws while it is being read, so
    // each of the three reads below answers "no such attribute" rather than ending the scan.
    static func HasExtensionAttribute(candidateType: Type): bool {
        try {
            return HasAttributeNamed(candidateType.GetCustomAttributesData(), "System.Runtime.CompilerServices.ExtensionAttribute")
        } catch {
            return false
        }
    }

    static func MethodHasExtensionAttribute(method: MethodInfo): bool {
        try {
            return HasAttributeNamed(method.GetCustomAttributesData(), "System.Runtime.CompilerServices.ExtensionAttribute")
        } catch {
            return false
        }
    }

    static func IsParamsParameter(parameter: ParameterInfo): bool {
        try {
            return HasAttributeNamed(parameter.GetCustomAttributesData(), "System.ParamArrayAttribute")
        } catch {
            return false
        }
    }

    static func IsExtensionMethodCandidate(method: MethodInfo): bool {
        if method == null {
            return false
        }

        try {
            // `public` OR, in an assembly that made this emission a friend, `internal` and
            // `protected internal` — the same relation every other external member filter applies.
            if !method.IsStatic || !InternalsVisibleToEmissionScope.ReachesLevel(MemberAccessibility.LevelOfMethod(method), method.DeclaringType) {
                return false
            }
        } catch {
            return false
        }

        // Generic extension methods are indexed only as OPEN definitions; resolution closes them by
        // receiver/argument inference. A partially constructed generic method is never a candidate.
        if method.IsGenericMethod && !method.IsGenericMethodDefinition {
            return false
        }

        return MethodHasExtensionAttribute(method)
    }

    // A `params` TAIL IS NOW A SHAPE, NOT AN EXCLUSION. It used to keep the whole method out of the
    // index, which made `logger.LogDebug("…")` — and every other `LoggerExtensions` member, whose
    // tail is `params object?[] args` — invisible to extension resolution entirely. The tail is
    // admitted in its declared LAST position only, which is the only position C# allows it in, and
    // `ColumnarParamsExpansion` decides at the call site whether the arguments pass through in
    // normal form or pack into a fresh array.
    static func HasExcludedParameterShape(parameters: ParameterInfo[]): bool {
        index := 0
        while index < parameters.Length {
            parameter := parameters[index]
            if parameter == null {
                return true
            }

            parameterType := ParameterTypeOrNull(parameter)
            if parameterType == null || parameterType.IsByRef || parameterType.IsPointer {
                return true
            }

            if IsParamsParameter(parameter) && index != parameters.Length - 1 {
                return true
            }

            index = index + 1
        }

        return false
    }

    // WHAT CAN BE A RECEIVER SLOT IN THE INDEX. A by-ref or pointer slot has no call shape here and a
    // BARE type parameter (`static void Use<T>(this T value)`) would make every extension of that name
    // a candidate for every receiver, which is a resolution change this owner does not make. A VALUE
    // type is an ordinary receiver slot: `JsonSerializer.Deserialize<TValue>(this JsonElement, ...)`
    // is declared on a struct, and the call site loads the struct's VALUE rather than its address.
    static func IsSupportedReceiverParameter(receiverParameterType: Type): bool {
        return receiverParameterType != null && !receiverParameterType.IsByRef && !receiverParameterType.IsPointer && !receiverParameterType.IsGenericParameter
    }

    static func ParameterTypesOrNull(parameters: ParameterInfo[]): Type[]? {
        result := new Type[](parameters.Length)
        index := 0
        while index < parameters.Length {
            parameter := parameters[index]
            if parameter == null {
                return null
            }

            parameterType := ParameterTypeOrNull(parameter)
            if parameterType == null {
                return null
            }

            result[index] = parameterType
            index = index + 1
        }

        return result
    }

    // THE HOSTS THIS EMISSION MAY REACH. The public surface for an ordinary reference; the DECLARED
    // surface for one that named the assembly being emitted in an `InternalsVisibleTo`, because an
    // extension declared on an `internal static class` of a friend is a real candidate and only
    // `GetTypes()` returns it. `IsStaticExtensionHost` and `IsExtensionMethodCandidate` still decide
    // what of the wider list is a host and what of its methods is reachable.
    static func HostTypesOrEmpty(assembly: Assembly): Type[] {
        if InternalsVisibleToEmissionScope.GrantsAccess(assembly) {
            try {
                declared := assembly.GetTypes()
                if declared != null {
                    return declared
                }
            } catch {
                // A granting assembly whose declared surface cannot be enumerated falls back to the
                // exported one rather than contributing nothing.
                return ExportedTypesOrEmpty(assembly)
            }
        }

        return ExportedTypesOrEmpty(assembly)
    }

    static func ExportedTypesOrEmpty(assembly: Assembly): Type[] {
        try {
            result := assembly.GetExportedTypes()
            if result == null {
                return new Type[](0)
            }

            return result
        } catch {
            // A referenced assembly whose exported surface cannot be enumerated (missing transitive
            // dependency, unreadable image) contributes no extension methods.
            return new Type[](0)
        }
    }

    static func MethodsOrEmpty(hostType: Type): MethodInfo[] {
        try {
            result := hostType.GetMethods()
            if result == null {
                return new MethodInfo[](0)
            }

            return result
        } catch {
            return new MethodInfo[](0)
        }
    }

    // Select the single best extension method for `receiver.memberName(args...)`. Ranking mirrors the
    // ordinary call resolver: exact conversion beats a weaker one, among equal-conversion matches the
    // fewest total parameters (least optional filling) wins, and at a full tie a non-generic candidate
    // beats an inference-closed generic one (the CLR's less-generic-is-better rule). Any remaining tie
    // declines.
    static func Resolve(index: ColumnarExtensionMethodIndex, receiverType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): ColumnarExtensionMethodSelection {
        if index == null || receiverType == null || memberName == null || argumentTypes == null || argumentFacts == null {
            return ColumnarExtensionMethodSelection.None()
        }

        if receiverType.IsValueType || receiverType.IsByRef || receiverType.IsPointer || receiverType.IsGenericParameter {
            return ColumnarExtensionMethodSelection.None()
        }

        candidates := new List<ColumnarExtensionMethodCandidate>()
        if !index.TryGet(memberName, out candidates) {
            return ColumnarExtensionMethodSelection.None()
        }

        explicitCount := argumentTypes.Length
        bestScore := -1
        bestParameterCount := 0
        bestIsGeneric := false
        bestCount := 0
        selected: ColumnarExtensionMethodCandidate? = null
        for indexed in candidates {
            candidate: ColumnarExtensionMethodCandidate? = null
            if indexed != null {
                candidate = ResolveCandidateShape(indexed, receiverType, argumentTypes, argumentFacts, explicitCount)
            }

            if candidate != null && CandidateAppliesToReceiver(candidate, receiverType) {
                parameterTypes := candidate.ParameterTypes
                if parameterTypes.Length - 1 >= explicitCount && TrailingDefaultsFillable(candidate.Method, parameterTypes, 1 + explicitCount) {
                    leading := ExplicitParameterTypes(parameterTypes, explicitCount)
                    score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(leading, argumentTypes, argumentFacts)
                    if score >= 0 {
                        parameterCount := parameterTypes.Length
                        candidateIsGeneric := candidate.Method.IsGenericMethod
                        if score > bestScore || (score == bestScore && parameterCount < bestParameterCount) || (score == bestScore && parameterCount == bestParameterCount && bestIsGeneric && !candidateIsGeneric) {
                            bestScore = score
                            bestParameterCount = parameterCount
                            bestIsGeneric = candidateIsGeneric
                            bestCount = 1
                            selected = candidate
                        } else if score == bestScore && parameterCount == bestParameterCount && bestIsGeneric == candidateIsGeneric {
                            bestCount = bestCount + 1
                        }
                    }
                }
            }
        }

        if bestCount == 0 {
            // NOTHING BOUND IN NORMAL FORM, so the `params` tails get their turn — and only now, which
            // is what keeps an ordinary overload preferred over a packed one. An AMBIGUITY in normal
            // form is not "nothing bound": it is two equally good answers, and it declines here as it
            // always has rather than being resolved by a rule the site never asked for.
            return ResolveExpanded(candidates, receiverType, argumentTypes, argumentFacts)
        }

        if bestCount != 1 || selected == null {
            return ColumnarExtensionMethodSelection.None()
        }

        return new ColumnarExtensionMethodSelection(true, selected.Method, selected.DeclaringType, selected.ParameterTypes, selected.ReturnType, explicitCount, null)
    }

    // THE EXPANDED TIER: every candidate whose last parameter is a `params` array, scored against the
    // per-argument types the packing produces. The scorer is the shared one, given the expanded list,
    // so `LogDebug("started")` picks the same conversion story an ordinary two-parameter call would.
    //
    // A GENERIC DEFINITION CLOSES BY INFERENCE FIRST. `set.FromSqlRaw(sql, n)` against `FromSqlRaw<TEntity>(
    // this DbSet<TEntity> source, string sql, params object[] parameters)` binds `TEntity` from the
    // receiver, and a type parameter the packed tail mentions (`Create<T>(this X x, params T[] items)`)
    // binds from every packed argument, each unified against the tail's element type. A site that
    // WRITES its type arguments has nothing to infer, and `ResolveExplicitExpanded` packs its tail.
    static func ResolveExpanded(candidates: List<ColumnarExtensionMethodCandidate>, receiverType: Type, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): ColumnarExtensionMethodSelection {
        explicitCount := argumentTypes.Length
        bestScore := -1
        bestParameterCount := 0
        bestCount := 0
        bestElementType: Type? = null
        selected: ColumnarExtensionMethodCandidate? = null
        tiedCandidates := new List<ColumnarExtensionMethodCandidate>()
        tiedParameters := new List<Type[]>()
        for indexed in candidates {
            // A generic definition is closed first, by inferring its type arguments from the receiver,
            // the fixed arguments and every PACKED argument; the closed candidate is then scored as
            // any other is.
            candidate: ColumnarExtensionMethodCandidate? = indexed
            if indexed != null && indexed.Method.IsGenericMethodDefinition {
                candidate = ResolveExpandedShape(indexed, receiverType, argumentTypes, argumentFacts)
            }

            if candidate != null && CandidateAppliesToReceiver(candidate, receiverType) {
                parameters := ParametersOrNull(candidate.Method)
                if parameters != null {
                    expanded := ColumnarParamsExpansion.ExpandedParameterTypesOrNull(parameters, candidate.ParameterTypes, 1, explicitCount)
                    elementType := ColumnarParamsExpansion.ElementTypeOrNull(parameters, candidate.ParameterTypes)
                    if expanded != null && elementType != null {
                        score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(expanded, argumentTypes, argumentFacts)
                        if score >= 0 {
                            parameterCount := candidate.ParameterTypes.Length
                            if score > bestScore || (score == bestScore && parameterCount < bestParameterCount) {
                                bestScore = score
                                bestParameterCount = parameterCount
                                bestCount = 1
                                bestElementType = elementType
                                selected = candidate
                                tiedCandidates.Clear()
                                tiedParameters.Clear()
                                tiedCandidates.Add(candidate)
                                tiedParameters.Add(ExpandedParametersWithReceiver(candidate.ParameterTypes, expanded))
                            } else if score == bestScore && parameterCount == bestParameterCount {
                                bestCount = bestCount + 1
                                tiedCandidates.Add(candidate)
                                tiedParameters.Add(ExpandedParametersWithReceiver(candidate.ParameterTypes, expanded))
                            }
                        }
                    }
                }
            }
        }

        if bestCount > 1 {
            selectedIndex := SelectExpandedExtensionCandidate(tiedCandidates, tiedParameters, receiverType, argumentTypes, argumentFacts)
            if selectedIndex < 0 {
                return ColumnarExtensionMethodSelection.None()
            }
            selected = tiedCandidates[selectedIndex]
            bestCount = 1
            selectedMethodParameters := ParametersOrNull(selected.Method)
            if selectedMethodParameters == null {
                return ColumnarExtensionMethodSelection.None()
            }
            bestElementType = ColumnarParamsExpansion.ElementTypeOrNull(selectedMethodParameters, selected.ParameterTypes)
        }

        if bestCount != 1 || selected == null || bestElementType == null {
            return ColumnarExtensionMethodSelection.None()
        }

        return new ColumnarExtensionMethodSelection(true, selected.Method, selected.DeclaringType, selected.ParameterTypes, selected.ReturnType, explicitCount, bestElementType)
    }

    static func ExpandedParametersWithReceiver(parameterTypes: Type[], expandedArguments: Type[]): Type[] {
        result := new Type[](expandedArguments.Length + 1)
        result[0] = parameterTypes[0]
        Array.Copy(expandedArguments, 0, result, 1, expandedArguments.Length)
        return result
    }

    // An extension's receiver is its first argument. Compare it alongside the explicit arguments so
    // a better conversion to IEnumerable<T> can beat a conversion to object.
    static func SelectExpandedExtensionCandidate(candidates: List<ColumnarExtensionMethodCandidate>, parameterLists: List<Type[]>, receiverType: Type, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): int {
        actual := new Type[](argumentTypes.Length + 1)
        actual[0] = receiverType
        Array.Copy(argumentTypes, 0, actual, 1, argumentTypes.Length)
        comparisonFacts := ColumnarDirectCallArgumentFacts.Empty(actual.Length)
        comparisonFacts.SourceTypeDefinitions = argumentFacts.SourceTypeDefinitions

        selected := ColumnarSourceDirectCallResolver.SelectMostSpecificParameters(parameterLists, actual, comparisonFacts)
        if selected >= 0 {
            return selected
        }

        // The less-generic tie-break is available only when every effective parameter type ties.
        nonGenericIndex := -1
        for index := 0; index < candidates.Count; index++ {
            if !candidates[index].Method.IsGenericMethod {
                if nonGenericIndex >= 0 {
                    return -1
                }
                nonGenericIndex = index
            }
        }
        if nonGenericIndex < 0 {
            return -1
        }
        for index := 0; index < parameterLists.Count; index++ {
            if !EquivalentParameterLists(parameterLists[nonGenericIndex], parameterLists[index]) {
                return -1
            }
        }
        return nonGenericIndex
    }

    static func EquivalentParameterLists(left: Type[], right: Type[]): bool {
        if left == null || right == null || left.Length != right.Length {
            return false
        }
        for index := 0; index < left.Length; index++ {
            if !RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(left[index], right[index]) {
                return false
            }
        }
        return true
    }

    // THE SAME SELECTION FOR A SITE THAT WROTE ITS TYPE ARGUMENTS. C#'s rule (ECMA-334 §12.6.4.1) is
    // that explicit type arguments SKIP inference entirely: a candidate whose own arity differs from
    // the written count is not a candidate at all — excluded, not an error — and what remains closes
    // over exactly what was written. `element.Deserialize<Request>(options)` therefore reaches
    // `JsonSerializer.Deserialize<TValue>(this JsonElement, JsonSerializerOptions?)` the same way
    // `items.First()` reaches `Enumerable.First<TSource>`, and neither names a member.
    //
    // The closed signature is SUBSTITUTED from the declaration, for the reason `TryClose` states: a
    // type argument the compilation is itself writing produces a handle that reports the definition's
    // own parameters.
    //
    // This collects the NORMAL-FORM candidates: every slot past the supplied arguments fills from its
    // metadata default. `CollectExplicitExpanded` collects the same closures in their packed form.
    static func CollectExplicit(index: ColumnarExtensionMethodIndex, receiverType: Type, memberName: string, typeArguments: Type[], argumentCount: int, selected: List<ColumnarExtensionMethodCandidate>): bool {
        candidates := new List<ColumnarExtensionMethodCandidate>()
        if selected == null || !TryGetExplicitCandidates(index, receiverType, memberName, typeArguments, argumentCount, out candidates) {
            return false
        }

        for indexed in candidates {
            if indexed != null && indexed.ParameterTypes.Length - 1 >= argumentCount {
                closed := CloseExplicitOrNull(indexed, receiverType, typeArguments)
                if closed != null && TrailingDefaultsFillable(indexed.Method, closed.ParameterTypes, 1 + argumentCount) {
                    selected.Add(closed)
                }
            }
        }

        return selected.Count > 0
    }

    // THE EXPANDED HALF OF THE SAME RULE. A written type-argument list closes a `params` tail as
    // completely as it closes every other slot, so there is no inference question here:
    // `app.UseMiddleware<Stamp>()` closes `UseMiddleware<TMiddleware>(this IApplicationBuilder,
    // params object?[] args)` from what the site wrote and packs its zero trailing arguments into an
    // empty `object?[]`, exactly as C# does.
    static func CollectExplicitExpanded(index: ColumnarExtensionMethodIndex, receiverType: Type, memberName: string, typeArguments: Type[], argumentCount: int, selected: List<ColumnarExtensionMethodCandidate>): bool {
        candidates := new List<ColumnarExtensionMethodCandidate>()
        if selected == null || !TryGetExplicitCandidates(index, receiverType, memberName, typeArguments, argumentCount, out candidates) {
            return false
        }

        for indexed in candidates {
            parameters: ParameterInfo[]? = null
            if indexed != null {
                parameters = ParametersOrNull(indexed.Method)
            }

            if parameters != null {
                closed := CloseExplicitOrNull(indexed, receiverType, typeArguments)
                if closed != null && ExplicitExpandedParameterTypesOrNull(parameters, closed.ParameterTypes, argumentCount) != null {
                    selected.Add(closed)
                }
            }
        }

        return selected.Count > 0
    }

    // The bucket an explicit site searches, after the checks both forms share: a bindable receiver,
    // written type arguments the closure can use, and a name the index knows.
    static func TryGetExplicitCandidates(index: ColumnarExtensionMethodIndex, receiverType: Type, memberName: string, typeArguments: Type[], argumentCount: int, out candidates: List<ColumnarExtensionMethodCandidate>): bool {
        candidates = new List<ColumnarExtensionMethodCandidate>()
        if index == null || receiverType == null || memberName == null || typeArguments == null || typeArguments.Length == 0 || argumentCount < 0 {
            return false
        }

        if receiverType.IsByRef || receiverType.IsPointer || receiverType.IsGenericParameter {
            return false
        }

        for typeArgument in typeArguments {
            if typeArgument == null || ColumnarRuntimeGenericMethodResolver.IsUnbindableInferredType(typeArgument) {
                return false
            }
        }

        return index.TryGet(memberName, out candidates)
    }

    // One generic definition of the written arity, closed over the written type arguments, or null
    // when the arity differs, a declared constraint fails, Reflection cannot close the method, or the
    // closed receiver slot does not accept the receiver.
    static func CloseExplicitOrNull(indexed: ColumnarExtensionMethodCandidate, receiverType: Type, typeArguments: Type[]): ColumnarExtensionMethodCandidate? {
        if !indexed.Method.IsGenericMethodDefinition || indexed.Method.GetGenericArguments().Length != typeArguments.Length {
            return null
        }

        closed := ColumnarRuntimeGenericMethodResolver.CloseSubstituted(indexed.Method, typeArguments)
        if closed == null || !ReferenceAssignableFrom(closed.ParameterTypes[0], receiverType) {
            return null
        }

        return new ColumnarExtensionMethodCandidate(closed.Method, indexed.DeclaringType, closed.ParameterTypes, closed.ReturnType)
    }

    // The unique candidate for a site whose arguments cannot all be typed before emission — a lambda
    // written at an explicitly-closed extension call. More than one surviving candidate is a decline,
    // because the argument types are exactly what would have chosen between them. The expanded form
    // is asked only when NO candidate exists in normal form, for the reason `Resolve` states.
    static func ResolveExplicitUnique(index: ColumnarExtensionMethodIndex, receiverType: Type, memberName: string, typeArguments: Type[], argumentCount: int): ColumnarExtensionMethodSelection {
        candidates := new List<ColumnarExtensionMethodCandidate>()
        if CollectExplicit(index, receiverType, memberName, typeArguments, argumentCount, candidates) {
            if candidates.Count != 1 {
                return ColumnarExtensionMethodSelection.None()
            }

            chosen := candidates[0]
            return new ColumnarExtensionMethodSelection(true, chosen.Method, chosen.DeclaringType, chosen.ParameterTypes, chosen.ReturnType, argumentCount, null)
        }

        expanded := new List<ColumnarExtensionMethodCandidate>()
        if !CollectExplicitExpanded(index, receiverType, memberName, typeArguments, argumentCount, expanded) || expanded.Count != 1 {
            return ColumnarExtensionMethodSelection.None()
        }

        return ExpandedExplicitSelection(expanded[0], argumentCount)
    }

    // The same candidate set, ranked by the argument-flow scorer every other call selection uses.
    static func ResolveExplicit(index: ColumnarExtensionMethodIndex, receiverType: Type, memberName: string, typeArguments: Type[], argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): ColumnarExtensionMethodSelection {
        if argumentTypes == null || argumentFacts == null {
            return ColumnarExtensionMethodSelection.None()
        }

        explicitCount := argumentTypes.Length
        candidates := new List<ColumnarExtensionMethodCandidate>()
        if CollectExplicit(index, receiverType, memberName, typeArguments, explicitCount, candidates) {
            bestScore := -1
            bestParameterCount := 0
            bestCount := 0
            bestIndex := -1
            candidateIndex := 0
            while candidateIndex < candidates.Count {
                closedParameterTypes := candidates[candidateIndex].ParameterTypes
                leading := ExplicitParameterTypes(closedParameterTypes, explicitCount)
                score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(leading, argumentTypes, argumentFacts)
                if score >= 0 {
                    parameterCount := closedParameterTypes.Length
                    if score > bestScore || (score == bestScore && parameterCount < bestParameterCount) {
                        bestScore = score
                        bestParameterCount = parameterCount
                        bestCount = 1
                        bestIndex = candidateIndex
                    } else if score == bestScore && parameterCount == bestParameterCount {
                        bestCount = bestCount + 1
                    }
                }

                candidateIndex = candidateIndex + 1
            }

            if bestCount == 1 && bestIndex >= 0 {
                chosen := candidates[bestIndex]
                return new ColumnarExtensionMethodSelection(true, chosen.Method, chosen.DeclaringType, chosen.ParameterTypes, chosen.ReturnType, explicitCount, null)
            }

            // A normal-form AMBIGUITY is two equally good answers, not "nothing bound", so it
            // declines here rather than being settled by the packed form.
            if bestCount > 1 {
                return ColumnarExtensionMethodSelection.None()
            }
        }

        return ResolveExplicitExpanded(index, receiverType, memberName, typeArguments, argumentTypes, argumentFacts)
    }

    // THE EXPANDED TIER OF AN EXPLICIT SITE, scored exactly as `ResolveExpanded` scores an inferred
    // one: against the per-argument types the packing produces.
    static func ResolveExplicitExpanded(index: ColumnarExtensionMethodIndex, receiverType: Type, memberName: string, typeArguments: Type[], argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): ColumnarExtensionMethodSelection {
        explicitCount := argumentTypes.Length
        candidates := new List<ColumnarExtensionMethodCandidate>()
        if !CollectExplicitExpanded(index, receiverType, memberName, typeArguments, explicitCount, candidates) {
            return ColumnarExtensionMethodSelection.None()
        }

        bestScore := -1
        bestParameterCount := 0
        bestCount := 0
        selected: ColumnarExtensionMethodCandidate? = null
        for candidate in candidates {
            parameters := ParametersOrNull(candidate.Method)
            if parameters != null {
                expanded := ExplicitExpandedParameterTypesOrNull(parameters, candidate.ParameterTypes, explicitCount)
                if expanded != null {
                    score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(expanded, argumentTypes, argumentFacts)
                    if score >= 0 {
                        parameterCount := candidate.ParameterTypes.Length
                        if score > bestScore || (score == bestScore && parameterCount < bestParameterCount) {
                            bestScore = score
                            bestParameterCount = parameterCount
                            bestCount = 1
                            selected = candidate
                        } else if score == bestScore && parameterCount == bestParameterCount {
                            bestCount = bestCount + 1
                        }
                    }
                }
            }
        }

        if bestCount != 1 || selected == null {
            return ColumnarExtensionMethodSelection.None()
        }

        return ExpandedExplicitSelection(selected, explicitCount)
    }

    // THE PER-ARGUMENT PARAMETER TYPES OF AN EXPANDED EXPLICIT CALL. A site that supplies every fixed
    // argument packs the rest, exactly as `ColumnarParamsExpansion` lays it out. One that supplies
    // FEWER packs nothing: each fixed slot it omits must fill from its metadata default, and the
    // tail is an empty array — the C# reading of `route.Produces<Todo>()`, whose `statusCode` and
    // `contentType` are defaulted and whose `params` tail has no argument at all.
    static func ExplicitExpandedParameterTypesOrNull(parameters: ParameterInfo[], parameterTypes: Type[], argumentCount: int): Type[]? {
        if ColumnarParamsExpansion.ElementTypeOrNull(parameters, parameterTypes) == null || argumentCount < 0 {
            return null
        }

        fixedCount := ColumnarParamsExpansion.FixedArgumentCount(parameterTypes, 1)
        if argumentCount >= fixedCount {
            return ColumnarParamsExpansion.ExpandedParameterTypesOrNull(parameters, parameterTypes, 1, argumentCount)
        }

        omitted := 1 + argumentCount
        while omitted < parameterTypes.Length - 1 {
            if !CanFillOptional(parameters[omitted], parameterTypes[omitted]) {
                return null
            }

            omitted = omitted + 1
        }

        return ExplicitParameterTypes(parameterTypes, argumentCount)
    }

    static func ExpandedExplicitSelection(candidate: ColumnarExtensionMethodCandidate, explicitCount: int): ColumnarExtensionMethodSelection {
        parameters := ParametersOrNull(candidate.Method)
        if parameters == null {
            return ColumnarExtensionMethodSelection.None()
        }

        elementType := ColumnarParamsExpansion.ElementTypeOrNull(parameters, candidate.ParameterTypes)
        if elementType == null {
            return ColumnarExtensionMethodSelection.None()
        }

        return new ColumnarExtensionMethodSelection(true, candidate.Method, candidate.DeclaringType, candidate.ParameterTypes, candidate.ReturnType, explicitCount, elementType)
    }

    // A non-generic candidate resolves as itself. A generic method DEFINITION resolves by inferring
    // EVERY method type argument from the receiver and the SUPPLIED argument types, then closing the
    // definition into an exact runtime handle. Inference follows matching base/interface shapes, an omitted
    // trailing optional contributes nothing to it (so a type parameter only the omitted tail mentions
    // stays unbound and loses the candidate), and a closure the declared constraints refuse is not a
    // candidate.
    static func ResolveCandidateShape(candidate: ColumnarExtensionMethodCandidate, receiverType: Type, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, explicitCount: int): ColumnarExtensionMethodCandidate? {
        if !candidate.Method.IsGenericMethodDefinition {
            return candidate
        }

        if candidate.ParameterTypes.Length < explicitCount + 1 || !CanInferExtensionReceiverShape(candidate.ReceiverParameterType, receiverType) {
            return null
        }

        return InferExtensionCandidate(candidate, receiverType, argumentTypes, argumentFacts, explicitCount, false)
    }

    // The expanded form of the same inference, for a candidate whose last parameter is a `params`
    // array: slots before the tail unify with their own arguments and every packed argument with the
    // tail's ELEMENT type.
    static func ResolveExpandedShape(candidate: ColumnarExtensionMethodCandidate, receiverType: Type, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): ColumnarExtensionMethodCandidate? {
        parameters := ParametersOrNull(candidate.Method)
        if parameters == null || parameters.Length != candidate.ParameterTypes.Length || parameters.Length < 2 || !IsParamsParameter(parameters[parameters.Length - 1]) {
            return null
        }
        if !CanInferExtensionReceiverShape(candidate.ReceiverParameterType, receiverType) {
            return null
        }

        return InferExtensionCandidate(candidate, receiverType, argumentTypes, argumentFacts, argumentTypes.Length, true)
    }

    // Generic extensions are indexed across every referenced assembly. Most same-named candidates
    // have a receiver shape that cannot bind from this call. Reject those shapes before allocating
    // the receiver-plus-arguments arrays and the inference dictionary used by the full loop.
    // This mirrors `Unify(..., allowInferenceWidening: false)`: generic definitions and method type
    // parameters must line up structurally; ordinary assignability is checked after closure.
    static func CanInferExtensionReceiverShape(pattern: Type, actual: Type): bool {
        if pattern == null || actual == null {
            return false
        }
        if !pattern.ContainsGenericParameters || pattern.IsGenericParameter {
            return true
        }
        if pattern.IsByRef {
            return false
        }
        if pattern.IsArray {
            if !actual.IsArray || !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(pattern) || !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(actual) {
                return false
            }
            patternElement := pattern.GetElementType()
            actualElement := actual.GetElementType()
            return patternElement != null && actualElement != null && CanInferExtensionReceiverShape(patternElement, actualElement)
        }
        if !pattern.IsGenericType {
            return true
        }

        try {
            matched := ColumnarRuntimeGenericMethodResolver.FindMatchingInstantiation(pattern.GetGenericTypeDefinition(), actual)
            if matched == null {
                return false
            }
            patternArguments := pattern.GetGenericArguments()
            actualArguments := matched.GetGenericArguments()
            if patternArguments.Length != actualArguments.Length {
                return false
            }
            index := 0
            while index < patternArguments.Length {
                if !CanInferExtensionReceiverShape(patternArguments[index], actualArguments[index]) {
                    return false
                }
                index = index + 1
            }
            return true
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }
    }

    // The one inference loop both shapes share: the receiver unifies with slot 0, then each supplied
    // argument with the slot `ArgumentSlotTypesOrNull` names for it. A `null` literal carries no type
    // and binds nothing, as it does for a static call. The runtime generic resolver owns the loop;
    // inference searches the receiver's base and interface instantiations, as C# input inference does.
    static func InferExtensionCandidate(candidate: ColumnarExtensionMethodCandidate, receiverType: Type, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, explicitCount: int, expanded: bool): ColumnarExtensionMethodCandidate? {
        if argumentTypes == null || argumentFacts == null || explicitCount < 0 || explicitCount > argumentTypes.Length {
            return null
        }

        // The shared infer-close-substitute helper enforces complete inference and declared
        // constraints, then substitutes both parameters and the return type from the definition.
        closed := ColumnarRuntimeGenericMethodResolver.InferAndCloseWithLeadingArgument(
            candidate.Method,
            candidate.ParameterTypes,
            receiverType,
            argumentTypes,
            argumentFacts,
            explicitCount,
            expanded,
            true
        )
        if closed == null {
            return null
        }

        return new ColumnarExtensionMethodCandidate(closed.Method, candidate.DeclaringType, closed.ParameterTypes, closed.ReturnType)
    }

    // Contextual extension inference shares the method type parameters' identity anchors when it
    // closes delegate signatures. Keep this owner-visible ordinal query alongside the shared loop so
    // the contextual path and ordinary extension path use the same method-parameter positions.
    static func MethodTypeParameterOrdinal(parameterType: Type, typeParameters: Type[]): int {
        ordinal := 0
        while ordinal < typeParameters.Length {
            if typeParameters[ordinal] == parameterType {
                return ordinal
            }

            ordinal = ordinal + 1
        }

        return -1
    }

    static func CandidateAppliesToReceiver(candidate: ColumnarExtensionMethodCandidate, receiverType: Type): bool {
        receiverParameterType := candidate.ReceiverParameterType
        return !receiverParameterType.IsValueType && ReferenceAssignableFrom(receiverParameterType, receiverType)
    }

    // Explicit call arguments occupy the extension parameters after the receiver slot.
    static func ExplicitParameterTypes(parameterTypes: Type[], explicitCount: int): Type[] {
        result := new Type[](explicitCount)
        index := 0
        while index < explicitCount {
            result[index] = parameterTypes[index + 1]
            index = index + 1
        }

        return result
    }

    static func TrailingDefaultsFillable(method: MethodInfo, parameterTypes: Type[], startIndex: int): bool {
        parameters := method.GetParameters()
        if parameters == null || parameters.Length != parameterTypes.Length {
            return false
        }

        index := startIndex
        while index < parameterTypes.Length {
            if !CanFillOptional(parameters[index], parameterTypes[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    // WHAT A TRAILING OPTIONAL PARAMETER CONTRIBUTES AT THE CALL SITE, AND IT IS A CONSTANT.
    //
    // C# BAKES A DEFAULT ARGUMENT INTO THE CALLER. The value lives in the callee's Constant table (or,
    // for a `decimal`, its `[DecimalConstant]`) and the call site writes it as a literal instruction,
    // so `b: int = 5` omitted at a call is an `ldc.i4.5` in the caller and nothing at all in the
    // callee. That is the whole rule, and it is why omitting a defaulted argument needs no
    // cooperation from the method being called.
    // A REFERENCED METHOD'S OMITTED ARGUMENT, filled from the default its metadata stores. What
    // that default is — and whether this call can write it at all — is
    // `ColumnarParameterDefaultValue.FromMetadata`'s decision; these are the plan and IL writers
    // every external call site shares.
    static func CanFillOptional(parameter: ParameterInfo, resolvedType: Type): bool {
        return ColumnarParameterDefaultValue.FromMetadata(parameter, resolvedType) != null
    }

    static func TryAppendOptionalDefault(plan: ColumnarCodePlan, parameter: ParameterInfo, resolvedType: Type): bool {
        defaultValue := ColumnarParameterDefaultValue.FromMetadata(parameter, resolvedType)
        return plan != null && defaultValue != null && defaultValue.AppendTo(plan)
    }

    static func TryEmitOptionalDefault(il: ILGenerator, parameter: ParameterInfo, resolvedType: Type): bool {
        defaultValue := ColumnarParameterDefaultValue.FromMetadata(parameter, resolvedType)
        return il != null && defaultValue != null && defaultValue.EmitTo(il)
    }

    static func ReferenceAssignableFrom(expectedType: Type, actualType: Type): bool {
        if expectedType == null || actualType == null {
            return false
        }

        if RuntimeTypeShapeFacts.ExactTypeShapeMatches(expectedType, actualType) {
            return true
        }

        // A TYPE CLOSED OVER A TYPE THIS COMPILATION IS WRITING answers `IsAssignableFrom` with a
        // throw or a flat `false`, because its interface list is not reflectable: `List<Query>` and
        // `Query[]` both do, for a source class `Query`. The closed shapes such a receiver HAS are
        // the same question method type inference asks of it, so the same owner answers both — there
        // is one notion of "what interface does this receiver have" and not two.
        //
        // THE SLOT BEING NON-GENERIC DOES NOT CHANGE THE QUESTION. `Cast<T>` and `OfType<T>` declare
        // the NON-GENERIC `System.Collections.IEnumerable`, and `List<Query>` implements it exactly
        // as it implements `IEnumerable<Query>`; gating this walk on a CONSTRUCTED slot left every
        // such call to the reflection answer that cannot be given, so
        // `unit.FileImports.OfType<FileImport>()` — the compiler's own source — declined. A
        // non-generic slot is its own definition and `FindClosedImplementation` already matches one
        // by identity, so the two slots share the single relation instead of one having none.
        expectedDefinition := ExpectedSlotDefinitionOrNull(expectedType)
        if expectedDefinition != null {
            implementation := ColumnarContextualExtensionInference.FindClosedImplementation(actualType, expectedDefinition)
            if implementation != null && ColumnarTypeEquivalenceFacts.TypesEquivalent(implementation, expectedType) {
                return true
            }
        }

        try {
            return expectedType.IsAssignableFrom(actualType)
        } catch {
            return false
        }
    }

    // The shape `FindClosedImplementation` searches for, for one declared receiver slot. A
    // CONSTRUCTED generic slot is searched by its definition, because what the receiver has is a
    // different instantiation of it; a slot with nothing open in it IS the shape to look for. A slot
    // that is still open — a bare type parameter, or anything containing one — names no shape a
    // receiver can be said to have, and keeps the ordinary reflection answer.
    static func ExpectedSlotDefinitionOrNull(expectedType: Type): Type? {
        if expectedType.IsGenericTypeDefinition {
            return null
        }

        if expectedType.IsGenericType {
            return expectedType.GetGenericTypeDefinition()
        }

        if expectedType.IsGenericParameter || expectedType.ContainsGenericParameters {
            return null
        }

        return expectedType
    }
}
