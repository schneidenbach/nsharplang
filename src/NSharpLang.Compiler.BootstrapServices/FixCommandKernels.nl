namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.IO
import System.Text
import System.Text.Json
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence

public class FixEntry {
    File: string
    DiagnosticCode: string
    Title: string
    Edits: List<TextEdit>
    Safety: string

    constructor(File: string, DiagnosticCode: string, Title: string, Edits: List<TextEdit>, Safety: string) {
        this.File = File
        this.DiagnosticCode = DiagnosticCode
        this.Title = Title
        this.Edits = Edits
        this.Safety = Safety
    }
}

public class FixAppliedFileGrouping {
    Files: string[]
    Starts: int[]
    Counts: int[]
    Indices: int[]
    GroupCount: int => Files.Length

    constructor(files: string[], starts: int[], counts: int[], indices: int[]) {
        Files = files
        Starts = starts
        Counts = counts
        Indices = indices
    }
}

public class FixCommandKernels {
    public static func ToFixEntry(relativeFile: string, fix: CodeAction): FixEntry {
        return new FixEntry(NormalizePath(relativeFile), fix.DiagnosticCode, fix.Title, fix.Edits, GetFixSafetyJsonName(fix.Safety))
    }

    public static func FilterBySafety(fixes: IReadOnlyList<CodeAction>, includeReviewNeeded: bool): List<CodeAction> {
        items := CodeActionList(fixes)
        fixCount := items.Count
        safetyRanks := new int[](fixCount)
        resultIndices := new int[](fixCount)

        i := 0
        while i < fixCount {
            safetyRanks[i] = GetFixSafetyRank(items[i].Safety)
            i = i + 1
        }

        safeCount := SelectSafetyIndices(safetyRanks, includeReviewNeeded, resultIndices)
        if safeCount < 0 || safeCount > fixCount || safeCount > resultIndices.Length {
            throw new InvalidOperationException("N# fix safety filter kernel rejected the fixes.")
        }

        safeActions := new List<CodeAction>(safeCount)
        i = 0
        while i < safeCount {
            sourceIndex := resultIndices[i]
            if sourceIndex < 0 || sourceIndex >= fixCount {
                throw new InvalidOperationException("N# fix safety filter kernel returned an invalid source index.")
            }

            safeActions.Add(items[sourceIndex])
            i = i + 1
        }

        return safeActions
    }

    public static func SelectSkippedEntries(results: IReadOnlyList<FixEntry>, includeReviewNeeded: bool): List<FixEntry> {
        items := FixEntryList(results)
        resultCount := items.Count
        safetyRanks := new int[](resultCount)
        resultIndices := new int[](resultCount)

        i := 0
        while i < resultCount {
            safetyRanks[i] = GetFixEntrySafetyRank(items[i].Safety)
            i = i + 1
        }

        skippedCount := SelectSkippedIndices(safetyRanks, includeReviewNeeded, resultIndices)
        if skippedCount < 0 || skippedCount > resultCount || skippedCount > resultIndices.Length {
            throw new InvalidOperationException("N# fix skipped-entry selection kernel rejected the fixes.")
        }

        skipped := new List<FixEntry>(skippedCount)
        i = 0
        while i < skippedCount {
            sourceIndex := resultIndices[i]
            if sourceIndex < 0 || sourceIndex >= resultCount {
                throw new InvalidOperationException("N# fix skipped-entry selection kernel returned an invalid source index.")
            }

            skipped.Add(items[sourceIndex])
            i = i + 1
        }

        return skipped
    }

