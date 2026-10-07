namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar

// ONE FILE'S PART OF A COMPILATION, KEPT FOR THE NEXT ONE.
//
// Everything `MultiFileCompiler` derived from this file alone: the unit exactly as analysis left it
// (the analyzer stamps import-usage facts on it and the linter reads them back), the parse and
// preprocessor diagnostics, and the products of its analysis — the semantic model the systems pass
// and the emitter read, the binding map the project index merges, the type-declaration rows, and
// the raw analyzer diagnostics before project-level suppression. Plus what the analysis DEPENDED on:
// the other files in its dependency closure when it ran, and the content of every file it imported
// by path.
class IncrementalFileRecord {
    Path: string
    Summary: IncrementalFileSummary
    Unit: CompilationUnit?
    // The parse itself when it is the one the analyzer would make (no preprocessor change, full
    // path), so a compilation that reuses this record can seed its analyzers with it too.
    ReusableParse: FileParseAst?
    ParseErrors: List<CompilerError>
    Analyzed: bool
    SemanticModel: SemanticModel?
    Bindings: BindingMap?
    AnalysisErrors: List<CompilerError>
    TypeDeclarationFiles: Dictionary<string, string>
    Dependencies: HashSet<string>
    ImportedFileHashes: Dictionary<string, string>

    constructor(path: string, summary: IncrementalFileSummary) {
        Path = path
        Summary = summary
        Unit = null
        ReusableParse = null
        ParseErrors = new List<CompilerError>()
        Analyzed = false
        SemanticModel = null
        Bindings = null
        AnalysisErrors = new List<CompilerError>()
        TypeDeclarationFiles = new Dictionary<string, string>(StringComparer.Ordinal)
        Dependencies = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        ImportedFileHashes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    }
}

// THE STATE AN INCREMENTAL COMPILATION CARRIES FROM ONE RUN TO THE NEXT, held in memory by whoever
// keeps compiling the same project: a warm daemon, an editor host, the differential test. It is
// handed to `MultiFileCompiler.IncrementalState`; the compiler reads it before the run and replaces
// its contents after.
//
// THE ENVIRONMENT KEY GUARDS EVERYTHING. The analyzer instance (its metadata load context, its
// well-known types, its caches) and every per-file record are valid only for the environment they
// were made in — the compiler, the configuration, the defines, the references and their contents,
// the options. A different key drops the analyzer and every fileRecord, and the next run is a full one.
//
// THE PLAN IS DECIDED BEFORE ANYTHING IS PARSED (`Plan`): which files' analyses can be reused and
// which must run. A file's analysis is reused exactly when its own text is unchanged, no file in its
// dependency closure — as recorded when it was analysed, and as computed now — changed its surface
// or appeared or disappeared, and every file it imports by path still has the same content.
class IncrementalCompilationState {
    EnvironmentKey: string
    RetainedAnalyzer: Analyzer?
    Files: Dictionary<string, IncrementalFileRecord>
    MetadataEntries: List<IncrementalInputEntry>

    // Persisted summaries by `path|content hash`, loaded from `obj/` when a session opens cold.
    SummaryCache: Dictionary<string, IncrementalFileSummary>

    // The last run's work, for counters and tests.
    LastFilesAnalyzed: int
    LastFilesReused: int
    LastWasFull: bool

    // THE BACK END'S HALF. Each file's columnar parse, kept while its text and position hold
    // (`ColumnarFileProgramCache`), and the last emission's outcome under the key of everything it
    // read (`MultiFileCompiler.ComputeEmissionKey`): its image when it emitted, and the diagnostics it
    // added either way. A compilation whose key matches is answered from them without walking a body.
    EmitParses: ColumnarFileProgramCache
    LastEmissionKey: string
    LastEmissionImage: byte[]?
    LastEmissionErrors: List<CompilerError>
    // Whether the last compilation's emission was answered by `LastEmissionKey`, for tests.
    LastEmissionReused: bool

