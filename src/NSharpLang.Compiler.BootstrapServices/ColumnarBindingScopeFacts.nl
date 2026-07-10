namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler

class ColumnarBindingNameSet {
    public Names: HashSet<string>

    constructor() {
        Names = new HashSet<string>(StringComparer.Ordinal)
    }
}

class ColumnarSourceBindingFacts {
    AliasNames: HashSet<string>
    UnaliasedNamespaceImports: List<string>
    UnaliasedFileImportPaths: List<string>
    ImportedNames: HashSet<string>
    DeclaredNames: HashSet<string>
    ExportedNames: HashSet<string>
    DeclaredTypeNames: HashSet<string>
    TypeAliasTargets: Dictionary<string, string>
    NestedNamesByOwner: Dictionary<string, ColumnarBindingNameSet>
    HasUnresolvedFileImport: bool
    HasPackageName: bool
    NamespaceName: string
    ScanComplete: bool

    constructor() {
        AliasNames = new HashSet<string>(StringComparer.Ordinal)
        UnaliasedNamespaceImports = new List<string>()
        UnaliasedFileImportPaths = new List<string>()
        ImportedNames = new HashSet<string>(StringComparer.Ordinal)
        DeclaredNames = new HashSet<string>(StringComparer.Ordinal)
        ExportedNames = new HashSet<string>(StringComparer.Ordinal)
        DeclaredTypeNames = new HashSet<string>(StringComparer.Ordinal)
        TypeAliasTargets = new Dictionary<string, string>(StringComparer.Ordinal)
        NestedNamesByOwner = new Dictionary<string, ColumnarBindingNameSet>(
            StringComparer.Ordinal)
        HasUnresolvedFileImport = false
        HasPackageName = false
        NamespaceName = ""
        ScanComplete = true
    }
}

class ColumnarTypeBindingFacts {
    IsInterface: bool
    IsReference: bool
    IsRecord: bool
    IsAmbiguous: bool

    constructor(isInterface: bool, isReference: bool, isRecord: bool) {
        IsInterface = isInterface
        IsReference = isReference
        IsRecord = isRecord
        IsAmbiguous = false
    }
}

class ColumnarExternalBaseBinding {
    Name: string
    SourceFileId: int

    constructor(name: string, sourceFileId: int) {
        Name = name
        SourceFileId = sourceFileId
    }
}

// Shared by the program scope and every file-specific view. Resolution is lazy and cached by
// source file and spelling, so later member and call owners can consume the same canonical
// assembly order without extending a feature whitelist.
class ColumnarExternalTypeCatalog {
    resolvedOwners: Dictionary<string, ExternalAssemblyTypeResolution>
    fileFactsById: Dictionary<int, ColumnarSourceBindingFacts>
    referenceAssemblyPaths: string[]
    IsPrepared: bool

    constructor() {
        resolvedOwners = new Dictionary<string, ExternalAssemblyTypeResolution>(
            StringComparer.Ordinal)
        fileFactsById = new Dictionary<int, ColumnarSourceBindingFacts>()
        referenceAssemblyPaths = new string[](0)
        IsPrepared = false
    }

    func Prepare(
        referenceAssemblyPaths: IReadOnlyList<string>?,
        sourceFactsById: Dictionary<int, ColumnarSourceBindingFacts>) {
        resolvedOwners.Clear()
        fileFactsById = sourceFactsById
        referenceCount := 0
        if referenceAssemblyPaths != null {
            referenceCount = referenceAssemblyPaths.Count
        }
        this.referenceAssemblyPaths = new string[](referenceCount)
        referenceIndex := 0
        while referenceIndex < referenceCount {
            this.referenceAssemblyPaths[referenceIndex] = referenceAssemblyPaths[referenceIndex]
            referenceIndex = referenceIndex + 1
        }

        // Signature emission resolves runtime Type handles before any expression planner asks
        // this catalog for an owner. Open the canonical scan once here so every exact runtime
        // implementation is admitted up front; owner lookup itself remains lazy and cached.
        preload := ExternalAssemblyScan.OpenWithReferences(this.referenceAssemblyPaths)
        preload.Dispose()
        IsPrepared = true
    }

    func TryGet(
        sourceFileId: int,
        ownerName: string,
        out resolution: ExternalAssemblyTypeResolution): bool {
        resolution = new ExternalAssemblyTypeResolution(
            ExternalAssemblyTypeLookupStatus.Unknown,
            "",
            typeof(object),
            false)
        if !IsPrepared || ownerName == null || ownerName.Length == 0 {
            return false
        }
        key := Key(sourceFileId, ownerName)
        if resolvedOwners.TryGetValue(key, out resolution) {
            return true
        }
        facts := new ColumnarSourceBindingFacts()
        if !fileFactsById.TryGetValue(sourceFileId, out facts)
            || !facts.ScanComplete {
            return false
        }

        scan := ExternalAssemblyScan.OpenWithReferences(referenceAssemblyPaths)
        try {
            resolution = ResolveOwner(scan, facts, ownerName)
            resolvedOwners[key] = resolution
        } finally {
            scan.Dispose()
        }
        return true
    }

    static func ResolveOwner(
        scan: ExternalAssemblyScanResult,
        facts: ColumnarSourceBindingFacts,
        ownerName: string): ExternalAssemblyTypeResolution {
        if ownerName.Contains(".") {
            resolution := ExternalAssemblyScan.FindExactOrNestedType(scan, ownerName)
            if resolution.Status != ExternalAssemblyTypeLookupStatus.Missing {
                return resolution
            }
        }
        importIndex := 0
        while importIndex < facts.UnaliasedNamespaceImports.Count {
            fullName := facts.UnaliasedNamespaceImports[importIndex]
                + "." + ownerName
            resolution := ExternalAssemblyScan.FindExactOrNestedType(scan, fullName)
            if resolution.Status != ExternalAssemblyTypeLookupStatus.Missing {
                return resolution
            }
            importIndex = importIndex + 1
        }
        return ExternalAssemblyScan.FindFirstVisibleType(scan, ownerName)
    }

