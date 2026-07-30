namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Columnar

// PROJECT DISCOVERY: how a name that no scope, no file alias and no import knows still resolves,
// because some OTHER file in the same project declares it.
//
// N# has no `using`-style type import. A project's files see each other's exported top-level
// declarations directly, which means the resolver has to be able to look at every source file in the
// project — read it, parse it, and read its declared namespace. That capability is what this file
// owns, in two pieces:
//
//   * `AnalyzerProjectSourceProvider` — the SOURCE AND UNIT PROVIDER. The project's source texts (an
//     in-memory snapshot when one was supplied, the files on disk otherwise), the parsed unit per
//     file, and the two namespace questions asked of files rather than of units. Four caches.
//   * `AnalyzerProjectTypeDiscovery` — the DISCOVERY WALK itself: the visible-namespace sweep, the
//     unique-exported fallback, the materialisation of a selection into a type plus a symbol
//     declaration, and the inaccessible-declaration DECISION.
//
// THREE RULES ARE LOAD-BEARING.
//
//   1. THE ENUMERATION ORDER IS PART OF THE ANSWER. Every walk here takes the FIRST file that
//      declares the name, and duplicate names across files are ordinary, not pathological: measured
//      over this repository's own root project (440 files) there are 47 distinct
//      (namespace, name) pairs declared by more than one file — `Person` by 14 files, `Main` by 42,
//      `Calculator` by 5. So "first wins" is a decision and the order it is taken in must be
//      reproduced exactly: the in-memory snapshot is walked in INSERTION order (the order
//      `AddSourceText` saw, first spelling of a path winning), and the disk fallback in
//      `ProjectConfig.EnumerateSourceFiles` order. `AnalyzerDeclarationContext` already depends on
//      this same order, because the units are handed to it in it.
//   2. THE WALK IS SILENT; ONE DECISION ON ITS PATH IS NOT. Resolution reports nothing. The
//      inaccessible-declaration probe DOES report (`InaccessibleMember`), so only its decision lives
//      here — "some visible namespace has a non-exported declaration of this name, declared in THIS
//      file" — and the shell keeps the report. That ordering matters: the probe runs BETWEEN the
//      namespace sweep and the unique-exported fallback, so a single entry point returns all three
//      outcomes rather than letting the shell interleave them.
//   3. A NEGATIVE PARSE IS CACHED. A file that fails to parse caches a null unit, so it is parsed
//      once and skipped thereafter. `Analyze` does NOT clear that cache or the source snapshot —
//      only `SetProjectSourceTexts` does — while the two namespace caches ARE cleared per analysis.
//      That asymmetry is reproduced, not tidied.

// The analyzer's view of the project's sources: which files there are, what they contain, what they
// parse to, and what namespace they declare. Constructed once per analyzer and never rebuilt, because
// the parsed-unit cache and the source snapshot outlive a single `Analyze` call.
public class AnalyzerProjectSourceProvider {

    // The in-memory snapshot, keyed by full path, case-insensitive — exactly the shell's dictionary.
    sourceTexts: Dictionary<string, string>
    // The snapshot's keys in INSERTION order. A dictionary with no removals enumerates in insertion
    // order, and rule 1 makes that order part of the answer, so it is held explicitly rather than
    // depended on implicitly.
    sourceTextOrder: List<string>
    // file full path -> parsed unit, or null when the file could not be parsed.
    unitCache: Dictionary<string, CompilationUnit?>
    // project root -> the set of namespaces its files declare.
    namespaceCache: Dictionary<string, HashSet<string>>
    // file full path -> the namespace that file declares, or null.
    fileNamespaceCache: Dictionary<string, string?>
    projectRootValue: string?

    // The project root of the analysis in progress, or null when there is none.
    public ProjectRoot: string? => projectRootValue

