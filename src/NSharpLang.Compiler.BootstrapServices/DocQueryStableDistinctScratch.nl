namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

public class StableDistinctStringScratch {
    RanksByValue: Dictionary<string, int>
    Ranks: int[]
    ResultIndices: int[]
    SeenRanks: int[]
    UniqueRankCount: int

    public func EnsureCapacity(count: int) {
        EnsureInitialized()
        if Ranks.Length != count {
            Ranks = new int[](count)
            ResultIndices = new int[](count)
        }
    }

    public func EnsureRankCapacity(uniqueRankCount: int) {
        EnsureInitialized()
        rankCapacity := uniqueRankCount + 1
        if SeenRanks.Length != rankCapacity {
            SeenRanks = new int[](rankCapacity)
        }
    }

    public func Reset() {
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

public class StableDistinctTypeScratch {
    RanksByValue: Dictionary<Type, int>
    Ranks: int[]
    ResultIndices: int[]
    SeenRanks: int[]
    UniqueRankCount: int

    public func EnsureCapacity(count: int) {
        EnsureInitialized()
        if Ranks.Length != count {
            Ranks = new int[](count)
            ResultIndices = new int[](count)
        }
    }

    public func EnsureRankCapacity(uniqueRankCount: int) {
        EnsureInitialized()
        rankCapacity := uniqueRankCount + 1
        if SeenRanks.Length != rankCapacity {
            SeenRanks = new int[](rankCapacity)
        }
    }

    public func Reset() {
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