    static func Key(sourceFileId: int, ownerName: string): string {
        return sourceFileId.ToString() + ":" + ownerName
    }
}

// Immutable program binding facts stamped onto every body node table. They are intentionally
// reusable across expression planners: C# never computes a shadowing boolean or reconstructs
// source/import/type scope inside an emitter.
public class ColumnarBindingScopeFacts {
    projectRoot: string
    sourceTypeNames: HashSet<string>
    exportedSourceTypeNames: HashSet<string>
    memberNamesByType: Dictionary<string, ColumnarBindingNameSet>
    currentLexicalNamesByType: Dictionary<string, ColumnarBindingNameSet>
    classBaseNameByType: Dictionary<string, string>
    externalBaseBindingByType: Dictionary<string, ColumnarExternalBaseBinding>
    invalidClassBaseOwners: HashSet<string>
    sourceTypeKindsByExactName: Dictionary<string, ColumnarTypeBindingFacts>
    fileFactsById: Dictionary<int, ColumnarSourceBindingFacts>
    activeImportAliasNames: HashSet<string>
    activeUnaliasedNamespaceImports: List<string>
    activeImportedNames: HashSet<string>
    activeDeclaredNames: HashSet<string>
    activeTypeAliasTargets: Dictionary<string, string>
    hasActiveUnresolvedFileImport: bool
    activeNamespaceName: string
    assemblyCatalog: ColumnarExternalTypeCatalog
    hasActiveFileFacts: bool
    activeSourceFileId: int
    sourceScanComplete: bool

    constructor() {
        projectRoot = Path.GetFullPath(".")
        sourceTypeNames = new HashSet<string>(StringComparer.Ordinal)
        exportedSourceTypeNames = new HashSet<string>(StringComparer.Ordinal)
        memberNamesByType = new Dictionary<string, ColumnarBindingNameSet>(StringComparer.Ordinal)
        currentLexicalNamesByType = new Dictionary<string, ColumnarBindingNameSet>(StringComparer.Ordinal)
        classBaseNameByType = new Dictionary<string, string>(StringComparer.Ordinal)
        externalBaseBindingByType = new Dictionary<string, ColumnarExternalBaseBinding>(
            StringComparer.Ordinal)
        invalidClassBaseOwners = new HashSet<string>(StringComparer.Ordinal)
        sourceTypeKindsByExactName = new Dictionary<string, ColumnarTypeBindingFacts>(StringComparer.Ordinal)
        fileFactsById = new Dictionary<int, ColumnarSourceBindingFacts>()
        activeImportAliasNames = new HashSet<string>(StringComparer.Ordinal)
        activeUnaliasedNamespaceImports = new List<string>()
        activeImportedNames = new HashSet<string>(StringComparer.Ordinal)
        activeDeclaredNames = new HashSet<string>(StringComparer.Ordinal)
        activeTypeAliasTargets = new Dictionary<string, string>(StringComparer.Ordinal)
        hasActiveUnresolvedFileImport = false
        activeNamespaceName = ""
        assemblyCatalog = new ColumnarExternalTypeCatalog()
        hasActiveFileFacts = false
        activeSourceFileId = -1
        sourceScanComplete = true
    }

    public static func Create(
        sources: ColumnarSourceFile[],
        enums: IReadOnlyList<ColumnarEnumInput>,
        structs: IReadOnlyList<ColumnarStructInput>,
        unions: IReadOnlyList<ColumnarUnionInput>,
        interfaces: IReadOnlyList<ColumnarInterfaceInput>,
        projectRootValue: string? = null): ColumnarBindingScopeFacts {
        if sources == null || enums == null || structs == null || unions == null
            || interfaces == null {
            throw new InvalidOperationException(
                "Binding-scope inputs cannot be null.")
        }

        result := new ColumnarBindingScopeFacts()
        result.projectRoot = ResolveProjectRoot(sources, projectRootValue)
        for sourceFile in sources {
            if sourceFile == null || sourceFile.Source == null
                || result.fileFactsById.ContainsKey(sourceFile.FileId) {
                result.sourceScanComplete = false
                continue
            }
            fileFacts := new ColumnarSourceBindingFacts()
            result.fileFactsById.Add(sourceFile.FileId, fileFacts)
            if !result.CollectSourceNames(sourceFile.Source, fileFacts) {
                fileFacts.ScanComplete = false
                result.sourceScanComplete = false
            } else {
                for sourceTypeName in fileFacts.DeclaredTypeNames {
                    exactSourceTypeName := sourceTypeName
                    if fileFacts.NamespaceName.Length > 0 {
                        exactSourceTypeName = fileFacts.NamespaceName
                            + "." + sourceTypeName
                    }
                    result.AddSourceType(exactSourceTypeName)
                    if fileFacts.ExportedNames.Contains(sourceTypeName) {
                        result.exportedSourceTypeNames.Add(exactSourceTypeName)
                    }
                }
            }
        }
        result.ResolveFileImports(sources)

        enumIndex := 0
        while enumIndex < enums.Count {
            result.AddSourceType(
                result.ExactTypeNameForFile(
                    enums[enumIndex].Name, enums[enumIndex].SourceFileId))
            enumIndex = enumIndex + 1
        }

        unionIndex := 0
        while unionIndex < unions.Count {
            unionInput := unions[unionIndex]
            result.AddSourceType(
                result.ExactTypeNameForFile(
                    unionInput.Name, unionInput.SourceFileId))
            unionIndex = unionIndex + 1
        }

        structIndex := 0
        while structIndex < structs.Count {
            result.RegisterStructKind(structs[structIndex])
            result.AddSourceType(
                result.ExactTypeNameForFile(
                    structs[structIndex].Name, structs[structIndex].SourceFileId))
            result.AddStructScope(structs[structIndex])
            structIndex = structIndex + 1
        }

        interfaceIndex := 0
        while interfaceIndex < interfaces.Count {
            result.RegisterInterfaceKind(interfaces[interfaceIndex])
            result.AddSourceType(
                result.ExactTypeNameForFile(
                    interfaces[interfaceIndex].Name,
                    interfaces[interfaceIndex].SourceFileId))
            result.AddInterfaceScope(interfaces[interfaceIndex])
            interfaceIndex = interfaceIndex + 1
        }
        structIndex = 0
        while structIndex < structs.Count {
            result.AddClassBaseScope(structs[structIndex])
            structIndex = structIndex + 1
        }
        return result
    }

