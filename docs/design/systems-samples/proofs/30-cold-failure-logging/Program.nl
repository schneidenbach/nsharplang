namespace SystemsProofs.ColdFailureLogging

import System

enum ParseError {
    Short,
    BadMagic
}

[hot]
func ParseMagic(buf: ReadOnlySpan<byte>): Result<int, ParseError> {
    if buf.Length < 2 {
        return Err(ParseError.Short)
    }

    if buf[0] != 78 || buf[1] != 35 {
        return Err(ParseError.BadMagic)
    }

    return Ok(2)
}

[boundary]
func LogColdFailure() {
    allow(alloc, reason: "cold diagnostic path after parse failure") {
        print alloc $"parse failed"
    }
}

[boundary]
func ParseWithColdLogging(buf: ReadOnlySpan<byte>, logEnabled: bool): Result<int, ParseError> {
    result := ParseMagic(buf)
    if result.IsErr {
        if logEnabled {
            LogColdFailure()
        }
    }
    return result
}

func Main(): int {
    okInput := alloc new byte[2]
    okInput[0] = (byte)78
    okInput[1] = (byte)35
    ok := ParseWithColdLogging(okInput, true)
    if ok.IsOk == false {
        return 1
    }

    shortInput := alloc new byte[1]
    failed := ParseWithColdLogging(shortInput, true)
    if failed.IsErr == false {
        return 2
    }
    if failed.ErrValueUnchecked != ParseError.Short {
        return 3
    }
    return 0
}
