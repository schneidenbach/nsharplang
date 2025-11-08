# N# (NewLang Sharp)

**"Go for .NET"** - A tight, pragmatic language targeting .NET/CLI with **perfect C# interoperability**.

## 🎯 Core Philosophy

- **Simplicity**: Go-level tightness with minimal constructs
- **Pragmatism**: Embraces .NET realities (including null)
- **Interop First**: C# consumers can't tell they're using N#-compiled code
- **Type System++**: Improves .NET's type system while maintaining seamless C# interop
- **Concreteness**: Encourages concrete implementations over abstractions

## 🚀 Why N#?

Unlike F# which has **poor C# interop** (F# discriminated unions, records, and async types don't map to C#), N# is designed from the ground up for **perfect .NET ecosystem integration**:

| Feature | N# | F# | Why N# Wins |
|---------|----|----|-------------|
| **Unions** | Emit as C# class hierarchies | Opaque to C# | C# can `new Result.Success { }` |
| **Records** | C# records | Weird constructors | Natural C# syntax |
| **Async** | C# async/await (Task/ValueTask) | Different type | Same async model |
| **Nullability** | C# nullable reference types | F# Option | C# understands nulls |
| **Duck interfaces** | Internal only, regular interfaces exposed | No duck typing | Best of both worlds |

## ✨ Language Features

### 🎨 Modern Syntax

```n#
// Variables with type inference
name := "Alice"
age := 30
items := [1, 2, 3, 4, 5]

// No semicolons required!
print "Hello, World!"
```

### 🏗️ Classes & Records

```n#
// Classes with convention-based visibility
class Person {
    Name: string           // public (PascalCase)
    age: int              // private (camelCase)

    // Primary constructor (C# 12)
    constructor(name: string, age: int) {
        Name = name
        this.age = age
    }

    // Expression-bodied property
    IsAdult => age >= 18

    func Greet() {
        print $"Hi, I'm {Name}!"
    }
}

// Records - immutable by default
record Point(x: double, y: double) {
    Distance => Math.Sqrt(x * x + y * y)
}

// With expressions for non-destructive mutation
p2 := p1 with { X: 10 }
```

### 🎯 Discriminated Unions

```n#
union Result {
    Success { value: int }
    Failure { error: string, code: int }
}

// Pattern matching with exhaustiveness checking
result := match someResult {
    Success { value } => value * 2,
    Failure { error, code } => 0
}
```

### 🔍 F#-Level Pattern Matching

```n#
// Relational patterns
ageGroup := match age {
    < 13 => "child",
    < 20 => "teen",
    >= 65 => "senior",
    _ => "adult"
}

// List patterns (C# 11)
result := match numbers {
    [] => "empty",
    [x] => $"single: {x}",
    [first, .. rest, last] => $"first: {first}, last: {last}",
    _ => "other"
}

// Property patterns with guards
classification := match person {
    { Address: { City: "NYC" } } when person.Age > 18 => "Adult New Yorker",
    { Age: < 18 } => "Minor",
    _ => "Other"
}

// Type patterns
message := match obj {
    string s when s.Length > 10 => "Long string",
    int n when n > 100 => "Large number",
    _ => "Other"
}
```

### 🦆 Duck Interfaces

```n#
// Duck interface - structural typing (internal only)
duck interface IReader {
    func Read(): string
}

// No explicit implementation needed!
class FileReader {
    func Read(): string { ... }
}

func ProcessReader(r: IReader) { ... }
ProcessReader(new FileReader())  // Works via structural typing!
```

### ⚡ Modern C# Features

```n#
// Collection expressions (C# 12)
let names: List<string> = ["Alice", "Bob", "Charlie"]
let unique: HashSet<int> = [1, 2, 3, 4, 5]

// Range and index operators (C# 8)
lastItem := array[^1]
slice := array[2..5]

// Inline out variables (C# 7)
if int.TryParse("123", out var num) {
    print num
}

// Required and init-only properties (C# 11)
class User {
    required init Id: string
    required init Email: string
    Name: string = ""
}

// File-scoped types (C# 11)
file class InternalHelper {
    func Process() { ... }
}

// Raw string literals with interpolation (C# 11)
json := $"""
{
    "name": "{person.Name}",
    "age": {person.Age}
}
"""
```

