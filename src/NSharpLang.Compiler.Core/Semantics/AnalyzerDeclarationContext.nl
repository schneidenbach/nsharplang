namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.CompilerServices
import NSharpLang.Compiler.Ast

class AnalyzerSourceTypeSelection {
    Type: TypeInfo
    Declaration: object?
    FilePath: string?
    Claimed: bool

    constructor(typeInfo: TypeInfo, declaration: object?, filePath: string?, claimed: bool) {
        Type = typeInfo
        Declaration = declaration
        FilePath = filePath
        Claimed = claimed
    }
}

class AnalyzerMemberSelection {
    Owner: TypeInfo
    Member: DeclaredMemberInfo?
    FilePath: string?
    Line: int
    Column: int
    KindName: string
    IsExported: bool

    constructor() {
        Owner = BuiltInTypes.Unknown
        Member = null
        FilePath = null
        Line = 0
        Column = 0
        KindName = ""
        IsExported = false
    }

    constructor(owner: TypeInfo, member: DeclaredMemberInfo?, filePath: string?, line: int, column: int, kindName: string, isExported: bool) {
        Owner = owner
        Member = member
        FilePath = filePath
        Line = line
        Column = column
        KindName = kindName
        IsExported = isExported
    }
}

class AnalyzerSourceMemberShape {
    Owner: TypeInfo
    DeclaredMembers: DeclaredMemberInfo[]
    PrimaryParameters: ParameterDeclarationInfo[]
    NestedTypes: NestedTypeInfo[]
    BaseType: TypeInfo?

    // THE INTERFACES THIS SHAPE INHERITS MEMBERS FROM, resolved and substituted, in written order.
    // A class has ONE base and an interface has MANY, so the two cannot share a slot: `BaseType` is
    // the single-inheritance chain every walk here already follows, and this is the fan-out beside
    // it. Empty for every form but `interface`, never null.
    BaseInterfaces: TypeInfo[]

    SupportsPrimaryParameters: bool
    SupportsObjectMembers: bool

    constructor() {
        Owner = BuiltInTypes.Unknown
        DeclaredMembers = new DeclaredMemberInfo[](0)
        PrimaryParameters = new ParameterDeclarationInfo[](0)
        NestedTypes = new NestedTypeInfo[](0)
        BaseType = null
        BaseInterfaces = new TypeInfo[](0)
        SupportsPrimaryParameters = false
        SupportsObjectMembers = false
    }

    constructor(owner: TypeInfo, declaredMembers: DeclaredMemberInfo[], primaryParameters: ParameterDeclarationInfo[], nestedTypes: NestedTypeInfo[], baseType: TypeInfo?, supportsPrimaryParameters: bool, supportsObjectMembers: bool, baseInterfaces: TypeInfo[]? = null) {
        Owner = owner
        DeclaredMembers = declaredMembers
        PrimaryParameters = primaryParameters
        NestedTypes = nestedTypes
        BaseType = baseType
        BaseInterfaces = baseInterfaces ?? new TypeInfo[](0)
        SupportsPrimaryParameters = supportsPrimaryParameters
        SupportsObjectMembers = supportsObjectMembers
    }
}

class AnalyzerNamespaceImportFacts {
    Namespace: string
    Alias: string?

    constructor(namespaceName: string, alias: string?) {
        Namespace = namespaceName
        Alias = alias
    }
}

class AnalyzerFileImportFacts {
    Path: string
    Alias: string?

    constructor(path: string, alias: string?) {
        Path = path
        Alias = alias
    }
}

class AnalyzerDeclarationFileFacts {
    FilePath: string
    NamespaceName: string?
    Declarations: IList
    NamespaceImports: List<AnalyzerNamespaceImportFacts>
    FileImports: List<AnalyzerFileImportFacts>

    constructor() {
        FilePath = ""
        NamespaceName = null
        Declarations = new List<object>()
        NamespaceImports = new List<AnalyzerNamespaceImportFacts>()
        FileImports = new List<AnalyzerFileImportFacts>()
    }

    constructor(filePath: string, unit: object) {
        FilePath = Path.GetFullPath(filePath)
        NamespaceName = GetUnitNamespace(unit)
        Declarations = TypeInfoFactoryReflection.GetRequiredList(unit, "Declarations")
        NamespaceImports = ReadNamespaceImports(unit)
        FileImports = ReadFileImports(unit)
    }

    static func GetUnitNamespace(unit: object): string? {
        packageValue := TypeInfoFactoryReflection.GetOptionalProperty(unit, "Package")
        if packageValue != null {
            nameValue := TypeInfoFactoryReflection.GetOptionalProperty(packageValue, "Name")
            packageName := nameValue as string
            if packageName != null {
                return packageName
            }
        }
        namespaceValue := TypeInfoFactoryReflection.GetOptionalProperty(unit, "Namespace")
        if namespaceValue == null {
            return null
        }
        nameValue := TypeInfoFactoryReflection.GetOptionalProperty(namespaceValue, "Name")
        return nameValue as string
    }

    static func ReadNamespaceImports(unit: object): List<AnalyzerNamespaceImportFacts> {
        result := new List<AnalyzerNamespaceImportFacts>()
        imports := TypeInfoFactoryReflection.GetRequiredList(unit, "Imports")
        for importValue in imports {
            if importValue != null {
                namespaceName := TypeInfoFactoryReflection.GetRequiredString(importValue, "Namespace")
                aliasValue := TypeInfoFactoryReflection.GetOptionalProperty(importValue, "Alias")
                result.Add(new AnalyzerNamespaceImportFacts(namespaceName, aliasValue as string))
            }
        }
        return result
    }

    static func ReadFileImports(unit: object): List<AnalyzerFileImportFacts> {
        result := new List<AnalyzerFileImportFacts>()
        imports := TypeInfoFactoryReflection.GetRequiredList(unit, "FileImports")
        for importValue in imports {
            if importValue != null && importValue.GetType().Name == "FileImport" {
                path := TypeInfoFactoryReflection.GetRequiredString(importValue, "Path")
                aliasValue := TypeInfoFactoryReflection.GetOptionalProperty(importValue, "Alias")
                result.Add(new AnalyzerFileImportFacts(path, aliasValue as string))
            }
        }
        return result
    }
}

// Canonical source declaration and declaration-context type resolution. The N# analyzer supplies
// already parsed units as opaque objects; all source binding policy and identity caches live here.
class AnalyzerDeclarationContext {
    projectRoot: string
    assemblies: List<Assembly>
    files: List<AnalyzerDeclarationFileFacts>
    filesByPath: Dictionary<string, AnalyzerDeclarationFileFacts>
    typesByFile: Dictionary<string, Dictionary<string, TypeInfo>>
    filesByType: Dictionary<object, string>
    containingTypes: Dictionary<object, TypeInfo>
    soaTypesByDeclaration: Dictionary<object, SoaRecordTypeInfo>
    externalTypes: Dictionary<string, TypeInfo>
    missingExternalTypes: HashSet<string>

    // The compilation's friend grants, or null for a context built without a project behind it.
    // A fully-qualified external spelling is nameable when it is visible OR when its assembly named
    // this compilation in an `InternalsVisibleTo`; the resolver below asks this object which.
    friendGrants: InternalsVisibleToGrants?

    // The import-usage ledger and the file it belongs to. This owner resolves names on behalf of
    // EVERY file in the project — a member's declared type is resolved against the file that declares
    // it — so a credit is only this file's when the facts being read are this file's.
    importUsageCredit: AnalyzerImportUsageCredit?
    importUsageFilePath: string?
    // Every TOP-LEVEL TYPE NAME the project declares, by arity key, built once per analysis on first
    // ask. NL002 needs it to answer one question — does this project declare a type of this name —
    // and answering it by walking every file's declarations per name would be quadratic.
    declaredTypeNames: HashSet<string>?

    // WHETHER THIS COMPILATION ACCEPTS THE EXPERIMENTAL `soa record` LOWERING. The analyzer decides it
    // ONCE, when it is built, from `NSHARP_EXPERIMENTAL_SOA` (`SoaFeature`), and every owner that
    // gates on the feature reads it here. A context built without an analyzer behind it accepts
    // nothing experimental; a caller that wants the feature says so on the context rather than
    // rewriting the process environment, which every other compilation in the process would read.
    soaEnabledValue: bool

