namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.CompilerServices
import NSharpLang.Compiler.Ast

public class AnalyzerSourceTypeSelection {
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

public class AnalyzerMemberSelection {
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

    constructor(
        owner: TypeInfo,
        member: DeclaredMemberInfo?,
        filePath: string?,
        line: int,
        column: int,
        kindName: string,
        isExported: bool) {
        Owner = owner
        Member = member
        FilePath = filePath
        Line = line
        Column = column
        KindName = kindName
        IsExported = isExported
    }
}

public class AnalyzerSourceMemberShape {
    Owner: TypeInfo
    DeclaredMembers: DeclaredMemberInfo[]
    PrimaryParameters: ParameterDeclarationInfo[]
    NestedTypes: NestedTypeInfo[]
    BaseType: TypeInfo?
    SupportsPrimaryParameters: bool
    SupportsObjectMembers: bool

    constructor() {
        Owner = BuiltInTypes.Unknown
        DeclaredMembers = new DeclaredMemberInfo[](0)
        PrimaryParameters = new ParameterDeclarationInfo[](0)
        NestedTypes = new NestedTypeInfo[](0)
        BaseType = null
        SupportsPrimaryParameters = false
        SupportsObjectMembers = false
    }

    constructor(
        owner: TypeInfo,
        declaredMembers: DeclaredMemberInfo[],
        primaryParameters: ParameterDeclarationInfo[],
        nestedTypes: NestedTypeInfo[],
        baseType: TypeInfo?,
        supportsPrimaryParameters: bool,
        supportsObjectMembers: bool) {
        Owner = owner
        DeclaredMembers = declaredMembers
        PrimaryParameters = primaryParameters
        NestedTypes = nestedTypes
        BaseType = baseType
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
        index := 0
        while index < imports.Count {
            importValue := imports[index]
            if importValue != null {
                namespaceName := TypeInfoFactoryReflection.GetRequiredString(
                    importValue,
                    "Namespace")
                aliasValue := TypeInfoFactoryReflection.GetOptionalProperty(
                    importValue,
                    "Alias")
                result.Add(new AnalyzerNamespaceImportFacts(
                    namespaceName,
                    aliasValue as string))
            }
            index = index + 1
        }
        return result
    }

    static func ReadFileImports(unit: object): List<AnalyzerFileImportFacts> {
        result := new List<AnalyzerFileImportFacts>()
        imports := TypeInfoFactoryReflection.GetRequiredList(unit, "FileImports")
        index := 0
        while index < imports.Count {
            importValue := imports[index]
            if importValue != null && importValue.GetType().Name == "FileImport" {
                path := TypeInfoFactoryReflection.GetRequiredString(importValue, "Path")
                aliasValue := TypeInfoFactoryReflection.GetOptionalProperty(importValue, "Alias")
                result.Add(new AnalyzerFileImportFacts(path, aliasValue as string))
            }
            index = index + 1
        }
        return result
    }
}

// Canonical source declaration and declaration-context type resolution. The C# analyzer supplies
// already parsed units as opaque objects; all source binding policy and identity caches live here.
public class AnalyzerDeclarationContext {
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

    constructor() {
        projectRoot = Path.GetFullPath(".")
        assemblies = new List<Assembly>()
        files = new List<AnalyzerDeclarationFileFacts>()
        filesByPath = new Dictionary<string, AnalyzerDeclarationFileFacts>(
            StringComparer.OrdinalIgnoreCase)
        typesByFile = new Dictionary<string, Dictionary<string, TypeInfo>>(
            StringComparer.OrdinalIgnoreCase)
        filesByType = new Dictionary<object, string>()
        containingTypes = new Dictionary<object, TypeInfo>()
        soaTypesByDeclaration = new Dictionary<object, SoaRecordTypeInfo>()
        externalTypes = new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
        missingExternalTypes = new HashSet<string>(StringComparer.Ordinal)
    }

    public func Reset(projectRootValue: string, assemblyValues: List<Assembly>) {
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
    }

    public func AddCompilationUnit(filePath: string, unit: object) {
        fullPath := Path.GetFullPath(filePath)
        if filesByPath.ContainsKey(fullPath) {
            return
        }
        facts := new AnalyzerDeclarationFileFacts(fullPath, unit)
        files.Add(facts)
        filesByPath.Add(fullPath, facts)
        typesByFile.Add(
            fullPath,
            new Dictionary<string, TypeInfo>(StringComparer.Ordinal))
    }

    public func ResolveTypeReference(
        typeReference: TypeReference,
        declarationFile: string,
        substitution: Dictionary<string, TypeInfo>? = null,
        lexicalOwner: TypeInfo? = null): TypeInfo {
        facts := FindFile(declarationFile)
        if facts == null {
            return BuiltInTypes.Unknown
        }
        activeAliases := new HashSet<string>(StringComparer.Ordinal)
        return ResolveTypeReferenceCore(
            typeReference,
            facts,
            activeAliases,
            substitution,
            lexicalOwner)
    }

