// Test file for N# Language Server features
// Open this file in VS Code to test LSP functionality

func Main() {
    // Test 1: Type inference - hover over 'name' to see type
    name := "Claude"

    // Test 2: Error detection - this should show a red squiggle
    // Uncomment to test:
    // x := "hello" + 5

    // Test 3: Auto-completion - type 'func' and press Ctrl+Space

    // Test 4: Hover - hover over 'greet' to see its type
    greet := $"Hello, {name}!"

    print greet
}

// Test 5: Declaration - hover over 'Person' to see it's a class
class Person {
    Name: string
    Age: int

    func Greet(): string => $"Hi, I'm {Name}"
}
