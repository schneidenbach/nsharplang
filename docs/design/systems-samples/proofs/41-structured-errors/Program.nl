namespace SystemsProofs.StructuredErrors

import System

enum ParseKind {
    Short
    BadTag
}

struct ParseError {
    Kind: ParseKind
    Offset: int
}

[hot]
func ReadTaggedByte(bytes: ReadOnlySpan<byte>): Result<byte, ParseError> {
    if bytes.Length < 2 {
        return Err(ParseError { Kind: ParseKind.Short, Offset: bytes.Length })
    }
    if bytes[0] != 42 {
        return Err(ParseError { Kind: ParseKind.BadTag, Offset: 0 })
    }
    return Ok(bytes[1])
}

func Main() {
    result := ReadTaggedByte(new byte[] { 1 })
    match result {
        Ok(value) => print value,
        Err(error) => print error.Kind
    }
}
