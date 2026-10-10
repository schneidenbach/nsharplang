namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// WHICH EXTENSION METHOD A MEMBER NAME RESOLVES TO — the analyzer's extension surface, whole.
//
// A member name that is not declared on the receiver's own shape reaches this surface, and the
// surface answers with the extension that claims it: a source `func` whose first parameter accepts
// the receiver, or a `[Extension]` static found in a referenced assembly under an imported
// namespace. This owner is SILENT: it reports no diagnostic and records nothing into the semantic
// model. Every answer is a value.
//
// SOURCE EXTENSIONS FIRST, AND THE EXTERNAL SCAN IS THE FALLBACK — but only when no source
// extension is APPLICABLE, not merely when none is named. A source `func` that shares the name and
// rejects the receiver falls through to the external scan exactly as an unnamed one does.
//
// THE THREE COLLECTIONS CROSS BY REFERENCE, NOT BY VALUE. The analyzer's `_extensionMethods`,
// `_usingNamespaces` and `_mlcAssemblies` are `readonly` fields mutated in place — cleared at the
// start of every `Analyze`, appended to as declarations and imports and references are walked,
// NEVER reassigned — so the reference held here is always the live collection. Snapshot none of
// them: an extension declared later in the same file would then be invisible, and the external scan
// would search whichever namespace set existed when the copy was taken. The containing type name is
// the opposite case and must NOT be held: `_currentTypeName` is a plain mutable field that changes
// every time the walk enters or leaves a type, so it crosses as a PARAMETER, read at the call.
// A STATIC CLASS OF A REFERENCED ASSEMBLY AND ITS NAMESPACE: the only types the external extension
// scan can take a method from. See `AnalyzerExtensionMethodResolution.EnsureExtensionHosts`.
class AnalyzerExtensionHostCandidate {
    HostType: Type
    Namespace: string

    constructor(hostType: Type, hostNamespace: string) {
        HostType = hostType
        Namespace = hostNamespace
    }
}

class AnalyzerExtensionMethodResolution {
    typeResolver: AnalyzerTypeResolver
    assignability: AnalyzerAssignability
    declarationContext: AnalyzerDeclarationContext
    functionTypeFactory: AnalyzerFunctionTypeFactory
    clrTypeConversion: AnalyzerClrTypeConversion
    extensionMethods: List<FunctionDeclaration>
    usingNamespaces: List<string>
    assemblies: List<Assembly>
    assemblyTypes: Dictionary<Assembly, Type[]>
    incompleteAssemblyTypeLists: HashSet<Assembly>
    // THE SCAN'S CANDIDATE HOSTS, in assembly then type order: every static (`sealed abstract`) type
    // with a namespace, of every loaded assembly. The scan used to walk EVERY type of EVERY reference
    // -- reading each one's namespace -- for every member name that fell through to an extension
    // lookup, which was over a fifth of a Compiler.Core build's CPU; the static types are a few
    // hundred of those tens of thousands. Both facts read here are fixed for a type, so the list only
    // grows with the assembly list (and is rebuilt if that list shrinks or is replaced); the
    // per-query tests -- the imported namespace, the friend rule -- still run per query, in order.
    extensionHosts: List<AnalyzerExtensionHostCandidate>
    extensionHostAssemblies: int
    extensionHostLastAssembly: Assembly?
    extensionHostSurfaceComplete: bool
    // Bumped every time the host list changes, so the answers below can tell.
    extensionHostVersion: int
    // THE SCAN'S ANSWERS, per (method name, receiver CLR type), for as long as the imported namespaces,
    // the host list and the friend grants they were computed under are unchanged -- a file asks the
    // same few names of the same few receivers over and over (`.Add`, `.Count`, `.Select`), and each
    // ask was a walk of every host. The inputs are compared on every ask (the import list element by
    // element), so a new file's imports, a newly loaded assembly or a changed grant starts afresh.
    extensionScanMemo: Dictionary<(Name: string, Receiver: Type), List<MethodInfo>>
    // Members may also reach the emitter through SDK-provided/global extension imports that are
    // not represented by a source `import` directive. This inventory is used only to decide whether
    // an absent reflected member name is certainly missing; normal binding still observes imports.
    extensionScanAnyNamespaceMemo: Dictionary<(Name: string, Receiver: Type), List<MethodInfo>>
    extensionScanMemoNamespaces: List<string>
    extensionScanMemoHosts: int
    extensionScanMemoGrantName: string
    importUsageCredit: AnalyzerImportUsageCredit?
    genericCallBinder: AnalyzerSyntheticCallBinder?

