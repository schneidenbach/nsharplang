import System

// A simple hello-world program demonstrating functions and string interpolation

func hi(): int {
    print "hi there!"
    return 42
}

// Greet someone by name
// Returns the greeting string

func Main() {
    name := "Spencer"
    greeting := $"Hello, {name}!"
    print greeting

    // Call hi() and capture the result
    i := hi()
    print $"hi returned {i}"
}