    constructor() {
        projectRoot = Path.GetFullPath(".")
        assemblies = new List<Assembly>()
        files = new List<AnalyzerDeclarationFileFacts>()
        filesByPath = new Dictionary<string, AnalyzerDeclarationFileFacts>(StringComparer.OrdinalIgnoreCase)
        typesByFile = new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.OrdinalIgnoreCase)
        filesByType = new Dictionary<object, string>()
        containingTypes = new Dictionary<object, TypeInfo>()
        soaTypesByDeclaration = new Dictionary<object, SoaRecordTypeInfo>()
        externalTypes = new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
        missingExternalTypes = new HashSet<string>(StringComparer.Ordinal)
        importUsageCredit = null
        importUsageFilePath = null
        declaredTypeNames = null
        soaEnabledValue = false
    }

    SoaEnabled: bool => soaEnabledValue

    func SetSoaEnabled(enabled: bool) {
        soaEnabledValue = enabled
    }

    // One call per `Analyze`: which file is being analysed, and where its import-usage facts go.
    func SetImportUsageCredit(credit: AnalyzerImportUsageCredit?, filePath: string?) {
        importUsageCredit = credit
        importUsageFilePath = filePath
    }

    // WHETHER THE PROJECT ITSELF DECLARES A TYPE OF THIS NAME, at any arity and in any namespace.
    //
    // NL002 asks it before it reports: a spelling the project declares is not a missing import, even
    // when a referenced assembly happens to declare the same name. That case is not hypothetical —
    // a receiver position resolves through the external probe before it ever consults a SIBLING
    // FILE's declarations, so `Guard.Fail(...)` beside a source `class Guard` answered with a
    // metadata `Guard` from a referenced assembly, and NL002 would have told the author to import a
    // namespace their program does not use.
    func DeclaresTypeNamed(name: string): bool {
        cached := declaredTypeNames
        if cached == null {
            built := new HashSet<string>(StringComparer.Ordinal)
            for fileItem in files {
                declarations := fileItem.Declarations
                index := 0
                while index < declarations.Count {
                    candidate := declarations[index]
                    if candidate != null && IsTopLevelTypeDeclaration(candidate) {
                        declaredName := DeclarationFacts.GetDeclarationName(candidate)
                        if declaredName != null {
                            built.Add(declaredName ?? "")
                        }
                    }

                    index = index + 1
                }
            }

            declaredTypeNames = built
            return built.Contains(name)
        }

        names := cached ?? new HashSet<string>(StringComparer.Ordinal)
        return names.Contains(name)
    }

    // THE COMPILATION'S FRIEND GRANTS, handed in by the analyzer. A context with none grants
    // nothing, which is the behaviour every unit-built context already had.
    func SetFriendGrants(grants: InternalsVisibleToGrants?) {
        friendGrants = grants
    }

    func GetFriendGrants(): InternalsVisibleToGrants? {
        return friendGrants
    }

    func Reset(projectRootValue: string, assemblyValues: List<Assembly>) {
        projectRoot = Path.GetFullPath(projectRootValue)
        assemblies = assemblyValues
        files.Clear()
        filesByPath.Clear()
        typesByFile.Clear()
        filesByType.Clear()
        containingTypes.Clear()
        soaTypesByDeclaration.Clear()
        externalTypes.Clear()
        missingExternalTypes.Clear()
        declaredTypeNames = null
    }

    func AddCompilationUnit(filePath: string, unit: object) {
        declaredTypeNames = null
        fullPath := Path.GetFullPath(filePath)
        if filesByPath.ContainsKey(fullPath) {
            return
        }
        facts := new AnalyzerDeclarationFileFacts(fullPath, unit)
        files.Add(facts)
        filesByPath.Add(fullPath, facts)
        typesByFile.Add(fullPath, new Dictionary<string, TypeInfo>(StringComparer.Ordinal))
    }

    func ResolveTypeReference(typeReference: TypeReference, declarationFile: string, substitution: Dictionary<string, TypeInfo>? = null, lexicalOwner: TypeInfo? = null): TypeInfo {
        facts := FindFile(declarationFile)
        if facts == null {
            return BuiltInTypes.Unknown
        }
        activeAliases := new HashSet<string>(StringComparer.Ordinal)
        return ResolveTypeReferenceCore(typeReference, facts, activeAliases, substitution, lexicalOwner)
    }

    func TryResolveTypeForOwner(typeReference: TypeReference, declarationOwner: TypeInfo, substitution: Dictionary<string, TypeInfo>?, out resolved: TypeInfo): bool {
        declarationFile := ""
        if !filesByType.TryGetValue(declarationOwner, out declarationFile) {
            resolved = BuiltInTypes.Unknown
            return false
        }
        effectiveSubstitution := CreateOwnerOpenSubstitution(declarationOwner, substitution)
        resolved = ResolveTypeReference(typeReference, declarationFile, effectiveSubstitution, declarationOwner)
        return true
    }

    // Normalize a declared type alias — and the ObliviousTypeInfo wrapper, which is the other
    // transparent shell over a type — down to the type it actually names. This is the whole of
    // the analyzer's former ResolveTypeAlias: an alias answers the resolution of its aliased
    // type reference AGAINST ITS OWN DECLARING FILE, walked to a fixed point, and a cycle
    // answers `unknown`. Every other TypeInfo is its own answer.
    //
    // The alias arm is a pure declaration-context fact because the analyzer registers the
    // AliasTypeInfo instance it builds (RegisterDeclaredAlias); an alias this context does not
    // own is transparent to it and is returned unchanged.
    func ResolveDeclaredAlias(candidate: TypeInfo): TypeInfo {
        return ResolveDeclaredAliasCore(candidate, new HashSet<object>())
    }

    func ResolveDeclaredAliasCore(candidate: TypeInfo, activeAliases: HashSet<object>): TypeInfo {
        alias := candidate as AliasTypeInfo
        if alias != null {
            if !activeAliases.Add(alias) {
                return BuiltInTypes.Unknown
            }
            resolved := BuiltInTypes.Unknown as TypeInfo
            if !TryResolveTypeForOwner(alias.AliasedType, alias, null, out resolved) {
                return candidate
            }
            return ResolveDeclaredAliasCore(resolved, activeAliases)
        }
        oblivious := candidate as ObliviousTypeInfo
        if oblivious != null {
            return ResolveDeclaredAliasCore(oblivious.InnerType, activeAliases)
        }
        return candidate
    }

    func ResolveDeclarationType(declaration: object, filePath: string): TypeInfo {
        facts := FindFile(filePath)
        if facts == null {
            return BuiltInTypes.Unknown
        }
        return ResolveDeclarationTypeCore(declaration, facts, new HashSet<string>(StringComparer.Ordinal))
    }

    func TryResolveName(declarationFile: string, name: string, out selection: AnalyzerSourceTypeSelection): bool {
        facts := FindFile(declarationFile)
        if facts == null {
            selection = MissingSelection(false)
            return false
        }
        activeAliases := new HashSet<string>(StringComparer.Ordinal)
        claimed := false
        typeInfo := ResolveTypeName(facts, name, activeAliases, out claimed)
        if BuiltInTypes.IsUnknown(typeInfo) {
            selection = MissingSelection(claimed)
            return false
        }
        declaration := FindDeclarationForType(typeInfo)
        declarationFileValue := ""
        fileValue: string? = null
        if filesByType.TryGetValue(typeInfo, out declarationFileValue) {
            fileValue = declarationFileValue
        }
        selection = new AnalyzerSourceTypeSelection(typeInfo, declaration, fileValue, claimed)
        return true
    }

    func TryResolveProjectTypeInNamespace(name: string, namespaceName: string?, requireExported: bool, out selection: AnalyzerSourceTypeSelection): bool {
        activeAliases := new HashSet<string>(StringComparer.Ordinal)
        typeInfo := BuiltInTypes.Unknown as TypeInfo
        claimed := false
        if TryResolveDeclarationInNamespace(name, namespaceName, requireExported, activeAliases, out typeInfo, out claimed) {
            selection = SelectionForNamedDeclaration(typeInfo, name, namespaceName, true, requireExported, claimed)
            return true
        }
        selection = MissingSelection(claimed)
        return false
    }

    func TryResolveUniqueExportedType(name: string, out selection: AnalyzerSourceTypeSelection): bool {
        activeAliases := new HashSet<string>(StringComparer.Ordinal)
        typeInfo := BuiltInTypes.Unknown as TypeInfo
        claimed := false
        if TryResolveUniqueExported(name, activeAliases, out typeInfo, out claimed) {
            selection = SelectionForNamedDeclaration(typeInfo, name, null, false, true, true)
            return true
        }
        selection = MissingSelection(claimed)
        return false
    }

    func TryGetCanonicalType(filePath: string, name: string, out typeInfo: TypeInfo): bool {
        fullPath := Path.GetFullPath(filePath)
        byName := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
        if typesByFile.TryGetValue(fullPath, out byName) && byName.TryGetValue(name, out typeInfo) {
            return true
        }
        typeInfo = BuiltInTypes.Unknown
        return false
    }

    func RegisterCanonicalType(filePath: string, name: string, typeInfo: TypeInfo) {
        fullPath := Path.GetFullPath(filePath)
        byName := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
        if !typesByFile.TryGetValue(fullPath, out byName) {
            byName = new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
            typesByFile[fullPath] = byName
        }
        byName[name] = typeInfo
        RegisterSourceType(typeInfo, fullPath, null)
    }

    // A type alias declaration is registered by INSTANCE only: the declaring scope keeps the
    // AliasTypeInfo it built, and this context records which file that instance came from so
    // alias resolution is a declaration-context fact rather than a scope-stack walk. The
    // canonical `typesByFile` entry for an alias NAME stays the RESOLVED target type that
    // ResolveDeclarationTypeCore computes, so name lookup is unchanged.
    func RegisterDeclaredAlias(filePath: string, alias: AliasTypeInfo) {
        filesByType[alias] = Path.GetFullPath(filePath)
    }

    func ContainsSourceType(typeInfo: TypeInfo): bool {
        return filesByType.ContainsKey(typeInfo)
    }

    func GetDeclarationFile(typeInfo: TypeInfo): string? {
        filePath := ""
        if filesByType.TryGetValue(typeInfo, out filePath) {
            return filePath
        }
        return null
    }

    // THE ATTRIBUTES A SOURCE TYPE'S OWN DECLARATION CARRIES.
    //
    // `[AttributeUsage(...)]` on a source-declared attribute class cannot be read the way it is read
    // for a referenced type — there is no metadata yet — so it is read from the DECLARATION, in the
    // file that declares the type. Only a `class` is asked: an attribute type is always a class, and a
    // struct or record named the same thing in the same file is not the type that resolved.
    func TryGetDeclaredClassAttributes(typeInfo: TypeInfo, typeName: string, out attributes: List<AttributeNode>): bool {
        attributes = new List<AttributeNode>()
        declarationFile := GetDeclarationFile(typeInfo)
        if declarationFile == null {
            return false
        }

        facts := FindFile(declarationFile)
        if facts == null {
            return false
        }

        knownFacts: AnalyzerDeclarationFileFacts = facts
        index := 0
        while index < knownFacts.Declarations.Count {
            classDeclaration := knownFacts.Declarations[index] as ClassDeclaration
            index = index + 1
            if classDeclaration == null || classDeclaration.Name != typeName {
                continue
            }

            declaredAttributes := classDeclaration.Attributes
            if declaredAttributes == null {
                return false
            }

            attributes = declaredAttributes
            return true
        }

        return false
    }

    func GetContainingType(typeInfo: TypeInfo): TypeInfo? {
        containing := new TypeInfo()
        if containingTypes.TryGetValue(typeInfo, out containing) {
            return containing
        }
        return null
    }

    func TryGetSoaType(declaration: SoaRecordDeclarationInfo, out typeInfo: SoaRecordTypeInfo): bool {
        return soaTypesByDeclaration.TryGetValue(declaration, out typeInfo)
    }

    func GetNamespaceForFile(filePath: string?): string? {
        if filePath == null {
            return null
        }
        facts := FindFile(filePath)
        if facts == null {
            return null
        }
        return facts.NamespaceName
    }

    // WHERE A NAMESPACE'S TYPE WAS DECLARED FIRST — the only evidence a per-file scope cannot hold.
    //
    // One namespace cannot contain two types with the same name and generic arity: the CLR would
    // carry two TypeDefs under one full name, and a consumer asking for that name gets whichever the
    // loader reached first. A duplicate written TWICE IN ONE FILE is caught by the file's own scope
    // (NL306); a duplicate SPLIT ACROSS TWO FILES is invisible there, and this walk is what sees it.
    //
    // THE ANSWER IS THE SAME NO MATTER WHICH FILE IS BEING ANALYSED, AND THAT IS WHY IT IS NOT THE
    // REGISTRATION ORDER'S. `Reset` empties this owner before every file's analysis and the file
    // being analysed is re-added FIRST, so "the file registered first" is always the current one —
    // an answer that would make every file its own first declaration and report nothing. The order
    // used here is instead the ORDINAL ORDER OF THE FULL PATHS, which is a property of the project
    // rather than of the analysis, so every file agrees on which declaration came first and the
    // report lands on the others.
    //
    // `arityName` is the identity key (`Widget`, `Widget``1`), never the written spelling: two types
    // named `Pair` at different arities are two types, and only the asked-for one answers.
    func TryFindFirstDeclaringFile(namespaceName: string?, arityName: string, out declaringFile: string, out declaringLine: int): bool {
        firstFile := ""
        firstLine := 0
        for facts in files {
            if string.Equals(facts.NamespaceName, namespaceName, StringComparison.Ordinal) {
                foundLine := 0
                if TryFindDeclarationLine(facts, arityName, out foundLine) {
                    if firstFile.Length == 0 || string.Compare(facts.FilePath, firstFile, StringComparison.OrdinalIgnoreCase) < 0 {
                        firstFile = facts.FilePath
                        firstLine = foundLine
                    }
                }
            }
        }

        declaringFile = firstFile
        declaringLine = firstLine
        return firstFile.Length > 0
    }

    // The first line in one file that declares `arityName` as a top-level type.
    func TryFindDeclarationLine(facts: AnalyzerDeclarationFileFacts, arityName: string, out declaringLine: int): bool {
        for candidate in facts.Declarations {
            if candidate != null && IsTopLevelTypeDeclaration(candidate) {
                candidateName := DeclarationFacts.GetDeclarationArityName(candidate)
                if candidateName != null && string.Equals(candidateName, arityName, StringComparison.Ordinal) {
                    declaringLine = TypeInfoFactoryReflection.GetRequiredInt(candidate, "Line")
                    return true
                }
            }
        }
        declaringLine = 0
        return false
    }

    // A declaration file as a reader should see it: relative to the project root when it is inside
    // one, and the path as given when it is not.
    func DisplayPathFor(filePath: string): string {
        try {
            relative := Path.GetRelativePath(projectRoot, filePath)
            if relative.Length > 0 && !relative.StartsWith("..", StringComparison.Ordinal) {
                return relative.Replace('\\', '/')
            }
        } catch {
        }

        return filePath
    }

    func TryResolveNestedType(owner: TypeInfo, name: string, requireExported: bool, out nestedType: TypeInfo): bool {
        activeAliases := new HashSet<string>(StringComparer.Ordinal)
        resolvedOwner := ResolveAlias(owner, activeAliases)
        if TryResolveNestedMember(resolvedOwner, name, requireExported, out nestedType) {
            nestedType = ResolveAlias(nestedType, activeAliases)
            return !BuiltInTypes.IsUnknown(nestedType)
        }
        nestedType = BuiltInTypes.Unknown
        return false
    }

    func TryFindMember(owner: TypeInfo, name: string, out selection: AnalyzerMemberSelection): bool {
        visited := new HashSet<object>()
        return TryFindMemberCore(owner, name, null, visited, out selection)
    }

    // Readonly-field eligibility is a semantic property of the selected source member, including
    // inherited members reached through closed generic base substitutions. Return `claimed` when
    // a source member with this name exists so the mechanical analyzer bridge cannot fall through
    // to reflection and reinterpret a non-field or writable/static source member.
    func TryFindReadonlyField(owner: TypeInfo, name: string, requireStatic: bool, out resolvedFieldName: string, out claimed: bool): bool {
        resolvedFieldName = ""
        selection := new AnalyzerMemberSelection()
        if !TryFindMember(owner, name, out selection) {
            claimed = false
            return false
        }
        claimed = true
        member := selection.Member
        if member == null || member.Kind != DeclaredMemberKind.Field || member.IsStatic != requireStatic || !member.IsReadonly {
            return false
        }
        resolvedFieldName = member.Name
        return true
    }

    // INIT-ONLY ELIGIBILITY, ASKED THE WAY READONLY ELIGIBILITY IS ASKED ABOVE. `init X: T` sets
    // `Modifiers.Init` on the member's own declaration, and the word travels with it through
    // inheritance and through closed generic base substitutions. `claimed` answers whether a SOURCE
    // member of this name exists at all, so a caller cannot fall through to reflection and reinterpret
    // a member the source already decided.
    func TryFindInitOnlyMember(owner: TypeInfo, name: string, out resolvedMemberName: string, out claimed: bool): bool {
        resolvedMemberName = ""
        selection := new AnalyzerMemberSelection()
        if !TryFindMember(owner, name, out selection) {
            claimed = false
            return false
        }

        claimed = true
        member := selection.Member
        if member == null || (member.Kind != DeclaredMemberKind.Field && member.Kind != DeclaredMemberKind.Property) {
            return false
        }

        if (member.DeclaredModifiers & Convert.ToInt32(Modifiers.Init)) == 0 {
            return false
        }

        resolvedMemberName = member.Name
        return true
    }

    // THE MEMBERS A SOURCE TYPE DEMANDS, by name, in declaration order — its own first, then every
    // base's. A name the derived type re-declares is listed once, because the nearest declaration is
    // the one a caller's initializer writes. Only source types answer; a reflected type's demands are
    // written in its metadata and are read there.
    func SourceRequiredMemberNames(owner: TypeInfo): List<string> {
        names := new List<string>()
        CollectSourceRequiredMemberNames(owner, null, new HashSet<object>(), names)
        return names
    }

    func CollectSourceRequiredMemberNames(owner: TypeInfo, substitution: Dictionary<string, TypeInfo>?, visited: HashSet<object>, names: List<string>) {
        if !visited.Add(owner) {
            return
        }

        generic := owner as GenericTypeInfo
        if generic != null && generic.GenericDefinition != null {
            CollectSourceRequiredMemberNames(generic.GenericDefinition, CreateSourceGenericSubstitution(generic.GenericDefinition, generic.TypeArguments), visited, names)
            return
        }

        alias := owner as AliasTypeInfo
        if alias != null {
            resolvedAlias := ResolveAlias(alias, new HashSet<string>(StringComparer.Ordinal))
            if resolvedAlias != owner {
                CollectSourceRequiredMemberNames(resolvedAlias, substitution, visited, names)
                return
            }
        }

        shape := new AnalyzerSourceMemberShape()
        if !TryGetSourceMemberShape(owner, substitution, out shape) {
            return
        }

        for member in shape.DeclaredMembers {
            if member != null && (member.Kind == DeclaredMemberKind.Field || member.Kind == DeclaredMemberKind.Property) && (member.DeclaredModifiers & Convert.ToInt32(Modifiers.Required)) != 0 && !names.Contains(member.Name) {
                names.Add(member.Name)
            }
        }

        if shape.BaseType != null {
            CollectSourceRequiredMemberNames(shape.BaseType, substitution, visited, names)
        }
    }

    // File-import aliases have their own terminal type namespace. Keep the dotted-name split,
    // declaration-kind validation, alias expansion, nested visibility, and claimed semantics in
    // N#; Analyzer only records the returned canonical SymbolDeclaration in its binding map.
    func TryResolveFileImportAliasType(name: string, currentFilePath: string?, importedSymbolsByAlias: Dictionary<string, Dictionary<string, TypeInfo>>, importedDeclarationsByAlias: Dictionary<string, Dictionary<string, SymbolDeclaration>>, out typeInfo: TypeInfo, out declaration: SymbolDeclaration?, out claimed: bool): bool {
        typeInfo = BuiltInTypes.Unknown
        declaration = null
        claimed = false
        separator := name.IndexOf('.')
        if separator <= 0 || separator >= name.Length - 1 {
            return false
        }

        alias := name.Substring(0, separator)
        symbols := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
        if !importedSymbolsByAlias.TryGetValue(alias, out symbols) {
            return false
        }
        claimed = true
        remainder := name.Substring(separator + 1)
        nestedSeparator := remainder.IndexOf('.')
        importedName := remainder
        if nestedSeparator >= 0 {
            importedName = remainder.Substring(0, nestedSeparator)
        }
        importedType := BuiltInTypes.Unknown as TypeInfo
        if !symbols.TryGetValue(importedName, out importedType) {
            return false
        }

        declarations := new Dictionary<string, SymbolDeclaration>(StringComparer.Ordinal)
        selectedDeclaration: SymbolDeclaration? = null
        if !importedDeclarationsByAlias.TryGetValue(alias, out declarations) || !declarations.TryGetValue(importedName, out selectedDeclaration) || selectedDeclaration == null || !AnalyzerBindingFacts.IsTypeDeclarationKind(selectedDeclaration.Kind) {
            return false
        }
        declaration = selectedDeclaration
        typeInfo = importedType
        if nestedSeparator < 0 {
            return true
        }

        resolved := ResolveAlias(importedType, new HashSet<string>(StringComparer.Ordinal))
        requireNestedExport := RequiresNestedExport(currentFilePath, selectedDeclaration.File)
        nestedPath := remainder.Substring(nestedSeparator + 1).Split('.')
        for nestedPathItem in nestedPath {
            nested := BuiltInTypes.Unknown as TypeInfo
            if !TryResolveNestedMember(resolved, nestedPathItem, requireNestedExport, out nested) {
                typeInfo = BuiltInTypes.Unknown
                declaration = null
                return false
            }
            resolved = ResolveAlias(nested, new HashSet<string>(StringComparer.Ordinal))
        }
        typeInfo = resolved
        return true
    }

    // WHAT `base` MEANS INSIDE A TYPE, WHICH IS THE DECLARED BASE OR `object`.
    //
    // Three answers, and the middle one is the interesting one. Outside any type there is no `base`
    // at all, so the answer is `unknown` — the value that means "nothing was resolved" and suppresses
    // the reports downstream of it. Inside a type whose shape names a base, the answer is that base.
    // Inside a type whose shape names NONE — a class with no `:` clause, a struct, a record — the
    // answer is `object`, because every CLR type derives from it and `base.ToString()` is a call a
    // user may legitimately write. The current type scope is passed in rather than read here: this
    // owner knows what a declared type IS, and the scope stack knows which one is open.
    func ResolveBaseType(currentType: TypeInfo?): TypeInfo {
        if currentType == null {
            return BuiltInTypes.Unknown
        }

        shape := new AnalyzerSourceMemberShape()
        if TryGetSourceMemberShape(currentType, null, out shape) && shape.BaseType != null {
            return shape.BaseType
        }

        return BuiltInTypes.Object
    }

    func TryGetSourceMemberShape(owner: TypeInfo, substitution: Dictionary<string, TypeInfo>?, out shape: AnalyzerSourceMemberShape): bool {
        classType := owner as ClassTypeInfo
        if classType != null {
            baseType: TypeInfo? = null
            resolvedBase := BuiltInTypes.Unknown as TypeInfo
            if classType.BaseClass != null && TryResolveTypeForOwner(classType.BaseClass, classType, substitution, out resolvedBase) {
                baseType = resolvedBase
            }
            shape = new AnalyzerSourceMemberShape(classType, classType.DeclaredMembers, classType.PrimaryConstructorParameters, classType.NestedTypes, baseType, true, true)
            return true
        }
        structType := owner as StructTypeInfo
        if structType != null {
            shape = new AnalyzerSourceMemberShape(structType, structType.DeclaredMembers, structType.PrimaryConstructorParameters, structType.NestedTypes, null, true, true)
            return true
        }
        recordType := owner as RecordTypeInfo
        if recordType != null {
            shape = new AnalyzerSourceMemberShape(recordType, recordType.DeclaredMembers, recordType.PrimaryConstructorParameters, recordType.NestedTypes, null, true, true)
            return true
        }
        interfaceType := owner as InterfaceTypeInfo
        if interfaceType != null {
            shape = new AnalyzerSourceMemberShape(interfaceType, interfaceType.DeclaredMembers, new ParameterDeclarationInfo[](0), interfaceType.NestedTypes, null, false, true, ResolveBaseInterfaces(interfaceType, substitution))
            return true
        }
        shape = new AnalyzerSourceMemberShape()
        return false
    }

    // THE BASE INTERFACES A DERIVED INTERFACE REACHES THROUGH, resolved against the file that WROTE
    // the derived declaration and substituted with the receiver's type arguments.
    //
    // `interface ITestCase: INamed` means an `ITestCase` receiver HAS everything `INamed` declares —
    // the CLR dispatches `INamed::Name` on it and no cast is involved — but member lookup stopped at
    // the derived declaration's own member list, so `t.Name()` on a `t: ITestCase` was NL303 "Member
    // 'Name' not found on type 'ITestCase'" for functions and for value members alike. The only way
    // out was an explicit `named: INamed = t`, which is not a conversion the source should have to
    // write.
    //
    // A REFERENCE THAT DOES NOT RESOLVE IS DROPPED rather than recorded as unknown: an unresolved
    // base clause is reported by the declaration walk, and a lookup that carried the failure would
    // turn one diagnostic into two.
    func ResolveBaseInterfaces(interfaceType: InterfaceTypeInfo, substitution: Dictionary<string, TypeInfo>?): TypeInfo[] {
        references := interfaceType.BaseInterfaces
        if references.Length == 0 {
            return new TypeInfo[](0)
        }

        resolvedBases := new List<TypeInfo>()
        for reference in references {
            resolved := BuiltInTypes.Unknown as TypeInfo
            if TryResolveTypeForOwner(reference, interfaceType, substitution, out resolved) && !BuiltInTypes.IsUnknown(resolved) {
                resolvedBases.Add(resolved)
            }
        }

        return resolvedBases.ToArray()
    }

    func RequiresNestedExport(currentFilePath: string?, declarationFilePath: string?): bool {
        if currentFilePath == null || currentFilePath.Length == 0 || declarationFilePath == null || declarationFilePath.Length == 0 {
            return false
        }
        currentPath := Path.GetFullPath(currentFilePath)
        declarationPath := Path.GetFullPath(declarationFilePath)
        if string.Equals(currentPath, declarationPath, StringComparison.OrdinalIgnoreCase) {
            return false
        }
        return true
    }

    func GetAvailableSourceMemberNames(owner: TypeInfo, includeStaticMembers: bool): List<string> {
        result := new List<string>()
        visited := new HashSet<object>()
        CollectAvailableSourceMemberNames(owner, includeStaticMembers, null, visited, result)
        return result
    }

    func SourceObjectMembersApply(owner: TypeInfo): bool {
        generic := owner as GenericTypeInfo
        if generic != null && generic.GenericDefinition != null {
            owner = generic.GenericDefinition
        }
        return owner as ClassTypeInfo != null || owner as StructTypeInfo != null || owner as RecordTypeInfo != null || owner as InterfaceTypeInfo != null || owner as EnumTypeInfo != null || owner as TupleTypeInfo != null
    }

    func CreateGenericSubstitution(definition: TypeInfo, arguments: List<TypeInfo>): Dictionary<string, TypeInfo>? {
        return CreateSourceGenericSubstitution(definition, arguments)
    }

    // AN EVENT THE OWNER DECLARED, and the delegate type it was declared with. The caller decides
    // which of the two readings the position gets — the handler type inside the declaring type, the
    // event itself everywhere else — because only the caller knows where the name was written.
    func TryResolveDeclaredEventMember(owner: TypeInfo, members: DeclaredMemberInfo[], name: string, substitution: Dictionary<string, TypeInfo>?, out handlerType: TypeInfo): bool {
        for member in members {
            if member.Name == name && member.Kind == DeclaredMemberKind.Event {
                declaredType := member.Type
                if declaredType == null || !TryResolveTypeForOwner(declaredType, owner, substitution, out handlerType) {
                    handlerType = BuiltInTypes.Unknown
                }

                return true
            }
        }

        handlerType = BuiltInTypes.Unknown
        return false
    }

    func TryResolveDeclaredValueMember(owner: TypeInfo, members: DeclaredMemberInfo[], name: string, substitution: Dictionary<string, TypeInfo>?, out memberType: TypeInfo): bool {
        for member in members {
            if member.Name == name && (member.Kind == DeclaredMemberKind.Field || member.Kind == DeclaredMemberKind.Property) {
                if member.Type == null {
                    memberType = BuiltInTypes.Unknown
                    return true
                }
                if TryResolveTypeForOwner(member.Type, owner, substitution, out memberType) {
                    return true
                }
                memberType = BuiltInTypes.Unknown
                return true
            }
        }
        memberType = BuiltInTypes.Unknown
        return false
    }

    func TryResolvePrimaryParameter(owner: TypeInfo, parameters: ParameterDeclarationInfo[], name: string, substitution: Dictionary<string, TypeInfo>?, out memberType: TypeInfo): bool {
        for parameter in parameters {
            if parameter.Name == name {
                if TryResolveTypeForOwner(parameter.Type, owner, substitution, out memberType) {
                    return true
                }
                memberType = BuiltInTypes.Unknown
                return true
            }
        }
        memberType = BuiltInTypes.Unknown
        return false
    }

    func TryResolveTupleMember(tupleType: TupleTypeInfo, name: string, out memberType: TypeInfo): bool {
        index := 0
        while index < tupleType.Elements.Count {
            element := tupleType.Elements[index]
            if name == "Item" + (index + 1).ToString() || name == element.Name {
                memberType = element.Type
                return true
            }
            index = index + 1
        }

        // `Rest` IS A MEMBER OF A LONG TUPLE, because `ValueTuple`8`'s eighth field is spelled that
        // way and C# lets a caller read it. The elements are held FLAT here -- a ten-element tuple is
        // ten elements, not seven plus a nested one -- so the rest tuple is rebuilt from the elements
        // past the seventh, which is the same nesting the CLR signature has.
        if name == "Rest" && tupleType.Elements.Count > 7 {
            rest := new List<TupleTypeElementInfo>()
            restIndex := 7
            while restIndex < tupleType.Elements.Count {
                rest.Add(tupleType.Elements[restIndex])
                restIndex = restIndex + 1
            }

            restTuple: TypeInfo = new TupleTypeInfo(rest)
            memberType = restTuple
            return true
        }

        memberType = BuiltInTypes.Unknown
        return false
    }

    func TryResolveKnownGenericStructuralMember(typeInfo: TypeInfo, name: string, out memberType: TypeInfo): bool {
        generic := typeInfo as GenericTypeInfo
        if generic != null && generic.TypeArguments.Count == 2 && IsRuntimeResultDefinition(generic) {
            if name == "IsOk" || name == "IsErr" {
                memberType = BuiltInTypes.Bool
                return true
            }
            if name == "OkValue" || name == "OkValueUnchecked" {
                memberType = generic.TypeArguments[0]
                return true
            }
            if name == "ErrValue" || name == "ErrValueUnchecked" {
                memberType = generic.TypeArguments[1]
                return true
            }
        }
        if generic != null && generic.TypeArguments.Count == 1 && IsRuntimeSpanDefinition(generic) {
            if name == "Length" {
                memberType = BuiltInTypes.Int
                return true
            }
            if name == "IsEmpty" {
                memberType = BuiltInTypes.Bool
                return true
            }
            // N# deliberately exposes one narrow pointer surface for governed systems code.
            // Both Span<T>.ptr and ReadOnlySpan<T>.ptr lower from the exact element address,
            // while the analyzer models the public Buffer.MemoryCopy boundary as void*.
            if name == "ptr" {
                invoke := typeof(Action).GetMethod("Invoke", new Type[](0))
                if invoke == null {
                    throw new InvalidOperationException("AnalyzerDeclarationContext takes the canonical void type from System.Action.Invoke's return type, and the compiler's own core library declares no such method.")
                }
                voidType := invoke.ReturnType
                pointerType := voidType.MakePointerType()
                memberType = new ReflectionTypeInfo(pointerType)
                return true
            }
        }
        if generic != null && name == "Count" {
            if (generic.TypeArguments.Count == 1 && IsRuntimeReadOnlyCollectionDefinition(generic)) || (generic.TypeArguments.Count == 2 && IsRuntimeReadOnlyDictionaryDefinition(generic)) {
                memberType = BuiltInTypes.Int
                return true
            }
        }
        if generic != null && UnqualifiedGenericTypeName(generic.Name) == "KeyValuePair" && generic.TypeArguments.Count == 2 {
            if name == "Key" {
                memberType = generic.TypeArguments[0]
                return true
            }
            if name == "Value" {
                memberType = generic.TypeArguments[1]
                return true
            }
        }
        memberType = BuiltInTypes.Unknown
        return false
    }

    // MemoryExtensions.AsSpan<T>(T[]) is a real BCL extension whose receiver contains an open
    // generic parameter. MetadataLoadContext cannot compare that T[] shell to a runtime array by
    // Type identity, so project the exact System import surface without mixing reflection worlds.
    func TryResolveKnownArrayExtensionMember(typeInfo: TypeInfo, name: string, systemNamespaceImported: bool, out memberType: TypeInfo): bool {
        array := typeInfo as ArrayTypeInfo
        if array == null || name != "AsSpan" || !systemNamespaceImported {
            memberType = BuiltInTypes.Unknown
            return false
        }

        arguments := new List<TypeInfo>()
        arguments.Add(array.ElementType)
        spanType := new GenericTypeInfo("Span", arguments, new ReflectionTypeInfo(typeof(Span<int>).GetGenericTypeDefinition()))

        zeroParameters := new FunctionTypeInfo()
        zeroParameters.SyntheticName = "AsSpan"
        zeroParameters.ParameterNames = new List<string>()
        zeroParameters.ParameterTypes = new List<TypeInfo>()
        zeroParameters.ReturnType = spanType

        rangeParameters := new FunctionTypeInfo()
        rangeParameters.SyntheticName = "AsSpan"
        rangeParameters.ParameterNames = new List<string>()
        rangeParameters.ParameterNames.Add("start")
        rangeParameters.ParameterNames.Add("length")
        rangeParameters.ParameterTypes = new List<TypeInfo>()
        rangeParameters.ParameterTypes.Add(BuiltInTypes.Int)
        rangeParameters.ParameterTypes.Add(BuiltInTypes.Int)
        rangeParameters.ReturnType = spanType

        functions := new List<FunctionTypeInfo>()
        functions.Add(zeroParameters)
        functions.Add(rangeParameters)
        memberType = new NSharpMethodGroupInfo(functions)
        return true
    }

    // Reflection does not surface inherited interface methods from Type.GetMethods.
    // Assemble the effective method surface explicitly so metadata and runtime
    // reflection types behave the same way.
    func TryResolveRuntimeInterfaceMethodMember(interfaceType: Type, name: string, includeStaticMembers: bool, out memberType: TypeInfo): bool {
        if !interfaceType.IsInterface {
            memberType = BuiltInTypes.Unknown
            return false
        }

        inheritedInterfaces := interfaceType.GetInterfaces()
        methods := new List<MethodInfo>()
        seenMethods := new HashSet<MethodInfo>()
        AddRuntimeInterfaceMethods(interfaceType.GetMethods(), name, includeStaticMembers, seenMethods, methods)
        for inheritedInterface in inheritedInterfaces {
            AddRuntimeInterfaceMethods(inheritedInterface.GetMethods(), name, false, seenMethods, methods)
        }
        if methods.Count > 0 {
            memberType = new ReflectionMethodGroupInfo(methods.ToArray(), methods[0].Name + "(...)")
            return true
        }

        memberType = BuiltInTypes.Unknown
        return false
    }

    // An INSTANCE method hides a same-named extension method — that is the C# rule and N#'s.
    //
    // The analyzer needs this asked separately whenever only a SURROGATE receiver CLR type exists,
    // which is what `Dictionary<string, SourceEnum>` becomes: no closed CLR type can be built for a
    // source-declared type argument, so the instance surface is never searched and the receiver's
    // methods stay unmodelled. Without this fact the extension surface answers instead, and a BCL
    // extension that merely SHARES the name is then reported as the call's only overload —
    // `Dictionary<K, V>.Remove(key)` losing to `CollectionExtensions.Remove(key, out value)`.
    // Unmodelled is the honest answer there; a wrong signature is not.
    //
    // Interfaces need their inherited surface walked explicitly, for the same reason
    // `TryResolveRuntimeInterfaceMethodMember` walks it: `Type.GetMethods` does not include it.
    func HasRuntimeInstanceMethod(receiverType: Type, name: string): bool {
        if DeclaresRuntimeInstanceMethod(receiverType, name) {
            return true
        }
        if !receiverType.IsInterface {
            return false
        }

        inheritedInterfaces := receiverType.GetInterfaces()
        for inheritedInterface in inheritedInterfaces {
            if DeclaresRuntimeInstanceMethod(inheritedInterface, name) {
                return true
            }
        }

        return false
    }

    static func DeclaresRuntimeInstanceMethod(receiverType: Type, name: string): bool {
        candidates := receiverType.GetMethods()
        for candidate in candidates {
            if candidate.Name == name && !candidate.IsStatic {
                return true
            }
        }

        return false
    }

    static func AddRuntimeInterfaceMethods(candidates: MethodInfo[], name: string, includeStaticMembers: bool, seenMethods: HashSet<MethodInfo>, methods: List<MethodInfo>) {
        for candidate in candidates {
            if candidate.Name == name {
                admitted := includeStaticMembers
                if !admitted {
                    admitted = !candidate.IsStatic
                }
                if admitted {
                    if seenMethods.Add(candidate) {
                        methods.Add(candidate)
                    }
                }
            }
        }
    }

    static func IsRuntimeResultDefinition(generic: GenericTypeInfo): bool {
        return IsRuntimeGenericDefinition(generic, "NSharpLang.Runtime.Result`2", "NSharpLang.Runtime", 2)
    }

    static func IsRuntimeSpanDefinition(generic: GenericTypeInfo): bool {
        return IsRuntimeGenericDefinition(generic, "System.Span`1", "System.Private.CoreLib", 1) || IsRuntimeGenericDefinition(generic, "System.ReadOnlySpan`1", "System.Private.CoreLib", 1)
    }

    static func IsRuntimeReadOnlyCollectionDefinition(generic: GenericTypeInfo): bool {
        return IsRuntimeGenericDefinition(generic, "System.Collections.Generic.IReadOnlyCollection`1", "System.Private.CoreLib", 1) || IsRuntimeGenericDefinition(generic, "System.Collections.Generic.IReadOnlyList`1", "System.Private.CoreLib", 1) || IsRuntimeGenericDefinition(generic, "System.Collections.Generic.IReadOnlySet`1", "System.Private.CoreLib", 1)
    }

    static func IsRuntimeReadOnlyDictionaryDefinition(generic: GenericTypeInfo): bool {
        return IsRuntimeGenericDefinition(generic, "System.Collections.Generic.IReadOnlyDictionary`2", "System.Private.CoreLib", 2)
    }

    static func IsRuntimeGenericDefinition(generic: GenericTypeInfo, fullName: string, assemblyName: string, arity: int): bool {
        reflection := generic.GenericDefinition as ReflectionTypeInfo
        if reflection == null {
            return false
        }
        definition := reflection.Type
        if !definition.IsGenericType {
            return false
        }
        if !definition.IsGenericTypeDefinition {
            definition = definition.GetGenericTypeDefinition()
        }
        if definition.FullName != fullName || definition.GetGenericArguments().Length != arity {
            return false
        }
        return definition.Assembly.GetName().Name == assemblyName
    }

    func ResolveTypeReferenceCore(typeReference: TypeReference, facts: AnalyzerDeclarationFileFacts, activeAliases: HashSet<string>, substitution: Dictionary<string, TypeInfo>?, lexicalOwner: TypeInfo?): TypeInfo {
        simple := typeReference as SimpleTypeReference
        if simple != null {
            bound := new TypeInfo()
            if substitution != null && substitution.TryGetValue(simple.Name, out bound) {
                return bound
            }
            nested := BuiltInTypes.Unknown as TypeInfo
            if TryResolveLexicalNestedType(lexicalOwner, simple.Name, out nested) {
                return ResolveAlias(nested, activeAliases)
            }
            claimed := false
            return ResolveTypeName(facts, simple.Name, activeAliases, out claimed)
        }

        generic := typeReference as GenericTypeReference
        if generic != null {
            return ResolveGenericType(generic, facts, activeAliases, substitution, lexicalOwner)
        }

        array := typeReference as ArrayTypeReference
        if array != null {
            return new ArrayTypeInfo(ResolveTypeReferenceCore(array.ElementType, facts, activeAliases, substitution, lexicalOwner))
        }

        nullable := typeReference as NullableTypeReference
        if nullable != null {
            innerType := ResolveTypeReferenceCore(nullable.InnerType, facts, activeAliases, substitution, lexicalOwner)
            if ErasesOwnerTypeParameterAnnotation(nullable.InnerType, substitution, lexicalOwner, innerType) {
                return innerType
            }

            return new NullableTypeInfo(innerType)
        }

        unionReference := typeReference as UnionTypeReference
        if unionReference != null {
            arms := new List<TypeInfo>()
            for arm2 in unionReference.Arms {
                arms.Add(ResolveTypeReferenceCore(arm2, facts, activeAliases, substitution, lexicalOwner))
            }
            return new AnonymousUnionTypeInfo(arms)
        }

        tuple := typeReference as TupleTypeReference
        if tuple != null {
            elements := new List<TupleTypeElementInfo>()
            for element in tuple.Elements {
                elements.Add(new TupleTypeElementInfo(element.Name, ResolveTypeReferenceCore(element.Type, facts, activeAliases, substitution, lexicalOwner)))
            }
            return new TupleTypeInfo(elements)
        }

        function := typeReference as FunctionTypeReference
        if function != null {
            parameters := new List<TypeInfo>()
            for parameterType2 in function.ParameterTypes {
                parameters.Add(ResolveTypeReferenceCore(parameterType2, facts, activeAliases, substitution, lexicalOwner))
            }
            result := new FunctionTypeInfo()
            result.ParameterTypes = parameters
            result.ReturnType = ResolveTypeReferenceCore(function.ReturnType, facts, activeAliases, substitution, lexicalOwner)
            return result
        }

        byRef := typeReference as ByRefTypeReference
        if byRef != null {
            return new ByRefTypeInfo(ResolveTypeReferenceCore(byRef.InnerType, facts, activeAliases, substitution, lexicalOwner))
        }
        return BuiltInTypes.Unknown
    }

    // `T?` ON THE OWNER'S OWN TYPE PARAMETER, READ THROUGH AN INSTANTIATION. `class Box<T> { func
    // Peek(): T? }` answers `int` for a `Box<int>` and `string?` for a `Box<string>`: on an
    // UNCONSTRAINED parameter C#'s `?` is a reference annotation that a value argument erases, and
    // only `where T : struct` spells a real `Nullable<T>`. This is the declaration-side twin of the
    // rule `AnalyzerSyntheticCallFacts.ApplyGenericBindings` applies to a generic FUNCTION's own
    // parameters, and both ask `NullabilityGenericSubstitution` the same two questions.
    //
    // An OPEN substitution — the owner's parameters mapped to themselves, which is what a read
    // inside the declaration gets — binds `T` to the named type itself, which carries a reference
    // annotation happily, so `T?` stays `T?` there.
    func ErasesOwnerTypeParameterAnnotation(writtenInnerType: TypeReference, substitution: Dictionary<string, TypeInfo>?, lexicalOwner: TypeInfo?, boundInnerType: TypeInfo): bool {
        if substitution == null || lexicalOwner == null {
            return false
        }

        simple := writtenInnerType as SimpleTypeReference
        if simple == null || !substitution.ContainsKey(simple.Name) {
            return false
        }

        lifted := NullabilityGenericSubstitution.LiftedTypeParameterNames(AnalyzerGenericConstraintChecks.ConstraintsOf(lexicalOwner))
        if lifted != null && lifted.Contains(simple.Name) {
            return false
        }

        return NullabilityGenericSubstitution.ErasesNullableAnnotation(boundInnerType)
    }

    func ResolveGenericType(generic: GenericTypeReference, facts: AnalyzerDeclarationFileFacts, activeAliases: HashSet<string>, substitution: Dictionary<string, TypeInfo>?, lexicalOwner: TypeInfo?): TypeInfo {
        arguments := new List<TypeInfo>()
        for typeArgument2 in generic.TypeArguments {
            arguments.Add(ResolveTypeReferenceCore(typeArgument2, facts, activeAliases, substitution, lexicalOwner))
        }

        definition := BuiltInTypes.Unknown as TypeInfo
        definitionClaimed := false
        nestedDefinition := BuiltInTypes.Unknown as TypeInfo
        if TryResolveLexicalNestedType(lexicalOwner, generic.Name, out nestedDefinition) {
            definition = ResolveAlias(nestedDefinition, activeAliases)
            definitionClaimed = true
        } else {
            definition = ResolveTypeName(facts, generic.Name, activeAliases, out definitionClaimed)
        }

        separator := generic.Name.IndexOf(".", StringComparison.Ordinal)
        namespaceAliasedHead := separator > 0 && HasNamespaceAlias(facts, generic.Name.Substring(0, separator))
        if (!definitionClaimed || namespaceAliasedHead) && BuiltInTypes.IsUnknown(definition) {
            ignoredClaim := false
            definition = ResolveTypeName(facts, TypeArityNames.Key(generic.Name, arguments.Count), activeAliases, out ignoredClaim)
        }
        if !definitionClaimed && BuiltInTypes.IsUnknown(definition) {
            knownDefinition := typeof(object)
            if TryResolveKnownOpenGeneric(generic.Name, arguments.Count, out knownDefinition) {
                definition = new ReflectionTypeInfo(knownDefinition)
            }
        }
        // THE HEAD THAT ANSWERED HAS THE WRONG ARITY, SO ASK FOR THE RIGHT IDENTITY. A CLR type
        // spells its arity in metadata (`List``1`) and, since source declarations are keyed the same
        // way, so does `Subscription<T>` declared beside a non-generic `Subscription`: the bare name
        // answers with the arity-0 type and the arity key is what finds the generic one.
        if !BuiltInTypes.IsUnknown(definition) && GenericHeadArity(definition) != arguments.Count {
            arityClaimed := false
            arityDefinition := ResolveTypeName(facts, TypeArityNames.Key(generic.Name, arguments.Count), activeAliases, out arityClaimed)
            if !BuiltInTypes.IsUnknown(arityDefinition) {
                definition = arityDefinition
            }
        }
        if !BuiltInTypes.IsUnknown(definition) && GenericHeadArity(definition) != arguments.Count {
            definition = BuiltInTypes.Unknown
        }
        genericDefinition: TypeInfo? = null
        if !BuiltInTypes.IsUnknown(definition) {
            genericDefinition = definition
        }
        // A HAND-WRITTEN `ValueTuple<...>` IS THE TUPLE IT SPELLS. See `ValueTupleTypeFacts`.
        normalizedTuple: TypeInfo = BuiltInTypes.Unknown
        if ValueTupleTypeFacts.TryNormalizeConstructed(genericDefinition, arguments, out normalizedTuple) {
            return normalizedTuple
        }
        return new GenericTypeInfo(generic.Name, arguments, genericDefinition)
    }

    // THE DECLARATION-SIDE NAME WALK, AND THE SECOND PLACE AN IMPORT IS CREDITED.
    //
    // A member's DECLARED type — a field's, a property's, a parameter's, a return's — is resolved
    // here, against the facts of the file that declares it, and not through the analyzer's own type
    // resolver. So a file whose only mention of an import is `builder: StringBuilder` on a field
    // reached this walk and nothing else, and NL010 would have read the import as dead.
    //
    // ONLY THE FILE BEING ANALYSED IS CREDITED. This owner answers for every file in the project —
    // resolving a member of a type declared elsewhere resolves that file's spellings — and another
    // file's imports are not this file's evidence.
    func ResolveTypeName(facts: AnalyzerDeclarationFileFacts, name: string, activeAliases: HashSet<string>, out claimed: bool): TypeInfo {
        resolved := ResolveTypeNameWalk(facts, name, activeAliases, out claimed)
        credit := importUsageCredit
        if credit != null && string.Equals(facts.FilePath, importUsageFilePath, StringComparison.OrdinalIgnoreCase) {
            credit.CreditResolvedType(name, resolved)
        }

        return resolved
    }

    func ResolveTypeNameWalk(facts: AnalyzerDeclarationFileFacts, name: string, activeAliases: HashSet<string>, out claimed: bool): TypeInfo {
        builtIn := BuiltInTypes.Unknown as TypeInfo
        if TryGetBuiltIn(name, out builtIn) {
            claimed = true
            return builtIn
        }

        if !name.Contains(".") {
            local := BuiltInTypes.Unknown as TypeInfo
            localDeclaration: object? = null
            localClaimed := false
            if TryResolveDeclarationInFile(facts, name, false, activeAliases, out local, out localDeclaration, out localClaimed) {
                claimed = true
                return local
            }
            if localClaimed {
                claimed = true
                return BuiltInTypes.Unknown
            }

            // THE LEXICAL CHAIN, from `SimpleNamePrecedence` — the same owner the analyzer's
            // visible-namespace walk and the emitter's binding scope read. The declaring file's own
            // namespace needs no export and CLAIMS the name (a private sibling declaration is what
            // the name means, even when it does not resolve); an ENCLOSING namespace requires an
            // export and, when it has none, is walked past rather than claiming — the file never
            // asked for that namespace, so a private declaration there must not take a name the file
            // explicitly imported. A referenced assembly's type in any of those namespaces is a
            // member of it too, and wins over every import exactly as a source declaration there
            // does. Only the lexical tier is decided here: file imports come next, then the
            // namespace imports.
            selection := SimpleNamePrecedence.Select(facts.NamespaceName, UnaliasedNamespaceImports(facts))
            lexicalType := BuiltInTypes.Unknown as TypeInfo
            lexicalResolved := false
            while !selection.IsSettled && !selection.Current.IsImport {
                candidate := selection.Current
                isOwnNamespace := !candidate.RequiresExport
                lexicalClaimed := false
                lexicalResolved = TryResolveDeclarationInNamespace(name, candidate.Namespace, candidate.RequiresExport, activeAliases, out lexicalType, out lexicalClaimed)
                declaresSource := lexicalResolved || (lexicalClaimed && isOwnNamespace)
                declaresMetadata := false
                if !declaresSource {
                    metadataType := BuiltInTypes.Unknown as TypeInfo
                    declaresMetadata = TryResolveExternalInNamespace(candidate.LexicalBase, name, out metadataType)
                    if declaresMetadata {
                        lexicalType = metadataType
                    }
                }

                selection.Answer(declaresSource, declaresMetadata)
            }

            if selection.IsSettled && !selection.FromImport && selection.Kind != SimpleNameSelectionKind.NotFound {
                claimed = true
                if selection.Kind == SimpleNameSelectionKind.Metadata || lexicalResolved {
                    return lexicalType
                }

                return BuiltInTypes.Unknown
            }

            for fileImport in facts.FileImports {
                importedFacts := ResolveImportedFile(facts, fileImport)
                if fileImport.Alias == null && importedFacts != null {
                    importedType := BuiltInTypes.Unknown as TypeInfo
                    importedDeclaration: object? = null
                    importedClaimed := false
                    if TryResolveDeclarationInFile(importedFacts, name, !string.Equals(importedFacts.NamespaceName, facts.NamespaceName, StringComparison.Ordinal), activeAliases, out importedType, out importedDeclaration, out importedClaimed) {
                        claimed = true
                        return importedType
                    }
                    if importedClaimed {
                        claimed = true
                        return BuiltInTypes.Unknown
                    }
                }
            }

            importedProjectType := BuiltInTypes.Unknown as TypeInfo
            importedProjectClaimed := false
            if TryResolveImportedProjectType(facts, name, activeAliases, out importedProjectType, out importedProjectClaimed) {
                claimed = true
                return importedProjectType
            }
            if importedProjectClaimed {
                claimed = true
                return BuiltInTypes.Unknown
            }

            // AN EXPLICIT IMPORT IS NOT A LAST RESORT, AND THE UNIQUE-EXPORTED FALLBACK IS: a CLR type
            // an import supplies outranks a project type the file never named, exactly as it does in
            // the analyzer's own type channel (`AnalyzerProjectTypeDiscovery.ResolveVisibleProjectType`).
            for importFacts in facts.NamespaceImports {
                if importFacts.Alias == null {
                    runtimeType := BuiltInTypes.Unknown as TypeInfo
                    if TryResolveExternal(importFacts.Namespace + "." + name, out runtimeType) {
                        claimed = true
                        return runtimeType
                    }
                }
            }

            uniqueType := BuiltInTypes.Unknown as TypeInfo
            uniqueClaimed := false
            if TryResolveUniqueExported(name, activeAliases, out uniqueType, out uniqueClaimed) {
                claimed = true
                return uniqueType
            }
            if uniqueClaimed {
                claimed = true
                return BuiltInTypes.Unknown
            }
            runtimeType := BuiltInTypes.Unknown as TypeInfo
            if TryResolveExternal(name, out runtimeType) {
                claimed = true
                return runtimeType
            }
            claimed = false
            return BuiltInTypes.Unknown
        }

        firstSeparator := name.IndexOf(".", StringComparison.Ordinal)
        root := name.Substring(0, firstSeparator)
        tail := name.Substring(firstSeparator + 1)

        namespaceImport := FindNamespaceAlias(facts, root)
        if namespaceImport != null {
            expanded := namespaceImport.Namespace + "." + tail
            // NL010: AN ALIAS-QUALIFIED SPELLING IS A USE OF THE IMPORT IT IS AN ALIAS OF, and this
            // is the channel that knows which namespace the alias names. The credit-side arithmetic
            // works on the resolved identity, and a SOURCE type carries only its own name — so
            // `new RightNamespace.Widget(5)` over a project namespace was credited by nothing and
            // the import read as dead.
            CreditAliasNamespace(facts, namespaceImport.Namespace)
            projectType := BuiltInTypes.Unknown as TypeInfo
            projectClaimed := false
            if TryResolveQualifiedProjectType(expanded, facts.NamespaceName, activeAliases, out projectType, out projectClaimed) {
                claimed = true
                return projectType
            }
            runtimeType := BuiltInTypes.Unknown as TypeInfo
            if !projectClaimed && TryResolveExternal(expanded, out runtimeType) {
                claimed = true
                return runtimeType
            }
            claimed = true
            return BuiltInTypes.Unknown
        }

        fileImport := FindFileAlias(facts, root)
        if fileImport != null {
            importedFacts := ResolveImportedFile(facts, fileImport)
            if importedFacts == null {
                claimed = true
                return BuiltInTypes.Unknown
            }
            nestedSeparator := tail.IndexOf(".", StringComparison.Ordinal)
            importedName := tail
            if nestedSeparator >= 0 {
                importedName = tail.Substring(0, nestedSeparator)
            }
            importedType := BuiltInTypes.Unknown as TypeInfo
            importedDeclaration: object? = null
            importedClaimed := false
            requireExported := !string.Equals(importedFacts.NamespaceName, facts.NamespaceName, StringComparison.Ordinal)
            if !TryResolveDeclarationInFile(importedFacts, importedName, requireExported, activeAliases, out importedType, out importedDeclaration, out importedClaimed) {
                claimed = true
                return BuiltInTypes.Unknown
            }
            if nestedSeparator < 0 {
                claimed = true
                return importedType
            }
            claimed = true
            return ResolveNestedPath(importedType, tail.Substring(nestedSeparator + 1), requireExported, activeAliases)
        }

        rootClaimed := false
        rootType := ResolveTypeName(facts, root, activeAliases, out rootClaimed)
        if !BuiltInTypes.IsUnknown(rootType) {
            requireNestedExport := rootType as ReflectionTypeInfo != null
            rootFile := ""
            if filesByType.TryGetValue(rootType, out rootFile) {
                rootFacts := FindFile(rootFile)
                requireNestedExport = rootFacts == null || !string.Equals(rootFacts.NamespaceName, facts.NamespaceName, StringComparison.Ordinal)
            }
            nested := ResolveNestedPath(rootType, tail, requireNestedExport, activeAliases)
            if !BuiltInTypes.IsUnknown(nested) {
                claimed = true
                return nested
            }
            if rootClaimed {
                claimed = true
                return BuiltInTypes.Unknown
            }
        } else if rootClaimed {
            claimed = true
            return BuiltInTypes.Unknown
        }

        // THE QUALIFIER CLIMBS THE LEXICAL CHAIN, exactly as the analyzer's own type resolver reads a
        // qualified name: `Ast.Node` written inside `App` names `App.Ast.Node` before it can name an
        // absolute `Ast.Node`, because the leftmost segment of a namespace-or-type-name is looked up
        // the way a simple name is. The written spelling is the chain's last candidate, so an
        // absolute qualifier still resolves. This walk resolves a declaration's types against the
        // file that WROTE them, so the chain is that file's and not the reader's. Each candidate is
        // asked of this project first and of the referenced assemblies second
        // (`SimpleNamePrecedence.SelectQualified`), so `Ast.Node` names `App.Ast.Node` whichever
        // assembly declares it; the written spelling read absolutely keeps its metadata reading below.
        qualifiedSelection := SimpleNamePrecedence.SelectQualified(facts.NamespaceName, name)
        qualifiedType := BuiltInTypes.Unknown as TypeInfo
        qualifiedResolved := false
        while !qualifiedSelection.IsSettled {
            candidate := qualifiedSelection.Current
            qualifiedClaimed := false
            qualifiedResolved = TryResolveQualifiedProjectType(candidate.Namespace ?? name, facts.NamespaceName, activeAliases, out qualifiedType, out qualifiedClaimed)
            declaresSource := qualifiedResolved || qualifiedClaimed
            declaresMetadata := false
            if !declaresSource && !candidate.IsWrittenSpelling {
                metadataType := BuiltInTypes.Unknown as TypeInfo
                declaresMetadata = TryResolveExternalInNamespace(candidate.LexicalBase, name, out metadataType)
                if declaresMetadata {
                    qualifiedType = metadataType
                }
            }

            qualifiedSelection.Answer(declaresSource, declaresMetadata)
        }
        if qualifiedSelection.Kind != SimpleNameSelectionKind.NotFound {
            claimed = true
            if qualifiedSelection.Kind == SimpleNameSelectionKind.Metadata || qualifiedResolved {
                return qualifiedType
            }

            return BuiltInTypes.Unknown
        }
        runtimeType := BuiltInTypes.Unknown as TypeInfo
        if TryResolveExternal(name, out runtimeType) {
            claimed = true
            return runtimeType
        }
        claimed = false
        return BuiltInTypes.Unknown
    }

    // The file's `import X` namespaces, in import order — `SimpleNamePrecedence`'s import tier. An
    // aliased import brings in a name for the namespace, not its types.
    static func UnaliasedNamespaceImports(facts: AnalyzerDeclarationFileFacts): List<string> {
        imports := new List<string>()
        for importFacts in facts.NamespaceImports {
            if importFacts.Alias == null {
                imports.Add(importFacts.Namespace)
            }
        }

        return imports
    }

    func TryResolveDeclarationInFile(facts: AnalyzerDeclarationFileFacts, name: string, requireExported: bool, activeAliases: HashSet<string>, out typeInfo: TypeInfo, out declaration: object?, out claimed: bool): bool {
        for candidate in facts.Declarations {
            if candidate != null && IsTopLevelTypeDeclaration(candidate) {
                // MATCHED BY IDENTITY, NOT BY NAME: `name` is an arity key (`Subscription` or
                // `Subscription``1), so a generic declaration and a non-generic one of the same name
                // are two candidates and only the asked-for one answers.
                candidateName := DeclarationFacts.GetDeclarationArityName(candidate)
                if candidateName != null && string.Equals(candidateName, name, StringComparison.Ordinal) {
                    claimed = true
                    declaration = candidate
                    if requireExported && !DeclarationFacts.IsExportedDeclaration(candidate, TypeArityNames.Display(name)) {
                        typeInfo = BuiltInTypes.Unknown
                        return false
                    }
                    typeInfo = ResolveDeclarationTypeCore(candidate, facts, activeAliases)
                    return !BuiltInTypes.IsUnknown(typeInfo)
                }
            }
        }
        typeInfo = BuiltInTypes.Unknown
        declaration = null
        claimed = false
        return false
    }

    // ONE NAMESPACE, IN FILE ORDER: THE FIRST FILE THAT DECLARES THE IDENTITY ANSWERS. A second file
    // of the same namespace declaring the same (name, arity) is a DUPLICATE, and the duplicate is
    // reported where it is — NL339 at the later declaration, by
    // `AnalyzerDeclarationPolicy.ReportTypeDeclaredInAnotherFile` through `TryFindFirstDeclaringFile`
    // — not here. This walk used to refuse the pair instead, and the refusal surfaced at every USE as
    // NL201 "not found" on top of the NL339: a true statement about nothing, since the type existed
    // twice and the declaration already carried the report. Picking the first file is what the
    // function channel and `SelectionForNamedDeclaration` already do, so a use site now resolves
    // consistently with the declaration the go-to-definition span lands on. A file that CLAIMS the
    // name but cannot resolve it (an unresolvable base, a broken alias) still answers false: that is
    // a miss, not a tie.
    func TryResolveDeclarationInNamespace(name: string, namespaceName: string?, requireExported: bool, activeAliases: HashSet<string>, out typeInfo: TypeInfo, out claimed: bool): bool {
        claimed = false
        for facts in files {
            if !string.Equals(facts.NamespaceName, namespaceName, StringComparison.Ordinal) {
                continue
            }

            candidate := BuiltInTypes.Unknown as TypeInfo
            declaration: object? = null
            unitClaimed := false
            resolved := TryResolveDeclarationInFile(facts, name, requireExported, activeAliases, out candidate, out declaration, out unitClaimed)
            if !unitClaimed {
                continue
            }

            claimed = true
            if !resolved {
                typeInfo = BuiltInTypes.Unknown
                return false
            }

            typeInfo = candidate
            return true
        }

        typeInfo = BuiltInTypes.Unknown
        return false
    }

    // The namespace an alias names, credited to the file being analysed and to no other. This owner
    // resolves names on behalf of EVERY file in the project, and another file's alias is not this
    // file's evidence.
    func CreditAliasNamespace(facts: AnalyzerDeclarationFileFacts, namespaceName: string) {
        credit := importUsageCredit
        if credit != null && string.Equals(facts.FilePath, importUsageFilePath, StringComparison.OrdinalIgnoreCase) {
            credit.CreditNamespaceSupplier(namespaceName)
        }
    }

    func TryResolveImportedProjectType(facts: AnalyzerDeclarationFileFacts, name: string, activeAliases: HashSet<string>, out typeInfo: TypeInfo, out claimed: bool): bool {
        matchedType: TypeInfo? = null
        sawClaim := false
        visitedNamespaces := new HashSet<string>(StringComparer.Ordinal)
        for importFacts in facts.NamespaceImports {
            if importFacts.Alias == null && visitedNamespaces.Add(importFacts.Namespace) {
                candidate := BuiltInTypes.Unknown as TypeInfo
                unitClaimed := false
                if TryResolveDeclarationInNamespace(name, importFacts.Namespace, !string.Equals(importFacts.Namespace, facts.NamespaceName, StringComparison.Ordinal), activeAliases, out candidate, out unitClaimed) {
                    // NL010: this import supplied the name, whatever the tie below decides.
                    CreditAliasNamespace(facts, importFacts.Namespace)
                    if matchedType != null {
                        typeInfo = BuiltInTypes.Unknown
                        claimed = true
                        return false
                    }
                    matchedType = candidate
                } else if unitClaimed {
                    sawClaim = true
                }
            }
        }
        if matchedType == null {
            typeInfo = BuiltInTypes.Unknown
            claimed = sawClaim
            return false
        }
        typeInfo = matchedType
        claimed = true
        return true
    }

    // "UNIQUE" COUNTS NAMESPACES, NOT FILES. The fallback exists for a name exactly one namespace
    // exports; two files of ONE namespace exporting it are that namespace's duplicate (NL339 at the
    // later declaration, see `TryResolveDeclarationInNamespace`), and the first of them answers here
    // just as it does in the namespace walk — the fallback must not turn a reported duplicate back
    // into a "not found" at every cross-namespace use. Two DIFFERENT namespaces exporting the name
    // remain the tie this fallback refuses to break.
    func TryResolveUniqueExported(name: string, activeAliases: HashSet<string>, out typeInfo: TypeInfo, out claimed: bool): bool {
        matchedType: TypeInfo? = null
        matchedNamespace: string? = null
        claimed = false
        for candidateFacts in files {
            candidate := BuiltInTypes.Unknown as TypeInfo
            declaration: object? = null
            unitClaimed := false
            if TryResolveDeclarationInFile(candidateFacts, name, true, activeAliases, out candidate, out declaration, out unitClaimed) {
                claimed = true
                if matchedType == null {
                    matchedType = candidate
                    matchedNamespace = candidateFacts.NamespaceName
                } else if !string.Equals(candidateFacts.NamespaceName, matchedNamespace, StringComparison.Ordinal) {
                    typeInfo = BuiltInTypes.Unknown
                    return false
                }
            } else if unitClaimed && declaration != null && DeclarationFacts.IsExportedDeclaration(declaration, name) {
                claimed = true
                typeInfo = BuiltInTypes.Unknown
                return false
            }
        }
        if matchedType == null {
            typeInfo = BuiltInTypes.Unknown
            claimed = false
            return false
        }
        typeInfo = matchedType
        claimed = true
        return true
    }

    func TryResolveQualifiedProjectType(qualifiedName: string, declarationNamespace: string?, activeAliases: HashSet<string>, out typeInfo: TypeInfo, out claimed: bool): bool {
        selectedNamespace: string? = null
        for fileItem in files {
            namespaceName := fileItem.NamespaceName
            if namespaceName != null && qualifiedName.StartsWith(namespaceName + ".", StringComparison.Ordinal) && (selectedNamespace == null || namespaceName.Length > selectedNamespace.Length) {
                selectedNamespace = namespaceName
            }
        }
        if selectedNamespace == null {
            typeInfo = BuiltInTypes.Unknown
            claimed = false
            return false
        }
        remainder := qualifiedName.Substring(selectedNamespace.Length + 1)
        separator := remainder.IndexOf(".", StringComparison.Ordinal)
        topLevelName := remainder
        if separator >= 0 {
            topLevelName = remainder.Substring(0, separator)
        }
        requireExported := !string.Equals(selectedNamespace, declarationNamespace, StringComparison.Ordinal)
        owner := BuiltInTypes.Unknown as TypeInfo
        if !TryResolveDeclarationInNamespace(topLevelName, selectedNamespace, requireExported, activeAliases, out owner, out claimed) {
            typeInfo = BuiltInTypes.Unknown
            return false
        }
        if separator < 0 {
            typeInfo = owner
            return true
        }
        typeInfo = ResolveNestedPath(owner, remainder.Substring(separator + 1), requireExported, activeAliases)
        return !BuiltInTypes.IsUnknown(typeInfo)
    }

    func ResolveDeclarationTypeCore(declaration: object, facts: AnalyzerDeclarationFileFacts, activeAliases: HashSet<string>): TypeInfo {
        // The per-file cache is keyed by the declaration's IDENTITY, so `Subscription` and
        // `Subscription<T>` in one file resolve to two TypeInfos rather than one shared instance —
        // which is also what stops the base-chain walk from seeing a class inherit from itself.
        name := DeclarationFacts.GetDeclarationArityName(declaration)
        if name == null {
            return BuiltInTypes.Unknown
        }
        declarationKind := declaration.GetType().Name
        byName := typesByFile[facts.FilePath]
        cached := new TypeInfo()
        if byName.TryGetValue(name, out cached) {
            if declarationKind != "TypeAliasDeclaration" && !BuiltInTypes.IsUnknown(cached) {
                RegisterSourceType(cached, facts.FilePath, null)
            }
            return cached
        }

        typeInfo := BuiltInTypes.Unknown as TypeInfo
        if declarationKind == "TypeAliasDeclaration" {
            aliasKey := facts.FilePath + "\u001f" + name
            if !activeAliases.Add(aliasKey) {
                return BuiltInTypes.Unknown
            }
            aliasValue := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "Type")
            aliasType := aliasValue as TypeReference
            if aliasType != null {
                typeInfo = ResolveTypeReferenceCore(aliasType, facts, activeAliases, null, null)
                if ContainsUnknown(typeInfo) {
                    typeInfo = BuiltInTypes.Unknown
                }
            }
            activeAliases.Remove(aliasKey)
        } else if declarationKind == "ClassDeclaration" {
            typeInfo = NominalTypeInfoFactory.FromClassDeclaration(declaration)
        } else if declarationKind == "StructDeclaration" {
            typeInfo = NominalTypeInfoFactory.FromStructDeclaration(declaration)
        } else if declarationKind == "RecordDeclaration" {
            typeInfo = NominalTypeInfoFactory.FromRecordDeclaration(declaration)
        } else if declarationKind == "SoaRecordDeclaration" {
            typeInfo = SoaTypeInfoFactory.FromDeclaration(declaration)
        } else if declarationKind == "InterfaceDeclaration" {
            typeInfo = NominalTypeInfoFactory.FromInterfaceDeclaration(declaration)
        } else if declarationKind == "UnionDeclaration" {
            typeInfo = UnionTypeInfoFactory.FromDeclaration(declaration)
        } else if declarationKind == "EnumDeclaration" {
            typeInfo = EnumTypeInfoFactory.FromDeclaration(declaration)
        } else if declarationKind == "NewtypeDeclaration" {
            underlyingValue := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "UnderlyingType")
            underlyingType := underlyingValue as TypeReference
            if underlyingType != null {
                typeInfo = new NewtypeInfo(name, underlyingType)
            }
        }
        byName[name] = typeInfo
        if declarationKind != "TypeAliasDeclaration" && !BuiltInTypes.IsUnknown(typeInfo) {
            RegisterSourceType(typeInfo, facts.FilePath, null)
        }
        return typeInfo
    }

    func RegisterSourceType(typeInfo: TypeInfo, filePath: string, containingType: TypeInfo?) {
        filesByType[typeInfo] = filePath
        if containingType != null {
            containingTypes[typeInfo] = containingType
        }
        soaType := typeInfo as SoaRecordTypeInfo
        if soaType != null {
            soaTypesByDeclaration[soaType.Declaration] = soaType
        }
        nestedTypes: NestedTypeInfo[]? = null
        classType := typeInfo as ClassTypeInfo
        if classType != null {
            nestedTypes = classType.NestedTypes
        }
        structType := typeInfo as StructTypeInfo
        if structType != null {
            nestedTypes = structType.NestedTypes
        }
        recordType := typeInfo as RecordTypeInfo
        if recordType != null {
            nestedTypes = recordType.NestedTypes
        }
        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null {
            nestedTypes = interfaceType.NestedTypes
        }
        if nestedTypes == null {
            return
        }
        for nestedType in nestedTypes {
            RegisterSourceType(nestedType.Type, filePath, typeInfo)
        }
    }

    func TryResolveLexicalNestedType(lexicalOwner: TypeInfo?, name: string, out nestedType: TypeInfo): bool {
        owner := lexicalOwner
        while owner != null {
            if TryResolveNestedMember(owner, name, false, out nestedType) {
                return true
            }
            containing := new TypeInfo()
            if !containingTypes.TryGetValue(owner, out containing) {
                owner = null
            } else {
                owner = containing
            }
        }
        nestedType = BuiltInTypes.Unknown
        return false
    }

    func ResolveNestedPath(owner: TypeInfo, path: string, requireExported: bool, activeAliases: HashSet<string>): TypeInfo {
        resolved := ResolveAlias(owner, activeAliases)
        segments := path.Split('.')
        for segment in segments {
            nested := BuiltInTypes.Unknown as TypeInfo
            if !TryResolveNestedMember(resolved, segment, requireExported, out nested) {
                return BuiltInTypes.Unknown
            }
            resolved = ResolveAlias(nested, activeAliases)
        }
        return resolved
    }

    func TryResolveNestedMember(owner: TypeInfo, name: string, requireExported: bool, out nestedType: TypeInfo): bool {
        reflection := owner as ReflectionTypeInfo
        if reflection != null {
            nested := reflection.Type.GetNestedType(name)
            if nested != null {
                nestedType = new ReflectionTypeInfo(nested)
                return true
            }
        }
        nestedTypes: NestedTypeInfo[]? = null
        classType := owner as ClassTypeInfo
        if classType != null {
            nestedTypes = classType.NestedTypes
        }
        structType := owner as StructTypeInfo
        if structType != null {
            nestedTypes = structType.NestedTypes
        }
        recordType := owner as RecordTypeInfo
        if recordType != null {
            nestedTypes = recordType.NestedTypes
        }
        interfaceType := owner as InterfaceTypeInfo
        if interfaceType != null {
            nestedTypes = interfaceType.NestedTypes
        }
        if nestedTypes != null {
            for nested in nestedTypes {
                if nested.Name == name && (!requireExported || nested.IsExported) {
                    nestedType = nested.Type
                    return true
                }
            }
        }
        nestedType = BuiltInTypes.Unknown
        return false
    }

    func ResolveAlias(typeInfo: TypeInfo, activeAliases: HashSet<string>): TypeInfo {
        alias := typeInfo as AliasTypeInfo
        if alias == null {
            oblivious := typeInfo as ObliviousTypeInfo
            if oblivious != null {
                return ResolveAlias(oblivious.InnerType, activeAliases)
            }
            return typeInfo
        }
        filePath := ""
        if !filesByType.TryGetValue(alias, out filePath) {
            return typeInfo
        }
        facts := FindFile(filePath)
        if facts == null {
            return BuiltInTypes.Unknown
        }
        key := filePath + "\u001f@" + RuntimeHelpers.GetHashCode(alias).ToString()
        if !activeAliases.Add(key) {
            return BuiltInTypes.Unknown
        }
        result := ResolveTypeReferenceCore(alias.AliasedType, facts, activeAliases, null, GetContainingType(alias))
        activeAliases.Remove(key)
        return ResolveAlias(result, activeAliases)
    }

    func ResolveImportedFile(containing: AnalyzerDeclarationFileFacts, importFacts: AnalyzerFileImportFacts): AnalyzerDeclarationFileFacts? {
        resolver := new FileResolver(projectRoot, containing.FilePath)
        resolvedPath := Path.GetFullPath(resolver.ResolveFilePath(importFacts.Path))
        result := new AnalyzerDeclarationFileFacts()
        if filesByPath.TryGetValue(resolvedPath, out result) {
            return result
        }
        return null
    }

    func FindNamespaceAlias(facts: AnalyzerDeclarationFileFacts, alias: string): AnalyzerNamespaceImportFacts? {
        for candidate in facts.NamespaceImports {
            if candidate.Alias != null && string.Equals(candidate.Alias, alias, StringComparison.Ordinal) {
                return candidate
            }
        }
        return null
    }

    func HasNamespaceAlias(facts: AnalyzerDeclarationFileFacts, alias: string): bool {
        return FindNamespaceAlias(facts, alias) != null
    }

    func FindFileAlias(facts: AnalyzerDeclarationFileFacts, alias: string): AnalyzerFileImportFacts? {
        for candidate in facts.FileImports {
            if candidate.Alias != null && string.Equals(candidate.Alias, alias, StringComparison.Ordinal) {
                return candidate
            }
        }
        return null
    }

    func FindFile(filePath: string): AnalyzerDeclarationFileFacts? {
        fullPath := Path.GetFullPath(filePath)
        result := new AnalyzerDeclarationFileFacts()
        if filesByPath.TryGetValue(fullPath, out result) {
            return result
        }
        return null
    }

    func FindDeclarationForType(typeInfo: TypeInfo): object? {
        filePath := ""
        if !filesByType.TryGetValue(typeInfo, out filePath) {
            return null
        }
        facts := FindFile(filePath)
        if facts == null {
            return null
        }
        name := TypeArityNames.Key(TypeName(typeInfo), AnalyzerTypeReferenceFacts.GenericHeadArity(typeInfo))
        for declaration in facts.Declarations {
            if declaration != null && string.Equals(DeclarationFacts.GetDeclarationArityName(declaration), name, StringComparison.Ordinal) {
                return declaration
            }
        }
        return null
    }

    func TryFindMemberCore(owner: TypeInfo, name: string, substitution: Dictionary<string, TypeInfo>?, visited: HashSet<object>, out selection: AnalyzerMemberSelection): bool {
        if !visited.Add(owner) {
            selection = new AnalyzerMemberSelection()
            return false
        }

        generic := owner as GenericTypeInfo
        if generic != null && generic.GenericDefinition != null {
            genericSubstitution := CreateSourceGenericSubstitution(generic.GenericDefinition, generic.TypeArguments)
            return TryFindMemberCore(generic.GenericDefinition, name, genericSubstitution, visited, out selection)
        }

        alias := owner as AliasTypeInfo
        if alias != null {
            resolvedAlias := ResolveAlias(alias, new HashSet<string>(StringComparer.Ordinal))
            if resolvedAlias != owner {
                return TryFindMemberCore(resolvedAlias, name, substitution, visited, out selection)
            }
        }
        nullable := owner as NullableTypeInfo
        if nullable != null {
            return TryFindMemberCore(nullable.InnerType, name, substitution, visited, out selection)
        }
        oblivious := owner as ObliviousTypeInfo
        if oblivious != null {
            return TryFindMemberCore(oblivious.InnerType, name, substitution, visited, out selection)
        }

        shape := new AnalyzerSourceMemberShape()
        if TryGetSourceMemberShape(owner, substitution, out shape) {
            for member in shape.DeclaredMembers {
                if member.Name == name {
                    selection = new AnalyzerMemberSelection(shape.Owner, member, GetDeclarationFile(shape.Owner), member.Line, member.Column, DeclarationFacts.MemberKindName(shape.Owner, member.KindName, member.IsStatic), member.IsExported)
                    return true
                }
            }
            if shape.BaseType != null {
                return TryFindMemberCore(shape.BaseType, name, substitution, visited, out selection)
            }

            // A DERIVED INTERFACE'S BASES, in written order. First declaration wins, which is the
            // same rule the single-inheritance chain above follows; `visited` makes a diamond safe.
            for baseInterface2 in shape.BaseInterfaces {
                if TryFindMemberCore(baseInterface2, name, substitution, visited, out selection) {
                    return true
                }
            }
        }

        enumType := owner as EnumTypeInfo
        if enumType != null {
            enumIndex := 0
            while enumIndex < enumType.Declaration.Members.Count {
                enumMember := enumType.Declaration.Members[enumIndex]
                if enumMember.Name == name {
                    selection = new AnalyzerMemberSelection(enumType, null, GetDeclarationFile(enumType), enumMember.Line, enumMember.Column, "enumMember", true)
                    return true
                }
                enumIndex = enumIndex + 1
            }
        }
        unionType := owner as UnionTypeInfo
        if unionType != null {
            caseIndex := 0
            while caseIndex < unionType.Declaration.Cases.Count {
                unionCase := unionType.Declaration.Cases[caseIndex]
                if unionCase.Name == name {
                    selection = new AnalyzerMemberSelection(unionType, null, GetDeclarationFile(unionType), unionCase.Line, unionCase.Column, "unionCase", VisibilityConventions.IsExportedIdentifier(name))
                    return true
                }
                caseIndex = caseIndex + 1
            }
        }

        selection = new AnalyzerMemberSelection()
        return false
    }

    func CreateSourceGenericSubstitution(definition: TypeInfo, arguments: List<TypeInfo>): Dictionary<string, TypeInfo>? {
        parameters: TypeParameter[]? = null
        classType := definition as ClassTypeInfo
        if classType != null {
            parameters = classType.TypeParameters
        }
        structType := definition as StructTypeInfo
        if structType != null {
            parameters = structType.TypeParameters
        }
        recordType := definition as RecordTypeInfo
        if recordType != null {
            parameters = recordType.TypeParameters
        }
        interfaceType := definition as InterfaceTypeInfo
        if interfaceType != null {
            parameters = interfaceType.TypeParameters
        }
        unionType := definition as UnionTypeInfo
        if unionType != null && unionType.Declaration.TypeParameters != null {
            unionParameters := unionType.Declaration.TypeParameters
            result := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
            index := 0
            while index < unionParameters.Count && index < arguments.Count {
                result[unionParameters[index].Name] = arguments[index]
                index = index + 1
            }
            return result
        }
        if parameters == null {
            return null
        }
        result := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
        index := 0
        while index < parameters.Length && index < arguments.Count {
            result[parameters[index].Name] = arguments[index]
            index = index + 1
        }
        return result
    }

    func CreateOwnerOpenSubstitution(declarationOwner: TypeInfo, substitution: Dictionary<string, TypeInfo>?): Dictionary<string, TypeInfo> {
        result := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
        if substitution != null {
            for entry in substitution {
                result[entry.Key] = entry.Value
            }
        }

        owner: TypeInfo? = declarationOwner
        while owner != null {
            AddOpenTypeParameters(owner, result)
            containing := new TypeInfo()
            if containingTypes.TryGetValue(owner, out containing) {
                owner = containing
            } else {
                owner = null
            }
        }
        return result
    }

    static func AddOpenTypeParameters(owner: TypeInfo, substitution: Dictionary<string, TypeInfo>) {
        parameters: TypeParameter[]? = null
        classType := owner as ClassTypeInfo
        if classType != null {
            parameters = classType.TypeParameters
        }
        structType := owner as StructTypeInfo
        if structType != null {
            parameters = structType.TypeParameters
        }
        recordType := owner as RecordTypeInfo
        if recordType != null {
            parameters = recordType.TypeParameters
        }
        interfaceType := owner as InterfaceTypeInfo
        if interfaceType != null {
            parameters = interfaceType.TypeParameters
        }
        if parameters != null {
            index := 0
            while index < parameters.Length {
                name := parameters[index].Name
                if !substitution.ContainsKey(name) {
                    substitution[name] = new SimpleTypeInfo(name)
                }
                index = index + 1
            }
        }

        unionType := owner as UnionTypeInfo
        if unionType != null && unionType.Declaration.TypeParameters != null {
            unionParameters := unionType.Declaration.TypeParameters
            index := 0
            while index < unionParameters.Count {
                name := unionParameters[index].Name
                if !substitution.ContainsKey(name) {
                    substitution[name] = new SimpleTypeInfo(name)
                }
                index = index + 1
            }
        }
    }

    func CollectAvailableSourceMemberNames(owner: TypeInfo, includeStaticMembers: bool, substitution: Dictionary<string, TypeInfo>?, visited: HashSet<object>, result: List<string>) {
        if !visited.Add(owner) {
            return
        }
        generic := owner as GenericTypeInfo
        if generic != null && generic.GenericDefinition != null {
            CollectAvailableSourceMemberNames(generic.GenericDefinition, includeStaticMembers, CreateSourceGenericSubstitution(generic.GenericDefinition, generic.TypeArguments), visited, result)
            return
        }
        alias := owner as AliasTypeInfo
        if alias != null {
            resolvedAlias := ResolveAlias(alias, new HashSet<string>(StringComparer.Ordinal))
            if resolvedAlias != owner {
                CollectAvailableSourceMemberNames(resolvedAlias, includeStaticMembers, substitution, visited, result)
            }
            return
        }
        nullable := owner as NullableTypeInfo
        if nullable != null {
            result.Add("HasValue")
            result.Add("Value")
            CollectAvailableSourceMemberNames(nullable.InnerType, includeStaticMembers, substitution, visited, result)
            return
        }
        oblivious := owner as ObliviousTypeInfo
        if oblivious != null {
            CollectAvailableSourceMemberNames(oblivious.InnerType, includeStaticMembers, substitution, visited, result)
            return
        }

        shape := new AnalyzerSourceMemberShape()
        if TryGetSourceMemberShape(owner, substitution, out shape) {
            memberIndex := 0
            while memberIndex < shape.DeclaredMembers.Length {
                memberName := shape.DeclaredMembers[memberIndex].Name
                if !string.IsNullOrWhiteSpace(memberName) {
                    result.Add(memberName)
                }
                memberIndex = memberIndex + 1
            }
            if shape.SupportsPrimaryParameters && !includeStaticMembers {
                for primaryParameter2 in shape.PrimaryParameters {
                    result.Add(primaryParameter2.Name)
                }
            }
            if shape.BaseType != null {
                CollectAvailableSourceMemberNames(shape.BaseType, includeStaticMembers, substitution, visited, result)
            }
            for baseInterface2 in shape.BaseInterfaces {
                CollectAvailableSourceMemberNames(baseInterface2, includeStaticMembers, substitution, visited, result)
            }
            return
        }

        soaRecord := owner as SoaRecordTypeInfo
        if soaRecord != null {
            if includeStaticMembers {
                result.Add("wrap")
                return
            }
            columnIndex := 0
            while columnIndex < soaRecord.Declaration.Columns.Count {
                result.Add(soaRecord.Declaration.Columns[columnIndex].Name)
                columnIndex = columnIndex + 1
            }
            result.Add("length")
            result.Add("capacity")
            result.Add("add")
            result.Add("clear")
            result.Add("ensureCapacity")
            result.Add("copyRow")
            return
        }
        soaRow := owner as SoaRowTypeInfo
        if soaRow != null {
            columnIndex := 0
            while columnIndex < soaRow.Declaration.Columns.Count {
                result.Add(soaRow.Declaration.Columns[columnIndex].Name)
                columnIndex = columnIndex + 1
            }
            return
        }
        enumType := owner as EnumTypeInfo
        if enumType != null {
            memberIndex := 0
            while memberIndex < enumType.Declaration.Members.Count {
                result.Add(enumType.Declaration.Members[memberIndex].Name)
                memberIndex = memberIndex + 1
            }
            return
        }
        tupleType := owner as TupleTypeInfo
        if tupleType != null {
            elementIndex := 0
            while elementIndex < tupleType.Elements.Count {
                result.Add("Item" + (elementIndex + 1).ToString())
                elementName := tupleType.Elements[elementIndex].Name
                if !string.IsNullOrWhiteSpace(elementName) {
                    result.Add(elementName)
                }
                elementIndex = elementIndex + 1
            }
            return
        }
        if owner as AnonymousUnionTypeInfo != null {
            result.Add("Index")
            result.Add("Value")
            return
        }
        unionType := owner as UnionTypeInfo
        if unionType != null {
            caseIndex := 0
            while caseIndex < unionType.Declaration.Cases.Count {
                result.Add(unionType.Declaration.Cases[caseIndex].Name)
                caseIndex = caseIndex + 1
            }
            return
        }
        if owner as NewtypeInfo != null {
            result.Add("Value")
            result.Add("ToString")
            result.Add("Equals")
            result.Add("GetHashCode")
        }
    }

    func SelectionFor(typeInfo: TypeInfo, claimed: bool): AnalyzerSourceTypeSelection {
        filePath := ""
        resultFile: string? = null
        if filesByType.TryGetValue(typeInfo, out filePath) {
            resultFile = filePath
        }
        return new AnalyzerSourceTypeSelection(typeInfo, FindDeclarationForType(typeInfo), resultFile, claimed)
    }

    func SelectionForNamedDeclaration(typeInfo: TypeInfo, name: string, namespaceName: string?, filterNamespace: bool, requireExported: bool, claimed: bool): AnalyzerSourceTypeSelection {
        for facts in files {
            if !filterNamespace || string.Equals(facts.NamespaceName, namespaceName, StringComparison.Ordinal) {
                declarationIndex := 0
                while declarationIndex < facts.Declarations.Count {
                    declaration := facts.Declarations[declarationIndex]
                    if declaration != null && string.Equals(DeclarationFacts.GetDeclarationArityName(declaration), name, StringComparison.Ordinal) && (!requireExported || DeclarationFacts.IsExportedDeclaration(declaration, TypeArityNames.Display(name))) {
                        return new AnalyzerSourceTypeSelection(typeInfo, declaration, facts.FilePath, claimed)
                    }
                    declarationIndex = declarationIndex + 1
                }
            }
        }
        return SelectionFor(typeInfo, claimed)
    }

    static func MissingSelection(claimed: bool): AnalyzerSourceTypeSelection {
        return new AnalyzerSourceTypeSelection(BuiltInTypes.Unknown, null, null, claimed)
    }

    func TryResolveExternal(fullName: string, out typeInfo: TypeInfo): bool {
        cached := new TypeInfo()
        if externalTypes.TryGetValue(fullName, out cached) {
            typeInfo = cached
            return true
        }
        if missingExternalTypes.Contains(fullName) {
            typeInfo = BuiltInTypes.Unknown
            return false
        }
        runtimeType := typeof(object)
        if ExternalQualifiedTypeResolver.TryResolve(assemblies, fullName, friendGrants, out runtimeType) {
            typeInfo = new ReflectionTypeInfo(runtimeType)
            externalTypes[fullName] = typeInfo
            return true
        }
        missingExternalTypes.Add(fullName)
        typeInfo = BuiltInTypes.Unknown
        return false
    }

    // A referenced assembly's type IN ONE NAMESPACE, read exactly: `<namespace>.<name>`, nested
    // spellings included (`TryResolveExternal` reads `Outer.Inner` as `Outer+Inner`). Unlike
    // `TryResolveExternal`, a bare name in the global namespace is never widened into a simple-name
    // scan: "does the global namespace declare `TypeInfo`" is a question about `TypeInfo`, not about
    // `System.Reflection.TypeInfo`.
    func TryResolveExternalInNamespace(namespaceName: string?, name: string, out typeInfo: TypeInfo): bool {
        fullName := name
        if namespaceName != null && namespaceName.Length > 0 {
            fullName = namespaceName + "." + name
        }

        if fullName.Contains(".") {
            return TryResolveExternal(fullName, out typeInfo)
        }

        // Memoised beside `TryResolveExternal`'s own entries under a key no full name can collide
        // with, because the answer differs from that resolver's bare-name scan.
        globalKey := "global::" + fullName
        cached := new TypeInfo()
        if externalTypes.TryGetValue(globalKey, out cached) {
            typeInfo = cached
            return true
        }
        if missingExternalTypes.Contains(globalKey) {
            typeInfo = BuiltInTypes.Unknown
            return false
        }

        exactType := typeof(object)
        if TryResolveExactBareExternal(fullName, out exactType) {
            typeInfo = new ReflectionTypeInfo(exactType)
            externalTypes[globalKey] = typeInfo
            return true
        }

        missingExternalTypes.Add(globalKey)
        typeInfo = BuiltInTypes.Unknown
        return false
    }

    // What this compilation may spell: the friend rule when the analyzer handed one in, the public
    // surface otherwise.
    func IsNameableExternal(candidate: Type): bool {
        grants := friendGrants
        if grants != null {
            return grants.IsNameableType(candidate)
        }

        return candidate.IsVisible
    }

    // A GLOBAL-namespace type of exactly this name, from any loaded assembly.
    func TryResolveExactBareExternal(name: string, out runtimeType: Type): bool {
        runtimeType = typeof(object)
        for assembly in assemblies {
            candidate: Type? = null
            try {
                candidate = assembly.GetType(name)
            } catch {
                candidate = null
            }

            if candidate != null && IsNameableExternal(candidate) {
                runtimeType = candidate
                return true
            }
        }

        return false
    }

    func TryResolveKnownOpenGeneric(name: string, arity: int, out typeInfo: Type): bool {
        fullName := ""
        if name == "List" && arity == 1 {
            fullName = "System.Collections.Generic.List`1"
        } else if name == "IEnumerable" && arity == 1 {
            fullName = "System.Collections.Generic.IEnumerable`1"
        } else if name == "IQueryable" && arity == 1 {
            fullName = "System.Linq.IQueryable`1"
        } else if name == "ICollection" && arity == 1 {
            fullName = "System.Collections.Generic.ICollection`1"
        } else if name == "IList" && arity == 1 {
            fullName = "System.Collections.Generic.IList`1"
        } else if name == "Dictionary" && arity == 2 {
            fullName = "System.Collections.Generic.Dictionary`2"
        } else if name == "IDictionary" && arity == 2 {
            fullName = "System.Collections.Generic.IDictionary`2"
        } else if name == "Task" && arity == 1 {
            fullName = "System.Threading.Tasks.Task`1"
        } else if name == "ValueTask" && arity == 1 {
            fullName = "System.Threading.Tasks.ValueTask`1"
        } else if name == "ValueTuple" && arity >= 1 && arity <= 8 {
            fullName = "System.ValueTuple`" + arity.ToString()
        } else if (name == "Result" || name == "NSharpLang.Runtime.Result") && arity == 2 {
            fullName = "NSharpLang.Runtime.Result`2"
        } else if (name == "JsonTypeInfo" || name == "System.Text.Json.Serialization.Metadata.JsonTypeInfo") && arity == 1 {
            fullName = "System.Text.Json.Serialization.Metadata.JsonTypeInfo`1"
        } else if name == "Func" && arity >= 1 && arity <= 5 {
            fullName = "System.Func`" + arity.ToString()
        } else if name == "Action" && arity >= 1 && arity <= 4 {
            fullName = "System.Action`" + arity.ToString()
        }
        if fullName.Length > 0 {
            resolved := new TypeInfo()
            if TryResolveExternal(fullName, out resolved) {
                reflection := resolved as ReflectionTypeInfo
                if reflection != null {
                    typeInfo = reflection.Type
                    return true
                }
            }
        }
        typeInfo = typeof(object)
        return false
    }

    static func TryGetBuiltIn(name: string, out typeInfo: TypeInfo): bool {
        if name == "int" {
            typeInfo = BuiltInTypes.Int
            return true
        }
        if name == "long" {
            typeInfo = BuiltInTypes.Long
            return true
        }
        if name == "float" {
            typeInfo = BuiltInTypes.Float
            return true
        }
        if name == "double" {
            typeInfo = BuiltInTypes.Double
            return true
        }
        if name == "decimal" {
            typeInfo = BuiltInTypes.Decimal
            return true
        }
        if name == "byte" {
            typeInfo = BuiltInTypes.Byte
            return true
        }
        if name == "sbyte" {
            typeInfo = BuiltInTypes.SByte
            return true
        }
        if name == "short" {
            typeInfo = BuiltInTypes.Short
            return true
        }
        if name == "ushort" {
            typeInfo = BuiltInTypes.UShort
            return true
        }
        if name == "uint" {
            typeInfo = BuiltInTypes.UInt
            return true
        }
        if name == "ulong" {
            typeInfo = BuiltInTypes.ULong
            return true
        }
        if name == "char" {
            typeInfo = BuiltInTypes.Char
            return true
        }
        if name == "bool" {
            typeInfo = BuiltInTypes.Bool
            return true
        }
        if name == "string" {
            typeInfo = BuiltInTypes.String
            return true
        }
        if name == "void" {
            typeInfo = BuiltInTypes.Void
            return true
        }
        if name == "object" {
            typeInfo = BuiltInTypes.Object
            return true
        }
        typeInfo = BuiltInTypes.Unknown
        return false
    }

    static func IsTopLevelTypeDeclaration(declaration: object): bool {
        kind := declaration.GetType().Name
        return kind == "ClassDeclaration" || kind == "StructDeclaration" || kind == "RecordDeclaration" || kind == "SoaRecordDeclaration" || kind == "InterfaceDeclaration" || kind == "UnionDeclaration" || kind == "EnumDeclaration" || kind == "TypeAliasDeclaration" || kind == "NewtypeDeclaration"
    }

    static func ContainsUnknown(typeInfo: TypeInfo): bool {
        if typeInfo as UnknownTypeInfo != null {
            return true
        }
        generic := typeInfo as GenericTypeInfo
        if generic != null {
            if generic.GenericDefinition == null {
                return true
            }
            index := 0
            while index < generic.TypeArguments.Count {
                if ContainsUnknown(generic.TypeArguments[index]) {
                    return true
                }
                index = index + 1
            }
            return false
        }
        array := typeInfo as ArrayTypeInfo
        if array != null {
            return ContainsUnknown(array.ElementType)
        }
        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            return ContainsUnknown(nullable.InnerType)
        }
        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            return ContainsUnknown(oblivious.InnerType)
        }
        unionType := typeInfo as AnonymousUnionTypeInfo
        if unionType != null {
            index := 0
            while index < unionType.Arms.Count {
                if ContainsUnknown(unionType.Arms[index]) {
                    return true
                }
                index = index + 1
            }
        }
        tuple := typeInfo as TupleTypeInfo
        if tuple != null {
            index := 0
            while index < tuple.Elements.Count {
                if ContainsUnknown(tuple.Elements[index].Type) {
                    return true
                }
                index = index + 1
            }
        }
        function := typeInfo as FunctionTypeInfo
        if function != null {
            if function.ParameterTypes == null || function.ReturnType == null {
                return true
            }
            index := 0
            while index < function.ParameterTypes.Count {
                if ContainsUnknown(function.ParameterTypes[index]) {
                    return true
                }
                index = index + 1
            }
            return ContainsUnknown(function.ReturnType)
        }
        byRef := typeInfo as ByRefTypeInfo
        return byRef != null && ContainsUnknown(byRef.InnerType)
    }

    static func GenericHeadArity(typeInfo: TypeInfo): int {
        classType := typeInfo as ClassTypeInfo
        if classType != null {
            return classType.TypeParameters.Length
        }
        structType := typeInfo as StructTypeInfo
        if structType != null {
            return structType.TypeParameters.Length
        }
        recordType := typeInfo as RecordTypeInfo
        if recordType != null {
            return recordType.TypeParameters.Length
        }
        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.TypeParameters.Length
        }
        unionType := typeInfo as UnionTypeInfo
        if unionType != null {
            parameters := unionType.Declaration.TypeParameters
            if parameters == null {
                return 0
            }
            return parameters.Count
        }
        reflection := typeInfo as ReflectionTypeInfo
        if reflection != null {
            if reflection.Type.IsGenericTypeDefinition {
                return reflection.Type.GetGenericArguments().Length
            }
            return 0
        }
        if typeInfo as SimpleTypeInfo != null || typeInfo as SoaRecordTypeInfo != null || typeInfo as EnumTypeInfo != null || typeInfo as AliasTypeInfo != null || typeInfo as NewtypeInfo != null {
            return 0
        }
        return -1
    }

    static func UnqualifiedGenericTypeName(name: string): string {
        lastDot := name.LastIndexOf(".", StringComparison.Ordinal)
        if lastDot >= 0 {
            name = name.Substring(lastDot + 1)
        }
        tick := name.IndexOf("`", StringComparison.Ordinal)
        if tick >= 0 {
            return name.Substring(0, tick)
        }
        return name
    }

    static func TypeName(typeInfo: TypeInfo): string {
        classType := typeInfo as ClassTypeInfo
        if classType != null {
            return classType.Name
        }
        structType := typeInfo as StructTypeInfo
        if structType != null {
            return structType.Name
        }
        recordType := typeInfo as RecordTypeInfo
        if recordType != null {
            return recordType.Name
        }
        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.Name
        }
        unionType := typeInfo as UnionTypeInfo
        if unionType != null {
            return unionType.Declaration.Name
        }
        enumType := typeInfo as EnumTypeInfo
        if enumType != null {
            return enumType.Declaration.Name
        }
        soaType := typeInfo as SoaRecordTypeInfo
        if soaType != null {
            return soaType.Declaration.Name
        }
        newtypeInfo := typeInfo as NewtypeInfo
        if newtypeInfo != null {
            return newtypeInfo.Name
        }
        return ""
    }
}