    // THE FRIEND GRANTS OF THE COMPILATION BEING ANALYSED, or null for an owner built without a
    // project behind it — which grants nothing, exactly as before friends existed.
    friendGrants: InternalsVisibleToGrants?
    referenceSetComplete: bool
    commonReferenceAssemblyNames: HashSet<string>

    constructor(types: AnalyzerTypeResolver, assignabilityOwner: AnalyzerAssignability, declarations: AnalyzerDeclarationContext, functionTypes: AnalyzerFunctionTypeFactory, clrConversion: AnalyzerClrTypeConversion, declaredExtensions: List<FunctionDeclaration>, importedNamespaces: List<string>, referenceAssemblies: List<Assembly>) {
        importUsageCredit = null
        typeResolver = types
        assignability = assignabilityOwner
        declarationContext = declarations
        functionTypeFactory = functionTypes
        clrTypeConversion = clrConversion
        extensionMethods = declaredExtensions
        usingNamespaces = importedNamespaces
        assemblies = referenceAssemblies
        assemblyTypes = new Dictionary<Assembly, Type[]>()
        incompleteAssemblyTypeLists = new HashSet<Assembly>()
        extensionHosts = new List<AnalyzerExtensionHostCandidate>()
        extensionHostAssemblies = 0
        extensionHostLastAssembly = null
        extensionHostSurfaceComplete = true
        extensionHostVersion = 0
        extensionScanMemo = new Dictionary<(Name: string, Receiver: Type), List<MethodInfo>>()
        extensionScanAnyNamespaceMemo = new Dictionary<(Name: string, Receiver: Type), List<MethodInfo>>()
        extensionScanMemoNamespaces = new List<string>()
        extensionScanMemoHosts = -1
        extensionScanMemoGrantName = ""
        friendGrants = null
        referenceSetComplete = false
        commonReferenceAssemblyNames = new HashSet<string>(AnalyzerMetadataLoadPolicy.CommonAssemblyNames(), StringComparer.Ordinal)
        genericCallBinder = null
    }

    func SetFriendGrants(grants: InternalsVisibleToGrants?) {
        friendGrants = grants
    }

    func SetGenericCallBinder(binder: AnalyzerSyntheticCallBinder?) {
        genericCallBinder = binder
    }

    func SetReferenceSetComplete(complete: bool) {
        referenceSetComplete = complete
    }

    // SOURCE EXTENSIONS FIRST, AND THE EXTERNAL SCAN IS THE FALLBACK — but only when no source
    // extension is APPLICABLE, not merely when none is named. A source `func` that shares the name
    // and rejects the receiver falls through to the external scan exactly as an unnamed one does.
    func TryResolveExtensionMethod(targetType: TypeInfo, methodName: string, currentTypeName: string?): TypeInfo {
        matchingExtensions := new List<FunctionDeclaration>()
        for candidate in extensionMethods {
            if candidate.Name == methodName {
                matchingExtensions.Add(candidate)
            }
        }

        if matchingExtensions.Count == 0 {
            return ExternalExtensionMethodType(targetType, methodName)
        }

        applicableExtensions := new List<FunctionDeclaration>()
        for candidate in matchingExtensions {
            if candidate.Parameters.Count > 0 && IsExtensionReceiverApplicable(candidate, targetType) {
                applicableExtensions.Add(candidate)
            }
        }

        if applicableExtensions.Count == 0 {
            return ExternalExtensionMethodType(targetType, methodName)
        }

        if applicableExtensions.Count == 1 {
            return functionTypeFactory.CreateFromDeclaration(applicableExtensions[0], currentTypeName)
        }

        // Several source extensions claim the name; overload resolution picks between them later.
        functionTypes := new List<FunctionTypeInfo>()
        for applicableExtension in applicableExtensions {
            functionTypes.Add(functionTypeFactory.CreateFromDeclaration(applicableExtension, currentTypeName))
        }

        return NSharpMethodGroupInfoFactory.FromFunctions(functionTypes)
    }