    constructor() {
        sourceTexts = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        sourceTextOrder = new List<string>()
        unitCache = new Dictionary<string, CompilationUnit?>(StringComparer.OrdinalIgnoreCase)
        namespaceCache = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal)
        fileNamespaceCache = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase)
        projectRootValue = null
    }

    // ---- the source snapshot -------------------------------------------------------------------

    // Starts a fresh snapshot. The parsed units go with it: they were parsed from the OLD texts.
    public func ResetSourceTexts() {
        sourceTexts.Clear()
        sourceTextOrder.Clear()
        unitCache.Clear()
    }

    // Adds one file to the snapshot. A path already present keeps its ORDER and takes the new text,
    // exactly as an indexer assignment into the shell's dictionary did.
    public func AddSourceText(filePath: string, sourceText: string) {
        fullPath := Path.GetFullPath(filePath)
        if !sourceTexts.ContainsKey(fullPath) {
            sourceTextOrder.Add(fullPath)
        }

        sourceTexts[fullPath] = sourceText
    }

    // Called at the start of every analysis: the project root changes and the two namespace caches
    // are per-analysis. The source snapshot and the parsed units deliberately survive.
    public func BeginAnalysis(projectRoot: string?) {
        projectRootValue = projectRoot
        namespaceCache.Clear()
        fileNamespaceCache.Clear()
    }

    // The snapshot's text for a file, or null when the file is not in the snapshot. Null means "ask
    // the disk", not "empty file".
    public func TryGetProjectSourceText(filePath: string?): string? {
        if filePath == null {
            return null
        }

        fullPath := Path.GetFullPath(filePath)
        text := ""
        if sourceTexts.TryGetValue(fullPath, out text) {
            return text
        }

        return null
    }

    // True when the snapshot holds this exact full path. Used where an unsaved editor buffer must
    // count as an existing file.
    public func ContainsSourceText(fullPath: string): bool {
        return sourceTexts.ContainsKey(fullPath)
    }

    // The text of a project file: the snapshot first, then the file on disk, then empty.
    public func ProjectSourceText(filePath: string): string {
        snapshot := TryGetProjectSourceText(filePath)
        if snapshot != null {
            return snapshot
        }

        if File.Exists(filePath) {
            return File.ReadAllText(filePath)
        }

        return ""
    }

    // ---- the file list ------------------------------------------------------------------------

    // Every project source file, in the order rule 1 requires. The snapshot wins whole when there is
    // one; otherwise the project root is enumerated and files that have vanished are skipped.
    public func SourceFilePaths(): List<string> {
        if sourceTexts.Count > 0 {
            return sourceTextOrder
        }

        paths := new List<string>()
        root := projectRootValue
        if root == null || string.IsNullOrWhiteSpace(root) || !Directory.Exists(root) {
            return paths
        }

        foreach filePath in ProjectConfig.EnumerateSourceFiles(root) {
            fullPath := Path.GetFullPath(filePath)
            if File.Exists(fullPath) {
                paths.Add(fullPath)
            }
        }

        return paths
    }

    // ---- parsed units -------------------------------------------------------------------------

    // The parsed unit for a project file, or null when it does not parse. Parsed at most once per
    // path: a failure caches null and is not retried (rule 3).
    public func GetProjectCompilationUnit(filePath: string): CompilationUnit? {
        fullPath := Path.GetFullPath(filePath)
        cached: CompilationUnit? = null
        if unitCache.TryGetValue(fullPath, out cached) {
            return cached
        }

        try {
            parseResult := ColumnarParserRecovery.ParseFileAst(ProjectSourceText(fullPath), fullPath)
            unit := parseResult.CompilationUnit
            unitCache[fullPath] = unit
            return unit
        } catch {
            // A bare `null` through a dictionary indexer is off the columnar surface; the typed
            // local is the same write.
            missingUnit: CompilationUnit? = null
            unitCache[fullPath] = missingUnit
            return null
        }
    }

    // Hands every parseable project file to the declaration context, in enumeration order — which is
    // what makes the context's own "first file wins" agree with this file's walks.
    public func AddProjectUnitsTo(context: AnalyzerDeclarationContext) {
        paths := SourceFilePaths()
        index := 0
        while index < paths.Count {
            filePath := paths[index]
            unit := GetProjectCompilationUnit(filePath)
            if unit != null {
                context.AddCompilationUnit(filePath, unit)
            }

            index = index + 1
        }
    }

    // ---- namespaces ---------------------------------------------------------------------------

    // The namespace a unit declares: its package name, else its namespace name, else none.
    public static func UnitNamespace(unit: CompilationUnit?): string? {
        if unit == null {
            return null
        }

        packageDeclaration := unit.Package
        if packageDeclaration != null {
            return packageDeclaration.Name
        }

        namespaceDeclaration := unit.Namespace
        if namespaceDeclaration != null {
            return namespaceDeclaration.Name
        }

        return null
    }

    // True when some file of the project under analysis declares this namespace.
    public func ProjectNamespaceExists(namespaceName: string): bool {
        root := projectRootValue
        if root == null || string.IsNullOrWhiteSpace(root) || !Directory.Exists(root) {
            return false
        }

        return ProjectNamespaces(root).Contains(namespaceName)
    }

    // Every namespace declared by the files under a root. Enumerated and parsed from DISK, not from
    // the snapshot, and memoised per root for the analysis.
    func ProjectNamespaces(projectRoot: string): HashSet<string> {
        cached := new HashSet<string>(StringComparer.Ordinal)
        if namespaceCache.TryGetValue(projectRoot, out cached) {
            return cached
        }

        namespaces := new HashSet<string>(StringComparer.Ordinal)
        foreach filePath in ProjectConfig.EnumerateSourceFiles(projectRoot) {
            source := File.ReadAllText(filePath)
            parseResult := ColumnarParserRecovery.ParseFileAst(source, filePath)
            declaredNamespace := UnitNamespace(parseResult.CompilationUnit)
            if !string.IsNullOrWhiteSpace(declaredNamespace) {
                namespaces.Add(declaredNamespace)
            }
        }

        namespaceCache[projectRoot] = namespaces
        return namespaces
    }

    // The namespace a FILE declares, read from disk and memoised for the analysis — including the
    // negative answer for a file that does not exist.
    public func GetNamespaceForFile(filePath: string?): string? {
        if filePath == null || string.IsNullOrWhiteSpace(filePath) {
            return null
        }

        fullPath := Path.GetFullPath(filePath)
        cached: string? = null
        if fileNamespaceCache.TryGetValue(fullPath, out cached) {
            return cached
        }

        if !File.Exists(fullPath) {
            missingNamespace: string? = null
            fileNamespaceCache[fullPath] = missingNamespace
            return null
        }

        source := File.ReadAllText(fullPath)
        parseResult := ColumnarParserRecovery.ParseFileAst(source, fullPath)
        declaredNamespace := UnitNamespace(parseResult.CompilationUnit)
        fileNamespaceCache[fullPath] = declaredNamespace
        return declaredNamespace
    }
}

