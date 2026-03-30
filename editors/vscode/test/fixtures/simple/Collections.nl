namespace SimpleTest

import System.Collections.Generic

// List operations with type inference
func TestListOperations() {
    numbers := [1, 2, 3, 4, 5]
    print $"Count: {numbers.Count}"

    names := ["Alice", "Bob", "Charlie"]
    print $"Names count: {names.Count}"
    for name in names {
        print $"  - {name}"
    }
}

// Working with collections
func TestCollectionIteration() {
    items := [10, 20, 30, 40, 50]
    total := 0
    for item in items {
        total = total + item
    }
    print $"Total: {total}"
}

// Array-style collection initialization
func TestCollectionInit() {
    numbers := [10, 20, 30, 40, 50]
    strings := ["hello", "world", "foo", "bar"]
    bools := [true, false, true]

    print $"Numbers: {numbers.Count}"
    print $"Strings: {strings.Count}"
    print $"Bools: {bools.Count}"
}

// String operations on collections
func TestStringCollections() {
    words := ["hello", "world"]
    for word in words {
        print $"Word: {word}, Length: {word.Length}, Upper: {word.ToUpper()}"
    }
}
