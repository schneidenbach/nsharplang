namespace SystemsProofs.CachePrewarm

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
    index := value
    if index < Tables.Lookup.Length {
        return Tables.Lookup[index]
    }
    return -1
}

func Main() {
    Warmup()
    print LookupByte((byte)7)
}
