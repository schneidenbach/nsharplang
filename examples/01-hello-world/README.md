# 01. Hello World

Your first N# programs! These examples show the basic structure of N# code.

## What You'll Learn

- Basic program structure
- Top-level functions
- String interpolation
- Print output

## Files

- **Program.nl** - A classic "Hello, World!" program

## Running

```bash
cd examples/01-hello-world
nlc run
```

From the repo root during local development:

```bash
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- run examples/01-hello-world/Program.nl
```

## Expected Output

```
Hello, World!
Hello, Alice!
```

## Code Walkthrough

### Program.nl

```n#
func main() {
    print "Hello, World!"
    name := "Alice"
    print $"Hello, {name}!"
}
```

**Key Concepts:**

- `func main()` - Entry point function
- `:=` - Type inference (compiler infers `string`)
- `$"..."` - String interpolation
- No semicolons required!

## Next Steps

Continue to [02. Variables and Types](../02-variables-and-types/) to learn about N#'s type system.
