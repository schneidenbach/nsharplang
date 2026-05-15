// Example: Required and Init-Only Properties (C# 9 & 11 Features)
// This demonstrates modern C# property features in N#
import System


// Record with init-only properties (C# 9)
// Init properties can only be set during object initialization
record Person {
    Name: string
    Age: int
    Email: string

    // Expression-bodied property (read-only, computed)
    IsAdult: bool => Age >= 18
}

// Class with required properties (C# 11)
// Required properties MUST be set during object creation
class User {
    Id: string
    UserName: string
    Email: string
    CreatedAt: DateTime = DateTime.Now

    func GetInfo(): string {
        return $"{UserName} ({Email}) - ID: {Id}"
    }
}

// Combining required and init for maximum safety
// These properties must be set AND are immutable after initialization
class Product {
    Id: string
    Name: string
    Price: double

    // Optional init property (can be omitted, but immutable after set)
    Description: string = "No description"

    // Regular mutable property
    Stock: int = 0

    func GetDisplayPrice(): string {
        return $"${Price:F2}"
    }
}

// Example usage
func Main() {
    // Record with init-only properties
    p := new Person { Name: "Alice", Age: 30, Email: "alice@example.com" }

    print $"Person: {p.Name}, Age: {p.Age}, Adult: {p.IsAdult}"

    // This would fail at compile-time (can't modify init property after creation):
    // p.Name = "Bob"  // ERROR!

    // Class with required properties
    user := new User { Id: "user123", UserName: "alice", Email: "alice@example.com" }

    print $"User: {user.GetInfo()}"

    // This would fail at compile-time (required properties not set):
    // badUser := new User { UserName: "bob" }  // ERROR! Id and Email required

    // Combining required and init
    product := new Product {
        Id: "prod-001",
        Name: "Widget",
        Price: 29.99,
        Description: "A useful widget",
        Stock: 100
    }

    print $"Product: {product.Name} - {product.GetDisplayPrice()}"
    print $"Description: {product.Description}"
    print $"Stock: {product.Stock} units"

    // Can update mutable properties
    product.Stock = 95
    print $"Updated stock: {product.Stock} units"

    // This would fail (can't modify init property):
    // product.Name = "Super Widget"  // ERROR!

    // This would fail (required init property not set):
    // badProduct := new Product { Name: "Bad", Price: 10.0m }  // ERROR! Id required

    print ""
    print "Benefits of required and init properties:"
    print "1. required: Ensures critical properties are always set"
    print "2. init: Prevents accidental mutations after object creation"
    print "3. Combined: Guarantees immutability for required data"
    print "4. Better than readonly: Can use object initializers"
}
