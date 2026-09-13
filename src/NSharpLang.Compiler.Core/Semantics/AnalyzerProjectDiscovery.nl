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
//     file, and the two namespace questions — asked of files, answered from their cached units.
//     Four caches.
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
//   3. A FILE IS PARSED AT MOST ONCE PER SNAPSHOT. Every question about a file — its unit, its
//      declared namespace, the project's namespace set — is answered through ONE parsed-unit cache,
//      snapshot text first and disk text otherwise. A file that fails to parse caches a null unit,
//      so it is parsed once and skipped thereafter. `Analyze` does NOT clear that cache or the
//      source snapshot — only `SetProjectSourceTexts` does — while the two namespace caches ARE
//      cleared per analysis. The namespace caches may be cheap to rebuild ONLY because rebuilding
//      them walks already-parsed units: a shared analyzer runs one `Analyze` per project file, so a
//      namespace rebuild that re-parsed the project would parse it once per file — O(files²), the
//      2026-08 `nlc query completions` hang (693 files, 480k recovery parses, tens of minutes).
//   4. THE UNIT OF PRIVACY IS THE NAMESPACE, NOT THE FILE. A camelCase top-level declaration — type
//      OR function — is visible to every file of the namespace that declares it and to no other
//      namespace. So both channels take the SAME export decision: require an export from every
//      visible namespace EXCEPT the asking file's own. A file-private tier does not exist in N#;
//      splitting one namespace across files is the ordinary way to write it, and two halves of one
//      namespace must see each other's helpers.

// The analyzer's view of the project's sources: which files there are, what they contain, what they
// parse to, and what namespace they declare. Constructed once per analyzer and never rebuilt, because
// the parsed-unit cache and the source snapshot outlive a single `Analyze` call.
class AnalyzerProjectSourceProvider {

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
    ProjectRoot: string? => projectRootValue

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
    func ResetSourceTexts() {
        sourceTexts.Clear()
        sourceTextOrder.Clear()
        unitCache.Clear()
    }

    // Adds one file to the snapshot. A path already present keeps its ORDER and takes the new text,
    // exactly as an indexer assignment into the shell's dictionary did.
    func AddSourceText(filePath: string, sourceText: string) {
        fullPath := Path.GetFullPath(filePath)
        if !sourceTexts.ContainsKey(fullPath) {
            sourceTextOrder.Add(fullPath)
        }

        sourceTexts[fullPath] = sourceText
    }

    // Called at the start of every analysis: the project root changes and the two namespace caches
    // are per-analysis. The source snapshot and the parsed units deliberately survive.
    func BeginAnalysis(projectRoot: string?) {
        projectRootValue = projectRoot
        namespaceCache.Clear()
        fileNamespaceCache.Clear()
    }

    // WHETHER THE FILES UNDER THIS ROOT COMPILE INTO ONE ASSEMBLY. A `project.yml` is what says so:
    // it is the file the SDK and `nlc build` read, and every file beneath it is one program with one
    // `Program` holder per namespace. A directory WITHOUT one is a folder of standalone scripts —
    // `examples/03-functions` is seven programs, each with its own `Main` — which the CLI builds one
    // file at a time and the Language Server opens with the directory as its fallback root. Rules
    // about what two FILES may declare between them apply only to the first shape.
    func CompilesAsOneProgram(): bool {
        root := projectRootValue
        if root == null || string.IsNullOrWhiteSpace(root) {
            return false
        }

        return File.Exists(Path.Combine(root, "project.yml"))
    }

