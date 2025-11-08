# 01. Hello World

Your first N# programs! These examples show the basic structure of N# code.

## What You'll Learn

- Basic program structure
- Package declarations
- Import statements
- Top-level functions
- String interpolation
- Print output

## Files

- **Program.nl** - A classic "Hello, World!" program
- **Simple.nl** - The simplest possible N# program

## Running

```bash
cd examples/01-hello-world
nsharp run Program.nl
```

## Expected Output

```
Hello, World!
Hello, Alice!
```

## Code Walkthrough

### Program.nl

```n#
import System

package Examples

func Main() {
    Console.WriteLine("Hello, World!")

    name := "Alice"
    Console.WriteLine($"Hello, {name}!")
}
```

**Key Concepts:**

- `import System` - Import .NET namespaces
- `package Examples` - Declare your package (similar to C# namespace)
- `func Main()` - Entry point function
- `:=` - Type inference (compiler infers `string`)
- `$"..."` - String interpolation
- No semicolons required!

### Simple.nl

The absolute simplest N# program:

```n#
import System

func Main() {
    Console.WriteLine("Hello!")
}
```

That's it! No classes, no namespaces required. Just write your code.

## Next Steps

Continue to [02. Variables and Types](../02-variables-and-types/) to learn about N#'s type system.
