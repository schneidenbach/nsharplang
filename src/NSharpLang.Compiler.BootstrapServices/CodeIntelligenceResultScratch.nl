namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

public class DiagnosticShadowSuppressionScratch {
    CodeIdsByText: Dictionary<string, int>
    FileRanksByText: Dictionary<string, int>

    CodeIds: int[]
    FileRanks: int[]
    Files: string[]
    ResultIndices: int[]
    ShadowFileFlags: int[]
    UniqueFiles: string[]
    UniqueFileCount: int

    public func EnsureCapacity(diagnosticCount: int, shadowedFileCount: int) {
        EnsureInitialized()
        if CodeIds.Length != diagnosticCount {
            CodeIds = new int[](diagnosticCount)
            FileRanks = new int[](diagnosticCount)
            Files = new string[](diagnosticCount)
            ResultIndices = new int[](diagnosticCount)
        }

        uniqueFileCapacity := diagnosticCount + shadowedFileCount
        if UniqueFiles.Length < uniqueFileCapacity {
            UniqueFiles = new string[](uniqueFileCapacity)
        }

        shadowFlagCapacity := uniqueFileCapacity + 1
        if ShadowFileFlags.Length < shadowFlagCapacity {
            ShadowFileFlags = new int[](shadowFlagCapacity)
        }
    }

    public func GetCodeId(text: string): int {
        EnsureInitialized()
        if CodeIdsByText.ContainsKey(text) {
            return CodeIdsByText[text]
        }

        id := CodeIdsByText.Count + 1
        CodeIdsByText.Add(text, id)
        return id
    }

    public func AddFile(text: string) {
        EnsureInitialized()
        if FileRanksByText.ContainsKey(text) {
            return
        }

        FileRanksByText.Add(text, 0)
        UniqueFiles[UniqueFileCount] = text
        UniqueFileCount = UniqueFileCount + 1
    }

    public func BuildFileRanks() {
        EnsureInitialized()
        Array.Sort(UniqueFiles, 0, UniqueFileCount, StringComparer.OrdinalIgnoreCase)

        i := 0
        while i < UniqueFileCount {
            FileRanksByText[UniqueFiles[i]] = i + 1
            i = i + 1
        }
    }

    public func GetFileRank(text: string): int {
        EnsureInitialized()
        if FileRanksByText.ContainsKey(text) {
            return FileRanksByText[text]
        }

        return -1
    }

    public func ClearFiles(count: int) {
        EnsureInitialized()
        if count > 0 {
            Array.Clear(Files, 0, count)
        }
    }

    public func ClearShadowFileFlags() {
        EnsureInitialized()
        if ShadowFileFlags.Length > 0 {
            Array.Clear(ShadowFileFlags, 0, ShadowFileFlags.Length)
        }
    }

    public func Reset() {
        EnsureInitialized()
        CodeIdsByText.Clear()
        FileRanksByText.Clear()
        if UniqueFileCount > 0 {
            Array.Clear(UniqueFiles, 0, UniqueFileCount)
            UniqueFileCount = 0
        }
    }

    func EnsureInitialized() {
        if CodeIdsByText != null {
            return
        }

        CodeIdsByText = new Dictionary<string, int>(StringComparer.Ordinal)
        FileRanksByText = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        CodeIds = new int[](0)
        FileRanks = new int[](0)
        Files = new string[](0)
        ResultIndices = new int[](0)
        ShadowFileFlags = new int[](0)
        UniqueFiles = new string[](0)
    }
}

public class DiagnosticDeduplicationScratch {
    CodeIdsByText: Dictionary<string, int>
    FileRanksByText: Dictionary<string, int>
    MessageIdsByText: Dictionary<string, int>

    CodeIds: int[]
    Columns: int[]
    FileRanks: int[]
    Files: string[]
    LineNumbers: int[]
    MessageIds: int[]
    ResultIndices: int[]
    SlotIndices: int[]
    UniqueFiles: string[]
    UniqueFileCount: int

    public func EnsureCapacity(count: int) {
        EnsureInitialized()
        if CodeIds.Length != count {
            CodeIds = new int[](count)
            FileRanks = new int[](count)
            LineNumbers = new int[](count)
            Columns = new int[](count)
            MessageIds = new int[](count)
            Files = new string[](count)
            ResultIndices = new int[](count)
            UniqueFiles = new string[](count)
        }

        slotCapacity := count * 2 + 1
        if SlotIndices.Length != slotCapacity {
            SlotIndices = new int[](slotCapacity)
        }
    }

    public func GetCodeId(text: string): int {
        EnsureInitialized()
        return GetId(CodeIdsByText, text)
    }