    public static func GroupAppliedEntriesByFile(applied: IReadOnlyList<FixEntry>): FixAppliedFileGrouping {
        items := FixEntryList(applied)
        appliedCount := items.Count
        scratch := new AppliedFileGroupingScratch()
        scratch.EnsureCapacity(appliedCount)

        i := 0
        while i < appliedCount {
            fileRank := scratch.GetOrAddFileRank(items[i].File)
            scratch.FileRanks[i] = fileRank
            i = i + 1
        }

        groupCount := AppliedFileGroups(
            scratch.FileRanks,
            scratch.UniqueFileRankCount,
            scratch.CountsByRank,
            scratch.OffsetsByRank,
            scratch.WriteOffsetsByRank,
            scratch.ResultRanks,
            scratch.ResultStarts,
            scratch.ResultCounts,
            scratch.ResultIndices)

        if groupCount < 0
            || groupCount > scratch.UniqueFileRankCount
            || groupCount > appliedCount {
            throw new InvalidOperationException("N# fix applied-file grouping kernel rejected the fixes.")
        }

        files := new string[](groupCount)
        starts := new int[](groupCount)
        counts := new int[](groupCount)
        indices := new int[](appliedCount)

        groupIndex := 0
        while groupIndex < groupCount {
            rank := scratch.ResultRanks[groupIndex]
            start := scratch.ResultStarts[groupIndex]
            count := scratch.ResultCounts[groupIndex]
            if rank <= 0
                || rank > scratch.UniqueFileRankCount
                || start < 0
                || count < 0
                || start + count > appliedCount {
                throw new InvalidOperationException("N# fix applied-file grouping kernel returned an invalid group.")
            }

            files[groupIndex] = scratch.FilesByRank[rank] ?? ""
            starts[groupIndex] = start
            counts[groupIndex] = count
            groupIndex = groupIndex + 1
        }

        i = 0
        while i < appliedCount {
            sourceIndex := scratch.ResultIndices[i]
            if sourceIndex < 0 || sourceIndex >= appliedCount {
                throw new InvalidOperationException("N# fix applied-file grouping kernel returned an invalid source index.")
            }

            indices[i] = sourceIndex
            i = i + 1
        }

        return new FixAppliedFileGrouping(files, starts, counts, indices)
    }

    public static func ResultText(
        results: IReadOnlyList<FixEntry>,
        applied: IReadOnlyList<FixEntry>,
        filesModified: int,
        dryRun: bool,
        includeReviewNeeded: bool): string {
        resultItems := FixEntryList(results)
        appliedItems := FixEntryList(applied)
        builder := new StringBuilder()

        if resultItems.Count == 0 {
            AppendLine(builder, GetNothingToFixMessage())
            return builder.ToString()
        }

        if appliedItems.Count > 0 {
            AppendLine(builder, GetAppliedHeader(appliedItems.Count, filesModified, dryRun))

            groupedApplied := GroupAppliedEntriesByFile(appliedItems)
            groupIndex := 0
            while groupIndex < groupedApplied.GroupCount {
                AppendLine(builder, GetAppliedFileHeader(groupedApplied.Files[groupIndex]))
                start := groupedApplied.Starts[groupIndex]
                count := groupedApplied.Counts[groupIndex]
                i := 0
                while i < count {
                    sourceIndex := groupedApplied.Indices[start + i]
                    fix := appliedItems[sourceIndex]
                    AppendLine(builder, GetEntryLine(fix.DiagnosticCode, fix.Title))
                    i = i + 1
                }

                groupIndex = groupIndex + 1
            }
        }

        skipped := SelectSkippedEntries(resultItems, includeReviewNeeded)
        if skipped.Count > 0 {
            AppendLine(builder, "")
            AppendLine(builder, GetSkippedHeader(skipped.Count))

            foreach fix in skipped {
                reason := GetSkippedReason(fix.Safety)
                AppendLine(builder, GetSkippedLine(fix.DiagnosticCode, fix.Title, reason))
            }
        }

        return builder.ToString()
    }

    public static func ResultJson(
        projectDir: string,
        dryRun: bool,
        includeReviewNeeded: bool,
        results: IReadOnlyList<FixEntry>,
        applied: IReadOnlyList<FixEntry>,
        filesModified: int): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 2
        envelope["command"] = "fix"
        envelope["projectRoot"] = NormalizePath(Path.GetFullPath(projectDir))
        envelope["dryRun"] = dryRun
        envelope["includeReviewNeeded"] = includeReviewNeeded
        envelope["ok"] = !dryRun || filesModified == 0
        envelope["filesModified"] = filesModified
        envelope["results"] = BuildJsonEntries(results)
        envelope["fixesApplied"] = BuildJsonEntries(applied)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    public static func GetExitCode(dryRun: bool, filesModified: int): int {
        if dryRun && filesModified > 0 {
            return 1
        }

        return 0
    }

    static func BuildJsonEntries(entries: IReadOnlyList<FixEntry>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        items := FixEntryList(entries)

        i := 0
        while i < items.Count {
            payload.Add(BuildJsonEntry(items[i]))
            i = i + 1
        }

        return payload
    }

