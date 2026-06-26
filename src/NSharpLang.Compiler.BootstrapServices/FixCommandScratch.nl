namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic

public class SafetyFilterScratch {
    ResultIndices: int[] = new int[](0)
    SafetyRanks: int[] = new int[](0)

    public func EnsureCapacity(fixCount: int) {
        if SafetyRanks.Length != fixCount {
            SafetyRanks = new int[](fixCount)
            ResultIndices = new int[](fixCount)
        }
    }
}

public class AppliedFileGroupingScratch {
    fileRanks: Dictionary<string, int> = new Dictionary<string, int>(StringComparer.Ordinal)

    CountsByRank: int[] = new int[](0)
    FileRanks: int[] = new int[](0)
    FilesByRank: string[] = new string[](0)
    OffsetsByRank: int[] = new int[](0)
    ResultCounts: int[] = new int[](0)
    ResultIndices: int[] = new int[](0)
    ResultRanks: int[] = new int[](0)
    ResultStarts: int[] = new int[](0)
    UniqueFileRankCount: int
    WriteOffsetsByRank: int[] = new int[](0)

    public func EnsureCapacity(appliedCount: int) {
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
        fileRanks.Clear()
        if UniqueFileRankCount > 0 {
            Array.Clear(FilesByRank, 0, UniqueFileRankCount + 1)
            UniqueFileRankCount = 0
        }
    }
}
