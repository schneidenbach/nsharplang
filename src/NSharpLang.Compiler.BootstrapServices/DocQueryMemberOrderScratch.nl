namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

public class DocQueryMemberOrderScratch {
    NameRanksByValue: Dictionary<string, int> = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)

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

    public func EnsureCapacity(memberCount: int) {
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

    public func AddName(name: string) {
        if NameRanksByValue.ContainsKey(name) {
            return
        }

        NameRanksByValue.Add(name, 0)
        UniqueNames[UniqueNameCount] = name
        UniqueNameCount = UniqueNameCount + 1
    }

    public func BuildSortedNameRanks() {
        Array.Sort(UniqueNames, 0, UniqueNameCount, StringComparer.OrdinalIgnoreCase)

        i := 0
        while i < UniqueNameCount {
            NameRanksByValue[UniqueNames[i]] = i + 1
            i = i + 1
        }
    }

    public func GetNameRank(name: string): int {
        return NameRanksByValue[name]
    }

    public func ResetNames() {
        NameRanksByValue.Clear()
        if UniqueNameCount > 0 {
            Array.Clear(UniqueNames, 0, UniqueNameCount)
            UniqueNameCount = 0
        }
    }
}
