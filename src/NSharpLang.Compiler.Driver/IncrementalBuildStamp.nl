namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Text

// One source file's durable analysis inputs and diagnostics from a completed check. Semantic models
// are deliberately process-local; a cold check reparses source declarations and reanalyses edited
// bodies while this row supplies the unchanged file's diagnostics and interface summary.
class IncrementalCheckFileResult {
    Path: string
    Summary: IncrementalFileSummary
    Analyzed: bool
    ParseErrors: List<CompilerError>
    AnalysisErrors: List<CompilerError>
    Dependencies: HashSet<string>
    ImportedFileHashes: Dictionary<string, string>

    constructor(path: string, summary: IncrementalFileSummary) {
        Path = path
        Summary = summary
        Analyzed = false
        ParseErrors = new List<CompilerError>()
        AnalysisErrors = new List<CompilerError>()
        Dependencies = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        ImportedFileHashes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    }
}

// THE UP-TO-DATE STAMP: what one successful compilation read, what it wrote, and what it reported.
//
// One file per (project, output) under `<projectRoot>/obj/nlc/`. Its layout is a payload followed by
// the payload's own SHA-256 (`IncrementalCacheFile`), so a stamp that was truncated by a crash, half-written by a killed
// process, or edited by hand fails the checksum and is a MISS — never a wrong answer. The payload
// opens with a magic string and `FormatVersion`; a stamp written by any other format is a miss, and
// so is one whose key (which carries the compiler's identity) differs. Writes go to a unique temp
// file renamed over the stamp, so a reader sees the old stamp or the new one and nothing between.
//
// THE DIAGNOSTICS ARE PART OF THE RESULT. A build that succeeded with warnings prints the same
// warnings when it is answered from the stamp, so every field of `CompilerError` is carried. A new
// field on `CompilerError` must be added to `WriteError`/`ReadError` — `tests/native/incremental-build`
// compares the serialised field set against the record's own members and fails until it is.
class IncrementalBuildStamp {
    static FormatVersion: int => 6
    static CheckResultKind: int => 1
    static CheckResultSchemaVersion: int => 5

    static func Magic(): string => "NSHARP-INCREMENTAL-STAMP"

    Key: string
    CheckAnalysisReuseKey: string
    Entries: List<IncrementalInputEntry>
    OutputPaths: List<string>
    OutputHashes: List<string>
    Diagnostics: List<CompilerError>
    ResultKind: int
    CheckSchemaVersion: int
    CheckExitCode: int
    CheckOutputToStandardError: bool
    CheckOutput: string
    CheckDiagnosticsJson: string
    CheckHadDiagnostics: bool
    CheckFiles: List<IncrementalCheckFileResult>

    constructor(key: string) {
        Key = key
        CheckAnalysisReuseKey = ""
        Entries = new List<IncrementalInputEntry>()
        OutputPaths = new List<string>()
        OutputHashes = new List<string>()
        Diagnostics = new List<CompilerError>()
        ResultKind = 0
        CheckSchemaVersion = 0
        CheckExitCode = 0
        CheckOutputToStandardError = false
        CheckOutput = ""
        CheckDiagnosticsJson = ""
        CheckHadDiagnostics = false
        CheckFiles = new List<IncrementalCheckFileResult>()
    }

    // `<projectRoot>/obj/nlc/<assembly>.<16 hex digits of the output path>.stamp`: one stamp per
    // output, because the same project builds Debug and Release, with and without its tests, into
    // different places.
    static func PathFor(projectRoot: string, assemblyName: string, outputPath: string): string {
        fullOutput := Path.GetFullPath(outputPath)
        outputHash := ContentHash.OfText(fullOutput).Substring(0, 16)
        directory := Path.Combine(Path.GetFullPath(projectRoot), "obj", "nlc")
        return Path.Combine(directory, assemblyName + "." + outputHash + ".stamp")
    }

