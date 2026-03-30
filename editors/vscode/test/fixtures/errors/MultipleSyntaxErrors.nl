namespace ErrorTest

func Broken() {
    // Missing closing paren
    x := add(1, 2

    // Type mismatch
    y: int = "not a number"

    // Undefined function call
    z := doesNotExist(42)
}

func AlsoBroken(a: int, {
    // Bad parameter list
    return a
}
