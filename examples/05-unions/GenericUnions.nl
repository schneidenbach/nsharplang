namespace GenericUnionsDemo


// Generic discriminated unions: the payload type is a parameter of the union.
// Result<T> is the canonical example — Success carries a T, Failure carries why.
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

union Option<T> {
    Some { value: T }
    None { }
}

// Type arguments go after the case name at construction time...
func ParsePositive(input: int): Result<int> {
    if input > 0 {
        return new Result.Success<int> { value: input }
    }
    return new Result.Failure<int> { error: $"{input} is not positive" }
}

// ...or are inferred from the expected type for payload-free cases.
func FirstAbove(items: int[], threshold: int): Option<int> {
    for item in items {
        if item > threshold {
            return new Option.Some<int> { value: item }
        }
    }
    return new Option.None
}

// Patterns never repeat the type arguments — they come from the scrutinee.
func Describe(result: Result<int>): string {
    return match result {
        Result.Success { value } => $"Got {value}",
        Result.Failure { error } => $"Error: {error}"
    }
}

func Main() {
    print "=== Generic Unions Demo ==="

    print Describe(ParsePositive(42))
    print Describe(ParsePositive(-1))

    items := [1, 5, 9, 12]
    found := match FirstAbove(items, 8) {
        Option.Some { value } => $"First above 8: {value}",
        Option.None => "Nothing above 8"
    }
    print found

    missing := match FirstAbove(items, 100) {
        Option.Some { value } => $"First above 100: {value}",
        Option.None => "Nothing above 100"
    }
    print missing

    // Each instantiation is its own closed type: Result<string> alongside Result<int>.
    greeting := new Result.Success<string> { value: "hello" }
    message := match greeting {
        Result.Success { value } => value + "!",
        Result.Failure { error } => error
    }
    print message
}
