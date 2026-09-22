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

        if isSelected && paramsElementType != null && explicitArgumentCount < parameterTypes.Length - 2 {
            throw new InvalidOperationException("An expanded extension call must supply every fixed argument of the selected signature.")
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
// This owner is intentionally narrow: reference-type receivers only, exact fixed arity or a
// trailing run of optional parameters whose metadata default is null. Generic candidates close by
// EXACT structural inference from the receiver and explicit argument types (`IEnumerable<int>`
// receiver -> Enumerable.Take<int>); partial inference, builder-bound type arguments,
// interface/variance receiver widening (`List<int>` against `IEnumerable<TSource>`), and
// trailing-optional filling on generic candidates all decline. Anything outside the admitted
// surface leaves the call to its later owner.
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

        entryIndex := 0
        while entryIndex < scan.Entries.Length {
            entry := scan.Entries[entryIndex]
            if entry != null && entry.RuntimeAssembly != null {
                AddAssembly(index, entry.RuntimeAssembly)
            }

            entryIndex = entryIndex + 1
        }

        return index
    }

    static func AddAssembly(index: ColumnarExtensionMethodIndex, assembly: Assembly) {
        types := HostTypesOrEmpty(assembly)
        typeIndex := 0
        while typeIndex < types.Length {
            candidateType := types[typeIndex]
            if IsStaticExtensionHost(candidateType) {
                AddType(index, candidateType)
            }

            typeIndex = typeIndex + 1
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
        methodIndex := 0
        while methodIndex < methods.Length {
            method := methods[methodIndex]
            if IsExtensionMethodCandidate(method) {
                parameters := ParametersOrNull(method)
                if parameters != null && parameters.Length >= 1 && !HasExcludedParameterShape(parameters) {
                    parameterTypes := ParameterTypesOrNull(parameters)
                    returnType := ReturnTypeOrNull(method)
                    if parameterTypes != null && returnType != null && IsSupportedReceiverParameter(parameterTypes[0]) {
                        index.Add(method.get_Name(), new ColumnarExtensionMethodCandidate(method, hostType, parameterTypes, returnType))
                    }
                }
            }

            methodIndex = methodIndex + 1
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
            return method.get_ReturnType()
        } catch {
            return null
        }
    }

    static func ParameterTypeOrNull(parameter: ParameterInfo): Type? {
        try {
            return parameter.get_ParameterType()
        } catch {
            return null
        }
    }

    static func IsStaticExtensionHost(candidateType: Type): bool {
        if candidateType == null {
            return false
        }

        try {
            if !candidateType.get_IsClass() || !candidateType.get_IsSealed() || !candidateType.get_IsAbstract() || candidateType.get_IsGenericType() {
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
            attributeType := attribute.get_AttributeType()
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
            if !method.get_IsStatic() || !InternalsVisibleToEmissionScope.ReachesLevel(MemberAccessibility.LevelOfMethod(method), method.get_DeclaringType()) {
                return false
            }
        } catch {
            return false
        }

        // Generic extension methods are indexed only as OPEN definitions; resolution closes them by
        // receiver/argument inference. A partially constructed generic method is never a candidate.
        if method.get_IsGenericMethod() && !method.get_IsGenericMethodDefinition() {
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
            if parameterType == null || parameterType.get_IsByRef() || parameterType.get_IsPointer() {
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
        return receiverParameterType != null && !receiverParameterType.get_IsByRef() && !receiverParameterType.get_IsPointer() && !receiverParameterType.get_IsGenericParameter()
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
            }
        }
        // A granting assembly whose declared surface cannot be enumerated falls back to the
        // exported one rather than contributing nothing.

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

        if receiverType.get_IsValueType() || receiverType.get_IsByRef() || receiverType.get_IsPointer() || receiverType.get_IsGenericParameter() {
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
        candidateIndex := 0
        while candidateIndex < candidates.Count {
            indexed := candidates[candidateIndex]
            candidate: ColumnarExtensionMethodCandidate? = null
            if indexed != null {
                candidate = ResolveCandidateShape(indexed, receiverType, argumentTypes, explicitCount)
            }

            if candidate != null && CandidateAppliesToReceiver(candidate, receiverType) {
                parameterTypes := candidate.ParameterTypes
                if parameterTypes.Length - 1 >= explicitCount && TrailingDefaultsFillable(candidate.Method, parameterTypes, 1 + explicitCount) {
                    leading := ExplicitParameterTypes(parameterTypes, explicitCount)
                    score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(leading, argumentTypes, argumentFacts)
                    if score >= 0 {
                        parameterCount := parameterTypes.Length
                        candidateIsGeneric := candidate.Method.get_IsGenericMethod()
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

            candidateIndex = candidateIndex + 1
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
    // GENERIC DEFINITIONS ARE DELIBERATELY OUTSIDE THIS TIER. Inferring a method type argument from
    // an argument that is a packed ELEMENT rather than a parameter is its own inference rule, and no
    // call site has needed it: the shapes this exists for (`LoggerExtensions.LogDebug` and its four
    // siblings, whose tail is `params object?[]`) are all non-generic. A generic `params` extension
    // therefore still declines rather than being guessed at.
    static func ResolveExpanded(candidates: List<ColumnarExtensionMethodCandidate>, receiverType: Type, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): ColumnarExtensionMethodSelection {
        explicitCount := argumentTypes.Length
        bestScore := -1
        bestParameterCount := 0
        bestCount := 0
        bestElementType: Type? = null
        selected: ColumnarExtensionMethodCandidate? = null
        candidateIndex := 0
        while candidateIndex < candidates.Count {
            candidate := candidates[candidateIndex]
            if candidate != null && !candidate.Method.get_IsGenericMethodDefinition() && CandidateAppliesToReceiver(candidate, receiverType) {
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
                            } else if score == bestScore && parameterCount == bestParameterCount {
                                bestCount = bestCount + 1
                            }
                        }
                    }
                }
            }

            candidateIndex = candidateIndex + 1
        }

        if bestCount != 1 || selected == null || bestElementType == null {
            return ColumnarExtensionMethodSelection.None()
        }

        return new ColumnarExtensionMethodSelection(true, selected.Method, selected.DeclaringType, selected.ParameterTypes, selected.ReturnType, explicitCount, bestElementType)
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
    static func CollectExplicit(index: ColumnarExtensionMethodIndex, receiverType: Type, memberName: string, typeArguments: Type[], argumentCount: int, selected: List<ColumnarExtensionMethodCandidate>): bool {
        if index == null || receiverType == null || memberName == null || typeArguments == null || typeArguments.Length == 0 || argumentCount < 0 || selected == null {
            return false
        }

        if receiverType.get_IsByRef() || receiverType.get_IsPointer() || receiverType.get_IsGenericParameter() {
            return false
        }

        position := 0
        while position < typeArguments.Length {
            if typeArguments[position] == null || ColumnarRuntimeGenericMethodResolver.IsUnbindableInferredType(typeArguments[position]) {
                return false
            }

            position = position + 1
        }

        candidates := new List<ColumnarExtensionMethodCandidate>()
        if !index.TryGet(memberName, out candidates) {
            return false
        }

        candidateIndex := 0
        while candidateIndex < candidates.Count {
            indexed := candidates[candidateIndex]
            if indexed != null && indexed.Method.get_IsGenericMethodDefinition() && indexed.Method.GetGenericArguments().Length == typeArguments.Length && indexed.ParameterTypes.Length - 1 >= argumentCount {
                closedMethod := ColumnarRuntimeGenericMethodResolver.CloseOrNull(indexed.Method, typeArguments)
                closedParameterTypes := ColumnarRuntimeGenericMethodResolver.ClosedParameterTypesOrNull(indexed.Method, typeArguments)
                closedReturnType := ColumnarRuntimeGenericMethodResolver.SubstituteMethodTypeArguments(indexed.ReturnType, typeArguments)
                if closedMethod != null && closedParameterTypes != null && closedReturnType != null && ReferenceAssignableFrom(closedParameterTypes[0], receiverType) && TrailingDefaultsFillable(indexed.Method, closedParameterTypes, 1 + argumentCount) {
                    selected.Add(new ColumnarExtensionMethodCandidate(closedMethod, indexed.DeclaringType, closedParameterTypes, closedReturnType))
                }
            }

            candidateIndex = candidateIndex + 1
        }

        return selected.Count > 0
    }

    // The unique candidate for a site whose arguments cannot all be typed before emission — a lambda
    // written at an explicitly-closed extension call. More than one surviving candidate is a decline,
    // because the argument types are exactly what would have chosen between them.
    static func ResolveExplicitUnique(index: ColumnarExtensionMethodIndex, receiverType: Type, memberName: string, typeArguments: Type[], argumentCount: int): ColumnarExtensionMethodSelection {
        candidates := new List<ColumnarExtensionMethodCandidate>()
        if !CollectExplicit(index, receiverType, memberName, typeArguments, argumentCount, candidates) || candidates.Count != 1 {
            return ColumnarExtensionMethodSelection.None()
        }

        chosen := candidates[0]
        return new ColumnarExtensionMethodSelection(true, chosen.Method, chosen.DeclaringType, chosen.ParameterTypes, chosen.ReturnType, argumentCount, null)
    }

    // The same candidate set, ranked by the argument-flow scorer every other call selection uses.
    static func ResolveExplicit(index: ColumnarExtensionMethodIndex, receiverType: Type, memberName: string, typeArguments: Type[], argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): ColumnarExtensionMethodSelection {
        if argumentTypes == null || argumentFacts == null {
            return ColumnarExtensionMethodSelection.None()
        }

        candidates := new List<ColumnarExtensionMethodCandidate>()
        if !CollectExplicit(index, receiverType, memberName, typeArguments, argumentTypes.Length, candidates) {
            return ColumnarExtensionMethodSelection.None()
        }

        explicitCount := argumentTypes.Length
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

        if bestCount != 1 || bestIndex < 0 {
            return ColumnarExtensionMethodSelection.None()
        }

        chosen := candidates[bestIndex]
        return new ColumnarExtensionMethodSelection(true, chosen.Method, chosen.DeclaringType, chosen.ParameterTypes, chosen.ReturnType, explicitCount, null)
    }

    // A non-generic candidate resolves as itself. A generic method DEFINITION resolves by inferring
    // EVERY method type argument from the receiver and explicit argument types, then closing the
    // definition into an exact runtime handle. The generic surface is deliberately exact: the arity
    // must match with no optional filling, inference is structural unification only, and a closure
    // the runtime rejects (a violated constraint) is not a candidate.
    static func ResolveCandidateShape(candidate: ColumnarExtensionMethodCandidate, receiverType: Type, argumentTypes: Type[], explicitCount: int): ColumnarExtensionMethodCandidate? {
        method := candidate.Method
        if !method.get_IsGenericMethodDefinition() {
            return candidate
        }

        if candidate.ParameterTypes.Length - 1 != explicitCount {
            return null
        }

        typeParameters := method.GetGenericArguments()
        if typeParameters == null || typeParameters.Length == 0 {
            return null
        }

        inferred := new Type[](typeParameters.Length)
        if !TryUnifyCandidateSlot(candidate.ParameterTypes[0], receiverType, typeParameters, inferred) {
            return null
        }

        argumentIndex := 0
        while argumentIndex < explicitCount {
            if !TryUnifyCandidateSlot(candidate.ParameterTypes[argumentIndex + 1], argumentTypes[argumentIndex], typeParameters, inferred) {
                return null
            }

            argumentIndex = argumentIndex + 1
        }

        // Partial inference never closes, and a builder-bound type argument stays with later owners:
        // MakeGenericMethod over Reflection.Emit builders is outside this exact-handle surface.
        inferredIndex := 0
        while inferredIndex < inferred.Length {
            inferredArgument := inferred[inferredIndex]
            if inferredArgument == null || RuntimeTypeShapeFacts.ContainsBuilderBoundType(inferredArgument) {
                return null
            }

            inferredIndex = inferredIndex + 1
        }

        closedMethod: MethodInfo? = null
        try {
            closedMethod = method.MakeGenericMethod(inferred)
        } catch {
            return null
        }

        if closedMethod == null {
            return null
        }

        closedParameters := closedMethod.GetParameters()
        if closedParameters == null || closedParameters.Length != candidate.ParameterTypes.Length {
            return null
        }

        closedParameterTypes := ParameterTypesOrNull(closedParameters)
        if closedParameterTypes == null {
            return null
        }

        closedReturnType := closedMethod.get_ReturnType()
        if closedReturnType == null || closedReturnType.get_ContainsGenericParameters() {
            return null
        }

        return new ColumnarExtensionMethodCandidate(closedMethod, candidate.DeclaringType, closedParameterTypes, closedReturnType)
    }

    // Structural unification of one declared slot against one actual type. A slot without open
    // generic parameters carries no inference (ordinary scoring validates it); a naked method type
    // parameter binds its position exactly once; constructed shapes must carry the SAME generic
    // definition (or both be SZ arrays) and unify their arguments pairwise. Interface and variance
    // widening (`List<int>` against `IEnumerable<TSource>`) is deliberately outside this owner.
    static func TryUnifyCandidateSlot(parameterType: Type, actualType: Type, typeParameters: Type[], inferred: Type[]): bool {
        if parameterType == null || actualType == null {
            return false
        }

        if !parameterType.get_ContainsGenericParameters() {
            return true
        }

        if parameterType.get_IsGenericParameter() {
            position := MethodTypeParameterOrdinal(parameterType, typeParameters)
            if position < 0 {
                return false
            }

            existing := inferred[position]
            if existing == null {
                inferred[position] = actualType
                return true
            }

            return existing == actualType
        }

        if ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(parameterType) {
            if !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(actualType) {
                return false
            }

            parameterElement := parameterType.GetElementType()
            actualElement := actualType.GetElementType()
            if parameterElement == null || actualElement == null {
                return false
            }

            return TryUnifyCandidateSlot(parameterElement, actualElement, typeParameters, inferred)
        }

        if !parameterType.get_IsGenericType() || !actualType.get_IsGenericType() {
            return false
        }

        if parameterType.GetGenericTypeDefinition() != actualType.GetGenericTypeDefinition() {
            return false
        }

        parameterArguments := parameterType.GetGenericArguments()
        actualArguments := actualType.GetGenericArguments()
        if parameterArguments.Length != actualArguments.Length {
            return false
        }

        pairIndex := 0
        while pairIndex < parameterArguments.Length {
            if !TryUnifyCandidateSlot(parameterArguments[pairIndex], actualArguments[pairIndex], typeParameters, inferred) {
                return false
            }

            pairIndex = pairIndex + 1
        }

        return true
    }

    // The definition's own generic arguments are the identity anchors for inference positions.
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
        return !receiverParameterType.get_IsValueType() && ReferenceAssignableFrom(receiverParameterType, receiverType)
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
    // C# BAKES A DEFAULT ARGUMENT INTO THE CALLER. The value lives in the callee's Constant table and
    // the call site writes it as a literal instruction, so `b: int = 5` omitted at a call is an
    // `ldc.i4.5` in the caller and nothing at all in the callee. That is the whole rule, and it is why
    // omitting a defaulted argument needs no cooperation from the method being called.
    //
    // THREE FAMILIES FILL. The null reference for a reference-typed parameter (`setupAction = null`,
    // `url = null` — the shape the Web API template needs); an integral, floating, `char`, `bool`,
    // `string` or enum constant, which is what every converted C# overload-with-defaults produces; and
    // `Nullable<T>` with no value, the one default that is not a single literal instruction, because
    // it needs a local to `initobj` into.
    //
    // FOUR SHAPES DECLINE, AND EACH FOR A REASON. `decimal` and `DateTime` keep their defaults in a
    // `[DecimalConstant]`/`[DateTimeConstant]` attribute rather than in the Constant table; a NON-null
    // `Nullable<T>` default (`n: int? = 5`) would have to construct the value as well; a parameter
    // that is merely `[Optional]` with no constant at all is not guessed as `default(T)`; and a
    // by-ref, pointer or type-parameter shape is not a value the site can write.
    static func OptionalDefaultKindNone(): int {
        return 0
    }

    static func OptionalDefaultKindNullReference(): int {
        return 1
    }

    static func OptionalDefaultKindInt32(): int {
        return 2
    }

    static func OptionalDefaultKindUInt32(): int {
        return 3
    }

    static func OptionalDefaultKindInt64(): int {
        return 4
    }

    static func OptionalDefaultKindUInt64(): int {
        return 5
    }

    static func OptionalDefaultKindSingle(): int {
        return 6
    }

    static func OptionalDefaultKindDouble(): int {
        return 7
    }

    static func OptionalDefaultKindString(): int {
        return 8
    }

    // A STRUCT'S `default` — the one default that is not a single literal instruction: it needs a
    // local to `initobj` into. `Nullable<T>` with no value (`kind: SymbolKind? = null`) is the case
    // that was needed first and this row was named after it, but `default(T)` for ANY struct reads
    // back the same way and emits the same three instructions: `Process.WaitForExitAsync()`
    // (`CancellationToken cancellationToken = default`) is the call that needed the general answer,
    // and it declined as unmodeled while every reference-typed optional filled. A NON-null value
    // default (`n: int? = 5`) still declines; it would have to construct the value as well, and no
    // call site here has asked for that yet.
    static func OptionalDefaultKindZeroValue(): int {
        return 9
    }

    // A `Nullable<T>` DEFAULT THAT HAS A VALUE — `long? fileSizeLimitBytes = 1073741824`,
    // `int? retainedFileCountLimit = 31`. The constant in the callee's metadata is the UNDERLYING
    // one (the row reads back as a `long`, not as a `Nullable<long>`), so the call site pushes that
    // literal and wraps it: `newobj Nullable<T>::.ctor(T)`, which is exactly what a C# call site
    // writes for the same omission. Until this row, such a parameter was unfillable and every
    // overload carrying one was refused at every arity — `builder.AddFile(path)`, whose two trailing
    // defaults are both of this shape, could not bind at all.
    static func OptionalDefaultKindNullableValue(): int {
        return 10
    }

    // The literal instruction a constant of this type takes, shared by the nullable wrap and the
    // plain fill so the two cannot drift. `None` means no literal exists for it, which is the
    // `decimal`/`DateTime` answer: those keep their defaults in an attribute, not in the Constant
    // table.
    static func ValueConstantKind(constantType: Type): int {
        if constantType == typeof(int) || constantType == typeof(short) || constantType == typeof(ushort) || constantType == typeof(byte) || constantType == typeof(sbyte) || constantType == typeof(bool) || constantType == typeof(char) {
            return OptionalDefaultKindInt32()
        }

        if constantType == typeof(uint) {
            return OptionalDefaultKindUInt32()
        }

        if constantType == typeof(long) {
            return OptionalDefaultKindInt64()
        }

        if constantType == typeof(ulong) {
            return OptionalDefaultKindUInt64()
        }

        if constantType == typeof(float) {
            return OptionalDefaultKindSingle()
        }

        if constantType == typeof(double) {
            return OptionalDefaultKindDouble()
        }

        return OptionalDefaultKindNone()
    }

    // The type whose literal a value-typed default writes: an enum's underlying type, a
    // `Nullable<T>`'s `T`, and otherwise the type itself.
    static func ConstantCarrierType(resolvedType: Type): Type {
        underlying := Nullable.GetUnderlyingType(resolvedType)
        carrier := underlying ?? resolvedType
        if carrier.get_IsEnum() {
            return carrier.GetEnumUnderlyingType()
        }

        return carrier
    }

    // The `Nullable<T>::.ctor(T)` this wrap dispatches, or null when the type is not a nullable or
    // its constructor cannot be read.
    static func NullableValueConstructorOrNull(resolvedType: Type): ConstructorInfo? {
        underlying := Nullable.GetUnderlyingType(resolvedType)
        if underlying == null {
            return null
        }

        signature := new Type[](1)
        signature[0] = underlying
        try {
            return resolvedType.GetConstructor(signature)
        } catch {
            return null
        }
    }

    static func OptionalDefaultKind(parameter: ParameterInfo, resolvedType: Type, out defaultValue: object?): int {
        defaultValue = null
        if parameter == null || resolvedType == null || !parameter.get_IsOptional() {
            return OptionalDefaultKindNone()
        }

        if resolvedType.get_IsByRef() || resolvedType.get_IsPointer() || resolvedType.get_IsGenericParameter() {
            return OptionalDefaultKindNone()
        }

        value: object? = null
        try {
            value = parameter.get_DefaultValue()
        } catch {
            // A parameter whose default value cannot be read is not a fillable default.
            return OptionalDefaultKindNone()
        }

        if !resolvedType.get_IsValueType() {
            if value != null {
                stringDefault := value as string
                if stringDefault != null && resolvedType == typeof(string) {
                    defaultValue = stringDefault
                    return OptionalDefaultKindString()
                }

                return OptionalDefaultKindNone()
            }

            return OptionalDefaultKindNullReference()
        }

        if value == null {
            // A VALUE-TYPED PARAMETER WHOSE DEFAULT READS BACK AS NULL IS `default(T)`. That is how a
            // `Nullable<T>` with no value is spelled and it is also how `= default` on any other
            // struct is: the metadata carries `[opt]` with a null constant either way, and the value
            // the call must push is the zeroed struct in both. Asking only about `Nullable<T>` made
            // every other struct's `default` unfillable, which is what refused
            // `p.WaitForExitAsync()`. `resolvedType` is known to be a value type here, and the
            // signature admission above has already accepted it, so `initobj` is exact.
            return OptionalDefaultKindZeroValue()
        }

        // `[Optional]` with no constant at all reads back as `DBNull`/`Missing`, which is not a value
        // this site may write.
        if (value as DBNull) != null || (value as Missing) != null {
            return OptionalDefaultKindNone()
        }

        constantType := ConstantCarrierType(resolvedType)
        constantKind := ValueConstantKind(constantType)
        if constantKind == OptionalDefaultKindNone() {
            return OptionalDefaultKindNone()
        }

        defaultValue = value

        // A NULLABLE WITH A VALUE IS THE LITERAL PLUS A WRAP, and it needs the constructor to exist.
        if Nullable.GetUnderlyingType(resolvedType) != null {
            if NullableValueConstructorOrNull(resolvedType) == null {
                defaultValue = null
                return OptionalDefaultKindNone()
            }

            return OptionalDefaultKindNullableValue()
        }

        return constantKind
    }

    // Write the literal for a constant of `carrierType` into a plan.
    static func TryAppendConstantLiteral(plan: ColumnarCodePlan, constantKind: int, defaultValue: object?): bool {
        if constantKind == OptionalDefaultKindString() {
            plan.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), plan.AddString((string)defaultValue))
            return true
        }

        if constantKind == OptionalDefaultKindInt32() {
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), plan.AddInt32(Convert.ToInt32(defaultValue)))
            return true
        }

        if constantKind == OptionalDefaultKindUInt32() {
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), plan.AddInt32((int)Convert.ToUInt32(defaultValue)))
            return true
        }

        if constantKind == OptionalDefaultKindInt64() {
            plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), plan.AddInt64(Convert.ToInt64(defaultValue)))
            return true
        }

        if constantKind == OptionalDefaultKindUInt64() {
            plan.AppendInt64Instruction(ColumnarCodePlanContract.LdcI8(), plan.AddInt64((long)Convert.ToUInt64(defaultValue)))
            return true
        }

        if constantKind == OptionalDefaultKindSingle() {
            plan.AppendSingleInstruction(ColumnarCodePlanContract.LdcR4(), plan.AddSingle(Convert.ToSingle(defaultValue)))
            return true
        }

        if constantKind == OptionalDefaultKindDouble() {
            plan.AppendDoubleInstruction(ColumnarCodePlanContract.LdcR8(), plan.AddDouble(Convert.ToDouble(defaultValue)))
            return true
        }

        return false
    }

    // The same literal, straight into an `ILGenerator`.
    static func TryEmitConstantLiteral(il: ILGenerator, constantKind: int, defaultValue: object?): bool {
        if constantKind == OptionalDefaultKindString() {
            il.Emit(OpCodes.Ldstr, (string)defaultValue)
            return true
        }

        if constantKind == OptionalDefaultKindInt32() {
            il.Emit(OpCodes.Ldc_I4, Convert.ToInt32(defaultValue))
            return true
        }

        if constantKind == OptionalDefaultKindUInt32() {
            il.Emit(OpCodes.Ldc_I4, (int)Convert.ToUInt32(defaultValue))
            return true
        }

        if constantKind == OptionalDefaultKindInt64() {
            il.Emit(OpCodes.Ldc_I8, Convert.ToInt64(defaultValue))
            return true
        }

        if constantKind == OptionalDefaultKindUInt64() {
            il.Emit(OpCodes.Ldc_I8, (long)Convert.ToUInt64(defaultValue))
            return true
        }

        if constantKind == OptionalDefaultKindSingle() {
            il.Emit(OpCodes.Ldc_R4, Convert.ToSingle(defaultValue))
            return true
        }

        if constantKind == OptionalDefaultKindDouble() {
            il.Emit(OpCodes.Ldc_R8, Convert.ToDouble(defaultValue))
            return true
        }

        return false
    }

    static func CanFillOptional(parameter: ParameterInfo, resolvedType: Type): bool {
        unusedDefault: object? = null
        return OptionalDefaultKind(parameter, resolvedType, out unusedDefault) != OptionalDefaultKindNone()
    }

    static func DefaultIsNullReference(parameter: ParameterInfo): bool {
        try {
            return parameter.get_DefaultValue() == null
        } catch {
            // A parameter whose default value cannot be read is not a fillable null default.
            return false
        }
    }

    // Emit the metadata default for a trailing optional parameter as its literal instruction. The
    // executor validates the resulting stack value against the exact parameter type.
    static func TryAppendOptionalDefault(plan: ColumnarCodePlan, parameter: ParameterInfo, resolvedType: Type): bool {
        if plan == null {
            return false
        }

        defaultValue: object? = null
        kind := OptionalDefaultKind(parameter, resolvedType, out defaultValue)
        if kind == OptionalDefaultKindNone() {
            return false
        }

        if kind == OptionalDefaultKindNullReference() {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
            return true
        }

        if kind == OptionalDefaultKindZeroValue() {
            zeroTypeIndex := plan.AddType(resolvedType)
            zeroLocal := plan.DeclarePlanLocal(zeroTypeIndex)
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), zeroLocal)
            plan.AppendTypeInstruction(ColumnarCodePlanContract.Initobj(), zeroTypeIndex)
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), zeroLocal)
            return true
        }

        if kind == OptionalDefaultKindNullableValue() {
            nullableConstructor := NullableValueConstructorOrNull(resolvedType)
            if nullableConstructor == null || !TryAppendConstantLiteral(plan, ValueConstantKind(ConstantCarrierType(resolvedType)), defaultValue) {
                return false
            }

            // THE SIGNATURE IS THE CONSTRUCTOR'S OWN `T`, not the literal's carrier: for a
            // `Nullable<SomeEnum>` the two differ — the literal is the enum's underlying integer and
            // the constructor still takes the enum.
            wrapSignature := new Type[](1)
            wrapSignature[0] = must Nullable.GetUnderlyingType(resolvedType)
            plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), plan.AddConstructorWithSignature(nullableConstructor, resolvedType, wrapSignature))
            return true
        }

        return TryAppendConstantLiteral(plan, kind, defaultValue)
    }

    // The same fill, written straight into an `ILGenerator` for the call sites that do not build a
    // plan. One rule, two writers.
    static func TryEmitOptionalDefault(il: ILGenerator, parameter: ParameterInfo, resolvedType: Type): bool {
        if il == null {
            return false
        }

        defaultValue: object? = null
        kind := OptionalDefaultKind(parameter, resolvedType, out defaultValue)
        if kind == OptionalDefaultKindNone() {
            return false
        }

        if kind == OptionalDefaultKindNullReference() {
            il.Emit(OpCodes.Ldnull)
            return true
        }

        if kind == OptionalDefaultKindZeroValue() {
            zeroLocal := il.DeclareLocal(resolvedType)
            il.Emit(OpCodes.Ldloca, zeroLocal)
            il.Emit(OpCodes.Initobj, resolvedType)
            il.Emit(OpCodes.Ldloc, zeroLocal)
            return true
        }

        if kind == OptionalDefaultKindNullableValue() {
            nullableConstructor := NullableValueConstructorOrNull(resolvedType)
            if nullableConstructor == null || !TryEmitConstantLiteral(il, ValueConstantKind(ConstantCarrierType(resolvedType)), defaultValue) {
                return false
            }

            il.Emit(OpCodes.Newobj, nullableConstructor)
            return true
        }

        return TryEmitConstantLiteral(il, kind, defaultValue)
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
        if expectedType.get_IsGenericTypeDefinition() {
            return null
        }

        if expectedType.get_IsGenericType() {
            return expectedType.GetGenericTypeDefinition()
        }

        if expectedType.get_IsGenericParameter() || expectedType.get_ContainsGenericParameters() {
            return null
        }

        return expectedType
    }
}
