# 05. Discriminated Unions

Discriminated unions are N#'s killer feature - they let you model data that can be "one of several options" in a type-safe way.

## What You'll Learn

- Defining discriminated unions
- Generic unions (`Result<T>`, `Option<T>`)
- Pattern matching on unions
- Using unions for error handling
- Result types and Option types

## Files

- **UnionsAndMatch.nl** - Basic union definition and matching
- **GenericUnions.nl** - Generic unions: construction, type-argument inference, and matching
- **ErrorHandling.nl** - Using unions for robust error handling

## Why Unions?

Unions model "one of several things" directly, and the compiler **forces** you to handle all cases:

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
    None { }
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
        return new Result.Error<double> { message: "Cannot divide by zero" }
    }
    return new Result.Success<double> { value: a / (double)b }
}

result := Divide(10, 2)
message := match result {
    Result.Success { value } => $"Result: {value}",
    Result.Error { message } => $"Error: {message}"
}
print message
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

## Benefits

| Pattern | N# Unions |
|---------|-----------|
| Optional values | `Option<T>` keeps absence explicit |
| Recoverable errors | `Result<T>` is explicit in the signature |
| Variant data | Simple, flat union |
| Pattern matching | Exhaustive, required |

## Next Steps

Continue to [06. Classes and Records](../06-classes-and-records/) to learn about N#'s object-oriented features.