    // Alias and namespace-import binding is file scoped. ProgramInput retains the shared immutable
    // source/member graph, but stamps each body with this view selected by its SourceFileId.
    public func ForSourceFile(sourceFileId: int): ColumnarBindingScopeFacts {
        view := new ColumnarBindingScopeFacts()
        view.projectRoot = projectRoot
        view.sourceTypeNames = sourceTypeNames
        view.exportedSourceTypeNames = exportedSourceTypeNames
        view.memberNamesByType = memberNamesByType
        view.currentLexicalNamesByType = currentLexicalNamesByType
        view.classBaseNameByType = classBaseNameByType
        view.externalBaseBindingByType = externalBaseBindingByType
        view.invalidClassBaseOwners = invalidClassBaseOwners
        view.sourceTypeKindsByExactName = sourceTypeKindsByExactName
        view.fileFactsById = fileFactsById
        view.sourceScanComplete = sourceScanComplete

        fileFacts := new ColumnarSourceBindingFacts()
        if fileFactsById.TryGetValue(sourceFileId, out fileFacts) {
            view.activeImportAliasNames = fileFacts.AliasNames
            view.activeUnaliasedNamespaceImports = fileFacts.UnaliasedNamespaceImports
            view.activeImportedNames = fileFacts.ImportedNames
            view.activeDeclaredNames = fileFacts.DeclaredNames
            view.activeTypeAliasTargets = fileFacts.TypeAliasTargets
            view.hasActiveUnresolvedFileImport = fileFacts.HasUnresolvedFileImport
            view.activeNamespaceName = fileFacts.NamespaceName
            view.assemblyCatalog = assemblyCatalog
            view.hasActiveFileFacts = true
            view.activeSourceFileId = sourceFileId
            if !fileFacts.ScanComplete {
                view.sourceScanComplete = false
            }
        } else {
            view.sourceScanComplete = false
        }
        return view
    }

    public func PrepareExternalTypeBindings(
        referenceAssemblyPaths: IReadOnlyList<string>?) {
        assemblyCatalog.Prepare(
            referenceAssemblyPaths,
            fileFactsById)
    }

    public UnaliasedNamespaceImportCount: int =>
        activeUnaliasedNamespaceImports.Count

    public func UnaliasedNamespaceImportAt(index: int): string {
        return activeUnaliasedNamespaceImports[index]
    }

    public func ExactTypeNameForFile(name: string, sourceFileId: int): string {
        if name == null || name.Length == 0 || name.Contains(".") {
            return name
        }
        facts := new ColumnarSourceBindingFacts()
        if fileFactsById.TryGetValue(sourceFileId, out facts)
            && facts.NamespaceName.Length > 0 {
            return facts.NamespaceName + "." + name
        }
        return name
    }

    // Mirrors Analyzer.TryResolveExternalType: ordered namespace imports first, then the first
    // simple/full-name match in deterministic assembly order. An incomplete reference scan cannot
    // prove identity and therefore declines.
    public func TryResolveExternalType(
        ownerName: string,
        expectedDeclaringTypeIdentity: string,
        out expectedDeclaringType: Type): bool {
        expectedDeclaringType = typeof(object)
        builtinType := typeof(object)
        if TryResolveBuiltinOwner(ownerName, out builtinType) {
            if ExternalAssemblyScan.HasExactTypeIdentity(
                    builtinType, expectedDeclaringTypeIdentity) {
                expectedDeclaringType = builtinType
                return true
            }
            return false
        }
        resolution := new ExternalAssemblyTypeResolution(
            ExternalAssemblyTypeLookupStatus.Unknown,
            "",
            typeof(object),
            false)
        if !hasActiveFileFacts || activeSourceFileId < 0
            || !sourceScanComplete || !assemblyCatalog.IsPrepared
            || ownerName == null || ownerName.Length == 0
            || expectedDeclaringTypeIdentity == null
            || expectedDeclaringTypeIdentity.Length == 0
            || !assemblyCatalog.TryGet(
                activeSourceFileId, ownerName, out resolution) {
            return false
        }
        if resolution.Status == ExternalAssemblyTypeLookupStatus.Found
            && resolution.HasRuntimeType
            && ExternalAssemblyScan.SemanticIdentityMatches(
                resolution.SemanticTypeIdentity,
                expectedDeclaringTypeIdentity) {
            expectedDeclaringType = resolution.RuntimeType
            return true
        }

        expectedRuntimeType := Type.GetType(expectedDeclaringTypeIdentity)
        if expectedRuntimeType == null || !expectedRuntimeType.get_IsGenericType() {
            return false
        }
        genericArguments := expectedRuntimeType.GetGenericArguments()
        genericResolution := new ExternalAssemblyTypeResolution(
            ExternalAssemblyTypeLookupStatus.Unknown,
            "",
            typeof(object),
            false)
        if !assemblyCatalog.TryGet(
                activeSourceFileId,
                ownerName + "`" + genericArguments.Length.ToString(),
                out genericResolution)
            || genericResolution.Status != ExternalAssemblyTypeLookupStatus.Found
            || !genericResolution.HasRuntimeType
            || genericResolution.RuntimeType
                != expectedRuntimeType.GetGenericTypeDefinition() {
            return false
        }
        expectedDeclaringType = expectedRuntimeType
        return true
    }

