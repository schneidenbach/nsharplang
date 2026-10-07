namespace NSharpLang.IncrementalBuild.Tests

import System
import System.Collections.Generic
import System.IO
import System.Text
import NSharpLang.Cli
import NSharpLang.Compiler

// THE DIFFERENTIAL HARNESS: one warm `IncrementalProjectSession` per project, driven through a seeded
// sequence of edits, and after every edit a from-scratch `MultiFileCompiler` over the same files. The
// two must agree on success, on every diagnostic (rendered with its location, snippet and hints),
// and — when the build succeeds — on every byte of the emitted assembly.
//
// The corpus is real multi-file programs: four examples straight from `examples/` (a CLI with
// models, services and commands in three directories; an ASP.NET backend on a framework reference;
// a pair joined by a file import; a three-file service) and `geo` (`IncrementalGeoCorpus.nl`),
// written for this test to reach the cross-file relations the dependency summaries must not miss.
class DifferentialProject {
    Name: string
    SourceDirectory: string
    FromCorpus: bool

    constructor(name: string, sourceDirectory: string, fromCorpus: bool) {
        Name = name
        SourceDirectory = sourceDirectory
        FromCorpus = fromCorpus
    }
}

class DifferentialReport {
    Steps: int
    SuccessfulComparisons: int
    FailedComparisons: int
    FilesAnalyzed: int
    FilesReused: int
    PartialSteps: int
    // Steps whose emission was answered from the state (`IncrementalCompilationState.LastEmissionKey`)
    // and file parses the back end reused (`ColumnarFileProgramCache`), so a run can prove the
    // incremental back end was exercised and not merely bypassed.
    EmissionReuses: int
    ParseReuses: int
    Mismatches: List<string>

    constructor() {
        Steps = 0
        SuccessfulComparisons = 0
        FailedComparisons = 0
        FilesAnalyzed = 0
        FilesReused = 0
        PartialSteps = 0
        EmissionReuses = 0
        ParseReuses = 0
        Mismatches = new List<string>()
    }

    func Summary(): string {
        return "steps=" + Steps.ToString() + " successful=" + SuccessfulComparisons.ToString() + " failing=" + FailedComparisons.ToString() + " analyzed=" + FilesAnalyzed.ToString() + " reused=" + FilesReused.ToString() + " partial=" + PartialSteps.ToString() + " emission-reuses=" + EmissionReuses.ToString() + " parse-reuses=" + ParseReuses.ToString() + " mismatches=" + Mismatches.Count.ToString()
    }
}

func DifferentialRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "AGENTS.md")) && Directory.Exists(Path.Combine(directory, "examples")) && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("the repository root was not found above " + AppContext.BaseDirectory)
}

func DifferentialCorpus(): List<DifferentialProject> {
    root := DifferentialRepositoryRoot()
    projects := new List<DifferentialProject>()
    projects.Add(new DifferentialProject("geo", "", true))
    projects.Add(new DifferentialProject("task-cli", Path.Combine(root, "examples", "16-task-cli"), false))
    projects.Add(new DifferentialProject("issue-tracker", Path.Combine(root, "examples", "17-issue-tracker", "backend"), false))
    projects.Add(new DifferentialProject("file-imports", Path.Combine(root, "examples", "12-multi-file-projects", "imports"), false))
    projects.Add(new DifferentialProject("weather", Path.Combine(root, "examples", "12-multi-file-projects", "WeatherDemo"), false))
    return projects
}

// The number of edits per project: `NSHARP_INCREMENTAL_DIFFERENTIAL_STEPS` for a longer run.
func DifferentialSteps(defaultSteps: int): int {
    configured := Environment.GetEnvironmentVariable("NSHARP_INCREMENTAL_DIFFERENTIAL_STEPS")
    if configured == null {
        return defaultSteps
    }

    parsed := 0
    if int.TryParse(configured, out parsed) && parsed > 0 {
        return parsed
    }

    return defaultSteps
}

func DifferentialCopy(project: DifferentialProject, destination: string): Dictionary<string, string> {
    originals := new Dictionary<string, string>(StringComparer.Ordinal)
    Directory.CreateDirectory(destination)
    if project.FromCorpus {
        File.WriteAllText(Path.Combine(destination, "project.yml"), "name: Geo\nversion: 1.0.0\nbackend: il\noutputType: exe\ntargetFramework: net10.0\n")
        for corpusFile in GeoCorpusFiles() {
            corpusTarget := Path.Combine(destination, corpusFile.Key)
            Directory.CreateDirectory(Path.GetDirectoryName(corpusTarget) ?? destination)
            File.WriteAllText(corpusTarget, corpusFile.Value)
            originals[corpusTarget] = corpusFile.Value
        }
        return originals
    }

    File.Copy(Path.Combine(project.SourceDirectory, "project.yml"), Path.Combine(destination, "project.yml"))
    for file in Directory.GetFiles(project.SourceDirectory, "*.nl", SearchOption.AllDirectories) {
        relative := Path.GetRelativePath(project.SourceDirectory, file)
        if relative.StartsWith("bin") || relative.StartsWith("obj") || relative.EndsWith(".tests.nl") {
            continue
        }

        target := Path.Combine(destination, relative)
        Directory.CreateDirectory(Path.GetDirectoryName(target) ?? destination)
        text := File.ReadAllText(file)
        File.WriteAllText(target, text)
        originals[target] = text
    }

    return originals
}

