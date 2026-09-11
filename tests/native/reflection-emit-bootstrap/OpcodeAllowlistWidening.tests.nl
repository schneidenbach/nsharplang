namespace NSharpLang.ReflectionEmitBootstrap.Tests

// Each new allowlist row is proved TWICE: that the compiler accepts the spelling at all (this file
// would not compile otherwise — the same spellings decline with NL103 on the pre-widening compiler),
// and that the instruction it emits is the right one, by running the body and reading its answer.
test "the four short-form argument loads each emit and execute on their own ordinal" {
    assert OpcodeAllowlistWideningProbe.LoadArgumentByShortForm(0, 10, 20, 30, 40) == 10
    assert OpcodeAllowlistWideningProbe.LoadArgumentByShortForm(1, 10, 20, 30, 40) == 20
    assert OpcodeAllowlistWideningProbe.LoadArgumentByShortForm(2, 10, 20, 30, 40) == 30
    assert OpcodeAllowlistWideningProbe.LoadArgumentByShortForm(3, 10, 20, 30, 40) == 40
}

test "the four short-form argument loads compose in one body" {
    // Weighted so that a repeated or omitted ordinal cannot land on the same total.
    assert OpcodeAllowlistWideningProbe.SumViaShortFormArgumentLoads(1000, 200, 30, 4) == 1234
    assert OpcodeAllowlistWideningProbe.SumViaShortFormArgumentLoads(0, 0, 0, 0) == 0
    assert OpcodeAllowlistWideningProbe.SumViaShortFormArgumentLoads(-1, 1, -2, 2) == 0
}

test "unbox.any emits and executes over both a value type and a reference type" {
    assert OpcodeAllowlistWideningProbe.UnboxAnyToInt32(42) == 42
    assert OpcodeAllowlistWideningProbe.UnboxAnyToInt32(-7) == -7
    assert OpcodeAllowlistWideningProbe.UnboxAnyToText("record-clone") == "record-clone"
}
