namespace SystemsProofs.StructuredErrors

import System

enum ParseKind {
    Short,
    BadTag
}

struct ParseError {
    Kind: ParseKind
    Offset: int
}

[hot]
func ReadTaggedByte(bytes: ReadOnlySpan<byte>): Result<byte, ParseError> {
    if bytes.Length < 2 {
        return Err(new ParseError { Kind: ParseKind.Short, Offset: bytes.Length })
    }
    if bytes[0] != 42 {
        return Err(new ParseError { Kind: ParseKind.BadTag, Offset: 0 })
    }
    return Ok(bytes[1])
}

func Main(): int {
    shortInput := alloc new byte[1]
    shortResult := ReadTaggedByte(shortInput)
    if shortResult.IsErr == false {
        return 1
    }

    shortError := shortResult.ErrValueUnchecked
    if shortError.Kind != ParseKind.Short || shortError.Offset != 1 {
        return 2
    }

    badTagInput := alloc new byte[2]
    badTagInput[0] = (byte)1
    badTagInput[1] = (byte)7
    badTagResult := ReadTaggedByte(badTagInput)
    if badTagResult.IsErr == false {
        return 3
    }

    badTagError := badTagResult.ErrValueUnchecked
    if badTagError.Kind != ParseKind.BadTag || badTagError.Offset != 0 {
        return 4
    }

    okInput := alloc new byte[2]
    okInput[0] = (byte)42
    okInput[1] = (byte)99
    okResult := ReadTaggedByte(okInput)
    if okResult.IsOk == false {
        return 5
    }

    if okResult.OkValueUnchecked != (byte)99 {
        return 6
    }

    return 0
}