func DifferentialSourceFiles(root: string): List<string> {
    files := new List<string>()
    for file in Directory.GetFiles(root, "*.nl", SearchOption.AllDirectories) {
        relative := Path.GetRelativePath(root, file)
        if relative.StartsWith("bin") || relative.StartsWith("obj") {
            continue
        }
        files.Add(file)
    }
    files.Sort(StringComparer.Ordinal)
    return files
}

func DifferentialRender(errors: IEnumerable<CompilerError>): string {
    builder := new StringBuilder()
    for error in errors {
        builder.AppendLine(error.FormatForTooling(true, true))
    }
    return builder.ToString()
}

// One comparison: the session's incremental compilation against a fresh full one.
// The configuration `nlc build` compiles with: parsed, then its framework, package and project
// references resolved to the assemblies the compiler reads.
func DifferentialConfig(root: string): ProjectConfig {
    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    options := new ReferenceResolutionOptions()
    options.Quiet = true
    CompilationReferenceResolver.AddResolvedDllReferences(root, config, options)
    return config
}

func DifferentialCompare(session: IncrementalProjectSession, root: string, label: string, report: DifferentialReport) {
    config := DifferentialConfig(root)
    files := config.GetSourceFiles(root, false)
    outputPath := Path.Combine(root, "bin", "Debug", "net10.0", session.AssemblyName + ".dll")
    Directory.CreateDirectory(Path.GetDirectoryName(outputPath) ?? root)
    options := new IncrementalCompileOptions()
    options.UseUpToDateStamp = false
    incremental := session.Compile(config, files, outputPath, options, null)
    incrementalBytes := "-"
    if incremental.Success {
        incrementalBytes = ContentHash.OfFileOrMissing(outputPath)
    }
    incrementalDiagnostics := DifferentialRender(incremental.Errors)
    report.FilesAnalyzed = report.FilesAnalyzed + session.State.LastFilesAnalyzed
    report.FilesReused = report.FilesReused + session.State.LastFilesReused
    if session.State.LastFilesReused > 0 {
        report.PartialSteps = report.PartialSteps + 1
    }
    DifferentialCountBackEndReuse(session, report)

    referenceConfig := DifferentialConfig(root)
    reference := new MultiFileCompiler(referenceConfig.GetSourceFiles(root, false), root, referenceConfig)
    full := reference.CompileToIlAssembly(session.AssemblyName, outputPath, true)
    fullBytes := "-"
    if full.Success {
        fullBytes = ContentHash.OfFileOrMissing(outputPath)
    }
    fullDiagnostics := DifferentialRender(full.Errors)

    report.Steps = report.Steps + 1
    if full.Success {
        report.SuccessfulComparisons = report.SuccessfulComparisons + 1
    } else {
        report.FailedComparisons = report.FailedComparisons + 1
    }

    if incremental.Success != full.Success || incrementalDiagnostics != fullDiagnostics || incrementalBytes != fullBytes {
        report.Mismatches.Add(label + ": success " + incremental.Success.ToString() + "/" + full.Success.ToString() + ", bytes " + incrementalBytes + "/" + fullBytes + "\n--- incremental\n" + incrementalDiagnostics + "--- full\n" + fullDiagnostics)
    }
}

func DifferentialCountBackEndReuse(session: IncrementalProjectSession, report: DifferentialReport) {
    if session.State.LastEmissionReused {
        report.EmissionReuses = report.EmissionReuses + 1
    }
    report.ParseReuses = report.ParseReuses + session.State.EmitParses.LastReused
}

func DifferentialImageHash(compiler: MultiFileCompiler): string {
    image := compiler.EmittedImage
    if image == null {
        return "-"
    }
    return ContentHash.OfBytes(image ?? new byte[](0))
}

