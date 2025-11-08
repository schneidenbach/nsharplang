# Pattern Matching

## Match Expressions

Match expressions provide exhaustive pattern matching (similar to Rust/F#).

### Basic Syntax
```
result := value match {
    pattern1 => expression1,
    pattern2 => expression2,
    _ => defaultExpression
}
```

## Pattern Types

### 1. Identifier Pattern
Binds value to variable:
```
result := x match {
    y => y * 2,           // Binds x to y
    _ => 0
}
```

Qualified names (union cases):
```
result := response match {
    Result.Success => "ok",
    Result.Failure => "error"
}
```

### 2. Literal Pattern
Matches exact values:
```
result := status match {
    0 => "zero",
    1 => "one",
    2 => "two",
    _ => "other"
}
```

String literals:
```
result := input match {
    "yes" => true,
    "no" => false,
    _ => null
}
```

### 3. Union Case Pattern
Matches union case and destructures properties:
```
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

message := result match {
    Result.Success { value: x } => $"Got {x}",
    Result.Failure { error: e } => $"Error: {e}"
}
```

### 4. Positional Pattern
Deconstructs tuples:
```
point := (10, 20)
result := point match {
    (0, 0) => "origin",
    (x, 0) => $"on x-axis at {x}",
    (0, y) => $"on y-axis at {y}",
    (x, y) => $"at ({x}, {y})"
}
```

### 5. List Pattern
Matches list/array structure:
```
result := list match {
    [] => "empty",
    [x] => $"single: {x}",
    [first, ..] => $"starts with {first}",
    [.., last] => $"ends with {last}",
    [first, .. rest, last] => $"first={first}, last={last}"
}
```

### 6. Type Pattern
Matches by type:
```
result := obj match {
    int n => $"integer: {n}",
    string s => $"string: {s}",
    _ => "other"
}
```

## Pattern Guards

Add boolean conditions with `when`:

```
result := value match {
    x when x > 0 => "positive",
    x when x < 0 => "negative",
    _ => "zero"
}
```

Guards can reference pattern variables:
```
result := result match {
    Result.Success { value: x } when x > 100 => "large",
    Result.Success { value: x } => "small",
    Result.Failure { error: e } => $"error: {e}"
}
```

## Exhaustiveness Checking

For discriminated unions, the compiler enforces exhaustive matching.

### Example
```
union Status {
    Active
    Inactive
    Pending
}

// ERROR: Non-exhaustive (missing Pending)
result := status match {
    Status.Active => "active",
    Status.Inactive => "inactive"
}

// OK: All cases covered
result := status match {
    Status.Active => "active",
    Status.Inactive => "inactive",
    Status.Pending => "pending"
}

// OK: Wildcard covers remaining
result := status match {
    Status.Active => "active",
    _ => "other"
}
```

### When Exhaustiveness is Skipped
- Guards present (too complex to analyze)
- Non-union types (can't enumerate all possible values)
- Type patterns (infinite possible types)

## Nested Property Patterns

Match on nested properties:

```
union Result<T> {
    Success { value: T, timestamp: DateTime }
    Failure { error: string, code: int }
}

message := result match {
    Result.Success { value: x, timestamp: t } => $"Got {x} at {t}",
    Result.Failure { error: e, code: c } => $"Error {c}: {e}"
}
```

## Transpilation to C#

Match expressions transpile to C# switch expressions:

**N# code:**
```
result := value match {
    0 => "zero",
    x when x > 0 => "positive",
    _ => "negative"
}
```

**Generated C#:**
```csharp
var result = value switch
{
    0 => "zero",
    var x when x > 0 => "positive",
    _ => "negative"
};
```

## Pattern Variable Scope

Variables bound in patterns are scoped to the case expression:

```
result := value match {
    Result.Success { value: x } => {
        // x is in scope here
        ProcessValue(x)
    },
    _ => DefaultValue()
    // x is NOT in scope here
}
```

## Analyzer Validation

The analyzer checks:
1. **Pattern types match value type** (e.g., can't match int with string pattern)
2. **Property patterns match union case properties**
3. **Guard expressions are boolean**
4. **All union cases covered** (exhaustiveness)
5. **Pattern variables don't shadow incorrectly**

See `memory/components/analyzer.md` for implementation details.

## Examples

### Simple Classification
```
grade := score match {
    x when x >= 90 => "A",
    x when x >= 80 => "B",
    x when x >= 70 => "C",
    x when x >= 60 => "D",
    _ => "F"
}
```

### Option Type
```
union Option<T> {
    Some { value: T }
    None
}

result := option match {
    Option.Some { value: x } => x,
    Option.None => defaultValue
}
```

### List Processing
```
message := numbers match {
    [] => "empty list",
    [x] => $"singleton: {x}",
    [x, y] => $"pair: {x}, {y}",
    [x, y, ..] => $"starts: {x}, {y}...",
    _ => "other"
}
```
