namespace SimpleTest


// Typed variable declarations WITH initialization (supported)
func TestTypedDeclarationsWithInit() {
    x: int = 42
    name: string = "hello"
    flag: bool = true
    ratio: double = 3.14

    print $"x={x}, name={name}, flag={flag}, ratio={ratio}"
}

// Mixed declarations: inferred and explicit types in same function
func TestMixedDeclarations() {
    inferred := 42
    typed: int = 42
    inferredStr := "hello"
    explicitStr: string = "hello"

    print $"{inferred}, {typed}, {inferredStr}, {explicitStr}"
}

// Multiple typed declarations with init in sequence
func TestSequentialTypedDeclarations() {
    a: int = 1
    b: int = 2
    c: int = 3
    d: string = "hello"
    e: string = "world"

    print $"a={a}, b={b}, c={c}, d={d}, e={e}"
}

// Type inference with various types
func TestTypeInference() {
    x := 42
    name := "hello"
    flag := true
    ratio := 3.14

    print $"x={x}, name={name}, flag={flag}, ratio={ratio}"
}