### 🔧 Error Handling

```n#
// Automatic exception capture with tuple deconstruction
result, err := MightThrow()
if err != null {
    print $"Error: {err.Message}"
}

// Throw expressions
name := input ?? throw new ArgumentNullException()
```

### ⚙️ Advanced Features

```n#
// Params arrays
func Sum(params numbers: int[]): int {
    total := 0
    for num in numbers {
        total += num
    }
    return total
}

// Ref/out parameters for .NET interop
func Swap(ref a: int, ref b: int) {
    temp := a
    a = b
    b = temp
}

// Operator overloading
struct Vector2D {
    X: double
    Y: double

    static func operator +(a: Vector2D, b: Vector2D): Vector2D =>
        new Vector2D { X: a.X + b.X, Y: a.Y + b.Y }
}

// Extension methods
static func IsEmpty(this s: string): bool {
    return s.Length == 0
}

// Async/await with implicit wrapping
func async FetchData(): string {
    return await LoadFromDb()  // Returns ValueTask<string>
}

// Iterators
func* GetNumbers(): IEnumerable<int> {
    yield 1
    yield 2
    yield 3
}
```

### 📦 Multi-File Projects

```n#
// project.yml
name: MyApp
version: 1.0.0
entry: Program.nl
targetFramework: net9.0
dependencies:
  Newtonsoft.Json: 13.0.3

// Models/Person.nl
namespace MyApp.Models

record Person {
    Name: string
    Age: int
}

// Program.nl
import "Models/Person"

func Main() {
    person := new Person { Name: "Alice", Age: 30 }
    print person.Name
}
```

## 🛠️ Installation & Usage

### Build from Source

```bash
# Clone and build
git clone https://github.com/anthropics/NewCLILang.git
cd NewCLILang
dotnet build

# Run tests (404 passing!)
dotnet test
```

### CLI Commands

```bash
# Transpile to C# (stdout)
dotnet run --project src/Cli/Cli.csproj -- transpile Program.nl

# Build executable
dotnet run --project src/Cli/Cli.csproj -- build Program.nl

# Build and run
dotnet run --project src/Cli/Cli.csproj -- run Program.nl

# Multi-file project
cd examples/WeatherDemo
dotnet run --project ../../src/Cli/Cli.csproj -- build
```

## 📚 Examples

Explore `examples/` for comprehensive demonstrations:

