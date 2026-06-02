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

ref struct FrameResult {
    ok: bool
    frame: ReadOnlySpan<byte>
    error: FrameError
}

[hot]
func NextFrame<'a>(reader: &FrameReader scoped 'a): FrameResult returns 'a {
    if reader.pos + 4 > reader.buf.Length {
        return new FrameResult { ok: false, frame: reader.buf.Slice(reader.pos, 0), error: FrameError.Eof }
    }

    len := BinaryPrimitives.ReadInt32LittleEndian(reader.buf.Slice(reader.pos, 4))
    reader.pos = reader.pos + 4

    if len < 0 || reader.pos + len > reader.buf.Length {
        return new FrameResult { ok: false, frame: reader.buf.Slice(reader.pos, 0), error: FrameError.Truncated }
    }

    frame := reader.buf.Slice(reader.pos, len)
    reader.pos = reader.pos + len
    return new FrameResult { ok: true, frame: frame, error: FrameError.Eof }
}

func Main(): int {
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
    if frame.ok == false {
        return 1
    }

    if frame.frame.Length != 3 {
        return 2
    }

    if frame.frame[0] != (byte)65 || frame.frame[1] != (byte)66 || frame.frame[2] != (byte)67 {
        return 3
    }

    if reader.pos != 7 {
        return 4
    }

    return 0
}