// The project-discovery walk: a name resolved because another file in a visible namespace declares
// it. Silent, except that it decides — and does not report — the inaccessible-declaration case.
public class AnalyzerProjectTypeDiscovery {

    sources: AnalyzerProjectSourceProvider
    declarationContext: AnalyzerDeclarationContext
    usingNamespaces: List<string>
    // name -> declaring file, the snapshot the project index is built from. Owned by the shell and
    // cleared per analysis, so it is handed in once and written through.
    typeDeclarationFiles: Dictionary<string, string>

    constructor(
        sourceProvider: AnalyzerProjectSourceProvider,
        context: AnalyzerDeclarationContext,
        usingNamespaceNames: List<string>,
        declarationFiles: Dictionary<string, string>) {
        sources = sourceProvider
        declarationContext = context
        usingNamespaces = usingNamespaceNames
        typeDeclarationFiles = declarationFiles
    }

    // THE TYPE CHANNEL, whole. Three outcomes in one call, because their ORDER is the semantics
    // (rule 2):
    //   * returns true — the name is a project type; `typeInfo` and `declaration` are set and the
    //     declaring file has been recorded.
    //   * returns false with `inaccessibleFilePath` non-null — a visible namespace declares the name
    //     but does not export it. The caller reports; the unique-exported fallback is NOT tried.
    //   * returns false with `inaccessibleFilePath` null — no project type of that name.
    // `probeInaccessible` is the caller's "I have a real source position" (line > 0); without one the
    // middle outcome cannot be reported and is not looked for.
    public func ResolveVisibleProjectType(
        name: string,
        currentNamespace: string?,
        probeInaccessible: bool,
        out typeInfo: TypeInfo,
        out declaration: SymbolDeclaration?,
        out inaccessibleFilePath: string?): bool {
        inaccessibleFilePath = null
        visible := AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(currentNamespace, usingNamespaces)
        index := 0
        while index < visible.Count {
            if TryResolveProjectTypeInNamespace(
                    name,
                    visible[index],
                    currentNamespace,
                    out typeInfo,
                    out declaration) {
                RecordDeclarationFile(name, declaration)
                return true
            }

            index = index + 1
        }

        // The guard is a nested `if` rather than `probeInaccessible && Try…(out …)`: an `out`
        // argument in the right-hand operand of `&&` is off the columnar surface.
        if probeInaccessible {
            if TryFindInaccessibleVisibleDeclaration(
                    name,
                    currentNamespace,
                    false,
                    out inaccessibleFilePath) {
                typeInfo = BuiltInTypes.Unknown
                declaration = null
                return false
            }
        }

        if TryResolveUniqueExportedProjectType(name, out typeInfo, out declaration) {
            RecordDeclarationFile(name, declaration)
            return true
        }

        typeInfo = BuiltInTypes.Unknown
        declaration = null
        return false
    }

