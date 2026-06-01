import System

ref struct FrameReader {
    buf: ReadOnlySpan<byte>
    pos: int
}

struct BadReader {
    buf: ReadOnlySpan<byte>
}