    // One check result slot per project. It uses the build stamp's envelope,
    // input entries, checksum and atomic replacement; the key selects output mode and compiler
    // options, so a different invocation misses and replaces the slot instead of retaining stale variants.
    static func CheckPathFor(projectRoot: string, assemblyName: string): string {
        directory := Path.Combine(Path.GetFullPath(projectRoot), "obj", "nlc")
        return Path.Combine(directory, assemblyName + ".check.stamp")
    }

    static func IsInsideProject(projectRoot: string, outputPath: string): bool {
        root := Path.GetFullPath(projectRoot)
        if !root.EndsWith(Path.DirectorySeparatorChar.ToString()) {
            root = root + Path.DirectorySeparatorChar.ToString()
        }

        return Path.GetFullPath(outputPath).StartsWith(root, StringComparison.Ordinal)
    }

    // Every recorded input and every output still has the value this stamp recorded for it.
    func IsCurrent(): bool {
        for entry in Entries {
            if !entry.IsCurrent() {
                return false
            }
        }

        index := 0
        while index < OutputPaths.Count {
            if !string.Equals(ContentHash.OfFileOrMissing(OutputPaths[index]), OutputHashes[index], StringComparison.Ordinal) {
                return false
            }
            if OutputHashes[index] == IncrementalInputEntry.MissingValue() {
                return false
            }
            index = index + 1
        }

        return true
    }

    func AddOutput(path: string) {
        fullPath := Path.GetFullPath(path)
        OutputPaths.Add(fullPath)
        OutputHashes.Add(ContentHash.OfFileOrMissing(fullPath))
    }

    // ---- reading ---------------------------------------------------------------------------------

    // The stamp at `path` if it exists, is intact, is this format and carries `expectedKey`; null for
    // every other case. Nothing here throws: an unusable stamp is simply not used.
    static func TryRead(path: string, expectedKey: string?, expectedAnalysisReuseKey: string? = null): IncrementalBuildStamp? {
        payload := IncrementalCacheFile.ReadPayload(path)
        if payload == null {
            return null
        }

        try {
            stream := new MemoryStream(payload)
            reader := new BinaryReader(stream, Encoding.UTF8)
            try {
                if reader.ReadString() != IncrementalBuildStamp.Magic() {
                    return null
                }
                if reader.ReadInt32() != IncrementalBuildStamp.FormatVersion {
                    return null
                }
                key := reader.ReadString()
                if expectedKey != null && !string.Equals(key, expectedKey, StringComparison.Ordinal) {
                    return null
                }

                stamp := new IncrementalBuildStamp(key)
                stamp.CheckAnalysisReuseKey = reader.ReadString()
                if expectedAnalysisReuseKey != null && !string.Equals(stamp.CheckAnalysisReuseKey, expectedAnalysisReuseKey, StringComparison.Ordinal) {
                    return null
                }
                stamp.ResultKind = reader.ReadInt32()
                stamp.CheckSchemaVersion = reader.ReadInt32()
                stamp.CheckExitCode = reader.ReadInt32()
                stamp.CheckOutputToStandardError = reader.ReadBoolean()
                stamp.CheckOutput = reader.ReadString()
                stamp.CheckDiagnosticsJson = reader.ReadString()
                stamp.CheckHadDiagnostics = reader.ReadBoolean()
                entryCount := reader.ReadInt32()
                entryIndex := 0
                while entryIndex < entryCount {
                    kind := reader.ReadInt32()
                    entryPath := reader.ReadString()
                    entryValue := reader.ReadString()
                    stamp.Entries.Add(new IncrementalInputEntry(kind, entryPath, entryValue))
                    entryIndex = entryIndex + 1
                }

                outputCount := reader.ReadInt32()
                outputIndex := 0
                while outputIndex < outputCount {
                    stamp.OutputPaths.Add(reader.ReadString())
                    stamp.OutputHashes.Add(reader.ReadString())
                    outputIndex = outputIndex + 1
                }

                diagnosticCount := reader.ReadInt32()
                diagnosticIndex := 0
                while diagnosticIndex < diagnosticCount {
                    stamp.Diagnostics.Add(IncrementalBuildStamp.ReadError(reader))
                    diagnosticIndex = diagnosticIndex + 1
                }

                checkFileCount := reader.ReadInt32()
                checkFileIndex := 0
                while checkFileIndex < checkFileCount {
                    filePath := reader.ReadString()
                    summary := IncrementalSummaryStore.ReadSummary(reader)
                    fileResult := new IncrementalCheckFileResult(filePath, summary)
                    fileResult.Analyzed = reader.ReadBoolean()
                    IncrementalBuildStamp.ReadErrors(reader, fileResult.ParseErrors)
                    IncrementalBuildStamp.ReadErrors(reader, fileResult.AnalysisErrors)
                    IncrementalBuildStamp.ReadStringSet(reader, fileResult.Dependencies)
                    IncrementalBuildStamp.ReadStringMap(reader, fileResult.ImportedFileHashes)
                    stamp.CheckFiles.Add(fileResult)
                    checkFileIndex = checkFileIndex + 1
                }

                if stream.Position != stream.Length {
                    return null
                }

                return stamp
            } finally {
                reader.Dispose()
            }
        } catch {
            return null
        }
    }