    constructor() {
        EnvironmentKey = ""
        RetainedAnalyzer = null
        Files = new Dictionary<string, IncrementalFileRecord>(StringComparer.OrdinalIgnoreCase)
        MetadataEntries = new List<IncrementalInputEntry>()
        SummaryCache = new Dictionary<string, IncrementalFileSummary>(StringComparer.Ordinal)
        LastFilesAnalyzed = 0
        LastFilesReused = 0
        LastWasFull = true
        EmitParses = new ColumnarFileProgramCache()
        LastEmissionKey = ""
        LastEmissionImage = null
        LastEmissionErrors = new List<CompilerError>()
        LastEmissionReused = false
    }

    // Drops everything: the next run analyses and emits every file with a new analyzer.
    func Reset(environmentKey: string) {
        EnvironmentKey = environmentKey
        RetainedAnalyzer = null
        Files.Clear()
        MetadataEntries.Clear()
        EmitParses.Clear()
        ForgetEmission()
    }

    func ForgetEmission() {
        LastEmissionKey = ""
        LastEmissionImage = null
        LastEmissionErrors = new List<CompilerError>()
    }

    // Whether the metadata the analyzer read last run is still what is on disk.
    func MetadataIsCurrent(): bool {
        for entry in MetadataEntries {
            if !entry.IsCurrent() {
                return false
            }
        }

        return true
    }

    // The summary of `text` at `path`: the record's when its content is unchanged, the persisted
    // cache's when it holds one for these exact bytes, computed otherwise.
    func SummaryFor(path: string, text: string): IncrementalFileSummary {
        contentHash := ContentHash.OfText(text)
        fileRecord: IncrementalFileRecord = null
        if Files.TryGetValue(path, out fileRecord) {
            if fileRecord.Summary.TextHash == contentHash {
                return fileRecord.Summary
            }
        }

        cached: IncrementalFileSummary = null
        if SummaryCache.TryGetValue(path + "|" + contentHash, out cached) {
            return cached
        }

        summary := IncrementalFileSummary.Compute(path, text)
        SummaryCache[path + "|" + contentHash] = summary
        return summary
    }
}

// THE PLAN FOR ONE RUN: the current summary of every source, the files whose surface changed (or
// that appeared or disappeared), and the files whose recorded analysis can be reused.
class IncrementalCompilationPlan {
    Summaries: Dictionary<string, IncrementalFileSummary>
    ChangedFiles: HashSet<string>
    // The segments of every namespace that appeared in, or vanished from, the project since the
    // state was made: an `import` of one, or a lookup through one, may now answer differently.
    ChangedNamespaceWords: HashSet<string>
    ReusedFiles: HashSet<string>
    private readonly declaredBy: Dictionary<string, List<string>>
    private readonly baseNamedBy: Dictionary<string, List<string>>
    private readonly opaqueFiles: List<string>

    constructor() {
        Summaries = new Dictionary<string, IncrementalFileSummary>(StringComparer.OrdinalIgnoreCase)
        ChangedFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        ChangedNamespaceWords = new HashSet<string>(StringComparer.Ordinal)
        ReusedFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        declaredBy = new Dictionary<string, List<string>>(StringComparer.Ordinal)
        baseNamedBy = new Dictionary<string, List<string>>(StringComparer.Ordinal)
        opaqueFiles = new List<string>()
    }

    // `texts` maps every source's full path to the text the analyzer will see, in compilation order.
    static func Create(state: IncrementalCompilationState, paths: List<string>, texts: Dictionary<string, string>): IncrementalCompilationPlan {
        plan := new IncrementalCompilationPlan()
        for path in paths {
            summary := state.SummaryFor(path, texts[path])
            plan.Summaries[path] = summary
            plan.Index(path, summary)

            fileRecord: IncrementalFileRecord = null
            if !state.Files.TryGetValue(path, out fileRecord) {
                plan.ChangedFiles.Add(path)
            } else if fileRecord.Summary.SurfaceHash != summary.SurfaceHash || fileRecord.Summary.Opaque != summary.Opaque {
                plan.ChangedFiles.Add(path)
            }
        }

        for previous in state.Files.Keys {
            if !plan.Summaries.ContainsKey(previous) {
                plan.ChangedFiles.Add(previous)
            }
        }

        currentNamespaces := new HashSet<string>(StringComparer.Ordinal)
        for current in plan.Summaries.Values {
            currentNamespace := current.Namespace
            if currentNamespace != null {
                currentNamespaces.Add(currentNamespace)
            }
        }
        previousNamespaces := new HashSet<string>(StringComparer.Ordinal)
        for previousRecord in state.Files.Values {
            previousNamespace := previousRecord.Summary.Namespace
            if previousNamespace != null {
                previousNamespaces.Add(previousNamespace)
            }
        }
        for namespaceName in currentNamespaces {
            if !previousNamespaces.Contains(namespaceName) {
                IncrementalFileSummary.AddWords(plan.ChangedNamespaceWords, namespaceName)
            }
        }
        for namespaceName in previousNamespaces {
            if !currentNamespaces.Contains(namespaceName) {
                IncrementalFileSummary.AddWords(plan.ChangedNamespaceWords, namespaceName)
            }
        }

        for path in paths {
            if plan.CanReuse(state, path) {
                plan.ReusedFiles.Add(path)
            }
        }

        return plan
    }

