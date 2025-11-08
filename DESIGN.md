# N# (NewLang Sharp) Design Document

**Official Name:** N# (NewLang Sharp) - subject to change

## Core Philosophy

A tight, pragmatic language targeting .NET/CLI that prioritizes:
- **Simplicity**: Go-level tightness with minimal constructs
- **Pragmatism**: Embraces .NET realities (including null)
- **Interop**: First-class C# interoperability with sane type emissions
- **Concreteness**: Encourages concrete implementations over abstractions
- **Type System**: Improve .NET's type system while maintaining seamless C# interop

**Mental Model**: "Go for .NET" - avoiding C# complexity while staying practical

### The Type System Philosophy

N# aims to **improve the .NET type system** by adding features C# lacks:
- Discriminated unions (proper ADTs, not just inheritance)
- Exhaustive pattern matching (compiler-enforced)
- Duck typing / structural interfaces (Go-style)
- Cleaner syntax for common patterns

**CRITICAL**: Unlike F#, all N# types must interop seamlessly with C#:

| Feature | N# | F# (Poor Interop) | Why N# is Better |
|---------|----|--------------------|------------------|
| **Unions** | Emit as C# classes with inheritance | F# discriminated unions are opaque | C# can `new Result.Success { }` |
| **Records** | Emit as C# records | F# records have weird constructors | Natural C# syntax |
| **Properties** | C# auto-properties | F# properties need explicit getters | No ceremony |
| **Functions** | C# methods (static or instance) | F# functions aren't methods | C# can call directly |
| **Async** | C# async/await (Task/ValueTask) | F# Async is different type | Same async model |
| **Nullability** | C# nullable reference types | F# uses Option (not null) | C# understands nulls |
| **Duck interfaces** | Internal only, regular interfaces exposed | F# has no duck typing | Best of both worlds |

**Goal**: C# consumers should not know they're using N#-compiled code. It should look and feel like idiomatic C#.

## Key Constraints

### What We're NOT
- **NOT F#** - F# has **trash interop** with C#. F# types (discriminated unions, records, options, async) don't map cleanly to C#. F# chooses functional purity over practicality.
- NOT based on OCaml syntax