    static func TryReadCheckStamp(path: string, expectedKey: string): IncrementalBuildStamp? {
        stamp := IncrementalBuildStamp.TryRead(path, expectedKey)
        if stamp == null {
            return null
        }
        if !IncrementalBuildStamp.IsCheckResultStamp(stamp) || !stamp.IsCurrent() {
            return null
        }
        if stamp.CheckDiagnosticsJson.Length == 0 {
            return null
        }

        return stamp
    }

    // A source edit makes the complete check result stale, but its checksum-protected per-file
    // records remain candidates for an interface-preserving cold analysis. The caller separately
    // verifies every non-source input before using them.
    static func TryReadCheckStampForReuse(path: string, expectedKey: string): IncrementalBuildStamp? {
        stamp := IncrementalBuildStamp.TryRead(path, expectedKey)
        if stamp == null || !IncrementalBuildStamp.IsCheckResultStamp(stamp) || stamp.CheckDiagnosticsJson.Length == 0 {
            return null
        }
        return stamp
    }

    // Per-file summaries can seed a full reanalysis when the source set changes. The separate
    // analysis identity excludes only the source path set; current project/reference inputs and
    // every reused file's content hash are still checked by the compiler before reuse.
    static func TryReadCheckStampForAnalysisReuse(path: string, expectedAnalysisReuseKey: string): IncrementalBuildStamp? {
        stamp := IncrementalBuildStamp.TryRead(path, null, expectedAnalysisReuseKey)
        if stamp == null || !IncrementalBuildStamp.IsCheckResultStamp(stamp) || stamp.CheckDiagnosticsJson.Length == 0 {
            return null
        }
        return stamp
    }

    private static func IsCheckResultStamp(stamp: IncrementalBuildStamp): bool {
        return stamp.ResultKind == IncrementalBuildStamp.CheckResultKind && stamp.CheckSchemaVersion == IncrementalBuildStamp.CheckResultSchemaVersion
    }

    static func TryReadCheckResult(path: string, expectedKey: string): IncrementalCheckResult? {
        stamp := IncrementalBuildStamp.TryReadCheckStamp(path, expectedKey)
        if stamp == null {
            return null
        }

        return new IncrementalCheckResult(
            stamp.CheckOutput,
            stamp.CheckDiagnosticsJson,
            stamp.CheckOutputToStandardError,
            stamp.CheckExitCode
        )
    }

    // ---- writing ---------------------------------------------------------------------------------

