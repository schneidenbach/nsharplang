# N# Examples

Welcome to the N# examples! These examples demonstrate the language features and capabilities of N# in an organized, easy-to-follow structure.

## Getting Started

Make sure you have N# installed:
```bash
dotnet tool install -g nsharp
```

## Example Categories

### [01. Hello World](./01-hello-world/)
Your first N# programs - basic syntax and structure.

### [02. Variables and Types](./02-variables-and-types/)
Type inference, target-typed new expressions, and type operators.

### [03. Functions](./03-functions/)
Expression-bodied members, local functions, generics, params collections, and more.

### [04. Pattern Matching](./04-pattern-matching/)
Guards, list patterns, type patterns, nested property patterns, and exhaustiveness checking.

### [05. Discriminated Unions](./05-unions/)
Define and match on unions - one of N#'s most powerful features.

### [06. Classes and Records](./06-classes-and-records/)
Records, record structs, primary constructors, and property features.

### [07. Interfaces](./07-interfaces/)
Duck interfaces and extension methods.

### [08. Async Programming](./08-async/)
Async streams and asynchronous iteration.

### [09. LINQ and Collections](./09-linq-and-collections/)
Collection expressions, iterators, ranges, and indexes.

### [10. C# Interop](./10-interop/)
Attributes, ref/out parameters, and calling C# code.

### [11. Advanced Features](./11-advanced-features/)
Operator overloading, conversions, locks, preprocessor directives, and more.

### [12. Multi-File Projects](./12-multi-file-projects/)
Complete projects demonstrating how to structure larger N# applications.

### [13. ASP.NET Core Demo](./13-aspnet-demo/)
Production-quality ASP.NET Core Web API built with N#.

## Running Examples

Each example can be run using:
```bash
cd examples/XX-category-name
nsharp run ExampleFile.nl
```

Or compiled and run:
```bash
nsharp build ExampleFile.nl
dotnet ExampleFile.dll
```

## Learning Path

If you're new to N#, we recommend following the examples in order:

1. Start with **Hello World** to understand basic syntax
2. Learn **Variables and Types** for type system fundamentals
3. Explore **Functions** to see N#'s functional features
4. Master **Pattern Matching** - this is where N# really shines
5. Understand **Discriminated Unions** - a game-changer for domain modeling
6. Study **Classes and Records** for object-oriented programming
7. Try the **Multi-File Projects** to see how to structure real applications
8. Dive into the **ASP.NET Core Demo** for a production example

## Contributing

Found an issue or want to add an example? Please open an issue or pull request!
