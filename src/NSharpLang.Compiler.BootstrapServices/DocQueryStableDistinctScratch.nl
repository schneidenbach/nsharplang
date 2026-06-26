namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

public class StableDistinctStringScratch {
    RanksByValue: Dictionary<string, int> = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
    Ranks: int[] = new int[](0)
    ResultIndices: int[] = new int[](0)
    SeenRanks: int[] = new int[](0)
    UniqueRankCount: int

    public func EnsureCapacity(count: int) {
        if Ranks.Length != count {
            Ranks = new int[](count)
            ResultIndices = new int[](count)
        }
    }

    public func EnsureRankCapacity(uniqueRankCount: int) {
        rankCapacity := uniqueRankCount + 1
        if SeenRanks.Length != rankCapacity {
            SeenRanks = new int[](rankCapacity)
        }
    }

    public func Reset() {
        RanksByValue.Clear()
        UniqueRankCount = 0
    }
}

public class StableDistinctTypeScratch {
    RanksByValue: Dictionary<Type, int> = new Dictionary<Type, int>()
    Ranks: int[] = new int[](0)
    ResultIndices: int[] = new int[](0)
    SeenRanks: int[] = new int[](0)
    UniqueRankCount: int

    public func EnsureCapacity(count: int) {
        if Ranks.Length != count {
            Ranks = new int[](count)
            ResultIndices = new int[](count)
        }
    }

    public func EnsureRankCapacity(uniqueRankCount: int) {
        rankCapacity := uniqueRankCount + 1
        if SeenRanks.Length != rankCapacity {
            SeenRanks = new int[](rankCapacity)
        }
    }

    public func Reset() {
        RanksByValue.Clear()
        UniqueRankCount = 0
    }
}
