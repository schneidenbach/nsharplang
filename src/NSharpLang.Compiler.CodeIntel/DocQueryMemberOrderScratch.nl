namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

class DocQueryMemberOrderScratch {
    NameRanksByValue: Dictionary<string, int>

    KindCounts: int[]
    KindOffsets: int[]
    KindRanks: int[]
    NameCounts: int[]
    NameOffsets: int[]
    NameRanks: int[]
    ResultIndices: int[]
    TempIndices: int[]
    UniqueNames: string[]
    UniqueNameCount: int

    func EnsureCapacity(memberCount: int) {
        EnsureInitialized()
        if KindRanks.Length != memberCount {
            KindRanks = new int[](memberCount)
            NameRanks = new int[](memberCount)
            TempIndices = new int[](memberCount)
            ResultIndices = new int[](memberCount)
            UniqueNames = new string[](memberCount)
        }

        nameRankCapacity := memberCount + 1
        if NameCounts.Length != nameRankCapacity {
            NameCounts = new int[](nameRankCapacity)
            NameOffsets = new int[](nameRankCapacity)
        }

        if KindCounts.Length != 16 {
            KindCounts = new int[](16)
            KindOffsets = new int[](16)
        }
    }

    func AddName(name: string) {
        EnsureInitialized()
        if NameRanksByValue.ContainsKey(name) {
            return
        }

        NameRanksByValue.Add(name, 0)
        UniqueNames[UniqueNameCount] = name
        UniqueNameCount = UniqueNameCount + 1
    }

    func BuildSortedNameRanks() {
        EnsureInitialized()
        Array.Sort(UniqueNames, 0, UniqueNameCount, StringComparer.OrdinalIgnoreCase)

        i := 0
        while i < UniqueNameCount {
            NameRanksByValue[UniqueNames[i]] = i + 1
            i = i + 1
        }
    }

    func GetNameRank(name: string): int {
        EnsureInitialized()
        return NameRanksByValue[name]
    }

    func ResetNames() {
        EnsureInitialized()
        NameRanksByValue.Clear()
        if UniqueNameCount > 0 {
            Array.Clear(UniqueNames, 0, UniqueNameCount)
            UniqueNameCount = 0
        }
    }

    func EnsureInitialized() {
        if NameRanksByValue != null {
            return
        }

        NameRanksByValue = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        KindCounts = new int[](0)
        KindOffsets = new int[](0)
        KindRanks = new int[](0)
        NameCounts = new int[](0)
        NameOffsets = new int[](0)
        NameRanks = new int[](0)
        ResultIndices = new int[](0)
        TempIndices = new int[](0)
        UniqueNames = new string[](0)
    }
}
