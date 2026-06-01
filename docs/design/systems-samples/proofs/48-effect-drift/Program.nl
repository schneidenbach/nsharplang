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

func FormatForDebug(value: int): string {
    return alloc $"value={value}"
}

func Main() {
    _ = ParseDigits(new byte[] { 49, 50, 51 })
    print FormatForDebug(123)
}

// Drift proof:
// If ParseDigits starts calling FormatForDebug, NSYS150 must report that
// ParseDigits gained allocation through FormatForDebug.
