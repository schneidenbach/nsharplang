// THE OPT-OUT PROBE.
//
// A minimal executable whose `Main` runs ONE counted integer reduction — the exact shape
// `ColumnarIlEmitter.TryMatchForReduction` accepts — and prints its checksum. It exists so a test can build
// it three times under three different `NSHARP_VECTORIZE_REDUCTIONS` settings and compare both the emitted
// metadata and the printed answer.
//
// `tests/native/systems-vectorization-facts/OptOutFacts.tests.nl` owns the contract and explains the finding:
// the documented opt-out is dead, so all three builds must be identical.
//
// The checksum is the wrapping sum of `k * 3 - 7` over 1000 elements, which is 1491500.
func Main(_args: string[]) {
    data := new int[1000]
    for k := 0; k < data.Length; k++ {
        data[k] = k * 3 - 7
    }

    checksum := 0
    for i := 0; i < data.Length; i++ {
        checksum = checksum + data[i]
    }

    print checksum
}