    public func TryResolveExternalStaticOwner(
        enclosingTypeName: string,
        visibleFunctionTypeParameterNames: string[],
        rootName: string,
        ownerName: string,
        expectedDeclaringTypeIdentity: string,
        out expectedDeclaringType: Type): bool {
        expectedDeclaringType = typeof(object)
        aliasTarget := ""
        if ownerName == rootName
            && activeTypeAliasTargets.TryGetValue(rootName, out aliasTarget) {
            if BlocksUnqualifiedRootCore(
                    enclosingTypeName,
                    visibleFunctionTypeParameterNames,
                    rootName,
                    true)
                || !TryResolveExternalCanonical(aliasTarget, out expectedDeclaringType)
                || !ExternalAssemblyScan.HasExactTypeIdentity(
                    expectedDeclaringType, expectedDeclaringTypeIdentity) {
                expectedDeclaringType = typeof(object)
                return false
            }
            return true
        }
        if BlocksQualifiedSourceOwner(ownerName)
            || BlocksUnqualifiedRootCore(
                enclosingTypeName,
                visibleFunctionTypeParameterNames,
                rootName,
                false) {
            return false
        }
        return TryResolveExternalType(
            ownerName, expectedDeclaringTypeIdentity, out expectedDeclaringType)
    }

    func BlocksQualifiedSourceOwner(ownerName: string): bool {
        candidate := ownerName
        while candidate.Contains(".") {
            if sourceTypeNames.Contains(candidate) {
                return true
            }
            separator := candidate.Length - 1
            while separator >= 0 && candidate[separator] != '.' {
                separator = separator - 1
            }
            if separator <= 0 {
                return false
            }
            candidate = candidate.Substring(0, separator)
        }
        return false
    }

    func TryResolveExternalCanonical(
        canonical: string,
        out runtimeType: Type): bool {
        runtimeType = typeof(object)
        if TryResolveBuiltinOwner(canonical, out runtimeType) {
            return true
        }
        genericStart := canonical.IndexOf("<", StringComparison.Ordinal)
        if genericStart > 0 && canonical.EndsWith(">", StringComparison.Ordinal) {
            arguments := ColumnarTypeCanonicalizer.SplitTopLevelCommas(
                canonical.Substring(
                    genericStart + 1,
                    canonical.Length - genericStart - 2))
            if arguments.Count == 0 {
                return false
            }
            argumentTypes := new Type[](arguments.Count)
            argumentIndex := 0
            while argumentIndex < arguments.Count {
                argumentType := typeof(object)
                if !TryResolveExternalCanonical(
                        arguments[argumentIndex],
                        out argumentType) {
                    return false
                }
                argumentTypes[argumentIndex] = argumentType
                argumentIndex = argumentIndex + 1
            }
            definition := new ExternalAssemblyTypeResolution(
                ExternalAssemblyTypeLookupStatus.Unknown,
                "",
                typeof(object),
                false)
            if !assemblyCatalog.TryGet(
                    activeSourceFileId,
                    canonical.Substring(0, genericStart)
                        + "`" + arguments.Count.ToString(),
                    out definition)
                || definition.Status != ExternalAssemblyTypeLookupStatus.Found
                || !definition.HasRuntimeType
                || !definition.RuntimeType.get_IsGenericTypeDefinition() {
                return false
            }
            runtimeType = definition.RuntimeType.MakeGenericType(argumentTypes)
            return true
        }
        resolution := new ExternalAssemblyTypeResolution(
            ExternalAssemblyTypeLookupStatus.Unknown,
            "",
            typeof(object),
            false)
        if !assemblyCatalog.TryGet(activeSourceFileId, canonical, out resolution)
            || resolution.Status != ExternalAssemblyTypeLookupStatus.Found
            || !resolution.HasRuntimeType {
            return false
        }
        runtimeType = resolution.RuntimeType
        return true
    }

    static func TryResolveBuiltinOwner(name: string, out runtimeType: Type): bool {
        runtimeType = typeof(object)
        if name == "int" || name == "Int32" || name == "System.Int32" { runtimeType = typeof(int) }
        else if name == "long" || name == "Int64" || name == "System.Int64" { runtimeType = typeof(long) }
        else if name == "uint" || name == "UInt32" || name == "System.UInt32" { runtimeType = typeof(uint) }
        else if name == "ulong" || name == "UInt64" || name == "System.UInt64" { runtimeType = typeof(ulong) }
        else if name == "short" || name == "Int16" || name == "System.Int16" { runtimeType = typeof(short) }
        else if name == "ushort" || name == "UInt16" || name == "System.UInt16" { runtimeType = typeof(ushort) }
        else if name == "byte" || name == "Byte" || name == "System.Byte" { runtimeType = typeof(byte) }
        else if name == "sbyte" || name == "SByte" || name == "System.SByte" { runtimeType = typeof(sbyte) }
        else { return false }
        return true
    }

    public func BlocksUnqualifiedRoot(
        enclosingTypeName: string,
        visibleFunctionTypeParameterNames: string[],
        rootName: string): bool {
        return BlocksUnqualifiedRootCore(
            enclosingTypeName,
            visibleFunctionTypeParameterNames,
            rootName,
            false)
    }