    private func Index(path: string, summary: IncrementalFileSummary) {
        if summary.Opaque {
            opaqueFiles.Add(path)
        }

        for name in summary.DeclaredNames {
            AddIndexed(declaredBy, name, path)
        }
        for name in summary.BaseNames {
            AddIndexed(baseNamedBy, name, path)
        }
    }

    private static func AddIndexed(index: Dictionary<string, List<string>>, name: string, path: string) {
        files: List<string> = null
        if !index.TryGetValue(name, out files) {
            files = new List<string>()
            index[name] = files
        }

        files.Add(path)
    }

    private func CanReuse(state: IncrementalCompilationState, path: string): bool {
        fileRecord: IncrementalFileRecord = null
        if !state.Files.TryGetValue(path, out fileRecord) {
            return false
        }
        if !fileRecord.Analyzed {
            return false
        }

        summary := Summaries[path]
        if fileRecord.Summary.TextHash != summary.TextHash {
            return false
        }
        if summary.Opaque && ChangedFiles.Count > 0 {
            return false
        }
        if summary.Mentions.Overlaps(ChangedNamespaceWords) {
            return false
        }

        for dependency in fileRecord.Dependencies {
            if ChangedFiles.Contains(dependency) {
                return false
            }
        }

        for dependency in DependenciesOf(path) {
            if ChangedFiles.Contains(dependency) {
                return false
            }
        }

        for imported in fileRecord.ImportedFileHashes {
            if ContentHash.OfFileOrMissing(imported.Key) != imported.Value {
                return false
            }
        }

        return true
    }

    // THE DEPENDENCY CLOSURE of one file in the CURRENT project: every file declaring a name it
    // mentions anywhere (or that name plus `Attribute`), every file whose types derive from such a
    // name, every opaque file, and transitively the same for every name the surfaces reached that way
    // REFER to.
    func DependenciesOf(path: string): HashSet<string> {
        closure := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        seenWords := new HashSet<string>(StringComparer.Ordinal)
        pending := new Queue<string>()
        for opaque in opaqueFiles {
            if !string.Equals(opaque, path, StringComparison.OrdinalIgnoreCase) && closure.Add(opaque) {
                EnqueueWords(Summaries[opaque].ReferencedNames, seenWords, pending)
            }
        }

        EnqueueWords(Summaries[path].Mentions, seenWords, pending)
        while pending.Count > 0 {
            word := pending.Dequeue()
            AddFilesFor(declaredBy, word, path, closure, seenWords, pending)
            AddFilesFor(baseNamedBy, word, path, closure, seenWords, pending)
        }

        return closure
    }

    private func AddFilesFor(index: Dictionary<string, List<string>>, word: string, selfPath: string, closure: HashSet<string>, seenWords: HashSet<string>, pending: Queue<string>) {
        files: List<string> = null
        if !index.TryGetValue(word, out files) {
            return
        }

        for file in files {
            if string.Equals(file, selfPath, StringComparison.OrdinalIgnoreCase) {
                continue
            }
            if closure.Add(file) {
                EnqueueWords(Summaries[file].ReferencedNames, seenWords, pending)
            }
        }
    }

    private static func EnqueueWords(words: HashSet<string>, seenWords: HashSet<string>, pending: Queue<string>) {
        for word in words {
            if seenWords.Add(word) {
                pending.Enqueue(word)
            }
            attributeName := word + "Attribute"
            if seenWords.Add(attributeName) {
                pending.Enqueue(attributeName)
            }
        }
    }
}
