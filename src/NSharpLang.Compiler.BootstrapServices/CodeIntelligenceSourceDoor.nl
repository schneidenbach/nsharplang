namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.Ast


// THE WORDS EVERY ANSWER CARRIES — the half that reads a file's text or its path.
//
// Ten members that turn a POSITION into the word, span, line, context or doc comment an answer
// prints, plus the relative path every result row carries. Like the pure half they resolve nothing;
// unlike it they need the file's text, and the text arrives as a `string?` rather than as a project
// snapshot. THAT WAS A WALL WHEN THESE MEMBERS WERE WRITTEN AND IS A CHOICE NOW:
// `IReadOnlyDictionary<K, V>` was absent from the columnar emitter's resolvable-type catalog, so a
// snapshot's `SourceTexts` could not cross into N# at all. 019 slice 15 published the head — which
// is why `SourceText` below takes the map itself — and 020 slice 10 published the WIDENING that lets
// a caller BUILD one. The other members still take `source: string` because the text is all they
// need, exactly as `CodeIntelligenceSourceTextKernels` does.
class CodeIntelligenceSourceDoor {

    // ── The path every result row carries ────────────────────────────────
    // THE PROJECT'S TEXT FOR A FILE — the door slice 13 could not move and slice 15 stage 2 owns.
    // A cached text is the LSP's unsaved-buffer path (the editor's in-memory content for a file whose
    // disk copy is stale); anything else is read from disk, and a path that does not exist THROWS.
    // The lookup key is always the FULL path, which is why a relative caller still finds its entry.
    static func SourceText(sourceTexts: IReadOnlyDictionary<string, string>, filePath: string?): string? {
        if filePath == null {
            return null
        }

        fullPath := Path.GetFullPath(filePath)
        text := ""
        if sourceTexts.TryGetValue(fullPath, out text) && text != null {
            return text
        }

        return File.ReadAllText(fullPath)
    }

    static func RelativePath(projectRoot: string, filePath: string): string {
        try {
            return Path.GetRelativePath(projectRoot, filePath)
        } catch ex: Exception {
            return filePath
        }
    }

    // Find the absolute path a code-intelligence answer's relative file name came from. Split out of
    // the doc-comment walk because the source text can only be fetched once the path is known, and
    // the fetch is the one step the catalog wall keeps on the caller's side.
    static func ResolveAbsolutePath(filePaths: IEnumerable<string>, relativeFile: string): string? {
        for filePath in filePaths {
            if CodeIntelligenceResultKernels.MatchesFilePath(filePath, relativeFile) {
                return filePath
            }
        }

        return null
    }

    // ── The text a diagnostic, a hover and a reference row carry ─────────

    // The three C# `ExtractSourceLine` shapes COLLAPSE INTO ONE, and the collapse is safe because
    // they differed only in how they got the text: one took a dictionary, one took a snapshot, one
    // took the string. All three then asked the same kernel and threw on the same rejection.
    static func SourceLine(source: string?, line: int): string? {
        if source == null {
            return null
        }

        text: string? = null
        if !CodeIntelligenceSourceTextKernels.TryExtractSourceLine(source, line, out text) {
            throw new InvalidOperationException("N# source line kernel rejected the source.")
        }

        return text
    }

    static func SourceContext(source: string?, line: int): string? {
        if source == null {
            return null
        }

        if line <= 0 {
            return null
        }

        context: string? = null
        if CodeIntelligenceSourceTextKernels.TryExtractSourceContext(source, line, out context) {
            return context
        }

        return null
    }

    static func DocComment(source: string?, definitionLine: int): string? {
        if source == null {
            return null
        }

        if definitionLine <= 1 {
            return null
        }

        documentation: string? = null
        if !CodeIntelligenceSourceTextKernels.TryExtractDocComment(source, definitionLine, out documentation) {
            throw new InvalidOperationException("N# doc comment kernel rejected the source.")
        }

        return documentation
    }

    // ── The words and spans read at a position ───────────────────────────

    static func WordAt(source: string?, line: int, column: int): string? {
        if source == null {
            return null
        }

        name: string? = null
        if CodeIntelligenceSourceTextKernels.TryExtractIdentifierName(source, line, column, out name) {
            return name
        }

        return null
    }

    static func IdentifierSpanAt(source: string?, line: int, column: int): ValueTuple<int, int>? {
        if source == null {
            return null
        }

        span: ValueTuple<int, int>? = null
        if CodeIntelligenceSourceTextKernels.TryExtractIdentifierSpan(source, line, column, out span) {
            return span
        }

        return null
    }

    static func VariableDeclarationNameAt(source: string?, line: int): string? {
        if source == null {
            return null
        }

        name: string? = null
        if CodeIntelligenceSourceTextKernels.TryExtractVariableDeclarationName(source, line, out name) {
            return name
        }

        return null
    }

    // ── The positions a robust lookup tries ──────────────────────────────

    // The C# was a `yield return` iterator and `yield` does not emit, so the sequence is built
    // eagerly. The EMISSION ORDER IS THE CONTRACT — the column itself, then each distance outward
    // left-before-right — because `FindExpressionAtPositionRobust` returns the FIRST hit and a
    // reordering would silently change which expression hover lands on.
    static func NearbyColumns(column: int, maxDistance: int): int[] {
        count := 0
        if column > 0 {
            count = count + 1
        }

        distance := 1
        while distance <= maxDistance {
            if column - distance > 0 {
                count = count + 1
            }

            count = count + 1
            distance = distance + 1
        }

        result := new int[](count)
        next := 0
        if column > 0 {
            result[next] = column
            next = next + 1
        }

        distance = 1
        while distance <= maxDistance {
            if column - distance > 0 {
                result[next] = column - distance
                next = next + 1
            }

            result[next] = column + distance
            next = next + 1
            distance = distance + 1
        }

        return result
    }

    // ── The names a type query will try, in order ────────────────────────

    static func CandidateQueryNames(expr: Expression?, source: string?, line: int, column: int): List<string> {
        names := new List<string>()

        AddCandidateName(names, CodeIntelligenceDisplayText.GetExpressionQueryName(expr))
        AddCandidateName(names, WordAt(source, line, column))
        AddCandidateName(names, WordAt(source, line, Math.Max(0, column - 1)))
        AddCandidateName(names, WordAt(source, line, column + 1))
        AddCandidateName(names, VariableDeclarationNameAt(source, line))

        return names
    }

    static func AddCandidateName(names: List<string>, name: string?) {
        if string.IsNullOrWhiteSpace(name) {
            return
        }

        index := 0
        while index < names.Count {
            if String.Equals(names[index], name, StringComparison.Ordinal) {
                return
            }

            index = index + 1
        }

        names.Add(name)
    }
}