    public func TryResolveTypeForOwner(
        typeReference: TypeReference,
        declarationOwner: TypeInfo,
        substitution: Dictionary<string, TypeInfo>?,
        out resolved: TypeInfo): bool {
        declarationFile := ""
        if !filesByType.TryGetValue(declarationOwner, out declarationFile) {
            resolved = BuiltInTypes.Unknown
            return false
        }
        effectiveSubstitution := CreateOwnerOpenSubstitution(
            declarationOwner,
            substitution)
        resolved = ResolveTypeReference(
            typeReference,
            declarationFile,
            effectiveSubstitution,
            declarationOwner)
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
    public func ResolveDeclaredAlias(candidate: TypeInfo): TypeInfo {
        return ResolveDeclaredAliasCore(candidate, new HashSet<object>())
    }

    func ResolveDeclaredAliasCore(
        candidate: TypeInfo,
        activeAliases: HashSet<object>): TypeInfo {
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

    public func ResolveDeclarationType(declaration: object, filePath: string): TypeInfo {
        facts := FindFile(filePath)
        if facts == null {
            return BuiltInTypes.Unknown
        }
        return ResolveDeclarationTypeCore(
            declaration,
            facts,
            new HashSet<string>(StringComparer.Ordinal))
    }

    public func TryResolveName(
        declarationFile: string,
        name: string,
        out selection: AnalyzerSourceTypeSelection): bool {
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
        selection = new AnalyzerSourceTypeSelection(
            typeInfo,
            declaration,
            fileValue,
            claimed)
        return true
    }

    public func TryResolveProjectTypeInNamespace(
        name: string,
        namespaceName: string?,
        requireExported: bool,
        out selection: AnalyzerSourceTypeSelection): bool {
        activeAliases := new HashSet<string>(StringComparer.Ordinal)
        typeInfo := BuiltInTypes.Unknown as TypeInfo
        claimed := false
        if TryResolveDeclarationInNamespace(
                name,
                namespaceName,
                requireExported,
                activeAliases,
                out typeInfo,
                out claimed) {
            selection = SelectionForNamedDeclaration(
                typeInfo,
                name,
                namespaceName,
                true,
                requireExported,
                claimed)
            return true
        }
        selection = MissingSelection(claimed)
        return false
    }

    public func TryResolveUniqueExportedType(
        name: string,
        out selection: AnalyzerSourceTypeSelection): bool {
        activeAliases := new HashSet<string>(StringComparer.Ordinal)
        typeInfo := BuiltInTypes.Unknown as TypeInfo
        claimed := false
        if TryResolveUniqueExported(
                name,
                activeAliases,
                out typeInfo,
                out claimed) {
            selection = SelectionForNamedDeclaration(
                typeInfo, name, null, false, true, true)
            return true
        }
        selection = MissingSelection(claimed)
        return false
    }

    public func TryGetCanonicalType(
        filePath: string,
        name: string,
        out typeInfo: TypeInfo): bool {
        fullPath := Path.GetFullPath(filePath)
        byName := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
        if typesByFile.TryGetValue(fullPath, out byName)
            && byName.TryGetValue(name, out typeInfo) {
            return true
        }
        typeInfo = BuiltInTypes.Unknown
        return false
    }

    public func RegisterCanonicalType(filePath: string, name: string, typeInfo: TypeInfo) {
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
    public func RegisterDeclaredAlias(filePath: string, alias: AliasTypeInfo) {
        filesByType[alias] = Path.GetFullPath(filePath)
    }

    public func ContainsSourceType(typeInfo: TypeInfo): bool {
        return filesByType.ContainsKey(typeInfo)
    }

    public func GetDeclarationFile(typeInfo: TypeInfo): string? {
        filePath := ""
        if filesByType.TryGetValue(typeInfo, out filePath) {
            return filePath
        }
        return null
    }

    public func GetContainingType(typeInfo: TypeInfo): TypeInfo? {
        containing := new TypeInfo()
        if containingTypes.TryGetValue(typeInfo, out containing) {
            return containing
        }
        return null
    }

    public func TryGetSoaType(
        declaration: SoaRecordDeclarationInfo,
        out typeInfo: SoaRecordTypeInfo): bool {
        return soaTypesByDeclaration.TryGetValue(declaration, out typeInfo)
    }

    public func GetNamespaceForFile(filePath: string?): string? {
        if filePath == null {
            return null
        }
        facts := FindFile(filePath)
        if facts == null {
            return null
        }
        return facts.NamespaceName
    }

    public func TryResolveNestedType(
        owner: TypeInfo,
        name: string,
        requireExported: bool,
        out nestedType: TypeInfo): bool {
        activeAliases := new HashSet<string>(StringComparer.Ordinal)
        resolvedOwner := ResolveAlias(owner, activeAliases)
        if TryResolveNestedMember(
                resolvedOwner,
                name,
                requireExported,
                out nestedType) {
            nestedType = ResolveAlias(nestedType, activeAliases)
            return !BuiltInTypes.IsUnknown(nestedType)
        }
        nestedType = BuiltInTypes.Unknown
        return false
    }

    public func TryFindMember(
        owner: TypeInfo,
        name: string,
        out selection: AnalyzerMemberSelection): bool {
        visited := new HashSet<object>()
        return TryFindMemberCore(owner, name, null, visited, out selection)
    }

    // Readonly-field eligibility is a semantic property of the selected source member, including
    // inherited members reached through closed generic base substitutions. Return `claimed` when
    // a source member with this name exists so the mechanical analyzer bridge cannot fall through
    // to reflection and reinterpret a non-field or writable/static source member.
    public func TryFindReadonlyField(
        owner: TypeInfo,
        name: string,
        requireStatic: bool,
        out resolvedFieldName: string,
        out claimed: bool): bool {
        resolvedFieldName = ""
        selection := new AnalyzerMemberSelection()
        if !TryFindMember(owner, name, out selection) {
            claimed = false
            return false
        }
        claimed = true
        member := selection.Member
        if member == null
            || member.Kind != DeclaredMemberKind.Field
            || member.IsStatic != requireStatic
            || !member.IsReadonly {
            return false
        }
        resolvedFieldName = member.Name
        return true
    }

    // File-import aliases have their own terminal type namespace. Keep the dotted-name split,
    // declaration-kind validation, alias expansion, nested visibility, and claimed semantics in
    // N#; Analyzer only records the returned canonical SymbolDeclaration in its binding map.
    public func TryResolveFileImportAliasType(
        name: string,
        currentFilePath: string?,
        importedSymbolsByAlias: Dictionary<string, Dictionary<string, TypeInfo> >,
        importedDeclarationsByAlias: Dictionary<string, Dictionary<string, SymbolDeclaration> >,
        out typeInfo: TypeInfo,
        out declaration: SymbolDeclaration?,
        out claimed: bool): bool {
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
        if !importedDeclarationsByAlias.TryGetValue(alias, out declarations)
            || !declarations.TryGetValue(importedName, out selectedDeclaration)
            || selectedDeclaration == null
            || !AnalyzerBindingFacts.IsTypeDeclarationKind(
                selectedDeclaration.Kind) {
            return false
        }
        declaration = selectedDeclaration
        typeInfo = importedType
        if nestedSeparator < 0 {
            return true
        }

        resolved := ResolveAlias(
            importedType,
            new HashSet<string>(StringComparer.Ordinal))
        requireNestedExport := RequiresNestedExport(
            currentFilePath, selectedDeclaration.File)
        nestedPath := remainder.Substring(nestedSeparator + 1).Split('.')
        nestedIndex := 0
        while nestedIndex < nestedPath.Length {
            nested := BuiltInTypes.Unknown as TypeInfo
            if !TryResolveNestedMember(
                    resolved,
                    nestedPath[nestedIndex],
                    requireNestedExport,
                    out nested) {
                typeInfo = BuiltInTypes.Unknown
                declaration = null
                return false
            }
            resolved = ResolveAlias(
                nested,
                new HashSet<string>(StringComparer.Ordinal))
            nestedIndex = nestedIndex + 1
        }
        typeInfo = resolved
        return true
    }

    public func TryGetSourceMemberShape(
        owner: TypeInfo,
        substitution: Dictionary<string, TypeInfo>?,
        out shape: AnalyzerSourceMemberShape): bool {
        classType := owner as ClassTypeInfo
        if classType != null {
            baseType: TypeInfo? = null
            resolvedBase := BuiltInTypes.Unknown as TypeInfo
            if classType.BaseClass != null
                && TryResolveTypeForOwner(
                    classType.BaseClass,
                    classType,
                    substitution,
                    out resolvedBase) {
                baseType = resolvedBase
            }
            shape = new AnalyzerSourceMemberShape(
                classType,
                classType.DeclaredMembers,
                classType.PrimaryConstructorParameters,
                classType.NestedTypes,
                baseType,
                true,
                true)
            return true
        }
        structType := owner as StructTypeInfo
        if structType != null {
            shape = new AnalyzerSourceMemberShape(
                structType,
                structType.DeclaredMembers,
                structType.PrimaryConstructorParameters,
                structType.NestedTypes,
                null,
                true,
                true)
            return true
        }
        recordType := owner as RecordTypeInfo
        if recordType != null {
            shape = new AnalyzerSourceMemberShape(
                recordType,
                recordType.DeclaredMembers,
                recordType.PrimaryConstructorParameters,
                recordType.NestedTypes,
                null,
                true,
                true)
            return true
        }
        interfaceType := owner as InterfaceTypeInfo
        if interfaceType != null {
            shape = new AnalyzerSourceMemberShape(
                interfaceType,
                interfaceType.DeclaredMembers,
                new ParameterDeclarationInfo[](0),
                interfaceType.NestedTypes,
                null,
                false,
                true)
            return true
        }
        shape = new AnalyzerSourceMemberShape()
        return false
    }

    func RequiresNestedExport(
        currentFilePath: string?,
        declarationFilePath: string?): bool {
        if currentFilePath == null || currentFilePath.Length == 0
            || declarationFilePath == null || declarationFilePath.Length == 0 {
            return false
        }
        currentPath := Path.GetFullPath(currentFilePath)
        declarationPath := Path.GetFullPath(declarationFilePath)
        if string.Equals(
                currentPath,
                declarationPath,
                StringComparison.OrdinalIgnoreCase) {
            return false
        }
        return true
    }

    public func GetAvailableSourceMemberNames(
        owner: TypeInfo,
        includeStaticMembers: bool): List<string> {
        result := new List<string>()
        visited := new HashSet<object>()
        CollectAvailableSourceMemberNames(
            owner,
            includeStaticMembers,
            null,
            visited,
            result)
        return result
    }

    public func SourceObjectMembersApply(owner: TypeInfo): bool {
        generic := owner as GenericTypeInfo
        if generic != null && generic.GenericDefinition != null {
            owner = generic.GenericDefinition
        }
        return owner as ClassTypeInfo != null
            || owner as StructTypeInfo != null
            || owner as RecordTypeInfo != null
            || owner as InterfaceTypeInfo != null
            || owner as EnumTypeInfo != null
            || owner as TupleTypeInfo != null
    }

    public func CreateGenericSubstitution(
        definition: TypeInfo,
        arguments: List<TypeInfo>): Dictionary<string, TypeInfo>? {
        return CreateSourceGenericSubstitution(definition, arguments)
    }

    public func TryResolveDeclaredValueMember(
        owner: TypeInfo,
        members: DeclaredMemberInfo[],
        name: string,
        substitution: Dictionary<string, TypeInfo>?,
        out memberType: TypeInfo): bool {
        index := 0
        while index < members.Length {
            member := members[index]
            if member.Name == name
                && (member.Kind == DeclaredMemberKind.Field
                    || member.Kind == DeclaredMemberKind.Property) {
                if member.Type == null {
                    memberType = BuiltInTypes.Unknown
                    return true
                }
                if TryResolveTypeForOwner(
                        member.Type,
                        owner,
                        substitution,
                        out memberType) {
                    return true
                }
                memberType = BuiltInTypes.Unknown
                return true
            }
            index = index + 1
        }
        memberType = BuiltInTypes.Unknown
        return false
    }

    public func TryResolvePrimaryParameter(
        owner: TypeInfo,
        parameters: ParameterDeclarationInfo[],
        name: string,
        substitution: Dictionary<string, TypeInfo>?,
        out memberType: TypeInfo): bool {
        index := 0
        while index < parameters.Length {
            parameter := parameters[index]
            if parameter.Name == name {
                if TryResolveTypeForOwner(
                        parameter.Type,
                        owner,
                        substitution,
                        out memberType) {
                    return true
                }
                memberType = BuiltInTypes.Unknown
                return true
            }
            index = index + 1
        }
        memberType = BuiltInTypes.Unknown
        return false
    }

    public func TryResolveTupleMember(
        tupleType: TupleTypeInfo,
        name: string,
        out memberType: TypeInfo): bool {
        index := 0
        while index < tupleType.Elements.Count {
            element := tupleType.Elements[index]
            if name == "Item" + (index + 1).ToString() || name == element.Name {
                memberType = element.Type
                return true
            }
            index = index + 1
        }
        memberType = BuiltInTypes.Unknown
        return false
    }

    public func TryResolveKnownGenericStructuralMember(
        typeInfo: TypeInfo,
        name: string,
        out memberType: TypeInfo): bool {
        generic := typeInfo as GenericTypeInfo
        if generic != null
            && generic.TypeArguments.Count == 2
            && IsRuntimeResultDefinition(generic) {
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
        if generic != null
            && generic.TypeArguments.Count == 1
            && IsRuntimeSpanDefinition(generic) {
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
                invoke := typeof(Action).GetMethod(
                    "Invoke", new Type[](0))
                if invoke == null {
                    throw new InvalidOperationException(
                        "System.Action.Invoke has no canonical void return type.")
                }
                voidType := invoke.get_ReturnType()
                pointerType := voidType.MakePointerType()
                memberType = new ReflectionTypeInfo(pointerType)
                return true
            }
        }
        if generic != null
            && generic.TypeArguments.Count == 1
            && IsRuntimeReadOnlyCollectionDefinition(generic)
            && name == "Count" {
            memberType = BuiltInTypes.Int
            return true
        }
        if generic != null
            && UnqualifiedGenericTypeName(generic.Name) == "KeyValuePair"
            && generic.TypeArguments.Count == 2 {
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
    public func TryResolveKnownArrayExtensionMember(
        typeInfo: TypeInfo,
        name: string,
        systemNamespaceImported: bool,
        out memberType: TypeInfo): bool {
        array := typeInfo as ArrayTypeInfo
        if array == null || name != "AsSpan" || !systemNamespaceImported {
            memberType = BuiltInTypes.Unknown
            return false
        }

        arguments := new List<TypeInfo>()
        arguments.Add(array.ElementType)
        spanType := new GenericTypeInfo(
            "Span",
            arguments,
            new ReflectionTypeInfo(
                typeof(Span<int>).GetGenericTypeDefinition()))

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
    public func TryResolveRuntimeInterfaceMethodMember(
        interfaceType: Type,
        name: string,
        includeStaticMembers: bool,
        out memberType: TypeInfo): bool {
        if !interfaceType.get_IsInterface() {
            memberType = BuiltInTypes.Unknown
            return false
        }

        inheritedInterfaces := interfaceType.GetInterfaces()
        methods := new List<MethodInfo>()
        seenMethods := new HashSet<MethodInfo>()
        AddRuntimeInterfaceMethods(
            interfaceType.GetMethods(),
            name,
            includeStaticMembers,
            seenMethods,
            methods)
        interfaceIndex := 0
        while interfaceIndex < inheritedInterfaces.Length {
            AddRuntimeInterfaceMethods(
                inheritedInterfaces[interfaceIndex].GetMethods(),
                name,
                false,
                seenMethods,
                methods)
            interfaceIndex = interfaceIndex + 1
        }
        if methods.Count > 0 {
            memberType = new ReflectionMethodGroupInfo(
                methods.ToArray(),
                methods[0].get_Name() + "(...)")
            return true
        }

        memberType = BuiltInTypes.Unknown
        return false
    }

    static func AddRuntimeInterfaceMethods(
        candidates: MethodInfo[],
        name: string,
        includeStaticMembers: bool,
        seenMethods: HashSet<MethodInfo>,
        methods: List<MethodInfo>) {
        candidateIndex := 0
        while candidateIndex < candidates.Length {
            candidate := candidates[candidateIndex]
            if candidate.get_Name() == name {
                admitted := includeStaticMembers
                if !admitted {
                    admitted = !candidate.get_IsStatic()
                }
                if admitted {
                    if seenMethods.Add(candidate) {
                        methods.Add(candidate)
                    }
                }
            }
            candidateIndex = candidateIndex + 1
        }
    }

    static func IsRuntimeResultDefinition(generic: GenericTypeInfo): bool {
        return IsRuntimeGenericDefinition(
            generic,
            "NSharpLang.Runtime.Result`2",
            "NSharpLang.Runtime",
            2)
    }

    static func IsRuntimeSpanDefinition(generic: GenericTypeInfo): bool {
        return IsRuntimeGenericDefinition(
                generic,
                "System.Span`1",
                "System.Private.CoreLib",
                1)
            || IsRuntimeGenericDefinition(
                generic,
                "System.ReadOnlySpan`1",
                "System.Private.CoreLib",
                1)
    }

    static func IsRuntimeReadOnlyCollectionDefinition(
        generic: GenericTypeInfo): bool {
        return IsRuntimeGenericDefinition(
                generic,
                "System.Collections.Generic.IReadOnlyCollection`1",
                "System.Private.CoreLib",
                1)
            || IsRuntimeGenericDefinition(
                generic,
                "System.Collections.Generic.IReadOnlyList`1",
                "System.Private.CoreLib",
                1)
    }

    static func IsRuntimeGenericDefinition(
        generic: GenericTypeInfo,
        fullName: string,
        assemblyName: string,
        arity: int): bool {
        reflection := generic.GenericDefinition as ReflectionTypeInfo
        if reflection == null {
            return false
        }
        definition := reflection.Type
        if !definition.get_IsGenericType() {
            return false
        }
        if !definition.get_IsGenericTypeDefinition() {
            definition = definition.GetGenericTypeDefinition()
        }
        if definition.get_FullName() != fullName
            || definition.GetGenericArguments().Length != arity {
            return false
        }
        return definition.get_Assembly().GetName().get_Name()
            == assemblyName
    }

    func ResolveTypeReferenceCore(
        typeReference: TypeReference,
        facts: AnalyzerDeclarationFileFacts,
        activeAliases: HashSet<string>,
        substitution: Dictionary<string, TypeInfo>?,
        lexicalOwner: TypeInfo?): TypeInfo {
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
            return ResolveGenericType(
                generic,
                facts,
                activeAliases,
                substitution,
                lexicalOwner)
        }

        array := typeReference as ArrayTypeReference
        if array != null {
            return new ArrayTypeInfo(ResolveTypeReferenceCore(
                array.ElementType,
                facts,
                activeAliases,
                substitution,
                lexicalOwner))
        }

        nullable := typeReference as NullableTypeReference
        if nullable != null {
            return new NullableTypeInfo(ResolveTypeReferenceCore(
                nullable.InnerType,
                facts,
                activeAliases,
                substitution,
                lexicalOwner))
        }

        unionReference := typeReference as UnionTypeReference
        if unionReference != null {
            arms := new List<TypeInfo>()
            armIndex := 0
            while armIndex < unionReference.Arms.Count {
                arms.Add(ResolveTypeReferenceCore(
                    unionReference.Arms[armIndex],
                    facts,
                    activeAliases,
                    substitution,
                    lexicalOwner))
                armIndex = armIndex + 1
            }
            return new AnonymousUnionTypeInfo(arms)
        }

        tuple := typeReference as TupleTypeReference
        if tuple != null {
            elements := new List<TupleTypeElementInfo>()
            elementIndex := 0
            while elementIndex < tuple.Elements.Count {
                element := tuple.Elements[elementIndex]
                elements.Add(new TupleTypeElementInfo(
                    element.Name,
                    ResolveTypeReferenceCore(
                        element.Type,
                        facts,
                        activeAliases,
                        substitution,
                        lexicalOwner)))
                elementIndex = elementIndex + 1
            }
            return new TupleTypeInfo(elements)
        }

        function := typeReference as FunctionTypeReference
        if function != null {
            parameters := new List<TypeInfo>()
            parameterIndex := 0
            while parameterIndex < function.ParameterTypes.Count {
                parameters.Add(ResolveTypeReferenceCore(
                    function.ParameterTypes[parameterIndex],
                    facts,
                    activeAliases,
                    substitution,
                    lexicalOwner))
                parameterIndex = parameterIndex + 1
            }
            result := new FunctionTypeInfo()
            result.ParameterTypes = parameters
            result.ReturnType = ResolveTypeReferenceCore(
                function.ReturnType,
                facts,
                activeAliases,
                substitution,
                lexicalOwner)
            return result
        }

        byRef := typeReference as ByRefTypeReference
        if byRef != null {
            return new ByRefTypeInfo(ResolveTypeReferenceCore(
                byRef.InnerType,
                facts,
                activeAliases,
                substitution,
                lexicalOwner))
        }
        return BuiltInTypes.Unknown
    }

    func ResolveGenericType(
        generic: GenericTypeReference,
        facts: AnalyzerDeclarationFileFacts,
        activeAliases: HashSet<string>,
        substitution: Dictionary<string, TypeInfo>?,
        lexicalOwner: TypeInfo?): TypeInfo {
        arguments := new List<TypeInfo>()
        argumentIndex := 0
        while argumentIndex < generic.TypeArguments.Count {
            arguments.Add(ResolveTypeReferenceCore(
                generic.TypeArguments[argumentIndex],
                facts,
                activeAliases,
                substitution,
                lexicalOwner))
            argumentIndex = argumentIndex + 1
        }

        definition := BuiltInTypes.Unknown as TypeInfo
        definitionClaimed := false
        nestedDefinition := BuiltInTypes.Unknown as TypeInfo
        if TryResolveLexicalNestedType(
                lexicalOwner,
                generic.Name,
                out nestedDefinition) {
            definition = ResolveAlias(nestedDefinition, activeAliases)
            definitionClaimed = true
        } else {
            definition = ResolveTypeName(
                facts,
                generic.Name,
                activeAliases,
                out definitionClaimed)
        }

        separator := generic.Name.IndexOf(".", StringComparison.Ordinal)
        namespaceAliasedHead := separator > 0
            && HasNamespaceAlias(facts, generic.Name.Substring(0, separator))
        if (!definitionClaimed || namespaceAliasedHead)
            && BuiltInTypes.IsUnknown(definition) {
            ignoredClaim := false
            definition = ResolveTypeName(
                facts,
                generic.Name + "`" + arguments.Count.ToString(),
                activeAliases,
                out ignoredClaim)
        }
        if !definitionClaimed && BuiltInTypes.IsUnknown(definition) {
            knownDefinition := typeof(object)
            if TryResolveKnownOpenGeneric(
                    generic.Name,
                    arguments.Count,
                    out knownDefinition) {
                definition = new ReflectionTypeInfo(knownDefinition)
            }
        }
        reflectionDefinition := definition as ReflectionTypeInfo
        if reflectionDefinition != null
            && GenericHeadArity(definition) != arguments.Count {
            arityClaimed := false
            arityDefinition := ResolveTypeName(
                facts,
                generic.Name + "`" + arguments.Count.ToString(),
                activeAliases,
                out arityClaimed)
            if !BuiltInTypes.IsUnknown(arityDefinition) {
                definition = arityDefinition
            }
        }
        if !BuiltInTypes.IsUnknown(definition)
            && GenericHeadArity(definition) != arguments.Count {
            definition = BuiltInTypes.Unknown
        }
        genericDefinition: TypeInfo? = null
        if !BuiltInTypes.IsUnknown(definition) {
            genericDefinition = definition
        }
        return new GenericTypeInfo(generic.Name, arguments, genericDefinition)
    }

    func ResolveTypeName(
        facts: AnalyzerDeclarationFileFacts,
        name: string,
        activeAliases: HashSet<string>,
        out claimed: bool): TypeInfo {
        builtIn := BuiltInTypes.Unknown as TypeInfo
        if TryGetBuiltIn(name, out builtIn) {
            claimed = true
            return builtIn
        }

        if !name.Contains(".") {
            local := BuiltInTypes.Unknown as TypeInfo
            localDeclaration: object? = null
            localClaimed := false
            if TryResolveDeclarationInFile(
                    facts,
                    name,
                    false,
                    activeAliases,
                    out local,
                    out localDeclaration,
                    out localClaimed) {
                claimed = true
                return local
            }
            if localClaimed {
                claimed = true
                return BuiltInTypes.Unknown
            }

            packageType := BuiltInTypes.Unknown as TypeInfo
            packageClaimed := false
            if TryResolveDeclarationInNamespace(
                    name,
                    facts.NamespaceName,
                    false,
                    activeAliases,
                    out packageType,
                    out packageClaimed) {
                claimed = true
                return packageType
            }
            if packageClaimed {
                claimed = true
                return BuiltInTypes.Unknown
            }

            fileImportIndex := 0
            while fileImportIndex < facts.FileImports.Count {
                fileImport := facts.FileImports[fileImportIndex]
                importedFacts := ResolveImportedFile(facts, fileImport)
                if fileImport.Alias == null && importedFacts != null {
                    importedType := BuiltInTypes.Unknown as TypeInfo
                    importedDeclaration: object? = null
                    importedClaimed := false
                    if TryResolveDeclarationInFile(
                            importedFacts,
                            name,
                            !string.Equals(
                                importedFacts.NamespaceName,
                                facts.NamespaceName,
                                StringComparison.Ordinal),
                            activeAliases,
                            out importedType,
                            out importedDeclaration,
                            out importedClaimed) {
                        claimed = true
                        return importedType
                    }
                    if importedClaimed {
                        claimed = true
                        return BuiltInTypes.Unknown
                    }
                }
                fileImportIndex = fileImportIndex + 1
            }

            importedProjectType := BuiltInTypes.Unknown as TypeInfo
            importedProjectClaimed := false
            if TryResolveImportedProjectType(
                    facts,
                    name,
                    activeAliases,
                    out importedProjectType,
                    out importedProjectClaimed) {
                claimed = true
                return importedProjectType
            }
            if importedProjectClaimed {
                claimed = true
                return BuiltInTypes.Unknown
            }

            uniqueType := BuiltInTypes.Unknown as TypeInfo
            uniqueClaimed := false
            if TryResolveUniqueExported(
                    name,
                    activeAliases,
                    out uniqueType,
                    out uniqueClaimed) {
                claimed = true
                return uniqueType
            }
            if uniqueClaimed {
                claimed = true
                return BuiltInTypes.Unknown
            }

            importIndex := 0
            while importIndex < facts.NamespaceImports.Count {
                importFacts := facts.NamespaceImports[importIndex]
                if importFacts.Alias == null {
                    runtimeType := BuiltInTypes.Unknown as TypeInfo
                    if TryResolveExternal(
                            importFacts.Namespace + "." + name,
                            out runtimeType) {
                        claimed = true
                        return runtimeType
                    }
                }
                importIndex = importIndex + 1
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
            projectType := BuiltInTypes.Unknown as TypeInfo
            projectClaimed := false
            if TryResolveQualifiedProjectType(
                    expanded,
                    facts.NamespaceName,
                    activeAliases,
                    out projectType,
                    out projectClaimed) {
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
            requireExported := !string.Equals(
                importedFacts.NamespaceName,
                facts.NamespaceName,
                StringComparison.Ordinal)
            if !TryResolveDeclarationInFile(
                    importedFacts,
                    importedName,
                    requireExported,
                    activeAliases,
                    out importedType,
                    out importedDeclaration,
                    out importedClaimed) {
                claimed = true
                return BuiltInTypes.Unknown
            }
            if nestedSeparator < 0 {
                claimed = true
                return importedType
            }
            claimed = true
            return ResolveNestedPath(
                importedType,
                tail.Substring(nestedSeparator + 1),
                requireExported,
                activeAliases)
        }

        rootClaimed := false
        rootType := ResolveTypeName(facts, root, activeAliases, out rootClaimed)
        if !BuiltInTypes.IsUnknown(rootType) {
            requireNestedExport := rootType as ReflectionTypeInfo != null
            rootFile := ""
            if filesByType.TryGetValue(rootType, out rootFile) {
                rootFacts := FindFile(rootFile)
                requireNestedExport = rootFacts == null
                    || !string.Equals(
                        rootFacts.NamespaceName,
                        facts.NamespaceName,
                        StringComparison.Ordinal)
            }
            nested := ResolveNestedPath(
                rootType,
                tail,
                requireNestedExport,
                activeAliases)
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

        qualifiedType := BuiltInTypes.Unknown as TypeInfo
        qualifiedClaimed := false
        if TryResolveQualifiedProjectType(
                name,
                facts.NamespaceName,
                activeAliases,
                out qualifiedType,
                out qualifiedClaimed) {
            claimed = true
            return qualifiedType
        }
        if qualifiedClaimed {
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

    func TryResolveDeclarationInFile(
        facts: AnalyzerDeclarationFileFacts,
        name: string,
        requireExported: bool,
        activeAliases: HashSet<string>,
        out typeInfo: TypeInfo,
        out declaration: object?,
        out claimed: bool): bool {
        index := 0
        while index < facts.Declarations.Count {
            candidate := facts.Declarations[index]
            if candidate != null && IsTopLevelTypeDeclaration(candidate) {
                candidateName := DeclarationFacts.GetDeclarationName(candidate)
                if candidateName != null
                    && string.Equals(candidateName, name, StringComparison.Ordinal) {
                    claimed = true
                    declaration = candidate
                    if requireExported
                        && !DeclarationFacts.IsExportedDeclaration(candidate, name) {
                        typeInfo = BuiltInTypes.Unknown
                        return false
                    }
                    typeInfo = ResolveDeclarationTypeCore(candidate, facts, activeAliases)
                    return !BuiltInTypes.IsUnknown(typeInfo)
                }
            }
            index = index + 1
        }
        typeInfo = BuiltInTypes.Unknown
        declaration = null
        claimed = false
        return false
    }

    func TryResolveDeclarationInNamespace(
        name: string,
        namespaceName: string?,
        requireExported: bool,
        activeAliases: HashSet<string>,
        out typeInfo: TypeInfo,
        out claimed: bool): bool {
        matchedType: TypeInfo? = null
        claimed = false
        fileIndex := 0
        while fileIndex < files.Count {
            facts := files[fileIndex]
            if string.Equals(facts.NamespaceName, namespaceName, StringComparison.Ordinal) {
                candidate := BuiltInTypes.Unknown as TypeInfo
                declaration: object? = null
                unitClaimed := false
                resolved := TryResolveDeclarationInFile(
                    facts,
                    name,
                    requireExported,
                    activeAliases,
                    out candidate,
                    out declaration,
                    out unitClaimed)
                if unitClaimed {
                    claimed = true
                    if !resolved || matchedType != null {
                        typeInfo = BuiltInTypes.Unknown
                        return false
                    }
                    matchedType = candidate
                }
            }
            fileIndex = fileIndex + 1
        }
        if matchedType == null {
            typeInfo = BuiltInTypes.Unknown
            return false
        }
        typeInfo = matchedType
        return true
    }

    func TryResolveImportedProjectType(
        facts: AnalyzerDeclarationFileFacts,
        name: string,
        activeAliases: HashSet<string>,
        out typeInfo: TypeInfo,
        out claimed: bool): bool {
        matchedType: TypeInfo? = null
        sawClaim := false
        visitedNamespaces := new HashSet<string>(StringComparer.Ordinal)
        importIndex := 0
        while importIndex < facts.NamespaceImports.Count {
            importFacts := facts.NamespaceImports[importIndex]
            if importFacts.Alias == null
                && visitedNamespaces.Add(importFacts.Namespace) {
                candidate := BuiltInTypes.Unknown as TypeInfo
                unitClaimed := false
                if TryResolveDeclarationInNamespace(
                        name,
                        importFacts.Namespace,
                        !string.Equals(
                            importFacts.Namespace,
                            facts.NamespaceName,
                            StringComparison.Ordinal),
                        activeAliases,
                        out candidate,
                        out unitClaimed) {
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
            importIndex = importIndex + 1
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

    func TryResolveUniqueExported(
        name: string,
        activeAliases: HashSet<string>,
        out typeInfo: TypeInfo,
        out claimed: bool): bool {
        matchedType: TypeInfo? = null
        claimed = false
        fileIndex := 0
        while fileIndex < files.Count {
            candidate := BuiltInTypes.Unknown as TypeInfo
            declaration: object? = null
            unitClaimed := false
            if TryResolveDeclarationInFile(
                    files[fileIndex],
                    name,
                    true,
                    activeAliases,
                    out candidate,
                    out declaration,
                    out unitClaimed) {
                claimed = true
                if matchedType != null {
                    typeInfo = BuiltInTypes.Unknown
                    return false
                }
                matchedType = candidate
            } else if unitClaimed && declaration != null
                && DeclarationFacts.IsExportedDeclaration(declaration, name) {
                claimed = true
                typeInfo = BuiltInTypes.Unknown
                return false
            }
            fileIndex = fileIndex + 1
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

    func TryResolveQualifiedProjectType(
        qualifiedName: string,
        declarationNamespace: string?,
        activeAliases: HashSet<string>,
        out typeInfo: TypeInfo,
        out claimed: bool): bool {
        selectedNamespace: string? = null
        fileIndex := 0
        while fileIndex < files.Count {
            namespaceName := files[fileIndex].NamespaceName
            if namespaceName != null
                && qualifiedName.StartsWith(
                    namespaceName + ".",
                    StringComparison.Ordinal)
                && (selectedNamespace == null
                    || namespaceName.Length > selectedNamespace.Length) {
                selectedNamespace = namespaceName
            }
            fileIndex = fileIndex + 1
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
        requireExported := !string.Equals(
            selectedNamespace,
            declarationNamespace,
            StringComparison.Ordinal)
        owner := BuiltInTypes.Unknown as TypeInfo
        if !TryResolveDeclarationInNamespace(
                topLevelName,
                selectedNamespace,
                requireExported,
                activeAliases,
                out owner,
                out claimed) {
            typeInfo = BuiltInTypes.Unknown
            return false
        }
        if separator < 0 {
            typeInfo = owner
            return true
        }
        typeInfo = ResolveNestedPath(
            owner,
            remainder.Substring(separator + 1),
            requireExported,
            activeAliases)
        return !BuiltInTypes.IsUnknown(typeInfo)
    }

    func ResolveDeclarationTypeCore(
        declaration: object,
        facts: AnalyzerDeclarationFileFacts,
        activeAliases: HashSet<string>): TypeInfo {
        name := DeclarationFacts.GetDeclarationName(declaration)
        if name == null {
            return BuiltInTypes.Unknown
        }
        declarationKind := declaration.GetType().Name
        byName := typesByFile[facts.FilePath]
        cached := new TypeInfo()
        if byName.TryGetValue(name, out cached) {
            if declarationKind != "TypeAliasDeclaration"
                && !BuiltInTypes.IsUnknown(cached) {
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
                typeInfo = ResolveTypeReferenceCore(
                    aliasType,
                    facts,
                    activeAliases,
                    null,
                    null)
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
            underlyingValue := TypeInfoFactoryReflection.GetOptionalProperty(
                declaration,
                "UnderlyingType")
            underlyingType := underlyingValue as TypeReference
            if underlyingType != null {
                typeInfo = new NewtypeInfo(name, underlyingType)
            }
        }
        byName[name] = typeInfo
        if declarationKind != "TypeAliasDeclaration"
            && !BuiltInTypes.IsUnknown(typeInfo) {
            RegisterSourceType(typeInfo, facts.FilePath, null)
        }
        return typeInfo
    }

    func RegisterSourceType(
        typeInfo: TypeInfo,
        filePath: string,
        containingType: TypeInfo?) {
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
        nestedIndex := 0
        while nestedIndex < nestedTypes.Length {
            RegisterSourceType(
                nestedTypes[nestedIndex].Type,
                filePath,
                typeInfo)
            nestedIndex = nestedIndex + 1
        }
    }

    func TryResolveLexicalNestedType(
        lexicalOwner: TypeInfo?,
        name: string,
        out nestedType: TypeInfo): bool {
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

    func ResolveNestedPath(
        owner: TypeInfo,
        path: string,
        requireExported: bool,
        activeAliases: HashSet<string>): TypeInfo {
        resolved := ResolveAlias(owner, activeAliases)
        segments := path.Split('.')
        segmentIndex := 0
        while segmentIndex < segments.Length {
            nested := BuiltInTypes.Unknown as TypeInfo
            if !TryResolveNestedMember(
                    resolved,
                    segments[segmentIndex],
                    requireExported,
                    out nested) {
                return BuiltInTypes.Unknown
            }
            resolved = ResolveAlias(nested, activeAliases)
            segmentIndex = segmentIndex + 1
        }
        return resolved
    }

    func TryResolveNestedMember(
        owner: TypeInfo,
        name: string,
        requireExported: bool,
        out nestedType: TypeInfo): bool {
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
        if classType != null { nestedTypes = classType.NestedTypes }
        structType := owner as StructTypeInfo
        if structType != null { nestedTypes = structType.NestedTypes }
        recordType := owner as RecordTypeInfo
        if recordType != null { nestedTypes = recordType.NestedTypes }
        interfaceType := owner as InterfaceTypeInfo
        if interfaceType != null { nestedTypes = interfaceType.NestedTypes }
        if nestedTypes != null {
            index := 0
            while index < nestedTypes.Length {
                nested := nestedTypes[index]
                if nested.Name == name && (!requireExported || nested.IsExported) {
                    nestedType = nested.Type
                    return true
                }
                index = index + 1
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
        result := ResolveTypeReferenceCore(
            alias.AliasedType,
            facts,
            activeAliases,
            null,
            GetContainingType(alias))
        activeAliases.Remove(key)
        return ResolveAlias(result, activeAliases)
    }

    func ResolveImportedFile(
        containing: AnalyzerDeclarationFileFacts,
        importFacts: AnalyzerFileImportFacts): AnalyzerDeclarationFileFacts? {
        resolver := new FileResolver(projectRoot, containing.FilePath)
        resolvedPath := Path.GetFullPath(resolver.ResolveFilePath(importFacts.Path))
        result := new AnalyzerDeclarationFileFacts()
        if filesByPath.TryGetValue(resolvedPath, out result) {
            return result
        }
        return null
    }

    func FindNamespaceAlias(
        facts: AnalyzerDeclarationFileFacts,
        alias: string): AnalyzerNamespaceImportFacts? {
        index := 0
        while index < facts.NamespaceImports.Count {
            candidate := facts.NamespaceImports[index]
            if candidate.Alias != null
                && string.Equals(candidate.Alias, alias, StringComparison.Ordinal) {
                return candidate
            }
            index = index + 1
        }
        return null
    }

    func HasNamespaceAlias(facts: AnalyzerDeclarationFileFacts, alias: string): bool {
        return FindNamespaceAlias(facts, alias) != null
    }

    func FindFileAlias(
        facts: AnalyzerDeclarationFileFacts,
        alias: string): AnalyzerFileImportFacts? {
        index := 0
        while index < facts.FileImports.Count {
            candidate := facts.FileImports[index]
            if candidate.Alias != null
                && string.Equals(candidate.Alias, alias, StringComparison.Ordinal) {
                return candidate
            }
            index = index + 1
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
        name := TypeName(typeInfo)
        index := 0
        while index < facts.Declarations.Count {
            declaration := facts.Declarations[index]
            if declaration != null
                && string.Equals(
                    DeclarationFacts.GetDeclarationName(declaration),
                    name,
                    StringComparison.Ordinal) {
                return declaration
            }
            index = index + 1
        }
        return null
    }

    func TryFindMemberCore(
        owner: TypeInfo,
        name: string,
        substitution: Dictionary<string, TypeInfo>?,
        visited: HashSet<object>,
        out selection: AnalyzerMemberSelection): bool {
        if !visited.Add(owner) {
            selection = new AnalyzerMemberSelection()
            return false
        }

        generic := owner as GenericTypeInfo
        if generic != null && generic.GenericDefinition != null {
            genericSubstitution := CreateSourceGenericSubstitution(
                generic.GenericDefinition,
                generic.TypeArguments)
            return TryFindMemberCore(
                generic.GenericDefinition,
                name,
                genericSubstitution,
                visited,
                out selection)
        }

        alias := owner as AliasTypeInfo
        if alias != null {
            resolvedAlias := ResolveAlias(
                alias,
                new HashSet<string>(StringComparer.Ordinal))
            if resolvedAlias != owner {
                return TryFindMemberCore(
                    resolvedAlias,
                    name,
                    substitution,
                    visited,
                    out selection)
            }
        }
        nullable := owner as NullableTypeInfo
        if nullable != null {
            return TryFindMemberCore(
                nullable.InnerType,
                name,
                substitution,
                visited,
                out selection)
        }
        oblivious := owner as ObliviousTypeInfo
        if oblivious != null {
            return TryFindMemberCore(
                oblivious.InnerType,
                name,
                substitution,
                visited,
                out selection)
        }

        shape := new AnalyzerSourceMemberShape()
        if TryGetSourceMemberShape(owner, substitution, out shape) {
            memberIndex := 0
            while memberIndex < shape.DeclaredMembers.Length {
                member := shape.DeclaredMembers[memberIndex]
                if member.Name == name {
                    selection = new AnalyzerMemberSelection(
                        shape.Owner,
                        member,
                        GetDeclarationFile(shape.Owner),
                        member.Line,
                        member.Column,
                        member.KindName,
                        member.IsExported)
                    return true
                }
                memberIndex = memberIndex + 1
            }
            if shape.BaseType != null {
                return TryFindMemberCore(
                    shape.BaseType,
                    name,
                    substitution,
                    visited,
                    out selection)
            }
        }

        enumType := owner as EnumTypeInfo
        if enumType != null {
            enumIndex := 0
            while enumIndex < enumType.Declaration.Members.Count {
                enumMember := enumType.Declaration.Members[enumIndex]
                if enumMember.Name == name {
                    selection = new AnalyzerMemberSelection(
                        enumType,
                        null,
                        GetDeclarationFile(enumType),
                        enumMember.Line,
                        enumMember.Column,
                        "enumMember",
                        true)
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
                    selection = new AnalyzerMemberSelection(
                        unionType,
                        null,
                        GetDeclarationFile(unionType),
                        unionCase.Line,
                        unionCase.Column,
                        "unionCase",
                        VisibilityConventions.IsExportedIdentifier(name))
                    return true
                }
                caseIndex = caseIndex + 1
            }
        }

        selection = new AnalyzerMemberSelection()
        return false
    }

    func CreateSourceGenericSubstitution(
        definition: TypeInfo,
        arguments: List<TypeInfo>): Dictionary<string, TypeInfo>? {
        parameters: TypeParameter[]? = null
        classType := definition as ClassTypeInfo
        if classType != null { parameters = classType.TypeParameters }
        structType := definition as StructTypeInfo
        if structType != null { parameters = structType.TypeParameters }
        recordType := definition as RecordTypeInfo
        if recordType != null { parameters = recordType.TypeParameters }
        interfaceType := definition as InterfaceTypeInfo
        if interfaceType != null { parameters = interfaceType.TypeParameters }
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

    func CreateOwnerOpenSubstitution(
        declarationOwner: TypeInfo,
        substitution: Dictionary<string, TypeInfo>?): Dictionary<string, TypeInfo> {
        result := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
        if substitution != null {
            foreach entry in substitution {
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

    static func AddOpenTypeParameters(
        owner: TypeInfo,
        substitution: Dictionary<string, TypeInfo>) {
        parameters: TypeParameter[]? = null
        classType := owner as ClassTypeInfo
        if classType != null { parameters = classType.TypeParameters }
        structType := owner as StructTypeInfo
        if structType != null { parameters = structType.TypeParameters }
        recordType := owner as RecordTypeInfo
        if recordType != null { parameters = recordType.TypeParameters }
        interfaceType := owner as InterfaceTypeInfo
        if interfaceType != null { parameters = interfaceType.TypeParameters }
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

    func CollectAvailableSourceMemberNames(
        owner: TypeInfo,
        includeStaticMembers: bool,
        substitution: Dictionary<string, TypeInfo>?,
        visited: HashSet<object>,
        result: List<string>) {
        if !visited.Add(owner) {
            return
        }
        generic := owner as GenericTypeInfo
        if generic != null && generic.GenericDefinition != null {
            CollectAvailableSourceMemberNames(
                generic.GenericDefinition,
                includeStaticMembers,
                CreateSourceGenericSubstitution(
                    generic.GenericDefinition,
                    generic.TypeArguments),
                visited,
                result)
            return
        }
        alias := owner as AliasTypeInfo
        if alias != null {
            resolvedAlias := ResolveAlias(
                alias,
                new HashSet<string>(StringComparer.Ordinal))
            if resolvedAlias != owner {
                CollectAvailableSourceMemberNames(
                    resolvedAlias,
                    includeStaticMembers,
                    substitution,
                    visited,
                    result)
            }
            return
        }
        nullable := owner as NullableTypeInfo
        if nullable != null {
            result.Add("HasValue")
            result.Add("Value")
            CollectAvailableSourceMemberNames(
                nullable.InnerType,
                includeStaticMembers,
                substitution,
                visited,
                result)
            return
        }
        oblivious := owner as ObliviousTypeInfo
        if oblivious != null {
            CollectAvailableSourceMemberNames(
                oblivious.InnerType,
                includeStaticMembers,
                substitution,
                visited,
                result)
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
                parameterIndex := 0
                while parameterIndex < shape.PrimaryParameters.Length {
                    result.Add(shape.PrimaryParameters[parameterIndex].Name)
                    parameterIndex = parameterIndex + 1
                }
            }
            if shape.BaseType != null {
                CollectAvailableSourceMemberNames(
                    shape.BaseType,
                    includeStaticMembers,
                    substitution,
                    visited,
                    result)
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
        return new AnalyzerSourceTypeSelection(
            typeInfo,
            FindDeclarationForType(typeInfo),
            resultFile,
            claimed)
    }

    func SelectionForNamedDeclaration(
        typeInfo: TypeInfo,
        name: string,
        namespaceName: string?,
        filterNamespace: bool,
        requireExported: bool,
        claimed: bool): AnalyzerSourceTypeSelection {
        fileIndex := 0
        while fileIndex < files.Count {
            facts := files[fileIndex]
            if !filterNamespace
                || string.Equals(
                    facts.NamespaceName,
                    namespaceName,
                    StringComparison.Ordinal) {
                declarationIndex := 0
                while declarationIndex < facts.Declarations.Count {
                    declaration := facts.Declarations[declarationIndex]
                    if declaration != null
                        && string.Equals(
                            DeclarationFacts.GetDeclarationName(declaration),
                            name,
                            StringComparison.Ordinal)
                        && (!requireExported
                            || DeclarationFacts.IsExportedDeclaration(
                                declaration,
                                name)) {
                        return new AnalyzerSourceTypeSelection(
                            typeInfo,
                            declaration,
                            facts.FilePath,
                            claimed)
                    }
                    declarationIndex = declarationIndex + 1
                }
            }
            fileIndex = fileIndex + 1
        }
        return SelectionFor(typeInfo, claimed)
    }

    static func MissingSelection(claimed: bool): AnalyzerSourceTypeSelection {
        return new AnalyzerSourceTypeSelection(
            BuiltInTypes.Unknown,
            null,
            null,
            claimed)
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
        if ExternalQualifiedTypeResolver.TryResolve(assemblies, fullName, out runtimeType) {
            typeInfo = new ReflectionTypeInfo(runtimeType)
            externalTypes[fullName] = typeInfo
            return true
        }
        missingExternalTypes.Add(fullName)
        typeInfo = BuiltInTypes.Unknown
        return false
    }

    func TryResolveKnownOpenGeneric(name: string, arity: int, out typeInfo: Type): bool {
        fullName := ""
        if name == "List" && arity == 1 { fullName = "System.Collections.Generic.List`1" }
        else if name == "IEnumerable" && arity == 1 { fullName = "System.Collections.Generic.IEnumerable`1" }
        else if name == "IQueryable" && arity == 1 { fullName = "System.Linq.IQueryable`1" }
        else if name == "ICollection" && arity == 1 { fullName = "System.Collections.Generic.ICollection`1" }
        else if name == "IList" && arity == 1 { fullName = "System.Collections.Generic.IList`1" }
        else if name == "Dictionary" && arity == 2 { fullName = "System.Collections.Generic.Dictionary`2" }
        else if name == "IDictionary" && arity == 2 { fullName = "System.Collections.Generic.IDictionary`2" }
        else if name == "Task" && arity == 1 { fullName = "System.Threading.Tasks.Task`1" }
        else if name == "ValueTask" && arity == 1 { fullName = "System.Threading.Tasks.ValueTask`1" }
        else if name == "ValueTuple" && arity >= 1 && arity <= 8 { fullName = "System.ValueTuple`" + arity.ToString() }
        else if (name == "Result" || name == "NSharpLang.Runtime.Result") && arity == 2 { fullName = "NSharpLang.Runtime.Result`2" }
        else if (name == "JsonTypeInfo" || name == "System.Text.Json.Serialization.Metadata.JsonTypeInfo") && arity == 1 { fullName = "System.Text.Json.Serialization.Metadata.JsonTypeInfo`1" }
        else if name == "Func" && arity >= 1 && arity <= 5 { fullName = "System.Func`" + arity.ToString() }
        else if name == "Action" && arity >= 1 && arity <= 4 { fullName = "System.Action`" + arity.ToString() }
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
        return kind == "ClassDeclaration"
            || kind == "StructDeclaration"
            || kind == "RecordDeclaration"
            || kind == "SoaRecordDeclaration"
            || kind == "InterfaceDeclaration"
            || kind == "UnionDeclaration"
            || kind == "EnumDeclaration"
            || kind == "TypeAliasDeclaration"
            || kind == "NewtypeDeclaration"
    }

    static func ContainsUnknown(typeInfo: TypeInfo): bool {
        if typeInfo as UnknownTypeInfo != null { return true }
        generic := typeInfo as GenericTypeInfo
        if generic != null {
            if generic.GenericDefinition == null { return true }
            index := 0
            while index < generic.TypeArguments.Count {
                if ContainsUnknown(generic.TypeArguments[index]) { return true }
                index = index + 1
            }
            return false
        }
        array := typeInfo as ArrayTypeInfo
        if array != null { return ContainsUnknown(array.ElementType) }
        nullable := typeInfo as NullableTypeInfo
        if nullable != null { return ContainsUnknown(nullable.InnerType) }
        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null { return ContainsUnknown(oblivious.InnerType) }
        unionType := typeInfo as AnonymousUnionTypeInfo
        if unionType != null {
            index := 0
            while index < unionType.Arms.Count {
                if ContainsUnknown(unionType.Arms[index]) { return true }
                index = index + 1
            }
        }
        tuple := typeInfo as TupleTypeInfo
        if tuple != null {
            index := 0
            while index < tuple.Elements.Count {
                if ContainsUnknown(tuple.Elements[index].Type) { return true }
                index = index + 1
            }
        }
        function := typeInfo as FunctionTypeInfo
        if function != null {
            if function.ParameterTypes == null || function.ReturnType == null { return true }
            index := 0
            while index < function.ParameterTypes.Count {
                if ContainsUnknown(function.ParameterTypes[index]) { return true }
                index = index + 1
            }
            return ContainsUnknown(function.ReturnType)
        }
        byRef := typeInfo as ByRefTypeInfo
        return byRef != null && ContainsUnknown(byRef.InnerType)
    }

    static func GenericHeadArity(typeInfo: TypeInfo): int {
        classType := typeInfo as ClassTypeInfo
        if classType != null { return classType.TypeParameters.Length }
        structType := typeInfo as StructTypeInfo
        if structType != null { return structType.TypeParameters.Length }
        recordType := typeInfo as RecordTypeInfo
        if recordType != null { return recordType.TypeParameters.Length }
        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null { return interfaceType.TypeParameters.Length }
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
            if reflection.Type.get_IsGenericTypeDefinition() {
                return reflection.Type.GetGenericArguments().Length
            }
            return 0
        }
        if typeInfo as SimpleTypeInfo != null
            || typeInfo as SoaRecordTypeInfo != null
            || typeInfo as EnumTypeInfo != null
            || typeInfo as AliasTypeInfo != null
            || typeInfo as NewtypeInfo != null {
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
        if classType != null { return classType.Name }
        structType := typeInfo as StructTypeInfo
        if structType != null { return structType.Name }
        recordType := typeInfo as RecordTypeInfo
        if recordType != null { return recordType.Name }
        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null { return interfaceType.Name }
        unionType := typeInfo as UnionTypeInfo
        if unionType != null { return unionType.Declaration.Name }
        enumType := typeInfo as EnumTypeInfo
        if enumType != null { return enumType.Declaration.Name }
        soaType := typeInfo as SoaRecordTypeInfo
        if soaType != null { return soaType.Declaration.Name }
        newtypeInfo := typeInfo as NewtypeInfo
        if newtypeInfo != null { return newtypeInfo.Name }
        return ""
    }
}
