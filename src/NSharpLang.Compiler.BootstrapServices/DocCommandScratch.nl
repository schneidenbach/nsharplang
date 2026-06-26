namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic

public class SymbolOrderScratch {
    nameRanks: Dictionary<string, int> = new Dictionary<string, int>(StringComparer.Ordinal)

    IncludeFlags: int[] = new int[](0)
    KindCounts: int[] = new int[](0)
    KindOffsets: int[] = new int[](0)
    KindRanks: int[] = new int[](0)
    NameCounts: int[] = new int[](0)
    NameOffsets: int[] = new int[](0)
    NameRanks: int[] = new int[](0)
    ResultIndices: int[] = new int[](0)
    TempIndices: int[] = new int[](0)
    UniqueNames: string[] = new string[](0)
    UniqueNameCount: int

    public func EnsureCapacity(symbolCount: int) {
        if KindRanks.Length != symbolCount {
            KindRanks = new int[](symbolCount)
            NameRanks = new int[](symbolCount)
            IncludeFlags = new int[](symbolCount)
            TempIndices = new int[](symbolCount)
            ResultIndices = new int[](symbolCount)
            UniqueNames = new string[](symbolCount)
        }

        nameRankCapacity := symbolCount + 1
        if NameCounts.Length != nameRankCapacity {
            NameCounts = new int[](nameRankCapacity)
            NameOffsets = new int[](nameRankCapacity)
        }

        if KindCounts.Length != 32 {
            KindCounts = new int[](32)
            KindOffsets = new int[](32)
        }
    }

    public func AddName(name: string) {
        if nameRanks.ContainsKey(name) {
            return
        }

        nameRanks.Add(name, 0)
        UniqueNames[UniqueNameCount] = name
        UniqueNameCount = UniqueNameCount + 1
    }

    public func BuildSortedNameRanks() {
        Array.Sort(UniqueNames, 0, UniqueNameCount, StringComparer.Ordinal)
        for i := 0; i < UniqueNameCount; i = i + 1 {
            nameRanks[UniqueNames[i]] = i + 1
        }
    }

    public func GetNameRank(name: string): int {
        return nameRanks[name]
    }

    public func ResetNames() {
        nameRanks.Clear()
        if UniqueNameCount > 0 {
            Array.Clear(UniqueNames, 0, UniqueNameCount)
            UniqueNameCount = 0
        }
    }
}