// THE CHECK'S SIDE: a warm session analyses and validates the emission in memory, the way `nlc check`
// runs in the workspace server, and a fresh compiler does the same over the same files; the two must
// agree on success, every diagnostic and the validated image.
func DifferentialCheckCompare(session: IncrementalProjectSession, root: string, label: string, report: DifferentialReport) {
    config := DifferentialConfig(root)
    files := config.GetSourceFiles(root, true)
    warm := session.Analyze(config, files, null)
    warmResult := warm.ValidateAnalyzedEmission(session.AssemblyName)
    warmDiagnostics := DifferentialRender(warmResult.Errors)
    report.FilesAnalyzed = report.FilesAnalyzed + session.State.LastFilesAnalyzed
    report.FilesReused = report.FilesReused + session.State.LastFilesReused
    if session.State.LastFilesReused > 0 {
        report.PartialSteps = report.PartialSteps + 1
    }
    DifferentialCountBackEndReuse(session, report)

    freshConfig := DifferentialConfig(root)
    fresh := new MultiFileCompiler(freshConfig.GetSourceFiles(root, true), root, freshConfig)
    fresh.CompileForAnalysis()
    freshResult := fresh.ValidateAnalyzedEmission(session.AssemblyName)
    freshDiagnostics := DifferentialRender(freshResult.Errors)

    report.Steps = report.Steps + 1
    if freshResult.Success {
        report.SuccessfulComparisons = report.SuccessfulComparisons + 1
    } else {
        report.FailedComparisons = report.FailedComparisons + 1
    }

    warmImage := DifferentialImageHash(warm)
    freshImage := DifferentialImageHash(fresh)
    if !warmResult.Success {
        warmImage = "-"
    }
    if !freshResult.Success {
        freshImage = "-"
    }
    if warmResult.Success != freshResult.Success || warmDiagnostics != freshDiagnostics || warmImage != freshImage {
        report.Mismatches.Add(label + " (check): success " + warmResult.Success.ToString() + "/" + freshResult.Success.ToString() + ", image " + warmImage + "/" + freshImage + "\n--- warm\n" + warmDiagnostics + "--- fresh\n" + freshDiagnostics)
    }
}

// THE EDITS. Each picks its target with the seeded generator from the sorted file list, so a seed
// names one exact sequence. Most produce a change the analysis must notice somewhere: a literal in a
// body, a blank line that moves every declaration below it, a renamed identifier, a type in a
// signature, a file added, duplicated, removed or restored.
func DifferentialEdit(random: Random, root: string, originals: Dictionary<string, string>, step: int): string {
    // Every fourth edit starts from the original program, so the run keeps returning to code that
    // builds instead of only accumulating errors.
    prefix := ""
    if step % 4 == 3 {
        DifferentialRestoreAll(root, originals)
        prefix = "restore, then "
    }

    return prefix + DifferentialEditOnce(random, root, originals, step)
}

func DifferentialEditOnce(random: Random, root: string, originals: Dictionary<string, string>, step: int): string {
    files := DifferentialSourceFiles(root)
    kind := random.Next(10)
    if files.Count == 0 {
        kind = 8
    }

    if kind == 0 {
        path := files[random.Next(files.Count)]
        text := File.ReadAllText(path)
        positions := DifferentialNumberPositions(text)
        if positions.Count > 0 {
            position := positions[random.Next(positions.Count)]
            File.WriteAllText(path, text.Substring(0, position) + "7" + text.Substring(position))
            return "literal in " + Path.GetFileName(path)
        }
        kind = 1
    }

    if kind == 1 || kind == 2 {
        path := files[random.Next(files.Count)]
        text := File.ReadAllText(path)
        lines := new List<string>(text.Split('\n'))
        index := random.Next(lines.Count)
        inserted := ""
        if kind == 2 {
            inserted = "// edited " + step.ToString()
        }
        lines.Insert(index, inserted)
        File.WriteAllText(path, string.Join("\n", lines))
        return "line inserted in " + Path.GetFileName(path) + " at " + index.ToString()
    }

    if kind == 3 {
        path := files[random.Next(files.Count)]
        text := File.ReadAllText(path)
        positions := DifferentialIdentifierEnds(text)
        if positions.Count > 0 {
            position := positions[random.Next(positions.Count)]
            File.WriteAllText(path, text.Substring(0, position) + "Q" + text.Substring(position))
            return "identifier renamed in " + Path.GetFileName(path)
        }
    }

    if kind == 4 {
        path := files[random.Next(files.Count)]
        text := File.ReadAllText(path)
        if text.Contains(": int") {
            index := text.IndexOf(": int", StringComparison.Ordinal)
            File.WriteAllText(path, text.Substring(0, index) + ": long" + text.Substring(index + 5))
            return "int -> long in " + Path.GetFileName(path)
        }
        if text.Contains(": string") {
            index := text.IndexOf(": string", StringComparison.Ordinal)
            File.WriteAllText(path, text.Substring(0, index) + ": object" + text.Substring(index + 8))
            return "string -> object in " + Path.GetFileName(path)
        }
    }

    if kind == 5 {
        template := File.ReadAllText(files[random.Next(files.Count)])
        namespaceLine := ""
        for line in template.Split('\n') {
            if line.StartsWith("namespace ") {
                namespaceLine = line + "\n\n"
                break
            }
        }
        added := Path.Combine(root, "Zadded" + step.ToString() + ".nl")
        File.WriteAllText(added, namespaceLine + "func Extra" + step.ToString() + "(): int {\n    return " + step.ToString() + "\n}\n")
        return "file added"
    }

    // The entry file stays: `project.yml` names it, and its absence is a configuration error the
    // project loader raises before any compiler runs.
    if kind == 6 && files.Count > 1 {
        path := files[random.Next(files.Count)]
        if Path.GetFileName(path) != "Program.nl" {
            File.Delete(path)
            return "file removed: " + Path.GetFileName(path)
        }
    }

    if kind == 7 {
        source := files[random.Next(files.Count)]
        File.WriteAllText(Path.Combine(root, "Zcopy" + step.ToString() + ".nl"), File.ReadAllText(source))
        return "file duplicated: " + Path.GetFileName(source)
    }

    if kind == 9 {
        originalPaths := new List<string>(originals.Keys)
        originalPaths.Sort(StringComparer.Ordinal)
        path := originalPaths[random.Next(originalPaths.Count)]
        File.WriteAllText(path, originals[path])
        return "file restored: " + Path.GetFileName(path)
    }

    DifferentialRestoreAll(root, originals)
    return "everything restored"
}

