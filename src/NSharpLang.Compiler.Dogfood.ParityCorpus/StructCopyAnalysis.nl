// PARITY CORPUS (Arc M1): checksum fixtures extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/StructCopyAnalysis.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

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
