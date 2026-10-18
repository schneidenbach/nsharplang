namespace NSharpLang.CensusEmitShapes.Tests

import System

func CountGuidLoop(): int {
    count := 0
    for id in [Guid.NewGuid(), Guid.Empty] {
        // Keep the assertion deterministic while reading the external struct loop variable.
        if id == id {
            count += 1
        }
    }
    return count
}