func DifferentialRestoreAll(root: string, originals: Dictionary<string, string>) {
    for file in DifferentialSourceFiles(root) {
        if !originals.ContainsKey(file) {
            File.Delete(file)
        }
    }
    for original in originals {
        File.WriteAllText(original.Key, original.Value)
    }
}

// Offsets of the first digit of every number that is not part of an identifier.
func DifferentialNumberPositions(text: string): List<int> {
    positions := new List<int>()
    index := 0
    while index < text.Length {
        if char.IsDigit(text[index]) && (index == 0 || !(char.IsLetterOrDigit(text[index - 1]) || text[index - 1] == '_' || text[index - 1] == '.')) {
            positions.Add(index)
            while index < text.Length && char.IsDigit(text[index]) {
                index = index + 1
            }
        } else {
            index = index + 1
        }
    }
    return positions
}

// Offsets just past every identifier-shaped word of three or more characters.
func DifferentialIdentifierEnds(text: string): List<int> {
    positions := new List<int>()
    index := 0
    while index < text.Length {
        if char.IsLetter(text[index]) {
            start := index
            while index < text.Length && (char.IsLetterOrDigit(text[index]) || text[index] == '_') {
                index = index + 1
            }
            if index - start >= 3 {
                positions.Add(index)
            }
        } else {
            index = index + 1
        }
    }
    return positions
}

func DifferentialCheckRun(project: DifferentialProject, seed: int, steps: int, report: DifferentialReport) {
    scratch := IncrementalScratch("differential-check-" + project.Name)
    try {
        root := Path.Combine(scratch, project.Name)
        originals := DifferentialCopy(project, root)
        config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
        assemblyName := config.Name ?? project.Name
        session := new IncrementalProjectSession(root, assemblyName)
        DifferentialCheckCompare(session, root, project.Name + " initial", report)
        DifferentialCheckCompare(session, root, project.Name + " unchanged", report)
        random := new Random(seed)
        step := 0
        while step < steps {
            edit := DifferentialEdit(random, root, originals, step)
            DifferentialCheckCompare(session, root, project.Name + " step " + step.ToString() + " (" + edit + ")", report)
            step = step + 1
        }
    } finally {
        IncrementalCleanup(scratch)
    }
}

func DifferentialRun(project: DifferentialProject, seed: int, steps: int, report: DifferentialReport) {
    scratch := IncrementalScratch("differential-" + project.Name)
    try {
        root := Path.Combine(scratch, project.Name)
        originals := DifferentialCopy(project, root)
        config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
        assemblyName := config.Name ?? project.Name
        session := new IncrementalProjectSession(root, assemblyName)
        DifferentialCompare(session, root, project.Name + " initial", report)
        DifferentialCompare(session, root, project.Name + " unchanged", report)
        random := new Random(seed)
        step := 0
        while step < steps {
            edit := DifferentialEdit(random, root, originals, step)
            DifferentialCompare(session, root, project.Name + " step " + step.ToString() + " (" + edit + ")", report)
            step = step + 1
        }
    } finally {
        IncrementalCleanup(scratch)
    }
}