    // One visible namespace. A namespace that is NOT the file's own requires the declaration to be
    // exported; the file's own namespace does not.
    public func TryResolveProjectTypeInNamespace(
        name: string,
        namespaceName: string?,
        currentNamespace: string?,
        out typeInfo: TypeInfo,
        out declaration: SymbolDeclaration?): bool {
        requireExported := !string.Equals(namespaceName, currentNamespace, StringComparison.Ordinal)
        selection := new AnalyzerSourceTypeSelection(BuiltInTypes.Unknown, null, null, false)
        resolved := declarationContext.TryResolveProjectTypeInNamespace(
            name,
            namespaceName,
            requireExported,
            out selection)
        return TryMaterializeProjectTypeSelection(name, resolved, selection, out typeInfo, out declaration)
    }

    // The last resort: exactly one file in the whole project exports this name, whatever namespace it
    // is in.
    func TryResolveUniqueExportedProjectType(
        name: string,
        out typeInfo: TypeInfo,
        out declaration: SymbolDeclaration?): bool {
        selection := new AnalyzerSourceTypeSelection(BuiltInTypes.Unknown, null, null, false)
        resolved := declarationContext.TryResolveUniqueExportedType(name, out selection)
        return TryMaterializeProjectTypeSelection(name, resolved, selection, out typeInfo, out declaration)
    }

    // A selection becomes an answer only when it carries BOTH a declaration and the file it came
    // from; either missing is a miss, not an error.
    func TryMaterializeProjectTypeSelection(
        name: string,
        resolved: bool,
        selection: AnalyzerSourceTypeSelection,
        out typeInfo: TypeInfo,
        out declaration: SymbolDeclaration?): bool {
        sourceDeclaration := selection.Declaration as Declaration
        filePath := selection.FilePath
        if !resolved || sourceDeclaration == null || filePath == null || string.IsNullOrWhiteSpace(filePath) {
            typeInfo = BuiltInTypes.Unknown
            declaration = null
            return false
        }

        typeInfo = selection.Type
        declaration = CreateTopLevelSymbolDeclaration(
            name,
            filePath,
            sources.ProjectSourceText(filePath),
            sourceDeclaration)
        return true
    }

    // A top-level declaration's symbol identity. The LINE is the declaration's own; the COLUMN is
    // where the NAME starts on that line, which is what a go-to-definition span has to point at.
    public func CreateTopLevelSymbolDeclaration(
        name: string,
        filePath: string,
        sourceText: string,
        topLevelDeclaration: Declaration): SymbolDeclaration {
        line := topLevelDeclaration.Line
        column := topLevelDeclaration.Column
        return new SymbolDeclaration(
            name,
            filePath,
            line,
            CodeIntelligenceTextUtilities.FindIdentifierNameColumn(sourceText, name, line, column),
            DeclarationFacts.GetDeclarationKind(topLevelDeclaration))
    }

    // THE FUNCTION CHANNEL's discovery half. Exported top-level functions are visible project-wide in
    // visible namespaces without an import; non-exported ones stay file-private and fall through to
    // the undefined/inaccessible diagnostics. The FunctionTypeInfo itself is built by the caller,
    // which is why the matched declaration and its file come back out.
    public func TryResolveVisibleProjectFunction(
        name: string,
        currentNamespace: string?,
        out filePath: string?,
        out functionDeclaration: FunctionDeclaration?,
        out declaration: SymbolDeclaration?): bool {
        visible := AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(currentNamespace, usingNamespaces)
        paths := sources.SourceFilePaths()
        namespaceIndex := 0
        while namespaceIndex < visible.Count {
            visibleNamespace := visible[namespaceIndex]
            fileIndex := 0
            while fileIndex < paths.Count {
                candidatePath := paths[fileIndex]
                unit := sources.GetProjectCompilationUnit(candidatePath)
                if unit != null
                    && string.Equals(
                        AnalyzerProjectSourceProvider.UnitNamespace(unit),
                        visibleNamespace,
                        StringComparison.Ordinal) {
                    declarations := unit.Declarations
                    declarationIndex := 0
                    while declarationIndex < declarations.Count {
                        candidate := declarations[declarationIndex]
                        if IsExportedFunctionNamed(candidate, name) {
                            filePath = candidatePath
                            functionDeclaration = candidate as FunctionDeclaration
                            declaration = CreateTopLevelSymbolDeclaration(
                                name,
                                candidatePath,
                                sources.ProjectSourceText(candidatePath),
                                candidate)
                            return true
                        }

                        declarationIndex = declarationIndex + 1
                    }
                }

                fileIndex = fileIndex + 1
            }

            namespaceIndex = namespaceIndex + 1
        }

        filePath = null
        functionDeclaration = null
        declaration = null
        return false
    }

