struct StructCopyFieldTable {
    ReadonlyFlags: int[]
}

func StructCopyAllInstanceFieldsInitOnly(fieldReadonlyFlags: int[], count: int): int {
    fields := new StructCopyFieldTable { ReadonlyFlags: fieldReadonlyFlags }
    return StructCopyAllInstanceFieldsInitOnlyCore(ref fields, count)
}

func StructCopyAllInstanceFieldsInitOnlyCore(fields: &StructCopyFieldTable, count: int): int {
    if count < 0 || count > fields.ReadonlyFlags.Length {
        return -1
    }

    i := 0
    limit := count - 3
    while i < limit {
        if fields.ReadonlyFlags[i]
            + fields.ReadonlyFlags[i + 1]
            + fields.ReadonlyFlags[i + 2]
            + fields.ReadonlyFlags[i + 3] != 4 {
            return 0
        }

        i = i + 4
    }

    while i < count {
        if fields.ReadonlyFlags[i] != 1 {
            return 0
        }

        i = i + 1
    }

    return 1
}
