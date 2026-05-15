# Pattern Matching in N#

N# provides powerful pattern matching inspired by F# and modern C#, with compile-time exhaustiveness checking for discriminated unions.

## Table of Contents

- [Match Expressions](#match-expressions)
- [Pattern Types](#pattern-types)
- [Exhaustiveness Checking](#exhaustiveness-checking)
- [Pattern Guards](#pattern-guards)
- [Advanced Patterns](#advanced-patterns)

## Match Expressions

The `match` expression is N#'s primary pattern matching construct:

```n#
result := match value {
    pattern1 => expression1,
    pattern2 => expression2,
    _ => defaultExpression
}
```

### Basic Example

```n#
status := match code {
    200 => "OK",
    404 => "Not Found",
    500 => "Server Error",
    _ => "Unknown"
}
```

### Match with Blocks

```n#
result := match user {
    null => {
        Console.WriteLine("No user found")
        return "Guest"
    },
    _ => {
        Console.WriteLine($"Found user: {user.Name}")
        return user.Name
    }
}
```

## Pattern Types

### 1. Literal Patterns

Match exact values:

```n#
result := match x {
    0 => "zero",
    1 => "one",
    2 => "two",
    _ => "other"
}

// String literals
greeting := match language {
    "en" => "Hello",
    "es" => "Hola",
    "fr" => "Bonjour",
    _ => "Hi"
}

// Boolean literals
status := match isActive {
    true => "Active",
    false => "Inactive"
}

// Null literal
message := match value {
    null => "No value",
    _ => "Has value"
}
```

### 2. Relational Patterns

Use comparison operators:

```n#
category := match age {
    < 13 => "child",
    < 20 => "teenager",
    < 65 => "adult",
    >= 65 => "senior"
}

grade := match score {
    >= 90 => "A",
    >= 80 => "B",
    >= 70 => "C",
    >= 60 => "D",
    _ => "F"
}
```

### 3. Logical Patterns

Combine patterns with `and`, `or`, `not`:

```n#
// And pattern
result := match value {
    > 0 and < 100 => "valid range",
    _ => "out of range"
}

// Or pattern
status := match code {
    200 or 201 or 204 => "success",
    400 or 404 => "client error",
    500 or 503 => "server error",
    _ => "unknown"
}

// Not pattern
result := match x {
    not 0 => "non-zero",
    _ => "zero"
}

// Complex combinations
category := match (age, hasLicense) {
    (>= 16, true) and not (> 80, _) => "can drive",
    _ => "cannot drive"
}
```

### 4. Type Patterns

Match by type:

```n#
result := match obj {
    int x => $"Integer: {x}",
    string s => $"String: {s}",
    double d => $"Double: {d}",
    _ => "Unknown type"
}

// With type test only
canProcess := match item {
    IProcessable => true,
    _ => false
}
```

### 5. Property Patterns

Match based on object properties:

```n#
result := match person {
    { Age: 0 } => "newborn",
    { Age: < 13 } => "child",
    { Age: >= 13, Name: "Alice" } => "teenage Alice",
    { Age: >= 65 } => "senior",
    _ => "adult"
}

// Nested property patterns
location := match person {
    { Address: { City: "NYC", State: "NY" } } => "New Yorker",
    { Address: { State: "CA" } } => "Californian",
    { Address: { Country: "Canada" } } => "Canadian",
    _ => "Unknown location"
}
```

### 6. Positional Patterns

Match tuples and deconstructable types:

```n#
result := match point {
    (0, 0) => "origin",
    (0, y) => $"on y-axis at {y}",
    (x, 0) => $"on x-axis at {x}",
    (x, y) when x == y => "on diagonal",
    (x, y) => $"point at ({x}, {y})"
}

// Multiple values
result := match (statusCode, hasBody) {
    (200, true) => "OK with body",
    (200, false) => "OK without body",
    (404, _) => "Not found",
    _ => "Other"
}
```

### 7. List Patterns

Match arrays and collections (C# 11):

```n#
result := match numbers {
    [] => "empty",
    [x] => $"single: {x}",
    [x, y] => $"pair: {x}, {y}",
    [first, ..] => $"starts with {first}",
    [.., last] => $"ends with {last}",
    [first, .. middle, last] => $"first: {first}, last: {last}",
    _ => "other"
}

// Specific patterns
result := match items {
    [1, 2, 3] => "exact match",
    [1, ..] => "starts with 1",
    [.., 5] => "ends with 5",
    [1, .., 5] => "starts with 1, ends with 5",
    _ => "other"
}
```

### 8. Union Patterns

Pattern matching discriminated unions (most powerful!):

```n#
union Result<T> {
    Success { value: T }
    Failure { error: string, code: int }
}

message := match result {
    Result.Success { value: v } => $"Success: {v}",
    Result.Failure { error: e, code: c } => $"Error {c}: {e}"
}

// Nested union matching
union Option<T> {
    Some { value: T }
    None { }
}

union Result<T> {
    Ok { value: T }
    Error { message: string }
}

outcome := match result {
    Result.Ok { value: Option.Some { value: x } } =>
        $"Got value: {x}",
    Result.Ok { value: Option.None } =>
        "Got none",
    Result.Error { message: m } =>
        $"Error: {m}"
}
```

## Exhaustiveness Checking

N# enforces exhaustiveness for discriminated unions:

```n#
union Status {
    Active { since: DateTime }
    Inactive { reason: string }
    Pending { until: DateTime }
}

// Compiler enforces all cases are handled
message := match status {
    Status.Active { since: s } => $"Active since {s}",
    Status.Inactive { reason: r } => $"Inactive: {r}",
    Status.Pending { until: u } => $"Pending until {u}"
    // No `_` needed - all cases covered!
}

// Error if you forget a case:
message := match status {
    Status.Active { since: s } => $"Active since {s}",
    Status.Inactive { reason: r } => $"Inactive: {r}"
    // Compiler error: This match doesn't cover all cases — missing: Pending
}
```

Property constraints make a union-case arm partial. For example, `Result.Success { value: 0 }` only covers successes whose value is `0`; the compiler reports the case as partially covered and suggests adding an unconstrained `Result.Success` arm or a wildcard `_` arm. Nested union-property patterns can prove coverage when all nested cases are covered:

```n#
union Option {
    Some { value: int }
    None
}

union Response {
    Ok { data: Option }
    Error { message: string }
}

value := match response {
    Response.Ok { data: Option.Some { value: x } } => x,
    Response.Ok { data: Option.None } => 0,
    Response.Error { message: _ } => 0
}
```

### Using Wildcard to Opt-Out

```n#
// Use `_` to handle multiple cases
result := match status {
    Status.Active { since: s } => $"Active since {s}",
    _ => "Not active"
}
```

## Pattern Guards

Add `when` clauses for conditional matching:

```n#
result := match value {
    x when x < 0 => "negative",
    x when x == 0 => "zero",
    x when x > 0 and x < 10 => "small positive",
    x when x >= 10 => "large positive",
    _ => "unknown"
}

// With property patterns
status := match person {
    { Age: a } when a < 13 => "child",
    { Age: a, Name: n } when n.StartsWith("A") => "adult named A*",
    { Age: a } when a >= 65 => "senior",
    _ => "adult"
}

// With union patterns
message := match result {
    Result.Success { value: v } when v > 100 =>
        $"Large success: {v}",
    Result.Success { value: v } =>
        $"Success: {v}",
    Result.Failure { code: c } when c >= 500 =>
        "Server error",
    Result.Failure { error: e } =>
        $"Client error: {e}"
}
```

## Advanced Patterns

### Combining Multiple Pattern Types

```n#
result := match (person, status) {
    ({ Age: < 18 }, "active") => "Minor account active",
    ({ Age: >= 18 }, "active") => "Adult account active",
    (_, "inactive") => "Account inactive",
    _ => "Unknown"
}
```

### Nested Patterns

```n#
union Response {
    Success { data: Result<User> }
    Failure { error: string }
}

union Result<T> {
    Ok { value: T }
    Error { message: string }
}

message := match response {
    Response.Success { data: Result.Ok { value: u } } =>
        $"User: {u.Name}",
    Response.Success { data: Result.Error { message: m } } =>
        $"Data error: {m}",
    Response.Failure { error: e } =>
        $"Response error: {e}"
}
```

### Var Pattern

Capture matched value:

```n#
result := match value {
    var x when x > 0 => x * 2,
    var x when x < 0 => x * -1,
    _ => 0
}
```

### Discard Pattern

Use `_` to ignore values:

```n#
result := match tuple {
    (x, _) => x,  // Ignore second element
    _ => 0
}
```

## Practical Examples

### Example 1: HTTP Status Handling

```n#
union HttpResult<T> {
    Ok { body: T, statusCode: int }
    Error { message: string, statusCode: int }
    Redirect { url: string, permanent: bool }
}

func handleResponse<T>(result: HttpResult<T>) {
    match result {
        HttpResult.Ok { body, statusCode: 200 } => {
            Console.WriteLine("Success!")
            processBody(body)
        },
        HttpResult.Ok { body, statusCode: code } => {
            Console.WriteLine($"Success with code {code}")
            processBody(body)
        },
        HttpResult.Error { message, statusCode: code } when code >= 500 => {
            Console.WriteLine($"Server error: {message}")
            logError(message)
        },
        HttpResult.Error { message, statusCode: code } => {
            Console.WriteLine($"Client error ({code}): {message}")
        },
        HttpResult.Redirect { url, permanent: true } => {
            Console.WriteLine($"Permanent redirect to {url}")
            followRedirect(url)
        },
        HttpResult.Redirect { url, permanent: false } => {
            Console.WriteLine($"Temporary redirect to {url}")
        },
        HttpResult.Redirect { url, permanent } => {
            Console.WriteLine($"Redirect to {url}")
        }
    }
}
```

### Example 2: AST Processing

```n#
union Expression {
    Number { value: int }
    Add { left: Expression, right: Expression }
    Multiply { left: Expression, right: Expression }
}

func evaluate(expr: Expression): int {
    return match expr {
        Expression.Number { value: v } => v,
        Expression.Add { left: l, right: r } => evaluate(l) + evaluate(r),
        Expression.Multiply { left: l, right: r } => evaluate(l) * evaluate(r)
    }
}

// Example: (2 + 3) * 4
expr := new Expression.Multiply {
    left: new Expression.Add {
        left: new Expression.Number { value: 2 },
        right: new Expression.Number { value: 3 }
    },
    right: new Expression.Number { value: 4 }
}

result := evaluate(expr)  // 20
```

### Example 3: Option Type

```n#
union Option<T> {
    Some { value: T }
    None { }
}

func divide(a: int, b: int): Option<int> {
    if b == 0 {
        return new Option.None<int> { }
    }
    return new Option.Some<int> { value: a / b }
}

// Usage with pattern matching
result := divide(10, 2)
description := match result {
    Option.Some { value: v } => $"Result: {v}",
    Option.None => "Cannot divide by zero"
}
```

### Example 4: State Machine

```n#
union State {
    Idle { }
    Loading { progress: int }
    Success { data: string }
    Error { message: string }
}

func renderUI(state: State): string {
    return match state {
        State.Idle { } => "Click to start",
        State.Loading { progress: p } when p < 50 =>
            $"Loading... {p}%",
        State.Loading { progress: p } =>
            $"Almost done... {p}%",
        State.Success { data: d } =>
            $"Success! Data: {d}",
        State.Error { message: m } =>
            $"Error: {m}"
    }
}
```

### Example 5: Validation

```n#
union ValidationResult {
    Valid { }
    Invalid { errors: List<string> }
}

func validateUser(user: User): ValidationResult {
    errors := new List<string>()

    if string.IsNullOrEmpty(user.Name) {
        errors.Add("Name is required")
    }

    if user.Age < 0 {
        errors.Add("Age must be positive")
    }

    return match errors.Count {
        0 => new ValidationResult.Valid { },
        _ => new ValidationResult.Invalid { errors: errors }
    }
}

// Usage
result := validateUser(user)
match result {
    ValidationResult.Valid { } => {
        Console.WriteLine("User is valid")
        saveUser(user)
    },
    ValidationResult.Invalid { errors: errs } => {
        Console.WriteLine("Validation errors:")
        for err in errs {
            Console.WriteLine($"  - {err}")
        }
    }
}
```

## Pattern Matching vs Switch

N# has both `match` (exhaustive) and `switch` (non-exhaustive):

### Match (Exhaustive)

```n#
// Compiler enforces all cases
result := match status {
    Status.Active { } => "active",
    Status.Inactive { } => "inactive",
    Status.Pending { } => "pending"
}
```

### Switch (Non-Exhaustive)

```n#
// Traditional C# switch - can have missing cases
switch (value) {
    case 0:
        Console.WriteLine("zero")
        break
    case 1:
        Console.WriteLine("one")
        break
    default:
        Console.WriteLine("other")
        break
}
```

Use `match` for:
- Discriminated unions (exhaustiveness checking)
- Complex pattern matching
- Expression-based flow

Use `switch` for:
- Traditional control flow
- When you don't need all cases
- Compatibility with C# patterns

## Best Practices

### 1. Prefer Match Over If-Else Chains

```n#
// Good
category := match age {
    < 13 => "child",
    < 20 => "teen",
    < 65 => "adult",
    _ => "senior"
}

// Less readable
if age < 13 {
    category = "child"
} else if age < 20 {
    category = "teen"
} else if age < 65 {
    category = "adult"
} else {
    category = "senior"
}
```

### 2. Use Exhaustiveness for Unions

```n#
// Let the compiler help you
message := match result {
    Result.Success { value: v } => $"Got {v}",
    Result.Failure { error: e } => $"Error: {e}"
    // Compiler ensures all cases covered
}
```

### 3. Extract Complex Guards to Functions

```n#
func isValidAge(age: int): bool => age >= 18 and age < 120

result := match user {
    { Age: a } when isValidAge(a) => "valid",
    _ => "invalid"
}
```

### 4. Use Nested Patterns for Deep Structures

```n#
// Good - clear and concise
city := match person {
    { Address: { City: c } } => c,
    _ => "Unknown"
}

// Avoid - manual null checking
city := if person != null and person.Address != null {
    person.Address.City
} else {
    "Unknown"
}
```

## Next Steps

- **[Types Guide](types.md)** - Learn about discriminated unions and other types
- **[Functions Guide](functions.md)** - Combine pattern matching with functions
- **[Examples](../../examples/)** - See pattern matching in real code

## Resources

- [Project README](../../README.md)
- [Language Design](../../DESIGN.md)
- [Pattern Matching Examples](../../examples/04-pattern-matching/)
