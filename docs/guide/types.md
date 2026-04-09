# Types in N#

This guide covers the type system in N#, including classes, structs, records, discriminated unions, duck interfaces, and enums.

## Table of Contents

- [Basic Types](#basic-types)
- [Classes](#classes)
- [Structs](#structs)
- [Records](#records)
- [Discriminated Unions](#discriminated-unions)
- [Duck Interfaces](#duck-interfaces)
- [Enums](#enums)
- [Interfaces](#interfaces)
- [Generics](#generics)
- [Nullable Types](#nullable-types)
- [Type Aliases](#type-aliases)
- [Newtypes (Branded Types)](#newtypes-branded-types)

## Basic Types

N# uses .NET's type system:

```n#
// Primitives
x: int = 42
y: long = 1000000
z: double = 3.14
w: decimal = 19.99
flag: bool = true
letter: char = 'A'

// String
name: string = "Alice"
message: string? = null  // Nullable string

// Arrays
numbers: int[] = [1, 2, 3, 4, 5]
names: string[] = ["Alice", "Bob", "Charlie"]
```

## Classes

### Basic Class Declaration

```n#
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
}
```

### Primary Constructors (C# 12)

```n#
class Person(firstName: string, lastName: string, age: int) {
    FirstName: string = firstName
    LastName: string = lastName
    Age: int = age

    func getFullName(): string => $"{FirstName} {LastName}"
}
```

### Properties

```n#
class Product {
    // Auto-property
    Name: string

    // Auto-property with initializer
    Price: decimal = 0.0

    // Expression-bodied property
    DisplayName: string => $"{Name} (${Price})"

    // Full property with getter and setter
    private _stock: int
    Stock: int {
        get => _stock
        set {
            if value < 0 {
                throw new ArgumentException("Stock cannot be negative")
            }
            _stock = value
        }
    }
}
```

### Init-only Properties

```n#
class Configuration {
    AppName: string { get; init; }
    Version: string { get; init; }
}

// Usage
config := new Configuration {
    AppName: "MyApp",
    Version: "1.0"
}

// config.AppName = "NewName"  // Error: init-only property
```

### Required Properties

```n#
class User {
    required Id: Guid
    required Name: string
    Email: string?  // Optional
}

// Must initialize required properties
user := new User {
    Id: Guid.NewGuid(),
    Name: "Alice"
}
```

### Inheritance

```n#
class Animal {
    Name: string

    constructor(name: string) {
        Name = name
    }

    virtual func makeSound(): string {
        return "..."
    }
}

class Dog : Animal {
    constructor(name: string) : base(name) {
    }

    override func makeSound(): string {
        return "Woof!"
    }
}
```

### Abstract Classes

```n#
abstract class Shape {
    abstract func getArea(): double
    abstract func getPerimeter(): double

    func describe() {
        Console.WriteLine($"Area: {getArea()}, Perimeter: {getPerimeter()}")
    }
}

class Circle : Shape {
    Radius: double

    constructor(radius: double) {
        Radius = radius
    }

    override func getArea(): double {
        return Math.PI * Radius * Radius
    }

    override func getPerimeter(): double {
        return 2 * Math.PI * Radius
    }
}
```

### Static Members

```n#
class MathHelper {
    static Pi: double = 3.14159

    static func square(x: double): double {
        return x * x
    }
}

// Usage
result := MathHelper.square(5)
pi := MathHelper.Pi
```

## Structs

Structs are value types:

```n#
struct Point {
    X: double
    Y: double

    constructor(x: double, y: double) {
        X = x
        Y = y
    }

    func distanceFrom(other: Point): double {
        dx := X - other.X
        dy := Y - other.Y
        return Math.Sqrt(dx * dx + dy * dy)
    }
}

// Usage
p1 := new Point(0, 0)
p2 := new Point(3, 4)
distance := p1.distanceFrom(p2)  // 5.0
```

### Readonly Structs

```n#
readonly struct Vector3 {
    X: double
    Y: double
    Z: double

    constructor(x: double, y: double, z: double) {
        X = x
        Y = y
        Z = z
    }
}
```

## Records

Records are immutable reference types:

```n#
record Person {
    FirstName: string
    LastName: string
    Age: int
}

// Usage
person := new Person {
    FirstName: "Alice",
    LastName: "Smith",
    Age: 30
}

// With expressions (create modified copy)
older := person with { Age: 31 }
```

### Record Structs

```n#
record struct Point {
    X: double
    Y: double
}

// Value semantics with record features
p1 := new Point { X: 1, Y: 2 }
p2 := p1 with { X: 3 }
```

### Positional Records

```n#
record Person(string FirstName, string LastName, int Age)

// Usage
person := new Person("Alice", "Smith", 30)
Console.WriteLine(person.FirstName)  // "Alice"

// Deconstruction
(first, last, age) := person
```

## Discriminated Unions

Unions are N#'s most powerful feature - they provide type-safe alternatives:

### Basic Union

```n#
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

// Usage
func divide(a: double, b: double): Result<double> {
    if b == 0 {
        return new Result.Failure<double> { error: "Division by zero" }
    }
    return new Result.Success<double> { value: a / b }
}
```

### Pattern Matching with Unions

```n#
result := divide(10, 2)

message := match result {
    Result.Success<double> { value: v } => $"Result: {v}",
    Result.Failure<double> { error: e } => $"Error: {e}"
}
```

### Union with Multiple Fields

```n#
union HttpResponse {
    Ok { body: string, statusCode: int }
    Error { message: string, code: int }
    Redirect { url: string, permanent: bool }
}

func handleResponse(response: HttpResponse) {
    match response {
        HttpResponse.Ok { body, statusCode } => {
            Console.WriteLine($"Success ({statusCode}): {body}")
        },
        HttpResponse.Error { message, code } => {
            Console.WriteLine($"Error {code}: {message}")
        },
        HttpResponse.Redirect { url, permanent } => {
            redirectType := if permanent { "permanent" } else { "temporary" }
            Console.WriteLine($"Redirect ({redirectType}): {url}")
        }
    }
}
```

### Option Type

```n#
union Option<T> {
    Some { value: T }
    None { }
}

func findUser(id: int): Option<User> {
    user := database.Find(id)
    if user == null {
        return new Option.None<User> { }
    }
    return new Option.Some<User> { value: user }
}
```

### How Unions Compile to C#

N# unions compile to C# class hierarchies:

```n#
union Result<T> {
    Success { value: T }
    Failure { error: string }
}
```

Compiles to:

```csharp
public abstract class Result<T>
{
    private Result() { }

    public sealed class Success : Result<T>
    {
        public T Value { get; init; }
    }

    public sealed class Failure : Result<T>
    {
        public string Error { get; init; }
    }
}
```

This means C# code can use N# unions naturally:

```csharp
// C# code consuming N# union
var result = new Result<int>.Success { Value = 42 };
```

## Duck Interfaces

Duck interfaces provide structural typing - types match based on their shape:

```n#
duck interface IReader {
    func Read(): string
}

class FileReader {
    func Read(): string {
        return "file contents"
    }
}

class HttpReader {
    func Read(): string {
        return "http contents"
    }
}

func processReader(reader: IReader) {
    content := reader.Read()
    Console.WriteLine(content)
}

// Both types work - they have the right shape!
processReader(new FileReader())
processReader(new HttpReader())
```

### Duck Interface Constraints

```n#
duck interface IProcessor<T> {
    func Process(input: T): T
}

class StringProcessor {
    func Process(input: string): string {
        return input.ToUpper()
    }
}

func execute<T>(processor: IProcessor<T>, value: T): T {
    return processor.Process(value)
}

// Usage
result := execute<string>(new StringProcessor(), "hello")
```

### How Duck Interfaces Compile

Duck interfaces are compile-time only - they're erased at runtime:

```n#
duck interface IReader {
    func Read(): string
}
```

Compiles to an internal interface:

```csharp
internal interface IReader
{
    string Read();
}
```

And the compiler automatically implements it on matching types:

```csharp
// Original N#
class FileReader {
    func Read(): string { ... }
}

// Generated C#
class FileReader : IReader
{
    public string Read() { ... }
}
```

## Enums

N# supports string enums for better APIs:

```n#
enum Status {
    Active = "active",
    Inactive = "inactive",
    Pending = "pending"
}

enum Role {
    Admin = "admin",
    User = "user",
    Guest = "guest"
}
```

### Using Enums

```n#
userStatus: string = Status.Active
userRole: string = Role.Admin

// In functions
func checkAccess(role: string): bool {
    return role == Role.Admin
}
```

### How Enums Compile

String enums compile to static classes:

```csharp
public static class Status
{
    public const string Active = "active";
    public const string Inactive = "inactive";
    public const string Pending = "pending";
}
```

## Interfaces

### Basic Interfaces

```n#
interface ICalculator {
    func Add(a: int, b: int): int
    func Subtract(a: int, b: int): int
}

class BasicCalculator : ICalculator {
    func Add(a: int, b: int): int => a + b
    func Subtract(a: int, b: int): int => a - b
}
```

### Interface Properties

```n#
interface IEntity {
    Id: Guid { get; }
    Name: string { get; set; }
}

class User : IEntity {
    Id: Guid { get; }
    Name: string { get; set; }

    constructor() {
        Id = Guid.NewGuid()
    }
}
```

### Generic Interfaces

```n#
interface IRepository<T> {
    func GetById(id: Guid): T?
    func GetAll(): List<T>
    func Add(entity: T): void
    func Delete(id: Guid): bool
}

class UserRepository : IRepository<User> {
    users: List<User> = new List<User>()

    func GetById(id: Guid): User? {
        return users.FirstOrDefault(u => u.Id == id)
    }

    func GetAll(): List<User> => users

    func Add(entity: User) {
        users.Add(entity)
    }

    func Delete(id: Guid): bool {
        user := GetById(id)
        if user != null {
            users.Remove(user)
            return true
        }
        return false
    }
}
```

## Generics

### Generic Classes

```n#
class Container<T> {
    value: T

    constructor(value: T) {
        this.value = value
    }

    func GetValue(): T => value
    func SetValue(newValue: T) {
        value = newValue
    }
}

// Usage
intContainer := new Container<int>(42)
stringContainer := new Container<string>("hello")
```

### Generic Constraints

```n#
// Class constraint
class Repository<T> where T : class {
    items: List<T> = new List<T>()

    func Add(item: T) {
        items.Add(item)
    }
}

// Struct constraint
class ValueContainer<T> where T : struct {
    value: T?

    func HasValue(): bool => value != null
}

// Interface constraint
class Processor<T> where T : IComparable<T> {
    func GetMax(a: T, b: T): T {
        return if a.CompareTo(b) > 0 { a } else { b }
    }
}

// Constructor constraint
class Factory<T> where T : new() {
    func Create(): T {
        return new T()
    }
}
```

### Multiple Constraints

```n#
class Service<T> where T : class, IDisposable, new() {
    func CreateAndUse() {
        instance := new T()
        try {
            // Use instance
        } finally {
            instance.Dispose()
        }
    }
}
```

## Nullable Types

### Nullable Reference Types

```n#
// Non-nullable (default)
name: string = "Alice"
// name = null  // Error!

// Nullable
optionalName: string? = null
optionalName = "Bob"  // OK
```

### Nullable Value Types

```n#
age: int? = null
age = 25

if age != null {
    Console.WriteLine($"Age: {age.Value}")
}

// Null-coalescing operator
displayAge := age ?? 0
```

### Null-conditional Operator

```n#
user: User? = GetUser()
name := user?.Name  // null if user is null

// Chaining
city := user?.Address?.City
```

### Null-forgiving Operator

```n#
// When you know it's not null
name: string = optionalName!
```

## Type Aliases

Create transparent type aliases (interchangeable with the underlying type):

```n#
type UserId = int
type StringDict = Dictionary<string, string>
type Callback = Func<void>
```

Type aliases are compile-time only — they do not create a distinct runtime type.

## Newtypes (Branded Types)

Create **distinct wrapper types** that prevent accidental type confusion:

```n#
type UserId = newtype int
type OrderId = newtype int
type Email = newtype string
```

Unlike type aliases, newtypes are **not interchangeable** with their underlying type:

```n#
id := UserId(42)           // Explicit construction
let raw: int = id.Value    // Explicit unwrapping

// These are compile errors:
// let x: int = id          // ERROR: UserId is not int
// let y: UserId = 42       // ERROR: int is not UserId
// let z: OrderId = id      // ERROR: UserId is not OrderId
```

Newtypes emit concrete wrapper types for .NET interop, giving C# consumers value equality, `ToString()`, and familiar value semantics.

## Complete Example

Here's a complete example demonstrating various type features:

```n#
import System
import System.Linq
import System.Collections.Generic

package TypesExample

// Enum
enum Status {
    Active = "active",
    Inactive = "inactive"
}

// Duck interface
duck interface IIdentifiable {
    Id: Guid { get; }
}

// Record
record Address {
    Street: string
    City: string
    State: string
    ZipCode: string
}

// Class with primary constructor
class Person(id: Guid, name: string, age: int) : IIdentifiable {
    Id: Guid = id
    Name: string = name
    Age: int = age
    Address: Address?

    func describe(): string =>
        $"{Name}, {Age} years old (ID: {Id})"
}

// Union
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

// Generic class with constraints
class Repository<T> where T : IIdentifiable {
    items: List<T> = new List<T>()

    func Add(item: T) {
        items.Add(item)
    }

    func GetById(id: Guid): Result<T> {
        found := items.FirstOrDefault(i => i.Id == id)
        return match found {
            null => new Result.Failure<T> { error: "Not found" },
            _ => new Result.Success<T> { value: found }
        }
    }
}

func main() {
    // Create a repository
    repo := new Repository<Person>()

    // Create a person
    person := new Person(Guid.NewGuid(), "Alice", 30) {
        Address: new Address {
            Street: "123 Main St",
            City: "New York",
            State: "NY",
            ZipCode: "10001"
        }
    }

    // Add to repository
    repo.Add(person)

    // Retrieve and match
    result := repo.GetById(person.Id)
    match result {
        Result.Success<Person> { value: p } => {
            Console.WriteLine($"Found: {p.describe()}")
            if p.Address != null {
                Console.WriteLine($"Lives in: {p.Address.City}")
            }
        },
        Result.Failure<Person> { error: e } => {
            Console.WriteLine($"Error: {e}")
        }
    }
}
```

## Next Steps

- **[Pattern Matching](pattern-matching.md)** - Deep dive into pattern matching with unions and more
- **[Functions Guide](functions.md)** - Learn about functions, lambdas, and async
- **[Interop Guide](interop.md)** - Using N# with C# and .NET libraries

## Resources

- [Project README](../../README.md)
- [Examples](../../examples/)
- [Language Design](../../DESIGN.md)
