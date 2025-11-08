# 05. Discriminated Unions

Discriminated unions are N#'s killer feature - they let you model data that can be "one of several options" in a type-safe way.

## What You'll Learn

- Defining discriminated unions
- Pattern matching on unions
- Using unions for error handling
- Result types and Option types

## Files

- **UnionsAndMatch.nl** - Basic union definition and matching
- **ErrorHandling.nl** - Using unions for robust error handling

## Why Unions?

In C#, you often use inheritance or nullable types to represent "one of several things". This is error-prone:

```csharp
// C# - Easy to forget to check!
var result = GetUser(id);
if (result != null) {  // Oops, forgot this check!
    Console.WriteLine(result.Name);
}
```

With unions, the compiler **forces** you to handle all cases:

```n#
// N# - Compiler enforces exhaustive matching
result := GetUser(id)
match result {
    Some { value } => Console.WriteLine(value.Name),
    None => Console.WriteLine("User not found")
}
```

## Key Concepts

### Defining Unions

```n#
union Option<T> {
    Some { value: T }
    None
}
```

### Result Type for Error Handling

```n#
union Result<T> {
    Success { value: T }
    Error { message: string }
}

func Divide(a: int, b: int): Result<double> {
    if b == 0 {
        return Result<double>.Error("Cannot divide by zero")
    }
    return Result<double>.Success(a / (double)b)
}

result := Divide(10, 2)
match result {
    Success { value } => Console.WriteLine($"Result: {value}"),
    Error { message } => Console.WriteLine($"Error: {message}")
}
```

### Exhaustiveness Checking

The compiler ensures you handle all union cases:

```n#
// Compile error if you forget a case!
match result {
    Success { value } => DoSomething(value)
    // Error: Non-exhaustive match - missing 'Error' case
}
```

## Real-World Use Cases

### API Responses

```n#
union ApiResponse<T> {
    Success { data: T, statusCode: int }
    NotFound
    Unauthorized
    ServerError { message: string }
}
```

### Command Results

```n#
union CommandResult {
    Success
    ValidationError { errors: string[] }
    NotFound { id: string }
    Conflict { message: string }
}
```

### Domain Modeling

```n#
union PaymentMethod {
    CreditCard { number: string, expiry: string }
    PayPal { email: string }
    BankTransfer { accountNumber: string, routingNumber: string }
}
```

## Benefits Over C# Patterns

| Pattern | C# | N# Unions |
|---------|-----|-----------|
| Nullable | `T?` - can forget null check | `Option<T>` - compiler enforces |
| Exceptions | Try-catch, can miss | `Result<T>` - explicit in signature |
| Inheritance | Complex hierarchy | Simple, flat union |
| Pattern matching | Partial, opt-in | Exhaustive, required |

## Next Steps

Continue to [06. Classes and Records](../06-classes-and-records/) to learn about N#'s object-oriented features.
