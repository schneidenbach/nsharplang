import System

struct Arena {
    backing: byte[]
    offset: int
}

enum ArenaError {
    Full
}

[hot]
func Allocate(self: &Arena scoped 'self, n: int): Result<Span<byte>, ArenaError> returns heap(self) {
    if n == 0 {
        return Err(ArenaError.Full)
    }

    return Ok(self.backing.AsSpan(0, n))
}