    // Best effort: a stamp that cannot be written costs the next build its shortcut and nothing else.
    func TryWrite(path: string): bool {
        try {
            stream := new MemoryStream()
            writer := new BinaryWriter(stream, Encoding.UTF8)
            writer.Write(IncrementalBuildStamp.Magic())
            writer.Write(IncrementalBuildStamp.FormatVersion)
            writer.Write(Key)
            writer.Write(CheckAnalysisReuseKey)
            writer.Write(ResultKind)
            writer.Write(CheckSchemaVersion)
            writer.Write(CheckExitCode)
            writer.Write(CheckOutputToStandardError)
            writer.Write(CheckOutput)
            writer.Write(CheckDiagnosticsJson)
            writer.Write(CheckHadDiagnostics)
            writer.Write(Entries.Count)
            for entry in Entries {
                writer.Write(entry.Kind)
                writer.Write(entry.Path)
                writer.Write(entry.Value)
            }
            writer.Write(OutputPaths.Count)
            index := 0
            while index < OutputPaths.Count {
                writer.Write(OutputPaths[index])
                writer.Write(OutputHashes[index])
                index = index + 1
            }
            writer.Write(Diagnostics.Count)
            for diagnostic in Diagnostics {
                IncrementalBuildStamp.WriteError(writer, diagnostic)
            }
            writer.Write(CheckFiles.Count)
            for checkFile in CheckFiles {
                writer.Write(checkFile.Path)
                IncrementalSummaryStore.WriteSummary(writer, checkFile.Summary)
                writer.Write(checkFile.Analyzed)
                IncrementalBuildStamp.WriteErrors(writer, checkFile.ParseErrors)
                IncrementalBuildStamp.WriteErrors(writer, checkFile.AnalysisErrors)
                IncrementalBuildStamp.WriteStringSet(writer, checkFile.Dependencies)
                IncrementalBuildStamp.WriteStringMap(writer, checkFile.ImportedFileHashes)
            }
            writer.Flush()
            payload := stream.ToArray()
            writer.Dispose()
            return IncrementalCacheFile.WritePayload(path, payload)
        } catch {
            return false
        }
    }

    // ---- diagnostics -----------------------------------------------------------------------------

    // The `CompilerError` members this stamp carries, in the order it writes them. The estate row
    // compares this list with the record's own settable members.
    static func SerializedErrorMembers(): string[] {
        return [
            "Code",
            "Message",
            "FileName",
            "Line",
            "Column",
            "Length",
            "Suggestion",
            "SourceSnippet",
            "Severity",
            "ActualType",
            "ExpectedType",
            "HumanExplanation",
            "ContextualHint",
            "DocsUrl",
            "Suggestions",
            "RelatedInfo",
            "DiagnosticIdOverride"
        ]
    }

    // The record's positional parameters. Nothing reads them — every reader goes through the explicit
    // members, which the record initialises from them — and `ReadError` reproduces them the way every
    // diagnostic is made: by calling the constructor.
    static func ConstructorErrorMembers(): string[] {
        return ["code", "message", "line", "column", "severity"]
    }

    static func WriteError(writer: BinaryWriter, error: CompilerError) {
        codeValue: int = (int)error.Code
        severityValue: int = (int)error.Severity
        writer.Write(codeValue)
        writer.Write(error.Message)
        WriteOptional(writer, error.FileName)
        writer.Write(error.Line)
        writer.Write(error.Column)
        writer.Write(error.Length)
        WriteOptional(writer, error.Suggestion)
        WriteOptional(writer, error.SourceSnippet)
        writer.Write(severityValue)
        WriteOptional(writer, error.ActualType)
        WriteOptional(writer, error.ExpectedType)
        WriteOptional(writer, error.HumanExplanation)
        WriteOptional(writer, error.ContextualHint)
        WriteOptional(writer, error.DocsUrl)
        suggestions := error.Suggestions
        if suggestions == null {
            writer.Write(-1)
        } else {
            writer.Write(suggestions.Count)
            for suggestion in suggestions {
                writer.Write(suggestion)
            }
        }
        relatedInfo := error.RelatedInfo
        if relatedInfo == null {
            writer.Write(-1)
        } else {
            writer.Write(relatedInfo.Count)
            for entry in relatedInfo {
                writer.Write(entry.Key)
                writer.Write(entry.Value)
            }
        }
        WriteOptional(writer, error.DiagnosticIdOverride)
    }

