# 04. Pattern Matching

Pattern matching is one of N#'s most powerful features, enabling concise and expressive code for working with complex data structures.

## What You'll Learn

- Match expressions
- Pattern guards (when clauses)
- List patterns for arrays and collections
- Type patterns
- Nested property patterns
- Exhaustiveness checking

## Files

- **GuardsSimple.nl** - Basic pattern matching with guards
- **PatternGuards.nl** - Advanced guard patterns
- **ListPatterns.nl** - Matching on lists and arrays
- **TypePatterns.nl** - Matching on types
- **NestedPropertyPatternsSimple.nl** - Simple nested property matching
- **NestedPropertyPatterns.nl** - Complex nested patterns
- **MatchExhaustiveness.nl** - Exhaustiveness checking examples

## Running

```bash
cd examples/04-pattern-matching
dotnet run --project ../../src/NSharpLang.Cli/Cli.csproj -- run GuardsSimple.nl
```

## Key Concepts

### Basic Match Expression

```n#
result := value match {
    0 => "zero",
    1 => "one",
    _ => "many"
}
```

### Pattern Guards

```n#
result := number match {
    n when n < 0 => "negative",
    n when n == 0 => "zero",
    n when n > 0 => "positive"
}
```

### List Patterns

```n#
result := list match {
    [] => "empty",
    [x] => $"single: {x}",
    [x, y] => $"pair: {x}, {y}",
    [first, .., last] => $"first: {first}, last: {last}",
    _ => "other"
}
```

### Type Patterns

```n#
result := obj match {
    int i => $"integer: {i}",
    string s => $"string: {s}",
    _ => "unknown type"
}
```

### Nested Property Patterns

```n#
result := person match {
    { Name: "Alice", Address: { City: "Seattle" } } => "Alice from Seattle",
    { Age: age } when age < 18 => "Minor",
    _ => "Other"
}
```

## Why Pattern Matching Matters

Pattern matching makes code:
- **More readable** - Intent is clear at a glance
- **Safer** - Exhaustiveness checking ensures you handle all cases
- **More concise** - Less boilerplate than if-else chains
- **More maintainable** - Adding new cases is straightforward

## Next Steps

Continue to [05. Discriminated Unions](../05-unions/) to see how pattern matching really shines with unions!
