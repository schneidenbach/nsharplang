namespace SimpleTest

// Basic string interpolation
func TestBasicInterpolation() {
    name := "World"
    print $"Hello, {name}!"

    x := 42
    print $"The answer is {x}"

    flag := true
    print $"Flag is {flag}"
}

// Expressions in interpolation
func TestExpressionInterpolation() {
    a := 10
    b := 20
    print $"Sum: {a + b}"
    print $"Product: {a * b}"
    print $"Comparison: {a > b}"
}

// Nested member access in interpolation
func TestMemberAccessInterpolation() {
    name := "hello"
    print $"Length: {name.Length}"
    print $"Upper: {name.ToUpper()}"
    print $"Contains 'ell': {name.Contains("ell")}"
}

// Multi-part interpolation
func TestMultiPartInterpolation() {
    first := "John"
    last := "Doe"
    age := 30
    print $"Name: {first} {last}, Age: {age}"
    print $"{first} {last} is {age} years old and has a name length of {first.Length + last.Length}"
}

// Empty and edge case interpolation
func TestEdgeCaseInterpolation() {
    empty := ""
    print $"Empty: '{empty}'"
    print $"Literal braces in text"
    print $"Number: {0}"
    print $"Bool: {true}"
    print $"Negative: {-1}"
}