    // The snapshot's text for a file, or null when the file is not in the snapshot. Null means "ask
    // the disk", not "empty file".
    func TryGetProjectSourceText(filePath: string?): string? {
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
    func ContainsSourceText(fullPath: string): bool {
        return sourceTexts.ContainsKey(fullPath)
    }

    // The text of a project file: the snapshot first, then the file on disk, then empty.
    func ProjectSourceText(filePath: string): string {
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
    func SourceFilePaths(): List<string> {
        if sourceTexts.Count > 0 {
            return sourceTextOrder
        }

        paths := new List<string>()
        root := projectRootValue
        if root == null || string.IsNullOrWhiteSpace(root) || !Directory.Exists(root) {
            return paths
        }

        for filePath in ProjectConfig.EnumerateSourceFiles(root) {
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
    func GetProjectCompilationUnit(filePath: string): CompilationUnit? {
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
    func AddProjectUnitsTo(context: AnalyzerDeclarationContext) {
        paths := SourceFilePaths()
        for filePath in paths {
            unit := GetProjectCompilationUnit(filePath)
            if unit != null {
                context.AddCompilationUnit(filePath, unit)
            }
        }
    }

    // ---- namespaces ---------------------------------------------------------------------------

    // The namespace a unit declares: its package name, else its namespace name, else none.
    static func UnitNamespace(unit: CompilationUnit?): string? {
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
    func ProjectNamespaceExists(namespaceName: string): bool {
        root := projectRootValue
        if root == null || string.IsNullOrWhiteSpace(root) || !Directory.Exists(root) {
            return false
        }

        return ProjectNamespaces(root).Contains(namespaceName)
    }

    // Every namespace declared by the files under a root. The file SET is the disk enumeration, but
    // each file's text and parse go through the SAME unit cache every other project question uses —
    // snapshot text first, disk otherwise, parsed at most once per snapshot (rule 3). Memoised per
    // root for the analysis; the per-analysis rebuild is a walk over cached units, never a re-parse.
    func ProjectNamespaces(projectRoot: string): HashSet<string> {
        cached := new HashSet<string>(StringComparer.Ordinal)
        if namespaceCache.TryGetValue(projectRoot, out cached) {
            return cached
        }

        namespaces := new HashSet<string>(StringComparer.Ordinal)
        for filePath in ProjectConfig.EnumerateSourceFiles(projectRoot) {
            declaredNamespace := UnitNamespace(GetProjectCompilationUnit(filePath))
            if !string.IsNullOrWhiteSpace(declaredNamespace) {
                namespaces.Add(declaredNamespace)
            }
        }

        namespaceCache[projectRoot] = namespaces
        return namespaces
    }

    // The namespace a FILE declares — the snapshot's text when the file is in it, the disk's
    // otherwise, through the shared unit cache (rule 3) — memoised for the analysis, including the
    // negative answer for a file that exists nowhere.
    func GetNamespaceForFile(filePath: string?): string? {
        if filePath == null || string.IsNullOrWhiteSpace(filePath) {
            return null
        }

        fullPath := Path.GetFullPath(filePath)
        cached: string? = null
        if fileNamespaceCache.TryGetValue(fullPath, out cached) {
            return cached
        }

        if !ContainsSourceText(fullPath) && !File.Exists(fullPath) {
            missingNamespace: string? = null
            fileNamespaceCache[fullPath] = missingNamespace
            return null
        }

        declaredNamespace := UnitNamespace(GetProjectCompilationUnit(fullPath))
        fileNamespaceCache[fullPath] = declaredNamespace
        return declaredNamespace
    }
}

// The project-discovery walk: a name resolved because another file in a visible namespace declares
// it. Silent, except that it decides — and does not report — the inaccessible-declaration case.
class AnalyzerProjectTypeDiscovery {
    sources: AnalyzerProjectSourceProvider
    declarationContext: AnalyzerDeclarationContext
    usingNamespaces: List<string>
    // name -> declaring file, the snapshot the project index is built from. Owned by the shell and
    // cleared per analysis, so it is handed in once and written through.
    typeDeclarationFiles: Dictionary<string, string>
    // The EXTERNAL half of the same question, because the project-wide fallback below has to know
    // whether an explicitly imported CLR type already answers the name. Handed in rather than
    // rebuilt: its cache is part of its answer. ABSENT means no assemblies are loaded — a contract
    // harness with no metadata load context — and then no imported CLR type can exist, which is the
    // same answer a probe over an empty assembly list gives.
    externalTypeProbe: AnalyzerExternalTypeProbe?
    // NL010's ledger. A SOURCE type is supplied by the namespace the sweep below found it in, and
    // that namespace is known HERE and nowhere else: the resolved type carries its own name and not
    // the namespace that answered for it.
    importUsageCredit: AnalyzerImportUsageCredit?
    // `SelectVisibleType`'s answers for the analysis in progress, keyed by everything they depend on.
    selectionMemo: Dictionary<string, SimpleNameSelection>

    constructor(sourceProvider: AnalyzerProjectSourceProvider, context: AnalyzerDeclarationContext, usingNamespaceNames: List<string>, declarationFiles: Dictionary<string, string>, externalProbe: AnalyzerExternalTypeProbe? = null) {
        sources = sourceProvider
        declarationContext = context
        usingNamespaces = usingNamespaceNames
        typeDeclarationFiles = declarationFiles
        externalTypeProbe = externalProbe
        importUsageCredit = null
        selectionMemo = new Dictionary<string, SimpleNameSelection>(StringComparer.Ordinal)
    }

    func SetImportUsageCredit(credit: AnalyzerImportUsageCredit?) {
        importUsageCredit = credit
    }

    // One call per analysis: the selections were decided against the previous file's namespace,
    // imports and sources.
    func BeginAnalysis() {
        selectionMemo.Clear()
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
    func ResolveVisibleProjectType(name: string, currentNamespace: string?, probeInaccessible: bool, out typeInfo: TypeInfo, out declaration: SymbolDeclaration?, out inaccessibleFilePath: string?): bool {
        inaccessibleFilePath = null

        // THE SELECTION DECIDES, AND THIS CHANNEL MATERIALISES ITS SOURCE ANSWER. The file's own
        // namespace, each enclosing one and then its imports are asked in `SimpleNamePrecedence`
        // order, and a SOURCE declaration found there is this channel's answer: the nearest one, or —
        // when two imports tie, which the caller reports as NL209 — the first import whose supplier
        // is source, so the tie still binds something while it is reported.
        //
        // A REFERENCED ASSEMBLY'S TYPE THAT WINS IS NOT A PROJECT TYPE AND IS NOT A MISS. In the
        // file's own or an enclosing namespace it is the nearest declaration of the name, so no
        // import, no inaccessible declaration and no project-wide fallback may answer in its place:
        // this channel steps aside and the external channel, which climbs the same chain first, binds
        // it. From an import it is exactly what the fallback guard below already defers to.
        selection := SelectVisibleType(name, currentNamespace)
        if selection.IsLexicalMetadata {
            typeInfo = BuiltInTypes.Unknown
            declaration = null
            return false
        }

        sourceNamespace: string? = null
        hasSourceNamespace := false
        if selection.Kind == SimpleNameSelectionKind.Source || (selection.Kind == SimpleNameSelectionKind.Ambiguous && selection.FirstIsSource) {
            sourceNamespace = selection.Namespace
            hasSourceNamespace = true
        } else if selection.Kind == SimpleNameSelectionKind.Ambiguous && selection.SecondIsSource {
            sourceNamespace = selection.SecondNamespace
            hasSourceNamespace = true
        }

        if hasSourceNamespace {
            if TryResolveProjectTypeInNamespace(name, sourceNamespace, currentNamespace, out typeInfo, out declaration) {
                RecordDeclarationFile(name, declaration)
                // NL010: THE NAMESPACE THAT ANSWERED IS THE IMPORT THAT SUPPLIED THE NAME. The
                // selection walks the file's own namespace, its enclosing ones and its imports in
                // order, so the entry that answered is exactly the one a reader would point at —
                // and an `import TaskCli.Services` beside `service: TaskService` is used, even
                // though the project-wide fallback below would also have found the type.
                credit := importUsageCredit
                if credit != null {
                    credit.CreditNamespaceSupplier(sourceNamespace)
                }

                return true
            }
        }

        // The guard is a nested `if` rather than `probeInaccessible && Try…(out …)`: an `out`
        // argument in the right-hand operand of `&&` is off the columnar surface.
        if probeInaccessible {
            if TryFindInaccessibleVisibleDeclaration(name, currentNamespace, false, out inaccessibleFilePath) {
                typeInfo = BuiltInTypes.Unknown
                declaration = null
                return false
            }
        }

        // AN EXPLICIT IMPORT IS NOT A LAST RESORT, AND THE FALLBACK BELOW IS.
        //
        // The sweep above is what the file ASKED for: its own namespace and the namespaces it wrote
        // an `import` for. The fallback is project-wide auto-discovery — a convenience that finds a
        // type nothing in this file named. An imported CLR type is an explicit reference, so it must
        // outrank the fallback, and until this guard it did not: a source class named
        // `SimdReductions` in a namespace this file never imported silently replaced the
        // `NSharpLang.Runtime.SimdReductions` the file's own `import` brought in, with no
        // diagnostic, and a parity harness became a self-comparison. Answering false here hands the
        // name to the caller's external channel, which resolves it through the imports in order.
        //
        // THE PROBE IS ASKED AT THE LOOKUP NAME, ARITY AND ALL. It used to be asked at the DISPLAY
        // name, which is the identity with its arity suffix removed — and metadata has no such name,
        // so `List`1` was probed as `List`, found nothing, and the guard did not fire: a source
        // `class List<T>` in a namespace a file never imported took the name back from the
        // `System.Collections.Generic.List` that file's own `import` brought in, and `items.Add(1)`
        // reported NL303. The guard was written for exactly that shape; only the generic half of it
        // was unreachable.
        importProbe := externalTypeProbe
        if importProbe != null && importProbe.ResolveImportedExternalType(name) != null {
            typeInfo = BuiltInTypes.Unknown
            declaration = null
            return false
        }

        if TryResolveUniqueExportedProjectType(name, out typeInfo, out declaration) {
            RecordDeclarationFile(name, declaration)
            return true
        }

        typeInfo = BuiltInTypes.Unknown
        declaration = null
        return false
    }

    // `SimpleNamePrecedence.Select`, answered from this project's sources and its referenced
    // assemblies. The SOURCE answer is the one the sweeps here take — the file's own namespace needs no
    // export, every other one does — and the METADATA answer is the probe's, asked only where no source
    // declaration answered, because at one namespace the source declaration wins. Nothing is
    // materialised and nothing is recorded; the caller decides what the selection means.
    //
    // MEMOISED FOR THE ANALYSIS. The type channel and the NL209 gate both ask it of every name that
    // reaches them, and each source answer is a sweep of the project's files, so the second asking is
    // a lookup. The key carries everything the answer depends on that can move inside one analysis:
    // the asking namespace, the import list (it grows as a file's imports are read) and the loaded
    // assembly count (an import can load a reference). `BeginAnalysis` drops it with the sources.
    func SelectVisibleType(name: string, currentNamespace: string?): SimpleNameSelection {
        probe := externalTypeProbe
        assemblyCount := 0
        if probe != null {
            assemblyCount = probe.AssemblyCount
        }

        key := (currentNamespace ?? "") + "|" + usingNamespaces.Count.ToString() + "|" + assemblyCount.ToString() + "|" + name
        memo := new SimpleNameSelection(new List<SimpleNameCandidate>())
        if selectionMemo.TryGetValue(key, out memo) {
            return memo
        }

        selection := SimpleNamePrecedence.Select(currentNamespace, usingNamespaces)
        while !selection.IsSettled {
            candidate := selection.Current
            declaresSource := DeclaresProjectTypeInNamespace(name, candidate.Namespace, candidate.RequiresExport)
            declaresMetadata := false
            if !declaresSource && probe != null {
                declaresMetadata = probe.NamespaceDeclares(candidate.Namespace, name)
            }

            selection.Answer(declaresSource, declaresMetadata)
        }

        selectionMemo[key] = selection
        return selection
    }

    // The SOURCE answer a selection asks of one namespace: exactly the condition under which
    // `TryResolveProjectTypeInNamespace` would materialise a declaration there, without materialising
    // it.
    func DeclaresProjectTypeInNamespace(name: string, namespaceName: string?, requireExported: bool): bool {
        sourceSelection := new AnalyzerSourceTypeSelection(BuiltInTypes.Unknown, null, null, false)
        if !declarationContext.TryResolveProjectTypeInNamespace(name, namespaceName, requireExported, out sourceSelection) {
            return false
        }

        return sourceSelection.Declaration as Declaration != null && !string.IsNullOrWhiteSpace(sourceSelection.FilePath)
    }

    // TWO IMPORTS THAT SUPPLY ONE NAME, which is an error rather than a race: C# reports CS0104 for
    // exactly this shape and so does N#, because whichever import happened to be written first is
    // not what the developer meant to select — and `nlc format` sorts imports, so "first" is not even
    // the developer's to choose.
    //
    // WHAT IS *NOT* AMBIGUOUS, and every exclusion is C#'s and `SimpleNamePrecedence`'s: a
    // declaration in the file's own namespace or an ENCLOSING one — from source OR from a referenced
    // assembly — wins outright over every import, and the project-wide auto-discovery fallback is
    // never a candidate. At ONE imported namespace a source declaration and a metadata type of the
    // same full name are one candidate, not two. The tie itself is source against source, source
    // against metadata or metadata against metadata; the selection does not care which.
    //
    // THE PROBE NAME CARRIES ITS ARITY AND THE REPORT CARRIES THE WRITTEN ONE. ``List`1`` and `List`
    // are different identities in metadata, so the question asked is the LOOKUP name; the two
    // candidates a reader is shown are spelled the way the file spells them, FULLY QUALIFIED, in
    // import order.
    func TryFindAmbiguousImportedType(name: string, currentNamespace: string?, out firstCandidate: string, out secondCandidate: string): bool {
        firstCandidate = ""
        secondCandidate = ""
        selection := SelectVisibleType(name, currentNamespace)
        if selection.Kind != SimpleNameSelectionKind.Ambiguous {
            return false
        }

        writtenName := TypeArityNames.Display(name)
        firstCandidate = selection.QualifiedName(writtenName)
        secondCandidate = selection.SecondQualifiedName(writtenName)
        return true
    }

    // A NAMESPACE-QUALIFIED PROJECT TYPE — the `Example` half of `Example.Handle`.
    //
    // The visible-namespace walk above answers a BARE name by trying every namespace the file can
    // see. A qualified reference has already NAMED its namespace, so exactly one is asked and the
    // file's imports do not enter into it. The export rule is the same one: the file's own namespace
    // needs no export, every other one does.
    func ResolveNamespaceQualifiedProjectType(namespaceName: string, name: string, currentNamespace: string?, out typeInfo: TypeInfo, out declaration: SymbolDeclaration?): bool {
        if TryResolveProjectTypeInNamespace(name, namespaceName, currentNamespace, out typeInfo, out declaration) {
            RecordDeclarationFile(name, declaration)
            return true
        }

        typeInfo = BuiltInTypes.Unknown
        declaration = null
        return false
    }

    // One visible namespace. A namespace that is NOT the file's own requires the declaration to be
    // exported; the file's own namespace does not.
    func TryResolveProjectTypeInNamespace(name: string, namespaceName: string?, currentNamespace: string?, out typeInfo: TypeInfo, out declaration: SymbolDeclaration?): bool {
        requireExported := !string.Equals(namespaceName, currentNamespace, StringComparison.Ordinal)
        selection := new AnalyzerSourceTypeSelection(BuiltInTypes.Unknown, null, null, false)
        resolved := declarationContext.TryResolveProjectTypeInNamespace(name, namespaceName, requireExported, out selection)
        return TryMaterializeProjectTypeSelection(name, resolved, selection, out typeInfo, out declaration)
    }

    // The last resort: exactly one file in the whole project exports this name, whatever namespace it
    // is in.
    func TryResolveUniqueExportedProjectType(name: string, out typeInfo: TypeInfo, out declaration: SymbolDeclaration?): bool {
        selection := new AnalyzerSourceTypeSelection(BuiltInTypes.Unknown, null, null, false)
        resolved := declarationContext.TryResolveUniqueExportedType(name, out selection)
        return TryMaterializeProjectTypeSelection(name, resolved, selection, out typeInfo, out declaration)
    }

    // A selection becomes an answer only when it carries BOTH a declaration and the file it came
    // from; either missing is a miss, not an error.
    func TryMaterializeProjectTypeSelection(name: string, resolved: bool, selection: AnalyzerSourceTypeSelection, out typeInfo: TypeInfo, out declaration: SymbolDeclaration?): bool {
        sourceDeclaration := selection.Declaration as Declaration
        filePath := selection.FilePath
        if !resolved || sourceDeclaration == null || filePath == null || string.IsNullOrWhiteSpace(filePath) {
            typeInfo = BuiltInTypes.Unknown
            declaration = null
            return false
        }

        typeInfo = selection.Type
        declaration = CreateTopLevelSymbolDeclaration(name, filePath, sources.ProjectSourceText(filePath), sourceDeclaration)
        return true
    }

    // A top-level declaration's symbol identity. The LINE is the declaration's own; the COLUMN is
    // where the NAME starts on that line, which is what a go-to-definition span has to point at.
    func CreateTopLevelSymbolDeclaration(name: string, filePath: string, sourceText: string, topLevelDeclaration: Declaration): SymbolDeclaration {
        line := topLevelDeclaration.Line
        column := topLevelDeclaration.Column
        // `name` may be an identity key (`Handle``1`); the SPAN is over what is written in the file,
        // which is the bare name.
        writtenName := TypeArityNames.Display(name)
        return new SymbolDeclaration(writtenName, filePath, line, CodeIntelligenceTextUtilities.FindIdentifierNameColumn(sourceText, writtenName, line, column), DeclarationFacts.GetDeclarationKind(topLevelDeclaration))
    }

    // THE FUNCTION CHANNEL's discovery half, and it takes the SAME export decision the type channel
    // takes in `TryResolveProjectTypeInNamespace`: a camelCase top-level declaration is private to its
    // NAMESPACE, not to its file. Every file that declares namespace `X` sees `X`'s camelCase
    // functions with no import and no export; every OTHER namespace needs the declaration exported
    // (PascalCase), and a camelCase one it names falls through to the inaccessible probe below, which
    // is what produces NL308 naming the declaring namespace. Before this the function channel required
    // export unconditionally, so `A.nl`'s `func formatTypeRef` was invisible to `B.nl` of the same
    // namespace (NL412 at a direct call, NL402 at a method group) while a camelCase CLASS in the same
    // two files already resolved — the two halves of one rule disagreed. The FunctionTypeInfo itself
    // is built by the caller, which is why the matched declaration and its file come back out.
    func TryResolveVisibleProjectFunction(name: string, currentNamespace: string?, out filePath: string?, out functionDeclaration: FunctionDeclaration?, out declaration: SymbolDeclaration?): bool {
        visible := AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(currentNamespace, usingNamespaces)
        paths := sources.SourceFilePaths()
        for visibleNamespace in visible {
            requireExported := SimpleNamePrecedence.RequiresExport(currentNamespace, visibleNamespace)
            fileIndex := 0
            while fileIndex < paths.Count {
                candidatePath := paths[fileIndex]
                unit := sources.GetProjectCompilationUnit(candidatePath)
                if unit != null && string.Equals(AnalyzerProjectSourceProvider.UnitNamespace(unit), visibleNamespace, StringComparison.Ordinal) {
                    declarations := unit.Declarations
                    declarationIndex := 0
                    while declarationIndex < declarations.Count {
                        candidate := declarations[declarationIndex]
                        if IsFunctionNamed(candidate, name, requireExported) {
                            filePath = candidatePath
                            functionDeclaration = candidate as FunctionDeclaration
                            declaration = CreateTopLevelSymbolDeclaration(name, candidatePath, sources.ProjectSourceText(candidatePath), candidate)
                            // NL010: A FREE FUNCTION IS WHAT ITS NAMESPACE'S IMPORT IS FOR, and the
                            // call writes no type name at all. A file whose whole use of
                            // `import Census.Holder` was `Hold(1)` had that import reported dead.
                            functionCredit := importUsageCredit
                            if functionCredit != null {
                                functionCredit.CreditNamespaceSupplier(visibleNamespace)
                            }

                            return true
                        }

                        declarationIndex = declarationIndex + 1
                    }
                }

                fileIndex = fileIndex + 1
            }
        }

        filePath = null
        functionDeclaration = null
        declaration = null
        return false
    }

    // THE ONE-DECLARATION-PER-NAMESPACE RULE FOR A FREE FUNCTION, asked across files.
    //
    // A free function is identified by (namespace, name): that is the emitter's identity for it
    // (`ColumnarFreeFunctionScope`), the key every bare-call view is built on, and what the function
    // channel above resolves a call to. A namespace spans files, so a second file of the same
    // namespace declaring a name the first already declares is a duplicate of it — whatever the two
    // parameter lists say, because there is no cross-file overload group for the second to join: a
    // top-level `func` name has ONE declaration per namespace. Before this walk existed, two files of
    // `X` could each declare `func Helper()`, `check` was clean, and the program printed whichever
    // one the emitter's declaration order happened to keep.
    //
    // The answer is every name some OTHER file of the namespace declares, each mapped to the FIRST
    // such file in enumeration order (rule 1) with the declaration's line, so a report can point at
    // it. The caller's own file is excluded on purpose: its own duplicates are its scope's business
    // (`AnalyzerDeclarationPolicy.DeclareSymbol`), and a file is never its own twin. Built once per
    // analysis by the policy, not once per declaration, since a project's files do not change
    // between two declarations of one unit. This is the INDEX only: whether the files are one program
    // at all is `CompilesAsOneProgram`, and the policy asks that first.
    func CompilesAsOneProgram(): bool {
        return sources.CompilesAsOneProgram()
    }

    func SameNamespaceFunctionTwins(currentFilePath: string?, currentNamespace: string?): Dictionary<string, ProjectFunctionTwin> {
        twins := new Dictionary<string, ProjectFunctionTwin>(StringComparer.Ordinal)
        ownPath := currentFilePath == null ? "" : Path.GetFullPath(currentFilePath)
        wantedNamespace := currentNamespace ?? ""
        paths := sources.SourceFilePaths()
        fileIndex := 0
        while fileIndex < paths.Count {
            candidatePath := paths[fileIndex]
            fileIndex = fileIndex + 1
            if string.Equals(Path.GetFullPath(candidatePath), ownPath, StringComparison.OrdinalIgnoreCase) {
                continue
            }

            unit := sources.GetProjectCompilationUnit(candidatePath)
            if unit == null {
                continue
            }

            candidateNamespace := AnalyzerProjectSourceProvider.UnitNamespace(unit) ?? ""
            if !string.Equals(candidateNamespace, wantedNamespace, StringComparison.Ordinal) {
                continue
            }

            declarations := unit.Declarations
            declarationIndex := 0
            while declarationIndex < declarations.Count {
                candidate := declarations[declarationIndex]
                declarationIndex = declarationIndex + 1
                functionDeclaration := candidate as FunctionDeclaration
                if functionDeclaration == null || twins.ContainsKey(functionDeclaration.Name) {
                    continue
                }

                twins[functionDeclaration.Name] = new ProjectFunctionTwin(candidatePath, functionDeclaration.Line)
            }
        }

        return twins
    }

    // NL209 FOR THE FUNCTION CHANNEL. The same tie the type half reports, asked of top-level `func`
    // declarations: two IMPORTED namespaces each export this spelling, so `SimpleNamePrecedence`
    // rule 3 has two winners and the file has to settle it.
    //
    // WHAT IS NOT AMBIGUOUS, and it is rule 1 and rule 2 again: a function this FILE declares, or an
    // exported one in the file's own or any enclosing namespace, is lexically nearer than every
    // import and wins outright — so a lexical match answers `false` before any import is asked. An
    // `import` naming an enclosing namespace is redundant rather than a rival and is skipped.
    //
    // The candidates come back FULLY QUALIFIED, in import order.
    func TryFindAmbiguousImportedFunction(name: string, currentNamespace: string?, out firstCandidate: string, out secondCandidate: string): bool {
        firstCandidate = ""
        secondCandidate = ""

        lexical := SimpleNamePrecedence.LexicalNamespaces(currentNamespace)
        for lexicalItem in lexical {
            if HasExportedFunctionInNamespace(name, lexicalItem) {
                return false
            }
        }

        matched := false
        index := 0
        while index < usingNamespaces.Count {
            candidateNamespace := usingNamespaces[index]
            index = index + 1
            if SimpleNamePrecedence.IsLexicalNamespace(currentNamespace, candidateNamespace) {
                continue
            }

            if !HasExportedFunctionInNamespace(name, candidateNamespace) {
                continue
            }

            if !matched {
                matched = true
                firstCandidate = candidateNamespace + "." + name
                continue
            }

            secondCandidate = candidateNamespace + "." + name
            return true
        }

        return false
    }

    // One namespace's answer to "does an exported top-level function of this name live here?".
    func HasExportedFunctionInNamespace(name: string, namespaceName: string?): bool {
        paths := sources.SourceFilePaths()
        for candidatePath in paths {
            unit := sources.GetProjectCompilationUnit(candidatePath)
            if unit != null && string.Equals(AnalyzerProjectSourceProvider.UnitNamespace(unit), namespaceName, StringComparison.Ordinal) {
                declarations := unit.Declarations
                declarationIndex := 0
                while declarationIndex < declarations.Count {
                    if IsFunctionNamed(declarations[declarationIndex], name, true) {
                        return true
                    }
                    declarationIndex = declarationIndex + 1
                }
            }
        }

        return false
    }

    // The inaccessible-FUNCTION decision, for the identifier path. Types take the same decision
    // inside `ResolveVisibleProjectType`, where its position in the sequence matters.
    func TryFindInaccessibleVisibleFunction(name: string, currentNamespace: string?, out filePath: string?): bool {
        return TryFindInaccessibleVisibleDeclaration(name, currentNamespace, true, out filePath)
    }

    // "A namespace I IMPORTED declares this name and does not export it." Every LEXICAL namespace is
    // skipped, and for two different reasons that come to the same answer. The file's OWN namespace:
    // a name that is not exported is still visible inside it, so finding it there is not an
    // accessibility failure at all. An ENCLOSING namespace: the file never asked for it — it is in
    // scope because of where the file sits — so a private declaration out there must not hijack a
    // name the file did explicitly import. The lookup walks past it instead, which is exactly what
    // the emitter's binding scope does (`TryFindEnclosingNamespaceSourceName` matches only EXPORTED
    // names and its caller then tries the imports).
    func TryFindInaccessibleVisibleDeclaration(name: string, currentNamespace: string?, wantFunctions: bool, out filePath: string?): bool {
        visible := AnalyzerTypeReferenceFacts.VisibleTypeNamespaces(currentNamespace, usingNamespaces)
        paths := sources.SourceFilePaths()
        for visibleNamespace in visible {
            if !SimpleNamePrecedence.IsLexicalNamespace(currentNamespace, visibleNamespace) {
                fileIndex := 0
                while fileIndex < paths.Count {
                    candidatePath := paths[fileIndex]
                    unit := sources.GetProjectCompilationUnit(candidatePath)
                    if unit != null && string.Equals(AnalyzerProjectSourceProvider.UnitNamespace(unit), visibleNamespace, StringComparison.Ordinal) {
                        declarations := unit.Declarations
                        declarationIndex := 0
                        while declarationIndex < declarations.Count {
                            candidate := declarations[declarationIndex]
                            if MatchesDeclarationKind(candidate, wantFunctions) && string.Equals(DeclarationFacts.GetDeclarationName(candidate), name, StringComparison.Ordinal) && !DeclarationFacts.IsExportedDeclaration(candidate, name) {
                                filePath = candidatePath
                                return true
                            }

                            declarationIndex = declarationIndex + 1
                        }
                    }

                    fileIndex = fileIndex + 1
                }
            }
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
            typeDeclarationFiles[TypeArityNames.Display(name)] = declarationFile
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
    static func IsTopLevelTypeDeclaration(declaration: Declaration): bool {
        if declaration as ClassDeclaration != null {
            return true
        }
        if declaration as StructDeclaration != null {
            return true
        }
        if declaration as RecordDeclaration != null {
            return true
        }
        if declaration as SoaRecordDeclaration != null {
            return true
        }
        if declaration as InterfaceDeclaration != null {
            return true
        }
        if declaration as UnionDeclaration != null {
            return true
        }
        if declaration as EnumDeclaration != null {
            return true
        }
        if declaration as TypeAliasDeclaration != null {
            return true
        }
        if declaration as NewtypeDeclaration != null {
            return true
        }
        return false
    }

    // A top-level function of this name, exported when the asking file is in ANOTHER namespace and
    // regardless of export when it is in the declaring one (a camelCase function is namespace-private).
    static func IsFunctionNamed(declaration: Declaration, name: string, requireExported: bool): bool {
        functionDeclaration := declaration as FunctionDeclaration
        if functionDeclaration == null {
            return false
        }

        if !string.Equals(functionDeclaration.Name, name, StringComparison.Ordinal) {
            return false
        }

        if !requireExported {
            return true
        }

        return DeclarationFacts.IsExportedDeclaration(declaration, name)
    }
}

// WHERE ANOTHER FILE OF THE SAME NAMESPACE DECLARES A TOP-LEVEL FUNCTION OF SOME NAME — the file and
// the declaration's line, which is all a duplicate report needs to point at it. Deliberately not a
// `SymbolDeclaration`: that carries the NAME column, which costs a read of the declaring file's text,
// and this index is built for every file of every analysis.
class ProjectFunctionTwin {
    FilePath: string
    Line: int

    constructor(filePath: string, line: int) {
        FilePath = filePath
        Line = line
    }
}
