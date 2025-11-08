// Primary Constructors (C# 12 Feature)
// Demonstrates primary constructor syntax for classes, structs, and records

using System

// 1. Class with Primary Constructor - Perfect for Dependency Injection
class Logger(name: string) {
    func Log(message: string) {
        print $"[{name}] {message}"
    }

    func LogError(message: string) {
        print $"[{name}] ERROR: {message}"
    }
}

// 2. Struct with Primary Constructor - Clean Value Types
struct Point(x: double, y: double) {
    func GetDistance(): double {
        return Math.Sqrt(x * x + y * y)
    }

    func GetAngle(): double {
        return Math.Atan2(y, x)
    }

    func ToString(): string {
        return $"Point({x}, {y})"
    }
}

// 3. Record with Primary Constructor - Immutable Data
record Person(name: string, age: int, email: string) {
    // Can add additional members
    FullInfo: string => $"{name} ({age}) - {email}"

    func Greet(): string {
        return $"Hello, I'm {name}!"
    }
}

// 4. Record with Validation
record EmailAddress(value: string) {
    // Simple validation using length only for now
    IsValid: bool => value.Length > 5

    func GetDomain(): string {
        parts := value.Split("@")
        return parts.Length > 1 ? parts[1] : ""
    }
}

// Usage Examples
func Main() {
    print "=== Primary Constructors Demo ==="
    print ""

    // Point struct
    p := new Point(3.0, 4.0)
    print $"Point: {p.ToString()}"
    print $"Distance from origin: {p.GetDistance()}"
    print ""

    // Person record
    person := new Person("Alice", 30, "alice@example.com")
    print person.Greet()
    print $"Full Info: {person.FullInfo}"
    print ""

    // EmailAddress validation
    email := new EmailAddress("user@example.com")
    print $"Email: {email.value}"
    print $"Valid: {email.IsValid}"
    print $"Domain: {email.GetDomain()}"
    print ""

    // Logger class
    logger := new Logger("MyApp")
    logger.Log("Application started")
    logger.LogError("Something went wrong")
    print ""

    print "=== Benefits of Primary Constructors ==="
    print "1. Less boilerplate code"
    print "2. Parameters available throughout the class"
    print "3. Perfect for dependency injection"
    print "4. Clean syntax for value types"
    print "5. Works with classes, structs, and records"
}