    static func BuildJsonEntry(entry: FixEntry): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["file"] = NormalizePath(entry.File)
        payload["diagnostic"] = entry.DiagnosticCode
        payload["title"] = entry.Title
        payload["safety"] = entry.Safety
        payload["edits"] = BuildJsonEdits(entry.Edits)
        return payload
    }

    static func BuildJsonEdits(edits: IReadOnlyList<TextEdit>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        i := 0
        while i < edits.Count {
            payload.Add(BuildJsonEdit(edits[i]))
            i = i + 1
        }

        return payload
    }

    static func BuildJsonEdit(edit: TextEdit): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["startLine"] = edit.StartLine
        payload["startColumn"] = edit.StartColumn
        payload["endLine"] = edit.EndLine
        payload["endColumn"] = edit.EndColumn
        if edit.NewText != null {
            payload["newText"] = edit.NewText
        }

        return payload
    }

    public static func GetHelpText(): string {
        return "N# Auto-Fix\n"
            + "\n"
            + "Usage: nlc fix [options] [project-dir]\n"
            + "\n"
            + "Options:\n"
            + "  --json                    Output as JSON (default)\n"
            + "  --text                    Output as human-readable summary\n"
            + "  --project                 Project root directory (default: current directory)\n"
            + "  --file                    Fix a single file\n"
            + "  --dry-run                 Preview fixes without writing files\n"
            + "  --include-review-needed   Also apply fixes that may need review (e.g. unused import removal)\n"
            + "  --help, -h                Show this help text\n"
            + "\n"
            + "Safety levels:\n"
            + "  Safe              Always applied by default\n"
            + "  ReviewNeeded      Only applied with --include-review-needed flag\n"
            + "  SuggestionOnly    Never applied automatically — reported in results only\n"
            + "\n"
            + "Examples:\n"
            + "  nlc fix\n"
            + "  nlc fix --dry-run --text\n"
            + "  nlc fix --include-review-needed\n"
            + "  nlc fix --file Program.nl\n"
            + "  nlc fix --project examples/16-task-cli"
    }

    public static func GetProjectDirectoryNotFoundMessage(projectDir: string): string {
        return "Directory not found: " + projectDir
    }

    public static func GetFileNotFoundMessage(filePath: string): string {
        return "File not found: " + filePath
    }

    public static func GetNoFilesFoundMessage(): string {
        return "No .nl files found."
    }

    public static func GetFailedMessage(message: string): string {
        return "Fix failed: " + message
    }

    public static func GetNothingToFixMessage(): string {
        return "Nothing to fix."
    }

    public static func GetAppliedHeader(appliedCount: int, filesModified: int, dryRun: bool): string {
        verb := "Fixed"
        if dryRun {
            verb = "Would fix"
        }

        issueSuffix := "s"
        if appliedCount == 1 {
            issueSuffix = ""
        }

        fileWord := "files"
        if filesModified == 1 {
            fileWord = "file"
        }

        return verb + " " + appliedCount.ToString() + " issue" + issueSuffix + " in " + filesModified.ToString() + " " + fileWord + ":"
    }

    public static func GetAppliedFileHeader(filePath: string): string {
        return "  " + filePath + ":"
    }

    public static func GetEntryLine(diagnosticCode: string, title: string): string {
        return "    [" + diagnosticCode + "] " + title
    }

    public static func GetSkippedHeader(skippedCount: int): string {
        suffix := "es"
        if skippedCount == 1 {
            suffix = ""
        }

        return "Skipped " + skippedCount.ToString() + " fix" + suffix + ":"
    }

    public static func GetSkippedReason(safety: string): string {
        if safety == "suggestionOnly" {
            return "suggestion only — manual review required"
        }

        return "requires --include-review-needed flag"
    }

    public static func GetSkippedLine(diagnosticCode: string, title: string, reason: string): string {
        return "  [" + diagnosticCode + "] " + title + " (" + reason + ")"
    }

    static func SelectSafetyIndices(safetyRanks: int[], includeReviewNeeded: bool, resultIndices: int[]): int {
        maxAppliedRank := 1
        if includeReviewNeeded {
            maxAppliedRank = 2
        }

        matchCount := 0
        i := 0
        while i < safetyRanks.Length {
            rank := safetyRanks[i]
            if rank > 0 && rank <= maxAppliedRank {
                if matchCount < resultIndices.Length {
                    resultIndices[matchCount] = i
                }

                matchCount = matchCount + 1
            }

            i = i + 1
        }

        return matchCount
    }

    static func SelectSkippedIndices(safetyRanks: int[], includeReviewNeeded: bool, resultIndices: int[]): int {
        maxAppliedRank := 1
        if includeReviewNeeded {
            maxAppliedRank = 2
        }

        skippedCount := 0
        i := 0
        while i < safetyRanks.Length {
            rank := safetyRanks[i]
            if rank == 0 || rank > maxAppliedRank {
                if skippedCount < resultIndices.Length {
                    resultIndices[skippedCount] = i
                }

                skippedCount = skippedCount + 1
            }

            i = i + 1
        }

        return skippedCount
    }

    static func AppliedFileGroups(
        fileRanks: int[],
        uniqueFileRankCount: int,
        countsByRank: int[],
        offsetsByRank: int[],
        writeOffsetsByRank: int[],
        resultRanks: int[],
        resultStarts: int[],
        resultCounts: int[],
        resultIndices: int[]): int {
        if uniqueFileRankCount < 0 {
            return -1
        }

        if fileRanks.Length == 0 {
            return 0
        }

        if uniqueFileRankCount == 0 {
            return -1
        }

        rankCapacity := uniqueFileRankCount + 1
        if countsByRank.Length < rankCapacity
            || offsetsByRank.Length < rankCapacity
            || writeOffsetsByRank.Length < rankCapacity
            || resultRanks.Length < uniqueFileRankCount
            || resultStarts.Length < uniqueFileRankCount
            || resultCounts.Length < uniqueFileRankCount
            || resultIndices.Length < fileRanks.Length {
            return -1
        }

        rank := 0
        while rank < rankCapacity {
            countsByRank[rank] = 0
            offsetsByRank[rank] = 0
            writeOffsetsByRank[rank] = 0
            rank = rank + 1
        }

        i := 0
        while i < fileRanks.Length {
            fileRank := fileRanks[i]
            if fileRank <= 0 || fileRank > uniqueFileRankCount {
                return -1
            }

            countsByRank[fileRank] = countsByRank[fileRank] + 1
            i = i + 1
        }

        offset := 0
        rank = 1
        while rank <= uniqueFileRankCount {
            groupIndex := rank - 1
            count := countsByRank[rank]
            resultRanks[groupIndex] = rank
            resultStarts[groupIndex] = offset
            resultCounts[groupIndex] = count
            offsetsByRank[rank] = offset
            writeOffsetsByRank[rank] = offset
            offset = offset + count
            rank = rank + 1
        }

        if offset > resultIndices.Length {
            return -1
        }

        i = 0
        while i < fileRanks.Length {
            fileRank := fileRanks[i]
            writeIndex := writeOffsetsByRank[fileRank]
            if writeIndex < 0 || writeIndex >= resultIndices.Length {
                return -1
            }

            resultIndices[writeIndex] = i
            writeOffsetsByRank[fileRank] = writeIndex + 1
            i = i + 1
        }

        return uniqueFileRankCount
    }

    static func GetFixSafetyRank(safety: FixSafety): int {
        if safety == FixSafety.Safe {
            return 1
        }

        if safety == FixSafety.ReviewNeeded {
            return 2
        }

        if safety == FixSafety.SuggestionOnly {
            return 3
        }

        return 0
    }

    static func GetFixSafetyJsonName(safety: FixSafety): string {
        if safety == FixSafety.Safe {
            return "safe"
        }

        if safety == FixSafety.ReviewNeeded {
            return "reviewNeeded"
        }

        if safety == FixSafety.SuggestionOnly {
            return "suggestionOnly"
        }

        return "unknown"
    }

    static func GetFixEntrySafetyRank(safety: string): int {
        if safety == "safe" {
            return 1
        }

        if safety == "reviewNeeded" {
            return 2
        }

        if safety == "suggestionOnly" {
            return 3
        }

        return 0
    }

    static func CodeActionList(fixes: IReadOnlyList<CodeAction>): List<CodeAction> {
        items := new List<CodeAction>()
        foreach fix in fixes {
            items.Add((CodeAction)fix)
        }

        return items
    }

    static func FixEntryList(results: IReadOnlyList<FixEntry>): List<FixEntry> {
        items := new List<FixEntry>()
        foreach result in results {
            items.Add((FixEntry)result)
        }

        return items
    }

    static func CreateWriteIndentedOptions(): JsonSerializerOptions {
        return new JsonSerializerOptions { WriteIndented: true }
    }

    static func NormalizePath(path: string): string {
        normalized := OutputFormatterNormalizationKernels.NormalizePath(path)
        if normalized != null {
            return normalized ?? ""
        }

        return path
    }

    static func AppendLine(builder: StringBuilder, text: string) {
        builder.Append(text)
        builder.Append((char)10)
    }
}