    // Does this source extension accept this receiver?
    //
    // AN UNCONSTRAINED RECEIVER ACCEPTS EVERYTHING, AND MUST ANSWER BEFORE THE REFERENCE IS
    // RESOLVED. A first parameter spelled with the function's OWN type parameter is a placeholder,
    // not a type: resolving it would answer with whichever type happens to share that name in scope
    // — a real declaration called `T`, or `unknown` — and the extension would then be offered to the
    // wrong receivers or to none. The spelling is therefore checked against the declaration's type
    // parameter list first, and only a spelling that is NOT one of them is resolved.
    //
    // A RESOLVED RECEIVER MATCHES BY IDENTITY OR BY ASSIGNABILITY, IN THAT ORDER. Identity is the
    // exact-shape answer that assignability's conversions would also give but more expensively;
    // assignability is what admits an extension declared on a base type, an interface the receiver
    // implements, or a nullable/oblivious spelling of the same underlying type.
    func IsExtensionReceiverApplicable(candidate: FunctionDeclaration, targetType: TypeInfo): bool {
        if candidate.Parameters.Count == 0 {
            return false
        }

        receiverTypeReference := candidate.Parameters[0].Type
        simple := receiverTypeReference as SimpleTypeReference
        if simple != null && IsFunctionTypeParameter(candidate, simple.Name) {
            return true
        }

        typeParameters := candidate.TypeParameters
        constructedReceiver := receiverTypeReference as GenericTypeReference
        if constructedReceiver != null && typeParameters != null && typeParameters.Count > 0 {
            binder := genericCallBinder
            if binder == null {
                return false
            }

            let matchedReceiverType: TypeInfo? = null
            bindings := new Dictionary<string, TypeInfo>()
            if !binder.TryInferReceiverParameterBindings(
                receiverTypeReference,
                targetType,
                typeParameters,
                typeResolver,
                out matchedReceiverType,
                out bindings
            ) || matchedReceiverType == null {
                return false
            }

            functionType := functionTypeFactory.CreateFromDeclaration(candidate, null)
            parameterTypes := functionType.ParameterTypes
            if parameterTypes == null || parameterTypes.Count == 0 {
                return false
            }

            closedReceiverType := AnalyzerSyntheticCallFacts.ApplyGenericBindings(
                parameterTypes[0],
                bindings,
                NullabilityGenericSubstitution.LiftedTypeParameterNames(functionType.GenericConstraints)
            )
            resolvedClosedReceiverType := declarationContext.ResolveDeclaredAlias(closedReceiverType)
            return TypeInfoIdentityFacts.AreEqual(resolvedClosedReceiverType, targetType) || assignability.IsAssignable(resolvedClosedReceiverType, targetType)
        }

        receiverType := typeResolver.ResolveType(receiverTypeReference)
        return TypeInfoIdentityFacts.AreEqual(receiverType, targetType) || assignability.IsAssignable(receiverType, targetType)
    }

    // A declaration with NO type parameter list at all is not a generic function, so no spelling can
    // be one of its type parameters.
    static func IsFunctionTypeParameter(candidate: FunctionDeclaration, name: string): bool {
        typeParameters := candidate.TypeParameters
        if typeParameters == null {
            return false
        }

        for typeParameter in typeParameters {
            if typeParameter.Name == name {
                return true
            }
        }

        return false
    }

    // Told about, not constructed here, and optional: a harness that asks what `.Select()` resolves
    // to is not answering NL010.
    func SetImportUsageCredit(credit: AnalyzerImportUsageCredit?) {
        importUsageCredit = credit
    }