    func BlocksUnqualifiedRootCore(
        enclosingTypeName: string,
        visibleFunctionTypeParameterNames: string[],
        rootName: string,
        allowMatchingTypeAlias: bool): bool {
        if !sourceScanComplete || !hasActiveFileFacts
            || hasActiveUnresolvedFileImport || rootName.Length == 0
            || activeImportedNames.Contains(rootName)
            || BlocksSourceType(rootName, allowMatchingTypeAlias)
            || activeImportAliasNames.Contains(rootName)
            || ContainsName(visibleFunctionTypeParameterNames, rootName) {
            return true
        }

        if enclosingTypeName.Length == 0 {
            return false
        }

        if currentLexicalNamesByType.ContainsKey(enclosingTypeName)
            && currentLexicalNamesByType[enclosingTypeName].Names.Contains(rootName) {
            return true
        }

        pending := new List<string>()
        visited := new HashSet<string>(StringComparer.Ordinal)
        pending.Add(enclosingTypeName)
        index := 0
        while index < pending.Count {
            typeName := pending[index]
            index = index + 1
            if !visited.Add(typeName) {
                continue
            }
            if invalidClassBaseOwners.Contains(typeName) {
                return true
            }
            if memberNamesByType.ContainsKey(typeName)
                && memberNamesByType[typeName].Names.Contains(rootName) {
                return true
            }
            if classBaseNameByType.ContainsKey(typeName) {
                pending.Add(classBaseNameByType[typeName])
            } else if externalBaseBindingByType.ContainsKey(typeName) {
                externalBase := externalBaseBindingByType[typeName]
                resolution := new ExternalAssemblyTypeResolution(
                    ExternalAssemblyTypeLookupStatus.Unknown,
                    "",
                    typeof(object),
                    false)
                if !assemblyCatalog.TryGet(
                        externalBase.SourceFileId,
                        externalBase.Name,
                        out resolution)
                    || resolution.Status != ExternalAssemblyTypeLookupStatus.Found
                    || !resolution.HasRuntimeType {
                    return true
                }
                if HasVisibleExternalMember(resolution.RuntimeType, rootName) {
                    return true
                }
            }
        }
        return false
    }

    func BlocksSourceType(
        rootName: string,
        allowMatchingTypeAlias: bool): bool {
        if allowMatchingTypeAlias
            && activeTypeAliasTargets.ContainsKey(rootName) {
            return false
        }
        if activeDeclaredNames.Contains(rootName) {
            return true
        }
        if activeNamespaceName.Length == 0
            && sourceTypeNames.Contains(rootName) {
            return true
        }
        if exportedSourceTypeNames.Contains(rootName) {
            return true
        }
        if activeNamespaceName.Length > 0
            && sourceTypeNames.Contains(activeNamespaceName + "." + rootName) {
            return true
        }
        importIndex := 0
        while importIndex < activeUnaliasedNamespaceImports.Count {
            importedName := activeUnaliasedNamespaceImports[importIndex]
                + "." + rootName
            if exportedSourceTypeNames.Contains(importedName) {
                return true
            }
            importIndex = importIndex + 1
        }
        return false
    }

    func AddStructScope(input: ColumnarStructInput) {
        exactName := ExactTypeNameForFile(input.Name, input.SourceFileId)
        members := GetOrAddNames(memberNamesByType, exactName)
        AddNames(members.Names, input.FieldNames)
        methodIndex := 0
        while methodIndex < input.Methods.Count {
            members.Names.Add(input.Methods[methodIndex].Name)
            methodIndex = methodIndex + 1
        }
        propertyIndex := 0
        while propertyIndex < input.Properties.Count {
            members.Names.Add(input.Properties[propertyIndex].Name)
            propertyIndex = propertyIndex + 1
        }
        lexical := GetOrAddNames(currentLexicalNamesByType, exactName)
        AddNames(lexical.Names, input.TypeParamNames)
        constructorIndex := 0
        while constructorIndex < input.Constructors.Count {
            constructor := input.Constructors[constructorIndex]
            if constructor.IsSynthesizedInitializer {
                AddNames(lexical.Names, constructor.Body.ParamNames)
            }
            constructorIndex = constructorIndex + 1
        }
        fileFacts := new ColumnarSourceBindingFacts()
        ownerShortName := ColumnarTypeCanonicalizer.UnqualifiedTypeName(input.Name)
        if fileFactsById.TryGetValue(input.SourceFileId, out fileFacts)
            && fileFacts.NestedNamesByOwner.ContainsKey(ownerShortName) {
            nestedNames := fileFacts.NestedNamesByOwner[ownerShortName]
            for nestedName in nestedNames.Names {
                members.Names.Add(nestedName)
            }
        }
    }

    func AddInterfaceScope(input: ColumnarInterfaceInput) {
        exactName := ExactTypeNameForFile(input.Name, input.SourceFileId)
        members := GetOrAddNames(memberNamesByType, exactName)
        AddNames(members.Names, input.MethodNames)
        AddNames(
            GetOrAddNames(currentLexicalNamesByType, exactName).Names,
            input.TypeParamNames)
    }

    func RegisterStructKind(input: ColumnarStructInput) {
        RegisterTypeKind(
            ExactTypeNameForFile(input.Name, input.SourceFileId),
            false,
            input.IsReference,
            input.IsRecord)
    }

    func RegisterInterfaceKind(input: ColumnarInterfaceInput) {
        RegisterTypeKind(
            ExactTypeNameForFile(input.Name, input.SourceFileId),
            true,
            true,
            false)
    }

