namespace NSharpLang.CensusEmitShapes.Tests

func ByteDifference(a: byte[], b: byte[]): int {
    diff := 0
    for i := 0; i < a.Length; i++ {
        diff = diff | ((int)a[i] ^ (int)b[i])
    }
    return diff
}
