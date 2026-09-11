namespace SystemsTemplate

import System
import System.Buffers.Binary

enum ParseError {
    Short
}

[hot]
func ParseLength(buf: ReadOnlySpan<byte>): Result<uint, ParseError> {
    if buf.Length < 4 {
        return Err(ParseError.Short)
    }

    return Ok(BinaryPrimitives.ReadUInt32LittleEndian(buf.Slice(0, 4)))
}

[boundary]
func Run(): Result<int, ParseError> {
    allow(alloc, reason: "CLI startup allocates outside the hot parser") {
        print "Systems N# template"
    }

    return Ok(0)
}

func Warmup(): void {
}

func main(): void {
    _ := Run()
}
