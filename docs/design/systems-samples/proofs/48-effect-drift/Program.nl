namespace SystemsProofs.EffectDrift

import System

[hot]
func ParseDigits(bytes: ReadOnlySpan<byte>): Result<int, string> {
    value := 0
    for i := 0; i < bytes.Length; i++ {
        b := bytes[i]
        if b < 48 || b > 57 {
            return Err("not a digit")
        }
        value = value * 10 + (b - 48)
    }
    return Ok(value)
}

func FormatForDebug(): int[] {
    return alloc new int[1]
}

[boundary]
func Main() {
    bytes := alloc new byte[3]
    bytes[0] = (byte)49
    bytes[1] = (byte)50
    bytes[2] = (byte)51
    _ = ParseDigits(bytes)
    _ = FormatForDebug()
}

// Drift proof:
// If ParseDigits starts calling FormatForDebug, the hot caller must report that
// it gained allocation through FormatForDebug. External package/body identity
// drift is covered separately by sidecar HotSummary NSYS150 tests.
