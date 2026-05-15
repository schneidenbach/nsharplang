# N# Language Basics

Welcome to N#! This guide covers the fundamental syntax and features of the N# programming language.

## What is N#?

N# (pronounced "N Sharp") is a pragmatic, simple language for the .NET CLR. Think of it as "Go for .NET" - it combines Go's simplicity and clean syntax with the power of the .NET ecosystem.

**Key Features:**
- Clean, minimal syntax (no semicolons!)
- First-class .NET interop
- Type inference with `:=`
- String enums for better APIs
- Full access to .NET libraries and NuGet packages

## Variables

N# supports both type inference and explicit type declarations.

### Type Inference with `:=`

The `:=` operator declares a variable and infers its type:

```n#
x := 5              // Inferred as int
name := "Alice"     // Inferred as string
isActive := true    // Inferred as bool
items := [1, 2, 3]  // Inferred as int[]
```

### Explicit Type Declarations

Use `: Type =` for explicit types:

```n#
y: int = 10
greeting: string = "Hello"
count: long = 1000000
price: decimal = 19.99
```

### let Keyword

Use `let` for immutable bindings:

```n#
let numbers: int[] = [1, 2, 3, 4, 5]
let pi: double = 3.14159
```

## Functions

Functions are declared with the `func` keyword.

### Basic Functions

```n#
func add(a: int, b: int): int {
    return a + b
}

func greet(name: string) {
    Console.WriteLine($"Hello, {name}!")
}
```

### Function Calls

```n#
result := add(5, 10)
greet("World")
```

### Async Functions

Use the `async` keyword for asynchronous functions:

```n#
async func fetchData(): string {
    result := await httpClient.GetStringAsync("https://api.example.com/data")
    return result
}
```

### Lambda Expressions

N# supports lambda expressions for inline functions:

```n#
doubled := numbers.Select(x => x * 2).ToList()
filtered := items.Where(item => item > 5)
```

## Control Flow

### If Statements

```n#
if x > 5 {
    Console.WriteLine("x is greater than 5")
} else if x == 5 {
    Console.WriteLine("x equals 5")
} else {
    Console.WriteLine("x is less than 5")
}
```

### While Loops

```n#
count := 0
while count < 10 {
    Console.WriteLine(count)
    count += 1
}
```

### For Loops

```n#
// For-each loop
for item in items {
    Console.WriteLine(item)
}

// With index
numbers := [10, 20, 30]
foreach num in numbers {
    Console.WriteLine(num)
}
```

## Collections

### Arrays

```n#
numbers := [1, 2, 3, 4, 5]
names: string[] = ["Alice", "Bob", "Charlie"]
let empty: int[] = []
```

### Object Initialization

```n#
person := new Person {
    Name: "Alice",
    Age: 30,
    Email: "alice@example.com"
}
```

### Anonymous Objects

```n#
data := new {
    name: "Alice",
    age: 30,
    active: true
}
```

## Types

### Classes

```n#
class Person {
    Name: string
    Age: int
    Email: string

    // Constructor
    constructor(name: string, age: int) {
        Name = name
        Age = age
        Email = ""
    }

    // Method
    func greet() {
        Console.WriteLine($"Hello, I'm {Name}")
    }
}
```

### Creating Instances

```n#
person := new Person("Alice", 30)
person.greet()

// With object initializer
person2 := new Person("Bob", 25) {
    Email: "bob@example.com"
}
```

### Enums (String Enums)

N# supports string enums for better API ergonomics:

```n#
enum Status {
    Active = "active",
    Inactive = "inactive",
    Pending = "pending"
}

enum Department {
    Engineering = "engineering",
    Sales = "sales",
    Marketing = "marketing",
    HR = "hr"
}
```

### Using Enums

```n#
currentStatus: string = Status.Active
dept: string = Department.Engineering
```

## Pattern Matching

N# includes powerful pattern matching with `match`:

```n#
result := match value {
    null => "Value is null",
    0 => "Value is zero",
    > 0 => "Value is positive",
    < 0 => "Value is negative",
    _ => "Unknown"
}
```

### Pattern Matching in Functions

```n#
async func GetById(id: Guid): IActionResult {
    employee := await db.Employees.FindAsync(id)

    return match employee {
        null => NotFound(),
        _ => Ok(employee)
    }
}
```

## String Interpolation

Use `$""` for string interpolation:

```n#
name := "Alice"
age := 30
message := $"Hello, {name}! You are {age} years old."
Console.WriteLine(message)
```

## Imports and Packages

### Import Statements

Import .NET namespaces at the top of your file:

```n#
import System
import System.Linq
import System.Collections.Generic
import Microsoft.AspNetCore.Mvc
```

### Package Declaration

Declare your package namespace:

```n#
package MyApp.Services

import System

func DoSomething() {
    Console.WriteLine("Doing something!")
}
```

## Comments

```n#
// Single-line comment

/*
 * Multi-line comment
 * Can span multiple lines
 */
```

## Nullability

N# embraces .NET's nullable types pragmatically:

```n#
// Nullable types use ?
name: string? = null
count: int? = null

// Non-nullable types
required: string = "must have value"
number: int = 42
```

## Attributes

N# supports .NET attributes on declarations and parameters:

```n#
[Required]
[MaxLength(100)]
FirstName: string

[HttpGet]
async func GetAll([FromRoute] id: int): IActionResult {
    // ...
}

[HttpPost]
func Create([FromBody] [Required] user: CreateUserRequest): IActionResult {
    // ...
}
```

Parameter attributes are emitted as real CLR parameter metadata, so ASP.NET model-binding attributes such as `[FromBody]` and `[FromRoute]`, plus xUnit-style parameter attributes from referenced packages, are visible to the framework at runtime.

## Example: Complete Program

Here's a complete N# program that demonstrates many of these features:

```n#
import System
import System.Linq

package HelloWorld

class Person {
    FirstName: string
    LastName: string
    Age: int

    constructor(firstName: string, lastName: string, age: int) {
        FirstName = firstName
        LastName = lastName
        Age = age
    }

    func getFullName(): string {
        return $"{FirstName} {LastName}"
    }

    func isAdult(): bool {
        return Age >= 18
    }
}

func main() {
    // Create some people
    people := [
        new Person("Alice", "Smith", 30),
        new Person("Bob", "Jones", 17),
        new Person("Charlie", "Brown", 25)
    ]

    Console.WriteLine("All people:")
    for person in people {
        fullName := person.getFullName()
        status := if person.isAdult() { "adult" } else { "minor" }
        Console.WriteLine($"  {fullName} - {person.Age} years old ({status})")
    }

    // Filter adults using LINQ
    adults := people.Where(p => p.isAdult()).ToList()
    Console.WriteLine($"\nFound {adults.Count} adults")
}
```

## Next Steps

- **[Functions Guide](functions.md)** - Deep dive into functions, lambdas, and async
- **[Types Guide](types.md)** - Advanced type system features
- **[Pattern Matching](pattern-matching.md)** - Master pattern matching

## Resources

- [Project README](../../README.md)
- [Examples](../../examples/)