### What We ARE
- C-esque syntax
- Pragmatic multi-paradigm (functional support, not functional-first)
- .NET/CLI native with **perfect** C# interop
- Null-aware by design (embraces C# nullable reference types)
- Type system improvements that C# can actually use

## Language Features (Initial)

### Visibility
- Default: Convention-based (Go-style)
  - PascalCase = public
  - camelCase = private
- Explicit modifiers supported when needed:
  - `internal` - assembly-level access
  - `protected` - subclass access
- Examples:
  ```
  class MyClass {
      PublicField: string           // public (PascalCase)
      privateField: string           // private (camelCase)
      internal InternalField: string // explicit internal
      protected ProtectedField: int  // explicit protected
  }
  ```

### Type System
- Discriminated unions (built-in, unlike Go)
- Types that C# can consume naturally

#### Discriminated Unions
```
union Result {
    Success { value: int }
    Failure { error: string, code: int }
}
```
- Cases can have named properties

#### Pattern Matching
- `match` expression for exhaustive pattern matching (compiler enforced)
- `switch` statement as separate construct (non-exhaustive)
- **F#-level pattern matching** with multiple pattern types:

**Union Case Patterns**:
```
result := match someValue {
    Success { value } => value * 2,
    Failure { error, code } => 0
}
```

**Relational Patterns**:
```
result := match age {
    < 13 => "child",
    < 20 => "teen",
    >= 65 => "senior",
    _ => "adult"
}
```

**Logical Patterns** (and/or/not):
```
result := match value {
    > 0 and < 100 => "valid range",
    < 0 or > 100 => "out of range",
    not 50 => "not fifty",
    _ => "default"
}
```

**Nested Property Patterns**:
```
result := match person {
    { Address: { City: "NYC", State: "NY" } } => "New Yorker",
    { Address: { State: "CA" } } => "Californian",
    _ => "Other"
}
```

**Positional Patterns** (tuples/deconstructable types):
```
result := match point {
    (0, 0) => "origin",
    (0, y) => "on y-axis",
    (x, 0) => "on x-axis",
    (x, y) when x == y => "diagonal",
    _ => "other"
}
```

**Guards** (additional conditions):
```
result := match value {
    x when x > 0 and x < 10 => "single digit",
    x when x % 2 == 0 => "even",
    _ => "other"
}
```

**Note**: Commas are required between match cases (like C# switch expressions) to prevent parsing ambiguities.

#### Classes and Structs
- `class` is the default (emits .NET reference types)
- Better C# interop (most .NET APIs expect reference types)
- `struct` available for specific value-type needs (small data)
- Syntax:
  ```
  class Person {
      Name: string        // public property (PascalCase)
      age: int            // private property (camelCase)

      // Expression-bodied property (type inferred)
      FullName => $"{FirstName} {LastName}"

      constructor(name: string) {
          Name = name
          // age must be set via struct-literal or another constructor
      }

      func GetInfo(): string {
          return Name + " is " + age
      }

      // Expression-bodied method
      func Greet() => print $"Hello, {Name}!"
  }
  ```
- Fields emit as properties under the hood
- Visibility follows naming convention (PascalCase = public, camelCase = private)
- Default constructor always available
- Multiple constructors supported (for DI scenarios)
- Compiler tracks which properties are set in constructors
- **Expression-bodied members**:
  - Properties: `PropertyName => expression` (type inferred from expression)
  - Methods: `func MethodName() => expression`
  - Single-expression implementations without full body syntax

#### Object Initialization
- Syntax: `p := new Person("John") { age: 30 }`
- Can call constructor then use struct-literal to set remaining properties
- Compiler ensures all non-nullable properties are set before object is usable

#### Definite Assignment
- Compiler performs flow analysis on constructor bodies
- Non-nullable properties must be assigned in all code paths before constructor exits
- Inline initialization satisfies requirement:
  ```
  class Person {
      Name: string           // must be set in constructor or at instantiation
      Age: int = 0           // inline init satisfies requirement
      Id: string = Guid.New() // function calls allowed in inline init
  }
  ```

#### Interfaces
- Two types of interfaces:

**Regular Interfaces** (C# interop):
```
interface IReader {
    func Read(): string
    func Close() {
        // default implementation supported
    }
}

class FileReader : IReader {  // explicit implementation
    func Read(): string { ... }
}
```
- Explicit implementation required (`: IReader`)
- Exposed to C# consumers
- Support default implementations

**Duck Interfaces** (internal only):
```
duck interface IReaderDuck {
    func Read(): string
}

class MemoryReader {
    func Read(): string { ... }
    // No explicit declaration needed
}

func doWork(r: IReaderDuck) { ... }
doWork(new MemoryReader())  // works via structural typing
```
- Structural/duck typing - no explicit declaration needed
- NOT exposed to C# (internal to the language)
- Provides flexibility without forcing interface declarations

#### Nullability
- Explicit nullable types with `?` syntax
- Examples: `string?`, `int?`, `Person?`
- Non-nullable by default (embracing modern .NET nullable reference types)

#### Type Checking and Casting
- Type checking with pattern matching: `is`
- Safe casting: `as`
- Hard casting: `(Type)`
- Examples:
  ```
  // Type check with pattern
  if obj is string s {
      // s is available here
  }

  // Safe cast (returns null if fails)
  str := obj as string

  // Hard cast (throws if fails)
  str := (string)obj
  ```

#### Generics
- C# style syntax with `<T>`
- Generic constraints supported
- Examples:
  ```
  class List<T> {
      items: T[]

      func Add(item: T) { ... }
  }

  func Process<T>(item: T): T where T : IComparable {
      // ...
  }

  class Repository<T> where T : class, IEntity {
      // ...
  }
  ```

#### Error Handling
- Exceptions as primary mechanism
- Automatic exception capture in tuple deconstruction:
  ```
  func DoThing(): string {
      throw new Exception("oops")
  }

  // Normal call - throws exception
  result := DoThing()

  // Tuple deconstruction - captures exception
  result, err := DoThing()  // err is Exception? (null if no error)
  ```
- Tuple deconstruction must include all values
- Use `_` to discard unused values: `_, err := DoThing()`
- Throw expressions supported:
  ```
  name := input ?? throw new Exception("Input required")
  value := condition ? result : throw new InvalidOperationException()
  ```

#### Async/Await
- Full async/await support with implicit wrapping
- Return type wrapping:
  - `func async FetchData(): string { }` → transpiles to `ValueTask<string>` (or `Task<string>` based on project config)
  - Explicit types allowed: `func async GetData(): Task<string> { }` (for nested Task types)
  - Configurable default in `project.yml`: `language.asyncDefaultType: ValueTask` or `Task`
- Examples:
  ```
  // Implicit wrapping (recommended)
  func async FetchData(): string {
      return await LoadFromDb()
  }

  // Explicit when needed (e.g., Task<Task<string>>)
  func async GetNestedTask(): Task<string> {
      return Task.FromResult("value")
  }

  // Usage
  result := await FetchData()
  ```

#### Iterators
- Generator functions marked with `*` on func keyword
- Examples:
  ```
  func* GetNumbers(): IEnumerable<int> {
      yield 1
      yield 2
      yield 3
  }
  ```

#### Namespaces
- File-scoped namespaces (modern C# style):
  ```
  namespace MyApp.Services;

  class UserService {
      // ...
  }
  ```
- Default namespace follows directory structure (like Go packages)
- Example: file at `MyApp/Services/UserService.ext` automatically gets `MyApp.Services` namespace if not explicitly declared

#### Imports
- C# style `using` statements:
  ```
  using System.Collections
  using Json = System.Text.Json  // aliasing supported
  ```
- Must appear at top of file (after namespace declaration)

#### Semicolons
- No semicolons required (Go-style)
- Automatic semicolon insertion rules
- Keeps syntax tight and clean

#### Arrays and Collections
- Array type syntax: `int[]`, `string[]` (C# style)
- Array initialization: `arr := [1, 2, 3]` (defaults to mutable array)
- Immutable arrays: `arr := immutable [1, 2, 3]`
- Spread operator: `...` for expanding collections
- Examples:
  ```
  numbers := [1, 2, 3]           // mutable array
  names := immutable ["a", "b"]  // immutable array
  items: int[] = [10, 20, 30]    // explicit type

  // Spread in arrays
  arr1 := [1, 2, 3]
  arr2 := [...arr1, 4, 5]        // [1, 2, 3, 4, 5]

  // Spread in function calls
  items := [1, 2, 3]
  Sum(...items)
  ```

#### Lambdas and Closures
- C# style lambda syntax, no parentheses on parameters
- Expression lambdas: `x => x * 2`
- Statement lambdas: `x => { return x * 2 }`
- Multiple parameters: `(x, y) => x + y` (parens required for multiple)
- Full closure support (capture variables from outer scope)
- Examples:
  ```
  numbers.Map(x => x * 2)

  multiplier := 10
  numbers.Map(x => x * multiplier)  // captures 'multiplier'

  pairs.Map((x, y) => x + y)  // multiple params need parens
  ```

#### Strings
- Regular strings: `"hello world"`
- Interpolated strings: `$"Hello {name}, you are {age} years old"`
- Template/multi-line strings: `"""multi-line content here"""`
- Examples:
  ```
  msg := "Hello"
  greeting := $"Hello {name}!"
  template := """
    This is a multi-line
    string literal
    """
  ```

#### Built-in Functions
**Print function** - simplified console output:
```
print "Hello, world!"                    // with newline
print $"Name: {name}, Age: {age}"       // string interpolation
print person.ToString()                  // any expression
```
- No parentheses required
- Always outputs with newline (like println)
- Transpiles to `Console.WriteLine()`
- Use string interpolation for formatting instead of printf

#### Control Flow
- No parentheses required (Go-style)
- If statements:
  ```
  if x > 5 {
      // ...
  } else if x > 2 {
      // ...
  } else {
      // ...
  }
  ```
- Ternary operator:
  ```
  result := x > 5 ? "big" : "small"
  ```
- For loops:
  ```
  // C-style loop
  for i := 0; i < 10; i++ {
      // ...
  }

  // Foreach-style iteration
  for item in items {
      // ...
  }

  // Also supports 'foreach' keyword for .NET devs
  foreach item in items {
      // ...
  }
  ```
- While loops:
  ```
  while condition {
      // ...
  }
  ```

#### Static Members and Top-Level Functions
- Top-level functions allowed (Go-style):
  ```
  func DoThing() {
      // ...
  }
  ```
  - Emitted as internal static methods on auto-generated class
  - Internal by default - not exposed to C# consumers

- Static classes and members for designed APIs:
  ```
  static class Helpers {
      static func DoThing() { }
  }

  class MyClass {
      static func Create(): MyClass { }
  }
  ```
  - Use when you want explicit control over static API design
  - Properly exposed to C# consumers

#### Extension Methods
- Supported using `this` parameter (C# style)
- Can be top-level (internal) or in static classes (public)
- Examples:
  ```
  // Top-level extension (internal)
  func IsEmpty(this s: string): bool {
      return s.Length == 0
  }

  // Static class extension (exposed to C#)
  static class StringExtensions {
      static func IsEmpty(this s: string): bool {
          return s.Length == 0
      }
  }

  // Usage
  result := someString.IsEmpty()
  ```

#### Attributes
- C# style attribute syntax
- Essential for .NET interop (serialization, validation, DI, etc.)
- Examples:
  ```
  [Serializable]
  class Person {
      [JsonProperty("user_name")]
      UserName: string

      [Required]
      Email: string
  }

  [HttpGet("/api/users")]
  func GetUsers(): User[] {
      // ...
  }
  ```

#### Inheritance
- Single inheritance (C# style)
- Abstract and sealed classes supported
- Method overriding:
  - `virtual` keyword required on base method to allow overriding
  - `override` keyword implied when derived method matches signature
  - No `new` keyword (simpler than C#)
- Examples:
  ```
  class Animal {
      virtual func MakeSound() { }
  }

  class Dog : Animal {
      func MakeSound() {  // implicitly overrides
          // ...
      }
  }

  abstract class Shape {
      abstract func GetArea(): double
  }

  sealed class FinalClass {
      // cannot be inherited
  }
  ```

#### Enums
- Support both int and string enums
- Compiler infers type from values
- Flags support via attributes
- Examples:
  ```
  // Traditional int enum (auto-numbered)
  enum Status {
      Pending,
      Active,
      Done
  }

  // String enum (TypeScript-style)
  enum Status {
      Pending = "pending",
      Active = "active",
      Done = "done"
  }

  // Explicit int values
  enum Priority {
      Low = 0,
      Medium = 1,
      High = 2
  }

  // Flags
  [Flags]
  enum Permissions {
      Read = 1,
      Write = 2,
      Execute = 4
  }
  ```

#### Tuples
- C# style value tuples
- Support named and unnamed
- Deconstruction with `_` to discard values
- Special: add `, err` to catch exceptions (see Error Handling)
- Examples:
  ```
  // Type declarations
  func GetPerson(): (string, int) { }
  func GetPerson(): (name: string, age: int) { }

  // Creation
  pair := ("John", 30)
  namedPair := (name: "John", age: 30)

  // Deconstruction
  (x, y) := GetPair()
  (name, _) := GetPerson()  // discard age

  // With error handling
  result, err := MightThrow()
  ```

#### LINQ/Collections
- Method chaining only (no query syntax)
- Uses standard .NET LINQ extension methods
- Examples:
  ```
  result := items
      .Where(x => x > 5)
      .Select(x => x * 2)
      .ToList()

  first := users
      .OrderBy(u => u.Name)
      .FirstOrDefault()
  ```

#### Nullable Operators
- Full support for C# nullable operators
- Null-conditional: `?.` and `?[]`
- Null-coalescing: `??`
- Null-coalescing assignment: `??=`
- Examples:
  ```
  name := person?.Name
  firstItem := list?[0]

  value := maybeNull ?? "default"

  cache ??= ExpensiveOperation()
  ```

#### Reflection Operators
**nameof** - get identifier name as string:
```
throw new ArgumentNullException(nameof(parameter))
fieldName := nameof(person.Name)  // "Name"
```

**typeof** - get Type object:
```
type := typeof(Person)
if obj.GetType() == typeof(string) { }
```

#### Function Types
- Use `Func<>` for all function types
- `Func<void>` maps to `Action<>` under the hood
- No separate Action<> type - fixes C# bifurcation
- Examples:
  ```
  callback: Func<void> = () => Console.WriteLine("done")
  handler: Func<string, void> = msg => Process(msg)
  transformer: Func<int, int> = x => x * 2
  ```

#### Resource Management
- Using statements for IDisposable (C# style)
- Block syntax and variable syntax supported
- Examples:
  ```
  // Block syntax
  using stream = File.OpenRead("file.txt") {
      // stream auto-disposed at end
  }

  // Variable syntax (C# 8+ style)
  using stream := File.OpenRead("file.txt")
  // stream disposed at end of scope
  ```

#### Indexers
- Custom indexer syntax supported (C# style)
- Examples:
  ```
  class Dictionary<K, V> {
      func this[key: K]: V {
          get { return storage[key] }
          set { storage[key] = value }
      }
  }

  // Usage
  dict["name"] = "John"
  value := dict["name"]
  ```

#### Type Aliases
- Create shorthand names for types
- Makes complex types more readable
- Examples:
  ```
  type UserId = int
  type Handler = Func<string, void>
  type StringDict = Dictionary<string, string>
  type Result<T> = (value: T, error: Exception?)

  func ProcessUser(id: UserId) { }

  callback: Handler = msg => Console.WriteLine(msg)
  ```

#### Partial Classes
- Split class definitions across multiple files
- Useful for code generation scenarios
- Examples:
  ```
  // File1.nl
  partial class User {
      Name: string
  }

  // File2.nl
  partial class User {
      Email: string
  }

  // Compiler merges both into single class
  ```

#### Records
- Immutable data types with value equality
- NO primary constructors (use regular class syntax)
- Generates constructor, equality, hash code, etc.
- Examples:
  ```
  record Person {
      Name: string
      Age: int
  }

  // Creates immutable type with:
  // - Constructor: new Person { Name: "John", Age: 30 }
  // - Value equality
  // - ToString, GetHashCode, etc.

  // With expressions for non-destructive mutation
  p2 := p1 with { Age: 31 }
  ```

#### Preprocessor Directives
- Support C# style preprocessor directives
- Conditional compilation, regions, etc.
- Examples:
  ```
  #if DEBUG
  Console.WriteLine("Debug mode")
  #endif

  #region Helpers
  // code here
  #endregion

  #define FEATURE_X
  ```

#### Comments
- C# style comments
- Single line: `// comment`
- Multi-line: `/* comment */`
- XML documentation: `/// <summary>...</summary>`

#### Testing
- Test files: `.tests.nl` extension
- Compiled as XUnit test projects
- Inline with source code (no separate test projects needed)
- Syntax:
  ```
  test "should add two numbers correctly" {
      result := Add(2, 3)
      assert result == 5
      assert result > 0
  }

  test "should handle null values" {
      value := GetValue()
      assert value != null
      assert value.Length > 0
  }
  ```
- **Assert syntax**:
  - Boolean expressions transpile to appropriate XUnit Assert calls
  - `assert x == y` → `Assert.Equal(y, x)`
  - `assert x != y` → `Assert.NotEqual(y, x)`
  - `assert x > y` → `Assert.True(x > y)`
  - `assert x` → `Assert.True(x)`
- Tests run with standard XUnit test runner
- Full access to project symbols and types

## Syntax Decisions

### Function Definitions
```
func foo(x: int): int {
    // body
}
```

- Type annotations use colon syntax (`: type`)
- Functions use statements, not everything is an expression
- Functions can return void implicitly (no unit type needed)
- Default parameter values supported
- Named arguments supported:
  ```
  func CreateUser(name: string, age: int, email: string) { }

  // Positional
  CreateUser("John", 30, "john@example.com")

  // Named
  CreateUser(name: "John", age: 30, email: "john@example.com")

  // Mixed
  CreateUser("John", age: 30, email: "john@example.com")
  ```
- Method overloading supported:
  ```
  func Process(x: int) { }
  func Process(x: string) { }
  func Process(x: int, y: int) { }
  ```

### Variables
- Multiple declaration styles supported
- `:=` is shorthand for `let` with type inference
- Declaration syntax:
  ```
  // Uninitialized with explicit type
  let name: string

  // Inferred type with initialization (Go-style shorthand)
  name := "value"

  // Explicit let with inferred type
  let name = "value"

  // Immutable/const
  const name = "value"

  // Reassignment (only works with let/`:=`)
  name = "new value"  // ok for let/`:=`, error for const
  ```

### Constants and Read-only (class/module level)
- `const` for compile-time constants (C# style)
- `readonly` for runtime constants
- Examples:
  ```
  const MaxSize: int = 100  // compile-time constant

  readonly startTime: DateTime = DateTime.Now  // runtime constant

  class MyClass {
      readonly id: string

      constructor() {
          id = Guid.NewGuid().ToString()  // can only set in constructor
      }
  }
  ```
- When transpiling: only emit C# `const` for valid compile-time constant values

## Compilation Strategy

### Initial Approach: Transpile to C#
- Parse source → Generate C# code → Use C# compiler/Roslyn
- Leverage existing .NET toolchain
- Easier to implement and maintain
- Good C# interop by design

### Future Considerations
- Could evolve to direct IL emission or Roslyn API usage
- Start simple, optimize later

## Project Structure

### File Extension
- Source files: `.nl`
- Test files: `.tests.nl` (compiled as XUnit tests)

### Project Manifest
- `project.yml` file for project configuration
- Example:
  ```yaml
  name: MyApp  # optional, defaults to root directory name
  version: 1.0.0
  entry: Program.nl  # entry point for executables
  dependencies:
    Newtonsoft.Json: 13.0.3
    Microsoft.Extensions.DependencyInjection: 8.0.0
  language:
    asyncDefaultType: ValueTask  # or "Task" - default wrapper for async methods
  ```
- Minimal configuration required
- No `.csproj` files needed - inferred from directory structure

### Multi-File Compilation
- Compiler processes ALL `.nl` files in project directory
- Entry point specified in `project.yml` (for executables)
- Top-level statements:
  - Entry file's top-level statements execute as `Main()`
  - Other files' top-level statements execute in import dependency order
  - Each file executes once (before entry point)
- Two-pass compilation:
  1. Collect all type declarations from all files
  2. Analyze and type-check with full symbol table

### Import System
Two types of imports:

**File-based imports** (relative paths):
```
import "Models/Person"      // imports all symbols from file
import "./Helpers"          // relative path
import "Services/Auth" as AuthService  // with alias
```

**Namespace imports** (like C# using):
```
import System.Collections.Generic
import System.Linq
import Newtonsoft.Json as Json  // with alias
```

**Collision handling**:
- If two imports provide same symbol name → compiler error
- Resolve with aliasing: `import "File" as Alias`
- Access symbols: `Alias.SymbolName`
- Follows Python-style import semantics

## Deferred Features

### Future Consideration
- Operator overloading (may add later)
- ref/out parameters (use tuples for multiple returns; may add later for .NET interop)
- Unsafe code and pointers (may add later for native interop)

### Explicitly NOT Supported
- **Events** - NO event syntax. N# does not interop with .NET events. Use callbacks/lambdas instead.
- **Delegates (custom)** - Use `Func<>` and `Action<>` from .NET. No custom delegate declarations.

## Philosophy Notes

N# is a **focused subset of C#** with **type system improvements**:

### What N# Is
- Clean, tight grammar for modern .NET development (removes C#'s "junk heap" of legacy features)
- **Improved type system**: Adds discriminated unions, exhaustive pattern matching, duck typing
- **Seamless C# interop**: All N# types are consumable as idiomatic C# types
- Pragmatic, multi-paradigm (functional support, but not dogmatic)
- "Go for .NET" with better type system and pattern matching

### What N# Is NOT
- **NOT F#** - F# has **absolute trash interop** with C#:
  - F# discriminated unions are opaque to C#
  - F# `option` type doesn't map to C# nullability
  - F# `Async<T>` is incompatible with C# `Task<T>`
  - F# records have weird constructors from C# perspective
  - F# modules don't map cleanly to C# static classes
  - F# chooses functional purity over .NET ecosystem compatibility
- NOT a functional-first language (functional features, not functional ideology)
- NOT based on OCaml syntax

### The Key Differentiator
**N# improves .NET's type system while maintaining perfect C# interop.**

When you compile N# code to a library, C# consumers should:
- Use your types naturally (no weird wrappers)
- Call your functions like normal C# methods
- Work with your unions as if they were hand-written C# class hierarchies
- Never know the difference

This is **critical** for .NET ecosystem adoption. F# failed at this. N# will succeed.

## Open Design Questions

(To be filled in through design discussions)

---
