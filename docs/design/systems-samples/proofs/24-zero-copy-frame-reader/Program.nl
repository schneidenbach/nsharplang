namespace SystemsProofs.ZeroCopyFrameReader

import System
import System.Buffers.Binary

enum FrameError {
    Eof,
    Truncated
}

ref struct FrameReader {
    buf: ReadOnlySpan<byte>
    pos: int

    constructor(input: ReadOnlySpan<byte>) {
        buf = input
        pos = 0
    }
}

[hot]
func NextFrame<'a>(reader: &FrameReader scoped 'a): Result<ReadOnlySpan<byte>, FrameError> returns 'a {
    if reader.pos + 4 > reader.buf.Length {
        return Err(FrameError.Eof)
    }

    len := BinaryPrimitives.ReadInt32LittleEndian(reader.buf.Slice(reader.pos, 4))
    reader.pos = reader.pos + 4

    if len < 0 || reader.pos + len > reader.buf.Length {
        return Err(FrameError.Truncated)
    }

    frame := reader.buf.Slice(reader.pos, len)
    reader.pos = reader.pos + len
    return Ok(frame)
}

func Main() {
    input := alloc new byte[7]
    input[0] = (byte)3
    input[1] = (byte)0
    input[2] = (byte)0
    input[3] = (byte)0
    input[4] = (byte)65
    input[5] = (byte)66
    input[6] = (byte)67
    reader := new FrameReader(input)
    frame := NextFrame(ref reader)
    print frame
}