    func RegisterTypeKind(
        name: string,
        isInterface: bool,
        isReference: bool,
        isRecord: bool) {
        if name.Length == 0 {
            sourceScanComplete = false
            return
        }
        existing := new ColumnarTypeBindingFacts(false, false, false)
        if sourceTypeKindsByExactName.TryGetValue(name, out existing) {
            existing.IsAmbiguous = true
            return
        }
        sourceTypeKindsByExactName.Add(
            name,
            new ColumnarTypeBindingFacts(
                isInterface, isReference, isRecord))
    }

    // Analyzer records the first colon-list entry as a class's lexical BaseClass even when that
    // entry is an interface. Later interface entries do not participate in unqualified lookup.
    func AddClassBaseScope(input: ColumnarStructInput) {
        if !input.IsReference || input.BaseNames.Length == 0 {
            return
        }
        ownerName := ExactTypeNameForFile(input.Name, input.SourceFileId)
        baseName := ResolveSourceBaseName(
            ownerName, input.SourceFileId, input.BaseNames[0])
        if baseName.Length == 0 {
            externalBaseBinding := new ColumnarExternalBaseBinding(
                input.BaseNames[0], input.SourceFileId)
            externalBaseBindingByType[ownerName] = externalBaseBinding
            return
        }
        baseKind := new ColumnarTypeBindingFacts(false, false, false)
        if !sourceTypeKindsByExactName.TryGetValue(baseName, out baseKind)
            || baseKind.IsAmbiguous || !baseKind.IsReference
            || String.Equals(ownerName, baseName, StringComparison.Ordinal) {
            invalidClassBaseOwners.Add(ownerName)
            return
        }
        classBaseNameByType[ownerName] = baseName
    }

    func ResolveSourceBaseName(
        ownerName: string,
        sourceFileId: int,
        baseName: string): string {
        if sourceTypeKindsByExactName.ContainsKey(baseName) {
            return baseName
        }
        separator := -1
        scan := ownerName.Length - 1
        while scan >= 0 && separator < 0 {
            if ownerName.Substring(scan, 1) == "." {
                separator = scan
            }
            scan--
        }
        if separator >= 0 {
            sameNamespace := ownerName.Substring(0, separator + 1) + baseName
            if sourceTypeKindsByExactName.ContainsKey(sameNamespace) {
                return sameNamespace
            }
        }
        fileFacts := new ColumnarSourceBindingFacts()
        if fileFactsById.TryGetValue(sourceFileId, out fileFacts) {
            importIndex := 0
            while importIndex < fileFacts.UnaliasedNamespaceImports.Count {
                importedName := fileFacts.UnaliasedNamespaceImports[importIndex]
                    + "." + baseName
                if sourceTypeKindsByExactName.ContainsKey(importedName) {
                    return importedName
                }
                importIndex = importIndex + 1
            }
        }
        if sourceTypeKindsByExactName.ContainsKey(baseName) {
            return baseName
        }
        return ""
    }

    func AddSourceType(name: string) {
        if name.Length > 0 {
            sourceTypeNames.Add(name)
        }
    }

    func CollectSourceNames(
        source: string,
        fileFacts: ColumnarSourceBindingFacts): bool {
        capacity := source.Length * 3 + 16
        rawKinds := new int[](capacity)
        rawStarts := new int[](capacity)
        rawLengths := new int[](capacity)
        compactKinds := new int[](capacity)
        compactStarts := new int[](capacity)
        compactLengths := new int[](capacity)
        counts := new int[](2)
        compactCount := TokenizeColumnarSourceInto(
            source,
            rawKinds,
            rawStarts,
            rawLengths,
            compactKinds,
            compactStarts,
            compactLengths,
            counts)
        if compactCount < 0 || compactCount > compactKinds.Length
            || counts[0] < 0 || counts[0] > rawKinds.Length {
            return false
        }

        braceDepth := 0
        bracketDepth := 0
        parenDepth := 0
        inWhereClause := false
        pendingOwner := ""
        currentOwner := ""
        ownerBraceDepth := 0
        pendingVisibilityModifiers := 0
        index := 0
        while index < compactCount {
            kind := compactKinds[index]
            atTopLevel := braceDepth == 0 && bracketDepth == 0
                && parenDepth == 0
            if atTopLevel {
                visibilityFlag := VisibilityModifierFlag(kind)
                if visibilityFlag != 0 {
                    pendingVisibilityModifiers = pendingVisibilityModifiers | visibilityFlag
                }
            }
            if atTopLevel && kind == 17 {
                CollectImportFacts(
                    source,
                    compactKinds,
                    compactStarts,
                    compactLengths,
                    compactCount,
                    index,
                    fileFacts)
                pendingVisibilityModifiers = 0
            }
            if atTopLevel && (kind == 15 || kind == 18) {
                CollectNamespaceFact(
                    source,
                    compactKinds,
                    compactStarts,
                    compactLengths,
                    compactCount,
                    index,
                    kind == 18,
                    fileFacts)
                pendingVisibilityModifiers = 0
            }
            if atTopLevel && kind == 53 {
                inWhereClause = true
            } else if atTopLevel && kind == 120 {
                inWhereClause = false
            } else if !inWhereClause && IsTypeDeclarationKeyword(kind)
                && !IsRecordStructTailToken(compactKinds, index) {
                nameIndex := index + 1
                if kind == 13 && nameIndex < compactCount
                    && compactKinds[nameIndex] == 9 {
                    nameIndex = nameIndex + 1
                }
                if nameIndex < compactCount && compactKinds[nameIndex] == 0 {
                    declarationName := source.Substring(
                        compactStarts[nameIndex], compactLengths[nameIndex])
                    if atTopLevel {
                        fileFacts.DeclaredNames.Add(declarationName)
                        fileFacts.DeclaredTypeNames.Add(declarationName)
                        if kind == Convert.ToInt32(TokenType.Type)
                            && !CollectTypeAliasFact(
                                source,
                                compactKinds,
                                compactStarts,
                                compactLengths,
                                compactCount,
                                nameIndex,
                                declarationName,
                                fileFacts) {
                            return false
                        }
                        if VisibilityConventions.IsExportedIdentifier(
                            declarationName, pendingVisibilityModifiers) {
                            fileFacts.ExportedNames.Add(declarationName)
                        }
                        pendingOwner = declarationName
                        pendingVisibilityModifiers = 0
                    } else if currentOwner.Length > 0 {
                        nestedNames := GetOrAddNames(
                            fileFacts.NestedNamesByOwner, currentOwner)
                        nestedNames.Names.Add(declarationName)
                    }
                }
            }
            if atTopLevel && kind == 7 && index + 1 < compactCount
                && compactKinds[index + 1] == 0 {
                declarationName := source.Substring(
                    compactStarts[index + 1], compactLengths[index + 1])
                fileFacts.DeclaredNames.Add(declarationName)
                if VisibilityConventions.IsExportedIdentifier(
                    declarationName, pendingVisibilityModifiers) {
                    fileFacts.ExportedNames.Add(declarationName)
                }
                pendingVisibilityModifiers = 0
            }

            if kind == 129 {
                if atTopLevel && pendingOwner.Length > 0 {
                    currentOwner = pendingOwner
                    ownerBraceDepth = braceDepth + 1
                    pendingOwner = ""
                }
                braceDepth = braceDepth + 1
                inWhereClause = false
            } else if kind == 130 {
                braceDepth = braceDepth - 1
                if braceDepth < 0 {
                    braceDepth = 0
                }
                if currentOwner.Length > 0 && braceDepth < ownerBraceDepth {
                    currentOwner = ""
                    ownerBraceDepth = 0
                }
            } else if kind == 131 {
                bracketDepth = bracketDepth + 1
            } else if kind == 132 {
                bracketDepth = bracketDepth - 1
                if bracketDepth < 0 {
                    bracketDepth = 0
                }
            } else if kind == 127 {
                parenDepth = parenDepth + 1
            } else if kind == 128 {
                parenDepth = parenDepth - 1
                if parenDepth < 0 {
                    parenDepth = 0
                }
            }
            index = index + 1
        }
        return true
    }

