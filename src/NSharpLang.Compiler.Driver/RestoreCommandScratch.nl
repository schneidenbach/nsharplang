namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic

class ReferenceTypeFilterScratch {
    TypeRanks: int[]
    ResultIndices: int[]

    func EnsureCapacity(referenceCount: int) {
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

class StableDistinctScratch {
    RanksByReference: Dictionary<string, int>
    Ranks: int[]
    ResultIndices: int[]
    SeenRanks: int[]

    func EnsureCapacity(count: int) {
        EnsureInitialized()
        if Ranks.Length != count {
            Ranks = new int[](count)
        }

        if ResultIndices.Length != count {
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
