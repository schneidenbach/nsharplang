import System.Threading

struct Ring {
    head: int
    tail: int
}

[hot]
func Publish(value: int): int {
    observed := Volatile.Read(value)
    next := Interlocked.Increment(observed)
    Thread.MemoryBarrier()
    return next
}
