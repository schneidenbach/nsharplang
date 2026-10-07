namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

// ONE FILE'S COLUMNAR PARSE, KEPT FOR THE NEXT COMPILATION OF THE SAME PROJECT.
//
// The IL back end reads source independently of the analyzer's syntax tree: every file is tokenized
// and parsed into node tables again (`ColumnarProgramInputBuilder`, the `emit.parse` phase, ~330 ms
// of a warm 80k-line body-edit check). A file's parse is a function of its text alone -- it reads no
// other file, and the source-file id it is stamped with is its position in the compilation -- so a
// caller that compiles the same project repeatedly (`IncrementalCompilationState`, held by the
// workspace server) keeps each file's parse and hands it back while the file's text and position are
// unchanged. What a later stage writes onto a reused parse is the binding context every merge stamps
// over all of its node tables (`ColumnarProgramInput.StampBindingContexts`), so a reused parse leaves
// a merge exactly as a fresh one does; the decline records the parse made travel with it, so a
// compilation that declines later still reads the serial trace.
//
// A parse that declined is never kept: the next compilation parses that file again.
class ColumnarCachedFileProgram {
    Source: string
    FileId: int
    Program: ColumnarProgramInput
    Declines: IReadOnlyList<ColumnarDeclineReason>

    constructor(source: string, fileId: int, program: ColumnarProgramInput, declines: IReadOnlyList<ColumnarDeclineReason>) {
        Source = source
        FileId = fileId
        Program = program
        Declines = declines
    }
}

class ColumnarFileProgramCache {
    private readonly entries: Dictionary<string, ColumnarCachedFileProgram>

    // The files the last build answered from the cache and parsed, for counters and tests.
    LastReused: int
    LastParsed: int

    constructor() {
        entries = new Dictionary<string, ColumnarCachedFileProgram>(StringComparer.Ordinal)
        LastReused = 0
        LastParsed = 0
    }

    Count: int => entries.Count

    // The kept parse of `fileName` when its text and position are exactly these, or null.
    func TryGet(fileName: string, source: string, fileId: int): ColumnarCachedFileProgram? {
        cached: ColumnarCachedFileProgram? = null
        if !entries.TryGetValue(fileName, out cached) || cached == null {
            return null
        }

        if cached.FileId != fileId || !string.Equals(cached.Source, source, StringComparison.Ordinal) {
            return null
        }

        return cached
    }

    func Store(fileName: string, source: string, fileId: int, program: ColumnarProgramInput, declines: IReadOnlyList<ColumnarDeclineReason>) {
        entries[fileName] = new ColumnarCachedFileProgram(source, fileId, program, declines)
    }

    // Forgets every file not in this compilation, so a removed file's parse is not kept alive.
    func RetainOnly(fileNames: IReadOnlyList<string>) {
        keep := new HashSet<string>(fileNames, StringComparer.Ordinal)
        stale := new List<string>()
        for entry in entries {
            if !keep.Contains(entry.Key) {
                stale.Add(entry.Key)
            }
        }
        for name in stale {
            entries.Remove(name)
        }
    }

    func Clear() {
        entries.Clear()
    }
}
