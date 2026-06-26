namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

public class DiagnosticShadowSuppressionScratch {
    CodeIdsByText: Dictionary<string, int> = new Dictionary<string, int>(StringComparer.Ordinal)
    FileRanksByText: Dictionary<string, int> = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)

    CodeIds: int[] = new int[](0)
    FileRanks: int[] = new int[](0)
    Files: string[] = new string[](0)
    ResultIndices: int[] = new int[](0)
    ShadowFileFlags: int[] = new int[](0)
    UniqueFiles: string[] = new string[](0)
    UniqueFileCount: int

    public func EnsureCapacity(diagnosticCount: int, shadowedFileCount: int) {
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
        if CodeIdsByText.ContainsKey(text) {
            return CodeIdsByText[text]
        }

        id := CodeIdsByText.Count + 1
        CodeIdsByText.Add(text, id)
        return id
    }

    public func AddFile(text: string) {
        if FileRanksByText.ContainsKey(text) {
            return
        }

        FileRanksByText.Add(text, 0)
        UniqueFiles[UniqueFileCount] = text
        UniqueFileCount = UniqueFileCount + 1
    }

    public func BuildFileRanks() {
        Array.Sort(UniqueFiles, 0, UniqueFileCount, StringComparer.OrdinalIgnoreCase)

        i := 0
        while i < UniqueFileCount {
            FileRanksByText[UniqueFiles[i]] = i + 1
            i = i + 1
        }
    }

    public func GetFileRank(text: string): int {
        if FileRanksByText.ContainsKey(text) {
            return FileRanksByText[text]
        }

        return -1
    }

    public func ClearFiles(count: int) {
        if count > 0 {
            Array.Clear(Files, 0, count)
        }
    }

    public func ClearShadowFileFlags() {
        if ShadowFileFlags.Length > 0 {
            Array.Clear(ShadowFileFlags, 0, ShadowFileFlags.Length)
        }
    }

    public func Reset() {
        CodeIdsByText.Clear()
        FileRanksByText.Clear()
        if UniqueFileCount > 0 {
            Array.Clear(UniqueFiles, 0, UniqueFileCount)
            UniqueFileCount = 0
        }
    }
}

public class DiagnosticDeduplicationScratch {
    CodeIdsByText: Dictionary<string, int> = new Dictionary<string, int>(StringComparer.Ordinal)
    FileRanksByText: Dictionary<string, int> = new Dictionary<string, int>(StringComparer.Ordinal)
    MessageIdsByText: Dictionary<string, int> = new Dictionary<string, int>(StringComparer.Ordinal)

    CodeIds: int[] = new int[](0)
    Columns: int[] = new int[](0)
    FileRanks: int[] = new int[](0)
    Files: string[] = new string[](0)
    LineNumbers: int[] = new int[](0)
    MessageIds: int[] = new int[](0)
    ResultIndices: int[] = new int[](0)
    SlotIndices: int[] = new int[](0)
    UniqueFiles: string[] = new string[](0)
    UniqueFileCount: int

    public func EnsureCapacity(count: int) {
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
        return GetId(CodeIdsByText, text)
    }

    public func GetFileId(text: string): int {
        return GetId(FileRanksByText, text)
    }

    public func GetMessageId(text: string): int {
        return GetId(MessageIdsByText, text)
    }

    public func AddFile(text: string) {
        if FileRanksByText.ContainsKey(text) {
            return
        }

        FileRanksByText.Add(text, 0)
        UniqueFiles[UniqueFileCount] = text
        UniqueFileCount = UniqueFileCount + 1
    }

    public func BuildFileRanks() {
        Array.Sort(UniqueFiles, 0, UniqueFileCount, StringComparer.Ordinal)

        i := 0
        while i < UniqueFileCount {
            FileRanksByText[UniqueFiles[i]] = i + 1
            i = i + 1
        }
    }

    public func GetFileRank(text: string): int {
        return FileRanksByText[text]
    }

    public func ClearFiles(count: int) {
        Array.Clear(Files, 0, count)
    }

    public func ResetIds() {
        CodeIdsByText.Clear()
        FileRanksByText.Clear()
        MessageIdsByText.Clear()
        if UniqueFileCount > 0 {
            Array.Clear(UniqueFiles, 0, UniqueFileCount)
            UniqueFileCount = 0
        }
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
    FileRanksByText: Dictionary<string, int> = new Dictionary<string, int>(StringComparer.Ordinal)

    Columns: int[] = new int[](0)
    FileRanks: int[] = new int[](0)
    Files: string[] = new string[](0)
    LineNumbers: int[] = new int[](0)
    ResultIndices: int[] = new int[](0)
    SlotIndices: int[] = new int[](0)
    UniqueFiles: string[] = new string[](0)
    UniqueFileCount: int

    public func EnsureCapacity(count: int) {
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
        if FileRanksByText.ContainsKey(text) {
            return
        }

        FileRanksByText.Add(text, 0)
        UniqueFiles[UniqueFileCount] = text
        UniqueFileCount = UniqueFileCount + 1
    }

    public func BuildFileRanks() {
        Array.Sort(UniqueFiles, 0, UniqueFileCount, StringComparer.Ordinal)

        i := 0
        while i < UniqueFileCount {
            FileRanksByText[UniqueFiles[i]] = i + 1
            i = i + 1
        }
    }

    public func GetFileRank(text: string): int {
        return FileRanksByText[text]
    }

    public func ClearFiles(count: int) {
        Array.Clear(Files, 0, count)
    }

    public func ResetFiles() {
        FileRanksByText.Clear()
        if UniqueFileCount > 0 {
            Array.Clear(UniqueFiles, 0, UniqueFileCount)
            UniqueFileCount = 0
        }
    }
}