    static func ReadError(reader: BinaryReader): CompilerError {
        codeValue := reader.ReadInt32()
        message := reader.ReadString()
        fileName := ReadOptional(reader)
        line := reader.ReadInt32()
        column := reader.ReadInt32()
        length := reader.ReadInt32()
        suggestion := ReadOptional(reader)
        sourceSnippet := ReadOptional(reader)
        severityValue := reader.ReadInt32()
        error := new CompilerError((ErrorCode)codeValue, message, line, column, (ErrorSeverity)severityValue)
        error.FileName = fileName
        error.Length = length
        error.Suggestion = suggestion
        error.SourceSnippet = sourceSnippet
        error.ActualType = ReadOptional(reader)
        error.ExpectedType = ReadOptional(reader)
        error.HumanExplanation = ReadOptional(reader)
        error.ContextualHint = ReadOptional(reader)
        error.DocsUrl = ReadOptional(reader)
        suggestionCount := reader.ReadInt32()
        if suggestionCount >= 0 {
            suggestions := new List<string>()
            suggestionIndex := 0
            while suggestionIndex < suggestionCount {
                suggestions.Add(reader.ReadString())
                suggestionIndex = suggestionIndex + 1
            }
            error.Suggestions = suggestions
        }
        relatedCount := reader.ReadInt32()
        if relatedCount >= 0 {
            relatedInfo := new Dictionary<string, string>()
            relatedIndex := 0
            while relatedIndex < relatedCount {
                relatedKey := reader.ReadString()
                relatedValue := reader.ReadString()
                relatedInfo[relatedKey] = relatedValue
                relatedIndex = relatedIndex + 1
            }
            error.RelatedInfo = relatedInfo
        }
        error.DiagnosticIdOverride = ReadOptional(reader)
        return error
    }

    private static func WriteErrors(writer: BinaryWriter, errors: List<CompilerError>): void {
        writer.Write(errors.Count)
        for error in errors {
            IncrementalBuildStamp.WriteError(writer, error)
        }
    }

    private static func ReadErrors(reader: BinaryReader, errors: List<CompilerError>): void {
        count := reader.ReadInt32()
        index := 0
        while index < count {
            errors.Add(IncrementalBuildStamp.ReadError(reader))
            index = index + 1
        }
    }

    private static func WriteStringSet(writer: BinaryWriter, values: HashSet<string>): void {
        ordered := new List<string>(values)
        ordered.Sort(StringComparer.Ordinal)
        writer.Write(ordered.Count)
        for value in ordered {
            writer.Write(value)
        }
    }

    private static func ReadStringSet(reader: BinaryReader, values: HashSet<string>): void {
        count := reader.ReadInt32()
        index := 0
        while index < count {
            values.Add(reader.ReadString())
            index = index + 1
        }
    }

    private static func WriteStringMap(writer: BinaryWriter, values: Dictionary<string, string>): void {
        keys := new List<string>(values.Keys)
        keys.Sort(StringComparer.Ordinal)
        writer.Write(keys.Count)
        for key in keys {
            writer.Write(key)
            writer.Write(values[key])
        }
    }

    private static func ReadStringMap(reader: BinaryReader, values: Dictionary<string, string>): void {
        count := reader.ReadInt32()
        index := 0
        while index < count {
            key := reader.ReadString()
            value := reader.ReadString()
            values[key] = value
            index = index + 1
        }
    }

    private static func WriteOptional(writer: BinaryWriter, value: string?): void {
        if value == null {
            writer.Write(false)
            return
        }

        writer.Write(true)
        writer.Write(value)
    }

    private static func ReadOptional(reader: BinaryReader): string? {
        if !reader.ReadBoolean() {
            return null
        }

        return reader.ReadString()
    }
}

// The output of one completed `nlc check` invocation under the input closure in its stamp. JSON and
// text modes share the same diagnostics JSON, while `Output` preserves the exact bytes of the
// selected user-facing stream (including the human elapsed line) for a cold cache hit.
class IncrementalCheckResult {
    Output: string
    DiagnosticsJson: string
    OutputToStandardError: bool
    ExitCode: int

    constructor(output: string, diagnosticsJson: string, outputToStandardError: bool, exitCode: int) {
        Output = output
        DiagnosticsJson = diagnosticsJson
        OutputToStandardError = outputToStandardError
        ExitCode = exitCode
    }
}