    // The external answer, in the shape the member surface expects: one method is a method INFO,
    // several are a method GROUP, none is `unknown`.
    //
    // THIS IS THE IMPORT THAT `import System.Linq` IS FOR, AND IT IS THE ONLY CHANNEL THAT SEES IT.
    // A file whose whole use of a namespace is `.Where(...).Select(...)` writes none of that
    // namespace's type names anywhere, so the type-position walk credits nothing and the import would
    // read as dead. What is credited is the DECLARING type's namespace — `Enumerable`'s, not the
    // receiver's — because that is the namespace the extension had to be imported from.
    func ExternalExtensionMethodType(targetType: TypeInfo, methodName: string): TypeInfo {
        externalExtensions := FindExternalExtensionMethods(targetType, methodName)
        if externalExtensions.Count == 1 {
            winner := externalExtensions[0]
            CreditExtensionNamespace(winner)
            return new ReflectionMethodInfo(winner, winner.Name + "(...)")
        }

        if externalExtensions.Count > 1 {
            first := externalExtensions[0]
            for externalExtension in externalExtensions {
                CreditExtensionNamespace(externalExtension)
            }

            return new ReflectionMethodGroupInfo(externalExtensions.ToArray(), first.Name + "(...)")
        }

        return BuiltInTypes.Unknown
    }

    func CreditExtensionNamespace(method: MethodInfo) {
        credit := importUsageCredit
        if credit != null {
            credit.CreditDeclaringNamespace(method.DeclaringType)
        }
    }

    // Every `[Extension]` static under an IMPORTED namespace whose receiver parameter accepts the
    // target, in assembly then type then method order — the order the caller's method group keeps.
    //
    // THE EXACT CONVERSION AND THE BINDING CONVERSION ARE NOT INTERCHANGEABLE. When the receiver
    // converts exactly, that CLR type is the receiver and the scan runs. When it does not, the
    // binding conversion supplies only a SURROGATE — a stand-in whose instance surface was never
    // searched on the receiver's behalf — so an instance method of the same name must still win, and
    // the scan is abandoned rather than allowed to answer with an extension that would hide it.
    func FindExternalExtensionMethods(targetType: TypeInfo, methodName: string): List<MethodInfo> {
        exactClrType := clrTypeConversion.TryConvertTypeInfoToClrType(targetType)
        if exactClrType != null {
            return ScanExternalExtensionMethods(exactClrType, methodName)
        }

        bindingClrType := clrTypeConversion.TryConvertTypeInfoToClrTypeForBinding(targetType)
        if bindingClrType == null {
            return new List<MethodInfo>()
        }

        if declarationContext.HasRuntimeInstanceMethod(bindingClrType, methodName) {
            return new List<MethodInfo>()
        }

        return ScanExternalExtensionMethods(bindingClrType, methodName)
    }

    // An unresolved member can still be supplied by an SDK/global import which is absent from the
    // source import list. The analyzer's normal binder remains import-scoped; this broader question
    // only protects NL303. A complete framework or project reference set with a complete host scan
    // and no compatible candidate proves the name absent. An open set does not.
    func ExtensionSearchCannotProveNoCandidate(targetType: TypeInfo, methodName: string): bool {
        EnsureExtensionHosts()
        reflection := targetType as ReflectionTypeInfo
        exactClrType: Type? = null
        if reflection != null {
            exactClrType = reflection.Type
        } else {
            exactClrType = clrTypeConversion.TryConvertTypeInfoToClrType(targetType)
        }

        if exactClrType == null {
            return !referenceSetComplete || !extensionHostSurfaceComplete
        }

        candidates := ScanExternalExtensionMethodsAnyNamespace(exactClrType, methodName)
        if candidates.Count > 0 {
            return true
        }

        // A framework member surface is complete from the common reference table. Other external
        // types need the project's loaded reference closure before an absent extension can be
        // ruled out. An incomplete type scan remains conservative in either case.
        assemblyName := exactClrType.Assembly.GetName().Name ?? ""
        frameworkType := commonReferenceAssemblyNames.Contains(assemblyName)
        return (!referenceSetComplete && !frameworkType) || !extensionHostSurfaceComplete
    }

