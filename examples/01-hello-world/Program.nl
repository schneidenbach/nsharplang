import System

// A simple hello-world program demonstrating functions and string interpolation

func Hi(): int {
    print "hi there!"
    return 42
}

// Greet someone by name
// Returns the greeting string

func Main() {
    name := "Spencer"
    greeting := $"Hello, {name}!"
    print greeting

    // Call Hi() and capture the result
    i := Hi()
    print $"hi returned {i}"
}