    public func GetFileId(text: string): int {
        EnsureInitialized()
        return GetId(FileRanksByText, text)
    }

    public func GetMessageId(text: string): int {
        EnsureInitialized()
        return GetId(MessageIdsByText, text)
    }

    public func AddFile(text: string) {
        EnsureInitialized()
        if FileRanksByText.ContainsKey(text) {
            return
        }

        FileRanksByText.Add(text, 0)
        UniqueFiles[UniqueFileCount] = text
        UniqueFileCount = UniqueFileCount + 1
    }

    public func BuildFileRanks() {
        EnsureInitialized()
        Array.Sort(UniqueFiles, 0, UniqueFileCount, StringComparer.Ordinal)

        i := 0
        while i < UniqueFileCount {
            FileRanksByText[UniqueFiles[i]] = i + 1
            i = i + 1
        }
    }

    public func GetFileRank(text: string): int {
        EnsureInitialized()
        return FileRanksByText[text]
    }

    public func ClearFiles(count: int) {
        EnsureInitialized()
        Array.Clear(Files, 0, count)
    }

    public func ResetIds() {
        EnsureInitialized()
        CodeIdsByText.Clear()
        FileRanksByText.Clear()
        MessageIdsByText.Clear()
        if UniqueFileCount > 0 {
            Array.Clear(UniqueFiles, 0, UniqueFileCount)
            UniqueFileCount = 0
        }
    }

    func EnsureInitialized() {
        if CodeIdsByText != null {
            return
        }

        CodeIdsByText = new Dictionary<string, int>(StringComparer.Ordinal)
        FileRanksByText = new Dictionary<string, int>(StringComparer.Ordinal)
        MessageIdsByText = new Dictionary<string, int>(StringComparer.Ordinal)
        CodeIds = new int[](0)
        Columns = new int[](0)
        FileRanks = new int[](0)
        Files = new string[](0)
        LineNumbers = new int[](0)
        MessageIds = new int[](0)
        ResultIndices = new int[](0)
        SlotIndices = new int[](0)
        UniqueFiles = new string[](0)
    }

    static func GetId(ids: Dictionary<string, int>, text: string): int {
        if ids.ContainsKey(text) {
            return ids[text]
        }

        id := ids.Count + 1
        ids.Add(text, id)
        return id
    }
}

public class ReferenceDeduplicationScratch {
    FileRanksByText: Dictionary<string, int>

    Columns: int[]
    FileRanks: int[]
    Files: string[]
    LineNumbers: int[]
    ResultIndices: int[]
    SlotIndices: int[]
    UniqueFiles: string[]
    UniqueFileCount: int

    public func EnsureCapacity(count: int) {
        EnsureInitialized()
        if FileRanks.Length != count {
            FileRanks = new int[](count)
            LineNumbers = new int[](count)
            Columns = new int[](count)
            Files = new string[](count)
            ResultIndices = new int[](count)
            UniqueFiles = new string[](count)
        }

        slotCapacity := count * 2 + 1
        if SlotIndices.Length != slotCapacity {
            SlotIndices = new int[](slotCapacity)
        }
    }

    public func AddFile(text: string) {
        EnsureInitialized()
        if FileRanksByText.ContainsKey(text) {
            return
        }

        FileRanksByText.Add(text, 0)
        UniqueFiles[UniqueFileCount] = text
        UniqueFileCount = UniqueFileCount + 1
    }

    public func BuildFileRanks() {
        EnsureInitialized()
        Array.Sort(UniqueFiles, 0, UniqueFileCount, StringComparer.Ordinal)

        i := 0
        while i < UniqueFileCount {
            FileRanksByText[UniqueFiles[i]] = i + 1
            i = i + 1
        }
    }

    public func GetFileRank(text: string): int {
        EnsureInitialized()
        return FileRanksByText[text]
    }

    public func ClearFiles(count: int) {
        EnsureInitialized()
        Array.Clear(Files, 0, count)
    }

    public func ResetFiles() {
        EnsureInitialized()
        FileRanksByText.Clear()
        if UniqueFileCount > 0 {
            Array.Clear(UniqueFiles, 0, UniqueFileCount)
            UniqueFileCount = 0
        }
    }

    func EnsureInitialized() {
        if FileRanksByText != null {
            return
        }

        FileRanksByText = new Dictionary<string, int>(StringComparer.Ordinal)
        Columns = new int[](0)
        FileRanks = new int[](0)
        Files = new string[](0)
        LineNumbers = new int[](0)
        ResultIndices = new int[](0)
        SlotIndices = new int[](0)
        UniqueFiles = new string[](0)
    }
}
