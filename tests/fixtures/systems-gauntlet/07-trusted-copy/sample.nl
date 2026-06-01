[memory(safe)]
[trusted(reason: "len is checked before native copy", owner: "runtime-core", review: "SYS-7")]
func Copy(): int {
    unsafe {
        marker := 1
    }
    return 1
}

func BadCopy(): int {
    unsafe {
        marker := 2
    }
    return 2
}
