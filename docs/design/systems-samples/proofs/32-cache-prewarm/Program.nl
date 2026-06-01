namespace SystemsProofs.CachePrewarm

import System

static class Tables {
    static Lookup: int[] = Build()

    static func Build(): int[] {
        values := alloc new int[256]
        for i := 0; i < values.Length; i++ {
            values[i] = i * 31
        }
        return values
    }
}

[boundary]
func Warmup() {
    _ = Tables.Lookup[0]
    _ = Tables.Lookup[255]
}

[hot]
func LookupByte(value: byte): int {
    return Tables.Lookup[value]
}

func Main() {
    Warmup()
    print LookupByte(7)
}
