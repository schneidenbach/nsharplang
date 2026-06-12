func StructCopyAllInstanceFieldsInitOnly(fieldReadonlyFlags: int[], count: int): int {
    if count < 0 || count > fieldReadonlyFlags.Length {
        return -1
    }

    i := 0
    limit := count - 3
    while i < limit {
        if fieldReadonlyFlags[i]
            + fieldReadonlyFlags[i + 1]
            + fieldReadonlyFlags[i + 2]
            + fieldReadonlyFlags[i + 3] != 4 {
            return 0
        }

        i = i + 4
    }

    while i < count {
        if fieldReadonlyFlags[i] != 1 {
            return 0
        }

        i = i + 1
    }

    return 1
}
