// Target-Typed New Expressions (C# 9 Feature)
// Demonstrates the `new()` syntax that infers type from context

// 1. Simple class for demonstration
class Person {
    Name: string
    Age: int

    constructor(name: string, age: int) {
        Name = name
        Age = age
    }

    func Greet(): string {
        return $"Hello, I'm {Name} and I'm {Age} years old"
    }
}

// 2. Generic class to show type inference with generics
class Box<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    func GetValue(): T {
        return Value
    }
}

// 3. Record for immutable data
record Point {
    X: double
    Y: double
}

func CreateDefaultPerson(): Person {
    // Return type clearly indicates this is Person
    return new("Default User", 0)
}

func Main() {
    print "=== Target-Typed New Expressions Demo ==="
    print ""

    // Example 1: Target-typed new with explicit type
    print "1. Target-typed new with constructor arguments:"
    let person: Person = new("Alice", 30)
    print person.Greet()
    print ""

    // Example 2: Target-typed new without arguments
    print "2. Target-typed new with object initializer:"
    let point: Point = new { X: 3.0, Y: 4.0 }
    print $"Point: ({point.X}, {point.Y})"
    print ""

    // Example 3: Target-typed new with generics
    print "3. Target-typed new with generic types:"
    let intBox: Box<int> = new(42)
    let stringBox: Box<string> = new("Hello")
    print $"Int box contains: {intBox.GetValue()}"
    print $"String box contains: {stringBox.GetValue()}"
    print ""

    // Example 4: Multiple instances with explicit type
    print "4. Multiple instances:"
    let bob: Person = new("Bob", 25)
    let charlie: Person = new("Charlie", 35)
    let diana: Person = new("Diana", 28)

    print bob.Greet()
    print charlie.Greet()
    print diana.Greet()
    print ""

    // Example 5: Return target-typed new from function
    print "5. Returning target-typed new from function:"
    defaultPerson := CreateDefaultPerson()
    print defaultPerson.Greet()
    print ""

    print "=== Benefits of Target-Typed New ==="
    print "1. Less verbose code - no need to repeat the type name"
    print "2. Cleaner when the type is obvious from context"
    print "3. Works seamlessly with generics"
    print "4. Reduces redundancy in variable declarations"
    print "5. Modern C# 9+ feature for concise syntax"
}
