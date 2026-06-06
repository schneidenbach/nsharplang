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

func StructCopyAllInstanceFieldsInitOnlyChecksum(fieldReadonlyFlags: int[], count: int): int {
    if count < 0 || count > fieldReadonlyFlags.Length {
        return -1
    }

    allInitOnly := 1
    checksum := 0
    i := 0
    while i < count {
        if fieldReadonlyFlags[i] == 0 {
            allInitOnly = 0
        }

        checksum = checksum + (i + 1) * 31 + fieldReadonlyFlags[i] * 17
        i = i + 1
    }

    return checksum + count + allInitOnly * 13
}
