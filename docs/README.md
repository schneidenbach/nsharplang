# N# Documentation

Welcome to the N# programming language documentation!

## What is N#?

N# (pronounced "N Sharp") is a pragmatic, simple language for the .NET CLR. It's designed as "Go for .NET" - combining Go's simplicity and clean syntax with the full power of the .NET ecosystem.

### Key Features

- **Clean Syntax**: No semicolons, short variable declarations with `:=`, convention-based visibility
- **Full .NET Interop**: Perfect interoperability with C# and all .NET libraries
- **Modern Type System**: String enums, type inference, and pragmatic nullability
- **Pattern Matching**: Powerful match expressions for cleaner code
- **Great Tooling**: VS Code extension with IntelliSense and syntax highlighting

## Getting Started

### Installation

```bash
# Install the templates
dotnet new install NSharp.Templates

# Create a new console app
dotnet new nsharp-console -o MyApp

# Run it
cd MyApp && dotnet run
```

### Your First Program

Create a file called `Program.nl`:

```n#
import System

package HelloWorld

func main() {
    name := "World"
    Console.WriteLine($"Hello, {name}!")
}
```

Build and run:

```bash
dotnet build
dotnet run
```

## Documentation Guides

### Language Guides

- **[Basics](guide/basics.md)** - Variables, functions, control flow, and core syntax
- **[Functions](guide/functions.md)** - Deep dive into functions, lambdas, async, and generics
- **[Types](guide/types.md)** - Classes, unions, records, duck interfaces, and the type system
- **[Pattern Matching](guide/pattern-matching.md)** - Master pattern matching with exhaustiveness checking

### Migration & Interop

- **[C# Migration Guide](guide/csharp-migration.md)** - Migrating from C# to N# - syntax mapping and strategies
- **[Interop Guide](guide/interop.md)** - Using N# with C# and .NET libraries

### Development & Deployment

- **[CI/CD Guide](guide/ci-cd.md)** - Setting up continuous integration and deployment with GitHub Actions, Azure Pipelines, and Docker

### Examples

Browse the [examples directory](../examples/) for complete working examples:

- **[01-hello-world](../examples/01-hello-world/)** - Simple hello world programs
- **[02-variables-and-types](../examples/02-variables-and-types/)** - Variable declarations and type inference
- **[03-functions](../examples/03-functions/)** - Function examples including generics and lambdas
- **[04-pattern-matching](../examples/04-pattern-matching/)** - Pattern matching examples
- **[13-aspnet-demo](../examples/13-aspnet-demo/)** - Complete ASP.NET Core REST API

## Quick Reference

### Variables

```n#
x := 5                    // Type inference
name: string = "Alice"    // Explicit type
let pi: double = 3.14     // Immutable binding
```

### Functions

```n#
func add(a: int, b: int): int {
    return a + b
}

func async fetchData(): string {
    return await client.GetStringAsync(url)
}
```

### Control Flow

```n#
if x > 5 {
    Console.WriteLine("big")
} else {
    Console.WriteLine("small")
}

for item in items {
    Console.WriteLine(item)
}
```

### Classes

```n#
class Person {
    Name: string
    Age: int

    constructor(name: string, age: int) {
        Name = name
        Age = age
    }
}
```

### Enums

```n#
enum Status {
    Active = "active",
    Inactive = "inactive"
}
```

### Pattern Matching

```n#
result := match value {
    null => "null value",
    0 => "zero",
    > 0 => "positive",
    _ => "other"
}
```

## Tooling

### VS Code Extension

Install the N# extension for VS Code:

1. Open VS Code
2. Go to Extensions (Ctrl+Shift+X / Cmd+Shift+X)
3. Search for "nsharp"
4. Click Install

Features:
- Syntax highlighting
- IntelliSense (autocomplete)
- Error diagnostics
- Format on save

### MSBuild Integration

N# projects use a minimal `.nlproj` file that references the MSBuild SDK:

```xml
<Project Sdk="NSharpLang.Sdk" />
```

All configuration goes in `project.yml`:

```yaml
name: MyApp
outputType: exe
targetFramework: net9.0
langVersion: latest
```

## Resources

- **[GitHub Repository](https://github.com/anthropics/NewCLILang)** - Source code and issue tracker
- **[Website](https://nsharp.dev)** - Official website
- **[Examples](../examples/)** - Working code examples

## Philosophy

N# follows these principles:

1. **Simplicity First**: Minimal constructs, clear syntax
2. **Pragmatic**: Embrace .NET realities (including null)
3. **Interop Excellence**: First-class C# interoperability
4. **Concrete over Abstract**: Encourage concrete implementations
5. **Better Type System**: Improve .NET's type system while maintaining seamless C# interop

## Contributing

N# is an open-source project. Contributions are welcome!

- Report bugs on [GitHub Issues](https://github.com/anthropics/NewCLILang/issues)
- Submit pull requests
- Improve documentation
- Share your projects

## License

N# is open source software. See the [LICENSE](../LICENSE) file for details.
