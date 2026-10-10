namespace NSharpLang.Compiler

import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.CodeIntelligence

// THE OPTIONS ONE SESSION COMPILATION RUNS WITH. The defaults are `nlc build`'s.
class IncrementalCompileOptions {
    ValidateStrictLint: bool
    AotMode: bool
    EmitReferenceAssembly: bool
    // Whether an unchanged compilation may be answered from its `obj/` stamp before the in-memory
    // state is even consulted. Off for a caller that wants the compiler's units and models after
    // every request (an editor host answering queries), since a stamp hit produces neither.
    UseUpToDateStamp: bool

    constructor() {
        ValidateStrictLint = true
        AotMode = false
        EmitReferenceAssembly = false
        UseUpToDateStamp = true
    }
}

// ONE PROJECT, COMPILED REPEATEDLY: the API a warm process (the daemon, an editor host, a watch loop)
// holds per project, and the one a cold process can open from disk.
//
//   session := IncrementalProjectSession.Open(projectRoot, assemblyName)   // loads obj/ summaries
//   result := session.Compile(config, sourceFiles, assemblyName, outputPath, options, overrides)
//   snapshot := session.Snapshot()        // units, models, diagnostics, index — for queries
//   session.Save()                        // persists the per-file summaries back to obj/
//
// Each `Compile` (or `Analyze`) hands the session's `IncrementalCompilationState` to a fresh
// `MultiFileCompiler`: the analyzer and the analyses of every file whose dependencies did not move
// are reused, everything else runs, and the whole-project passes (import cycles, the systems policy,
// the lint, emission) run every time. A session is NOT thread-safe; a server serialises the
// requests for one project. Source overrides (unsaved editor buffers) are ordinary inputs here: the
// state compares text, not files.
class IncrementalProjectSession {
    ProjectRoot: string
    AssemblyName: string
    State: IncrementalCompilationState
    LastCompiler: MultiFileCompiler?

    constructor(projectRoot: string, assemblyName: string) {
        ProjectRoot = Path.GetFullPath(projectRoot)
        AssemblyName = assemblyName
        State = new IncrementalCompilationState()
        LastCompiler = null
    }

    // A session over `projectRoot`, seeded with the per-file summaries a previous process persisted.
    // A missing, corrupt or foreign summary file seeds nothing.
    static func Open(projectRoot: string, assemblyName: string): IncrementalProjectSession {
        session := new IncrementalProjectSession(projectRoot, assemblyName)
        IncrementalSummaryStore.LoadInto(session.SummaryStorePath(), session.State.SummaryCache)
        return session
    }

    func SummaryStorePath(): string {
        return IncrementalSummaryStore.PathFor(ProjectRoot, AssemblyName)
    }

    // Compiles the project to `outputPath`, reusing whatever the state allows.
    func Compile(config: ProjectConfig, sourceFiles: IReadOnlyList<string>, outputPath: string, options: IncrementalCompileOptions?, sourceTextOverrides: IReadOnlyDictionary<string, string>?): MultiFileCompilationResult {
        effective := options ?? new IncrementalCompileOptions()
        compiler := new MultiFileCompiler(sourceFiles, ProjectRoot, config, sourceTextOverrides)
        compiler.IncrementalState = State
        compiler.IncrementalBuild = effective.UseUpToDateStamp
        compiler.AotMode = effective.AotMode
        compiler.EmitReferenceAssembly = effective.EmitReferenceAssembly
        LastCompiler = compiler
        return compiler.CompileToIlAssembly(AssemblyName, outputPath, effective.ValidateStrictLint, true)
    }

    // Parses and analyses the project without emitting — what a query or a check needs.
    func Analyze(config: ProjectConfig, sourceFiles: IReadOnlyList<string>, sourceTextOverrides: IReadOnlyDictionary<string, string>?): MultiFileCompiler {
        compiler := new MultiFileCompiler(sourceFiles, ProjectRoot, config, sourceTextOverrides)
        compiler.IncrementalState = State
        compiler.CompileForAnalysis()
        LastCompiler = compiler
        return compiler
    }

    // The last compilation as a code-intelligence snapshot, or null before the first one (and after
    // one the up-to-date stamp answered, which parses nothing).
    func Snapshot(): ProjectSnapshot? {
        compiler := LastCompiler
        if compiler == null || compiler.WasUpToDate {
            return null
        }

        return new ProjectSnapshot(
            ProjectRoot,
            compiler.CompilationUnits,
            compiler.SemanticModels,
            compiler.AllErrors,
            compiler.SourceFiles,
            compiler.ProjectIndex,
            compiler.SourceTexts,
            compiler.PerformanceFacts,
            compiler.SystemsReport,
            compiler.FriendGrants
        )
    }

    // Persists the summary of every file the state holds; best effort.
    func Save(): bool {
        summaries := new List<IncrementalFileSummary>()
        for pair in State.Files {
            summaries.Add(pair.Value.Summary)
        }

        return IncrementalSummaryStore.Write(SummaryStorePath(), summaries)
    }
}