    // The inaccessible-FUNCTION decision, for the identifier path. Types take the same decision
    // inside `ResolveVisibleProjectType`, where its position in the sequence matters.
    public func TryFindInaccessibleVisibleFunction(
        name: string,
        currentNamespace: string?,
        out filePath: string?): bool {
        return TryFindInaccessibleVisibleDeclaration(name, currentNamespace, true, out filePath)
    }

    // "A visible namespace OTHER than my own declares this name and does not export it." The file's
    // OWN namespace is skipped: a name that is not exported is still visible inside its own
    // namespace, so finding it there is not an accessibility failure.
    func TryFindInaccessibleVisibleDeclaration(
        name: string,
        currentNamespace: string?,
        wantFunctions: bool,
        out filePath: string?): bool {
        visible := AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(currentNamespace, usingNamespaces)
        paths := sources.SourceFilePaths()
        namespaceIndex := 0
        while namespaceIndex < visible.Count {
            visibleNamespace := visible[namespaceIndex]
            if !string.Equals(visibleNamespace, currentNamespace, StringComparison.Ordinal) {
                fileIndex := 0
                while fileIndex < paths.Count {
                    candidatePath := paths[fileIndex]
                    unit := sources.GetProjectCompilationUnit(candidatePath)
                    if unit != null
                        && string.Equals(
                            AnalyzerProjectSourceProvider.UnitNamespace(unit),
                            visibleNamespace,
                            StringComparison.Ordinal) {
                        declarations := unit.Declarations
                        declarationIndex := 0
                        while declarationIndex < declarations.Count {
                            candidate := declarations[declarationIndex]
                            if MatchesDeclarationKind(candidate, wantFunctions)
                                && string.Equals(
                                    DeclarationFacts.GetDeclarationName(candidate),
                                    name,
                                    StringComparison.Ordinal)
                                && !DeclarationFacts.IsExportedDeclaration(candidate, name) {
                                filePath = candidatePath
                                return true
                            }

                            declarationIndex = declarationIndex + 1
                        }
                    }

                    fileIndex = fileIndex + 1
                }
            }

            namespaceIndex = namespaceIndex + 1
        }

        filePath = null
        return false
    }

    // ---- helpers ------------------------------------------------------------------------------

    func RecordDeclarationFile(name: string, declaration: SymbolDeclaration?) {
        if declaration == null {
            return
        }

        declarationFile := declaration.File
        if declarationFile != null && !string.IsNullOrWhiteSpace(declarationFile) {
            typeDeclarationFiles[name] = declarationFile
        }
    }

    // The kind test is TYPE IDENTITY, not a spelling: exactly the shell's `is ClassDeclaration or …`
    // and `is FunctionDeclaration` patterns.
    static func MatchesDeclarationKind(declaration: Declaration, wantFunctions: bool): bool {
        if wantFunctions {
            return declaration as FunctionDeclaration != null
        }

        return IsTopLevelTypeDeclaration(declaration)
    }

    // A top-level declaration that introduces a TYPE. Every declared family, and nothing else.
    public static func IsTopLevelTypeDeclaration(declaration: Declaration): bool {
        if declaration as ClassDeclaration != null { return true }
        if declaration as StructDeclaration != null { return true }
        if declaration as RecordDeclaration != null { return true }
        if declaration as SoaRecordDeclaration != null { return true }
        if declaration as InterfaceDeclaration != null { return true }
        if declaration as UnionDeclaration != null { return true }
        if declaration as EnumDeclaration != null { return true }
        if declaration as TypeAliasDeclaration != null { return true }
        if declaration as NewtypeDeclaration != null { return true }
        return false
    }

    static func IsExportedFunctionNamed(declaration: Declaration, name: string): bool {
        functionDeclaration := declaration as FunctionDeclaration
        if functionDeclaration == null {
            return false
        }

        if !string.Equals(functionDeclaration.Name, name, StringComparison.Ordinal) {
            return false
        }

        return DeclarationFacts.IsExportedDeclaration(declaration, name)
    }
}
