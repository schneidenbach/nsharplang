// Result/error pattern matching demo used by the pattern matching guide.
// It intentionally uses unconstrained union arms for exhaustiveness and nested
// union-property arms where the inner union cases prove the outer case coverage.
union Option {
    Some { value: int }
    None
}

union Result {
    Success { value: int }
    Failure { error: string, code: int }
}

union Response {
    Ok { data: Option }
    Error { message: string }
}

func DescribeResult(result: Result): string {
    return match result {
        Result.Success { value } => $"Success: {value}",
        Result.Failure { error, code } => $"Error {code}: {error}"
    }
}

func ExtractResponse(response: Response): int {
    return match response {
        Response.Ok { data: Option.Some { value } } => value,
        Response.Ok { data: Option.None } => 0,
        Response.Error { message } => 0
    }
}

func Main() {
    success := new Result.Success(42)
    failure := new Result.Failure("not found", 404)
    withValue := new Response.Ok(new Option.Some(7))
    withoutValue := new Response.Ok(new Option.None())

    print DescribeResult(success)
    print DescribeResult(failure)
    print $"Response with value: {ExtractResponse(withValue)}"
    print $"Response without value: {ExtractResponse(withoutValue)}"
}
