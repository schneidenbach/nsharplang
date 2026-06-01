namespace SystemsProofs.DictionarySetupHotRead

import System
import System.Collections.Generic

static class Catalog {
    static Codes: Dictionary<int, int> = BuildCatalog()
}

[boundary]
func BuildCatalog(): Dictionary<int, int> {
    map := alloc new Dictionary<int, int>(capacity: 128)
    map[1] = 100
    map[2] = 200
    map[3] = 300
    return map
}

[hot]
func Lookup(code: int): Result<int, string> {
    value := 0
    if Catalog.Codes.TryGetValue(code, out value) {
        return Ok(value)
    }
    return Err("unknown")
}

func Main() {
    _ = BuildCatalog()
    print Lookup(2)
}
