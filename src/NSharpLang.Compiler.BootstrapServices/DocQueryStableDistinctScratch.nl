namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

class StableDistinctStringScratch {
    RanksByValue: Dictionary<string, int>
    Ranks: int[]
    ResultIndices: int[]
    SeenRanks: int[]
    UniqueRankCount: int

    func EnsureCapacity(count: int) {
        EnsureInitialized()
        if Ranks.Length != count {
            Ranks = new int[](count)
            ResultIndices = new int[](count)
        }
    }

    func EnsureRankCapacity(uniqueRankCount: int) {
        EnsureInitialized()
        rankCapacity := uniqueRankCount + 1
        if SeenRanks.Length != rankCapacity {
            SeenRanks = new int[](rankCapacity)
        }
    }

    func Reset() {
        EnsureInitialized()
        RanksByValue.Clear()
        UniqueRankCount = 0
    }

    func EnsureInitialized() {
        if RanksByValue != null {
            return
        }

        RanksByValue = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        Ranks = new int[](0)
        ResultIndices = new int[](0)
        SeenRanks = new int[](0)
    }
}

class StableDistinctTypeScratch {
    RanksByValue: Dictionary<Type, int>
    Ranks: int[]
    ResultIndices: int[]
    SeenRanks: int[]
    UniqueRankCount: int

    func EnsureCapacity(count: int) {
        EnsureInitialized()
        if Ranks.Length != count {
            Ranks = new int[](count)
            ResultIndices = new int[](count)
        }
    }

    func EnsureRankCapacity(uniqueRankCount: int) {
        EnsureInitialized()
        rankCapacity := uniqueRankCount + 1
        if SeenRanks.Length != rankCapacity {
            SeenRanks = new int[](rankCapacity)
        }
    }

    func Reset() {
        EnsureInitialized()
        RanksByValue.Clear()
        UniqueRankCount = 0
    }

    func EnsureInitialized() {
        if RanksByValue != null {
            return
        }

        RanksByValue = new Dictionary<Type, int>()
        Ranks = new int[](0)
        ResultIndices = new int[](0)
        SeenRanks = new int[](0)
    }
}