- **hello.nl** - Basic syntax, variables, LINQ
- **WeatherDemo/** - 🔥 **KILLER DEMO** - Multi-file project showcasing 10+ features
- **unions_and_match.nl** - Discriminated unions with exhaustive matching
- **duck_interfaces.nl** - Structural typing in action
- **primary_constructors.nl** - C# 12 primary constructors
- **list_patterns.nl** - C# 11 list pattern matching
- **error_handling.nl** - Exception capture with `result, err := Function()`
- **operator_overloading.nl** - Custom operators
- **ref_out_parameters.nl** - .NET interop patterns
- **type_patterns.nl** - Type-based pattern matching
- **range_and_index.nl** - C# 8 range/index operators

## 📊 Project Status

### ✅ Fully Implemented (v1.49)

- **406 tests passing** (27 lexer + 55 parser + 67 analyzer + 53 transpiler + more)
- Full lexical analysis with all operators and keywords
- Complete AST parsing for all language constructs
- Semantic analysis with type checking and inference
- External type resolution via .NET reflection
- C# code generation (transpiler)
- Multi-file compilation with imports
- CLI tool (build/transpile/run)
- project.yml support

### 🎯 Feature Highlights

- ✅ Discriminated unions
- ✅ Exhaustive pattern matching (relational, logical, list, property, type patterns)
- ✅ Duck interfaces (structural typing)
- ✅ Primary constructors (C# 12)
- ✅ Collection expressions (C# 12)
- ✅ List patterns (C# 11)
- ✅ File-scoped types (C# 11)
- ✅ Raw string literals (C# 11)
- ✅ Range and index operators (C# 8)
- ✅ Inline out variables (C# 7)
- ✅ Required and init-only properties
- ✅ Constructor chaining
- ✅ Operator overloading
- ✅ Ref/out parameters
- ✅ Params arrays
- ✅ Extension methods
- ✅ Async/await
- ✅ Iterators (yield)
- ✅ Pattern matching guards
- ✅ Expression-bodied members
- ✅ Lock statements
- ✅ Null-safe operators (?., ?[], ??, ??=)
- ✅ String enums
- ✅ Records with 'with' expressions
- ✅ Attributes
- ✅ Generics with constraints
- ✅ Method overloading
- ✅ Partial classes
- ✅ Abstract/sealed/virtual classes
- ✅ Namespaces (file-scoped)
- ✅ Top-level statements

### 🔄 Future Enhancements

- Global symbol table for automatic namespace resolution
- Partial class merging across files
- Circular import detection
- Top-level statement ordering
- IDE integration (LSP server)
- Better error messages

## 🏗️ Architecture

```
.nl source → Lexer → Parser → Analyzer → Transpiler → C# → IL → Assembly
```

**Compilation Strategy:** Transpile to C# (not direct IL emission)

Benefits:
- Simpler implementation
- Excellent C# interop by design
- Leverage existing .NET toolchain
- Can evolve to direct IL later

## 🎓 Design Decisions

### Why Transpile to C#?

1. **Perfect interop** - Generated code is idiomatic C#
2. **Leverage tooling** - Use existing C# compiler, debuggers, analyzers
3. **Simpler** - Don't reinvent IL emission
4. **Debuggable** - Can inspect generated C#

### Visibility Convention

```n#
class MyClass {
    PublicField: string    // PascalCase = public
    privateField: int      // camelCase = private
    internal InternalField: string  // Explicit modifier
}
```

### Union Type Emission

```n#
union Result {
    Success { value: int }
    Failure { error: string }
}
```

Transpiles to:

```csharp
abstract record Result;
record Success(int value) : Result;
record Failure(string error) : Result;
```

C# consumers can use it naturally!

## 🤝 C# Interop Example

N# library:

```n#
// Math.nl
class Calculator {
    func Add(x: int, y: int): int => x + y
}
```

C# consumer:

```csharp
// Completely natural!
var calc = new Calculator();
var result = calc.Add(2, 3);
```

## 📖 Documentation

- **DESIGN.md** - Complete language specification
- **tasks.md** - Development roadmap and completed features
- **memory/** - Implementation notes and architecture details

## 🧪 Testing

```bash
dotnet test
```

**Current:** 404 tests passing across:
- Lexer (token recognition, string interpolation, operators)
- Parser (all language constructs, AST building)
- Analyzer (type checking, semantic analysis, external types)
- Transpiler (C# code generation, all features)
- End-to-end (multi-file compilation, real-world scenarios)

## 🎯 Who Should Use N#?

- .NET developers who want **simpler syntax** without F#'s complexity
- Teams building **libraries for C# consumption**
- Developers who love **Go's simplicity** but need .NET
- Projects needing **discriminated unions** with C# interop
- Anyone wanting **modern C# features** with less ceremony

## 💡 Philosophy

> "F# chooses functional purity over .NET ecosystem compatibility. N# chooses pragmatism."

N# is **not**:
- ❌ F# (we have better C# interop)
- ❌ Functional-first (we're multi-paradigm)
- ❌ Based on OCaml syntax

N# **is**:
- ✅ Go-inspired syntax for .NET
- ✅ Type system improvements C# can actually use
- ✅ Pragmatic multi-paradigm
- ✅ Perfect for .NET libraries and applications

## 📜 License

MIT

## 🙏 Acknowledgments

Built with Claude Code to demonstrate modern language implementation on the CLR.

---

**Current Version:** v1.49 - WeatherDemo Multi-File Example
**Status:** Production-ready for experimentation and learning
**Tests:** 406 passing ✅
