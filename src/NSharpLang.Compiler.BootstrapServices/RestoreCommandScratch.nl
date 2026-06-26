namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic

public class ReferenceTypeFilterScratch {
    TypeRanks: int[] = new int[](0)
    ResultIndices: int[] = new int[](0)

    public func EnsureCapacity(referenceCount: int) {
        if TypeRanks.Length != referenceCount {
            TypeRanks = new int[](referenceCount)
        }

        if ResultIndices.Length != referenceCount {
            ResultIndices = new int[](referenceCount)
        }
    }
}

public class StableDistinctScratch {
    RanksByReference: Dictionary<string, int> = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
    Ranks: int[] = new int[](0)
    ResultIndices: int[] = new int[](0)
    SeenRanks: int[] = new int[](0)

    public func EnsureCapacity(count: int) {
        if Ranks.Length != count {
            Ranks = new int[](count)
        }

        if ResultIndices.Length != count {
            ResultIndices = new int[](count)
        }
    }

    public func EnsureRankCapacity(uniqueRankCount: int) {
        rankCapacity := uniqueRankCount + 1
        if SeenRanks.Length != rankCapacity {
            SeenRanks = new int[](rankCapacity)
        }
    }
}