    static func CollectTypeAliasFact(
        source: string,
        kinds: int[],
        starts: int[],
        lengths: int[],
        count: int,
        nameIndex: int,
        aliasName: string,
        fileFacts: ColumnarSourceBindingFacts): bool {
        assignIndex := nameIndex + 1
        targetIndex := nameIndex + 2
        if targetIndex >= count
            || kinds[assignIndex] != Convert.ToInt32(TokenType.Assign) {
            return false
        }
        tokens := new ParserDeclarationTokenTable(kinds, starts, lengths)
        result := new ParserDeclarationResultTable(new int[](2))
        if ParseDeclarationTypeSpanCore(tokens, count, targetIndex, result) < 0 {
            return false
        }
        canonical := ParserDeclarationCanonicalTypeText(
            source, result.Values[0], result.Values[1])
        if canonical.Length == 0 || fileFacts.TypeAliasTargets.ContainsKey(aliasName) {
            return false
        }
        fileFacts.TypeAliasTargets.Add(aliasName, canonical)
        return true
    }

    func CollectImportFacts(
        source: string,
        kinds: int[],
        starts: int[],
        lengths: int[],
        count: int,
        importIndex: int,
        fileFacts: ColumnarSourceBindingFacts) {
        index := importIndex + 1
        isNamespaceImport := index < count && kinds[index] == 0
        namespaceName := ""
        expectIdentifier := true
        while isNamespaceImport && index < count {
            if expectIdentifier && kinds[index] == 0 {
                if namespaceName.Length > 0 {
                    namespaceName = namespaceName + "."
                }
                namespaceName = namespaceName
                    + source.Substring(starts[index], lengths[index])
                expectIdentifier = false
                index = index + 1
                continue
            }
            if !expectIdentifier && kinds[index] == 124 {
                expectIdentifier = true
                index = index + 1
                continue
            }
            break
        }

        isFileImport := !isNamespaceImport && index < count && kinds[index] == 4
        fileImportPath := ""
        if isFileImport {
            fileImportPath = UnquoteStringLiteral(
                source.Substring(starts[index], lengths[index]))
            index = index + 1
        }

        if index < count && kinds[index] == 48
            && index + 1 < count && kinds[index + 1] == 0 {
            fileFacts.AliasNames.Add(
                source.Substring(starts[index + 1], lengths[index + 1]))
            return
        }
        if isNamespaceImport && namespaceName.Length > 0 && !expectIdentifier {
            fileFacts.UnaliasedNamespaceImports.Add(namespaceName)
        } else if isFileImport && fileImportPath.Length > 0 {
            fileFacts.UnaliasedFileImportPaths.Add(fileImportPath)
        } else if isFileImport {
            fileFacts.HasUnresolvedFileImport = true
        }
    }