    private func ScanExternalExtensionMethodsAnyNamespace(targetClrType: Type, methodName: string): List<MethodInfo> {
        EnsureExtensionHosts()
        ValidateExtensionScanMemo()
        memoKey := (Name: methodName, Receiver: targetClrType)
        remembered: List<MethodInfo>? = null
        if extensionScanAnyNamespaceMemo.TryGetValue(memoKey, out remembered) && remembered != null {
            return new List<MethodInfo>(remembered)
        }

        methods := new List<MethodInfo>()
        for candidate in extensionHosts {
            hostType := candidate.HostType
            if IsNameableHost(hostType) {
                CollectExtensionMethods(hostType, HostMemberFlags(hostType), methodName, targetClrType, methods, friendGrants)
            }
        }

        extensionScanAnyNamespaceMemo[memoKey] = new List<MethodInfo>(methods)
        return methods
    }

    // The DECLARED types of every reference assembly, not the exported ones. An extension declared
    // on an INTERNAL static class is a candidate the exported surface would silently drop.
    // EVERY READ HERE IS OVER A TYPE THE PROJECT MERELY REFERENCES, so every one of them goes
    // through `AnalyzerReflectionMemberProbe`. A referenced assembly is not a promise that its whole
    // closure is present — `System.Reactive` carries signatures over WPF types and `WindowsBase`
    // does not exist on macOS — and materialising such a signature throws. The scan must answer
    // "this host offers no extension of that name", not end the analysis.
    // A HOST THIS COMPILATION CANNOT NAME OFFERS NOTHING. The scan reads DECLARED types rather than
    // exported ones because an extension declared on an `internal static class` is a real candidate
    // — but only for a compilation the declaring assembly named a friend. Without that test the scan
    // offered every reference's internal hosts to everybody, which is the same unsoundness the
    // metadata type probe had. `IsNameableType` is the one rule both ask.
    func ScanExternalExtensionMethods(targetClrType: Type, methodName: string): List<MethodInfo> {
        EnsureExtensionHosts()
        ValidateExtensionScanMemo()
        memoKey := (Name: methodName, Receiver: targetClrType)
        remembered: List<MethodInfo>? = null
        if extensionScanMemo.TryGetValue(memoKey, out remembered) && remembered != null {
            return new List<MethodInfo>(remembered)
        }

        methods := new List<MethodInfo>()
        for candidate in extensionHosts {
            hostType := candidate.HostType
            if usingNamespaces.Contains(candidate.Namespace) && IsNameableHost(hostType) {
                CollectExtensionMethods(hostType, HostMemberFlags(hostType), methodName, targetClrType, methods, friendGrants)
            }
        }

        extensionScanMemo[memoKey] = new List<MethodInfo>(methods)
        return methods
    }

    // Clears the scan's answers when any input they were computed under has changed (see
    // `extensionScanMemo`).
    private func ValidateExtensionScanMemo() {
        grantName := ""
        grants := friendGrants
        if grants != null {
            grantName = grants.CompilingAssemblyName
        }

        unchanged := extensionScanMemoHosts == extensionHostVersion && string.Equals(extensionScanMemoGrantName, grantName, StringComparison.Ordinal) && extensionScanMemoNamespaces.Count == usingNamespaces.Count
        index := 0
        while unchanged && index < usingNamespaces.Count {
            if !string.Equals(extensionScanMemoNamespaces[index], usingNamespaces[index], StringComparison.Ordinal) {
                unchanged = false
            }
            index = index + 1
        }
        if unchanged {
            return
        }

        extensionScanMemo.Clear()
        extensionScanAnyNamespaceMemo.Clear()
        extensionScanMemoNamespaces.Clear()
        extensionScanMemoNamespaces.AddRange(usingNamespaces)
        extensionScanMemoHosts = extensionHostVersion
        extensionScanMemoGrantName = grantName
    }

