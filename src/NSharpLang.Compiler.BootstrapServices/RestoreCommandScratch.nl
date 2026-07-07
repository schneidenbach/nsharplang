namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic

public class ReferenceTypeFilterScratch {
    TypeRanks: int[]
    ResultIndices: int[]

    public func EnsureCapacity(referenceCount: int) {
        EnsureInitialized()
        if TypeRanks.Length != referenceCount {
            TypeRanks = new int[](referenceCount)
        }

        if ResultIndices.Length != referenceCount {
            ResultIndices = new int[](referenceCount)
        }
    }

    func EnsureInitialized() {
        if TypeRanks != null {
            return
        }

        TypeRanks = new int[](0)
        ResultIndices = new int[](0)
    }
}

public class StableDistinctScratch {
    RanksByReference: Dictionary<string, int>
    Ranks: int[]
    ResultIndices: int[]
    SeenRanks: int[]

    public func EnsureCapacity(count: int) {
        EnsureInitialized()
        if Ranks.Length != count {
            Ranks = new int[](count)
        }

        if ResultIndices.Length != count {
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

    func EnsureInitialized() {
        if RanksByReference != null {
            return
        }

        RanksByReference = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        Ranks = new int[](0)
        ResultIndices = new int[](0)
        SeenRanks = new int[](0)
    }
}
