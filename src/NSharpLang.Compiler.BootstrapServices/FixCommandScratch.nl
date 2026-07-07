namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic

public class SafetyFilterScratch {
    ResultIndices: int[]
    SafetyRanks: int[]

    public func EnsureCapacity(fixCount: int) {
        EnsureInitialized()
        if SafetyRanks.Length != fixCount {
            SafetyRanks = new int[](fixCount)
            ResultIndices = new int[](fixCount)
        }
    }

    func EnsureInitialized() {
        if ResultIndices != null {
            return
        }

        ResultIndices = new int[](0)
        SafetyRanks = new int[](0)
    }
}

public class AppliedFileGroupingScratch {
    fileRanks: Dictionary<string, int>

    CountsByRank: int[]
    FileRanks: int[]
    FilesByRank: string[]
    OffsetsByRank: int[]
    ResultCounts: int[]
    ResultIndices: int[]
    ResultRanks: int[]
    ResultStarts: int[]
    UniqueFileRankCount: int
    WriteOffsetsByRank: int[]

    public func EnsureCapacity(appliedCount: int) {
        EnsureInitialized()
        if FileRanks.Length != appliedCount {
            FileRanks = new int[](appliedCount)
            ResultCounts = new int[](appliedCount)
            ResultIndices = new int[](appliedCount)
            ResultRanks = new int[](appliedCount)
            ResultStarts = new int[](appliedCount)
        }

        rankCapacity := appliedCount + 1
        if CountsByRank.Length != rankCapacity {
            CountsByRank = new int[](rankCapacity)
            FilesByRank = new string[](rankCapacity)
            OffsetsByRank = new int[](rankCapacity)
            WriteOffsetsByRank = new int[](rankCapacity)
        }
    }

    public func GetOrAddFileRank(filePath: string): int {
        EnsureInitialized()
        rank := 0
        if fileRanks.TryGetValue(filePath, out rank) {
            return rank
        }

        rank = UniqueFileRankCount + 1
        fileRanks.Add(filePath, rank)
        FilesByRank[rank] = filePath
        UniqueFileRankCount = rank
        return rank
    }

    public func Reset() {
        EnsureInitialized()
        fileRanks.Clear()
        if UniqueFileRankCount > 0 {
            Array.Clear(FilesByRank, 0, UniqueFileRankCount + 1)
            UniqueFileRankCount = 0
        }
    }

    func EnsureInitialized() {
        if fileRanks != null {
            return
        }

        fileRanks = new Dictionary<string, int>(StringComparer.Ordinal)
        CountsByRank = new int[](0)
        FileRanks = new int[](0)
        FilesByRank = new string[](0)
        OffsetsByRank = new int[](0)
        ResultCounts = new int[](0)
        ResultIndices = new int[](0)
        ResultRanks = new int[](0)
        ResultStarts = new int[](0)
        WriteOffsetsByRank = new int[](0)
    }
}