    // Brings `extensionHosts` up to the live assembly list: a static class is `sealed abstract` in
    // metadata, nothing else may declare an extension method, and a host with no namespace cannot be
    // imported -- so only those are kept, in the order the full scan visited them.
    private func EnsureExtensionHosts() {
        listChanged := extensionHostAssemblies > assemblies.Count || (extensionHostAssemblies > 0 && !Object.ReferenceEquals(assemblies[extensionHostAssemblies - 1], extensionHostLastAssembly))
        if listChanged {
            extensionHosts.Clear()
            extensionHostAssemblies = 0
            extensionHostLastAssembly = null
            extensionHostSurfaceComplete = true
            extensionHostVersion = extensionHostVersion + 1
        }

        while extensionHostAssemblies < assemblies.Count {
            assembly := assemblies[extensionHostAssemblies]
            assemblyComplete := true
            assemblyTypes := AssemblyTypesOrEmpty(assembly, out assemblyComplete)
            if !assemblyComplete {
                extensionHostSurfaceComplete = false
            }
            typeIndex := 0
            while typeIndex < assemblyTypes.Length {
                hostType := assemblyTypes[typeIndex]
                hostNamespace := AnalyzerReflectionMemberProbe.NamespaceOrNull(hostType)
                if hostNamespace != null && AnalyzerReflectionMemberProbe.IsStaticHostType(hostType) {
                    extensionHosts.Add(new AnalyzerExtensionHostCandidate(hostType, hostNamespace))
                }
                typeIndex = typeIndex + 1
            }
            extensionHostAssemblies = extensionHostAssemblies + 1
            extensionHostLastAssembly = assembly
            extensionHostVersion = extensionHostVersion + 1
        }
    }

    // The same analyzer instance handles every source file in one project. Cache each immutable
    // assembly type list for that lifetime: extension lookup can ask for a different method name at
    // every member access, but `Assembly.GetTypes()` answers the same metadata each time. Keeping the
    // cache on the project analyzer bounds its lifetime and avoids retaining every member project's
    // unique reference graph for the lifetime of a CLI or language-server process.
    private func AssemblyTypesOrEmpty(assembly: Assembly, out complete: bool): Type[] {
        let cached: Type[]? = null
        if assemblyTypes.TryGetValue(assembly, out cached) && cached != null {
            complete = !incompleteAssemblyTypeLists.Contains(assembly)
            return cached
        }

        loaded := AnalyzerReflectionMemberProbe.TypesOrEmpty(assembly, out complete)
        if !complete {
            incompleteAssemblyTypeLists.Add(assembly)
        }
        assemblyTypes[assembly] = loaded
        return loaded
    }

    func IsNameableHost(hostType: Type): bool {
        if friendGrants == null {
            return hostType.IsVisible
        }

        return friendGrants.IsNameableType(hostType)
    }

    // An `internal` extension METHOD of a public host is as reachable as an internal host, and for
    // the same reason, so the flags widen for a granting assembly and the level filter below decides
    // what that admits.
    func HostMemberFlags(hostType: Type): BindingFlags {
        if friendGrants != null && friendGrants.SameAssemblyOrFriend(hostType) {
            return BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static
        }

        return BindingFlags.Public | BindingFlags.Static
    }

    static func CollectExtensionMethods(hostType: Type, memberFlags: BindingFlags, methodName: string, targetClrType: Type, methods: List<MethodInfo>) {
        CollectExtensionMethods(hostType, memberFlags, methodName, targetClrType, methods, null)
    }

    static func CollectExtensionMethods(hostType: Type, memberFlags: BindingFlags, methodName: string, targetClrType: Type, methods: List<MethodInfo>, grants: InternalsVisibleToGrants?) {
        hostMethods := AnalyzerReflectionMemberProbe.MethodsOrEmpty(hostType, memberFlags)
        for method in hostMethods {
            if method.Name == methodName && AnalyzerMemberResolution.IsReachableReflectedMethod(method, false, grants) && AnalyzerOverloadFacts.HasExtensionAttribute(method) {
                // The RECEIVER parameter's type is the read that reaches the missing assembly. A
                // candidate whose receiver cannot be materialised is not a candidate.
                parameters := AnalyzerReflectionMemberProbe.ParametersOrNull(method)
                if parameters != null && parameters.Length > 0 {
                    receiverParameterType := AnalyzerReflectionMemberProbe.ParameterTypeOrNull(parameters[0])
                    if receiverParameterType != null && AnalyzerOverloadFacts.IsExtensionParameterCompatible(receiverParameterType, targetClrType) {
                        methods.Add(method)
                    }
                }
            }
        }
    }
}