    func CollectNamespaceFact(
        source: string,
        kinds: int[],
        starts: int[],
        lengths: int[],
        count: int,
        namespaceIndex: int,
        isPackage: bool,
        fileFacts: ColumnarSourceBindingFacts) {
        index := namespaceIndex + 1
        namespaceName := ""
        expectIdentifier := true
        while index < count {
            if expectIdentifier && kinds[index] == 0 {
                if namespaceName.Length > 0 {
                    namespaceName = namespaceName + "."
                }
                namespaceName = namespaceName
                    + source.Substring(starts[index], lengths[index])
                expectIdentifier = false
                index = index + 1
                continue
            }
            if !expectIdentifier && kinds[index] == 124 {
                expectIdentifier = true
                index = index + 1
                continue
            }
            break
        }
        if namespaceName.Length == 0 || expectIdentifier {
            fileFacts.ScanComplete = false
            return
        }
        if isPackage {
            if fileFacts.HasPackageName
                && fileFacts.NamespaceName != namespaceName {
                fileFacts.ScanComplete = false
                return
            }
            fileFacts.NamespaceName = namespaceName
            fileFacts.HasPackageName = true
            return
        }
        if !fileFacts.HasPackageName {
            if fileFacts.NamespaceName.Length > 0
                && fileFacts.NamespaceName != namespaceName {
                fileFacts.ScanComplete = false
                return
            }
            fileFacts.NamespaceName = namespaceName
        }
    }

    func ResolveFileImports(sources: ColumnarSourceFile[]) {
        factsByPath := new Dictionary<string, ColumnarSourceBindingFacts>(
            StringComparer.OrdinalIgnoreCase)
        index := 0
        while index < sources.Length {
            sourceFile := sources[index]
            facts := new ColumnarSourceBindingFacts()
            if sourceFile == null || !fileFactsById.TryGetValue(
                sourceFile.FileId, out facts) {
                sourceScanComplete = false
                index = index + 1
                continue
            }
            if sourceFile.FileName.Length == 0 {
                index = index + 1
                continue
            }
            fullPath := Path.GetFullPath(sourceFile.FileName)
            if factsByPath.ContainsKey(fullPath) {
                sourceScanComplete = false
            } else {
                factsByPath[fullPath] = facts
            }
            index = index + 1
        }

        index = 0
        while index < sources.Length {
            sourceFile := sources[index]
            facts := new ColumnarSourceBindingFacts()
            if sourceFile == null || !fileFactsById.TryGetValue(
                sourceFile.FileId, out facts) {
                index = index + 1
                continue
            }
            if facts.UnaliasedFileImportPaths.Count == 0 {
                index = index + 1
                continue
            }
            if sourceFile.FileName.Length == 0 {
                facts.HasUnresolvedFileImport = true
                index = index + 1
                continue
            }
            sourcePath := Path.GetFullPath(sourceFile.FileName)
            resolver := new FileResolver(projectRoot, sourcePath)
            importIndex := 0
            while importIndex < facts.UnaliasedFileImportPaths.Count {
                importPath := resolver.ResolveFilePath(
                    facts.UnaliasedFileImportPaths[importIndex])
                importedFacts := new ColumnarSourceBindingFacts()
                if factsByPath.TryGetValue(importPath, out importedFacts)
                    && importedFacts.ScanComplete {
                    for importedName in importedFacts.ExportedNames {
                        facts.ImportedNames.Add(importedName)
                    }
                } else {
                    facts.HasUnresolvedFileImport = true
                }
                importIndex = importIndex + 1
            }
            index = index + 1
        }
    }

    static func UnquoteStringLiteral(value: string): string {
        if value.Length >= 2 && value.StartsWith("\"", StringComparison.Ordinal)
            && value.EndsWith("\"", StringComparison.Ordinal) {
            return value.Substring(1, value.Length - 2)
        }
        return ""
    }

    static func ResolveProjectRoot(
        sources: ColumnarSourceFile[],
        projectRootValue: string?): string {
        if projectRootValue != null && projectRootValue.Length > 0 {
            return Path.GetFullPath(projectRootValue)
        }
        index := 0
        while index < sources.Length {
            sourceFile := sources[index]
            if sourceFile != null && sourceFile.FileName.Length > 0 {
                fullPath := Path.GetFullPath(sourceFile.FileName)
                directory := Path.GetDirectoryName(fullPath)
                if directory != null && directory.Length > 0 {
                    return directory
                }
            }
            index = index + 1
        }
        return Path.GetFullPath(".")
    }

    static func IsTypeDeclarationKeyword(kind: int): bool {
        return kind == 8 || kind == 9 || kind == 10 || kind == 12
            || kind == 13 || kind == 14 || kind == 72
    }

    static func VisibilityModifierFlag(kind: int): int {
        if kind == Convert.ToInt32(TokenType.Public) { return 1 }
        if kind == Convert.ToInt32(TokenType.Private) { return 2 }
        if kind == Convert.ToInt32(TokenType.Protected) { return 4 }
        if kind == Convert.ToInt32(TokenType.Internal) { return 8 }
        if kind == Convert.ToInt32(TokenType.File) { return 32768 }
        return 0
    }

    static func IsRecordStructTailToken(kinds: int[], index: int): bool {
        return kinds[index] == 9 && index > 0 && kinds[index - 1] == 13
    }

    static func GetOrAddNames(
        values: Dictionary<string, ColumnarBindingNameSet>,
        typeName: string): ColumnarBindingNameSet {
        if values.ContainsKey(typeName) {
            return values[typeName]
        }
        names := new ColumnarBindingNameSet()
        values[typeName] = names
        return names
    }

    static func AddNames(target: HashSet<string>, values: string[]) {
        index := 0
        while index < values.Length {
            if values[index].Length > 0 {
                target.Add(values[index])
            }
            index = index + 1
        }
    }

    static func ContainsName(values: string[], name: string): bool {
        index := 0
        while index < values.Length {
            if String.Equals(values[index], name, StringComparison.Ordinal) {
                return true
            }
            index = index + 1
        }
        return false
    }

    static func HasVisibleExternalMember(externalType: Type, name: string): bool {
        try {
            if externalType.GetField(name) != null
                || externalType.GetProperty(name) != null {
                return true
            }
            return externalType.GetMethod(name) != null
        } catch {
            return true
        }
    }
}
