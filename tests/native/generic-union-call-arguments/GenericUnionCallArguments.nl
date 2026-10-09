namespace NSharpLang.GenericUnionCallArguments.Tests

import System.Collections.Generic

union Option<T> {
    Some { value: T }
    None
}

union Result<T, E> {
    Ok { value: T }
    Error { error: E }
}

class ResultEnvelope {
    Value: Result<int, string>

    constructor(value: Result<int, string>) {
        Value = value
    }
}

func AcceptIntResult(result: Result<int, string>): int {
    return match result {
        Result.Ok { value } => value,
        Result.Error { error } => -1
    }
}

func AcceptNestedResult(result: Result<Option<int>, string>): int {
    return match result {
        Result.Ok { value: Option.Some { value } } => value,
        Result.Ok { value: Option.None } => 0,
        Result.Error { error } => -1
    }
}

func Forward<T>(_seed: T, result: Result<T, string>): Result<T, string> {
    return result
}

func ForwardUnionFirst<T>(result: Result<T, string>, _seed: T): Result<T, string> {
    return result
}

func BuildWrappedResult(): Result<int, string> {
    wrapped := new ResultEnvelope(new Result.Ok { value: 23 })
    return wrapped.Value
}

func BuildCallResult(): int {
    return AcceptIntResult(new Result.Ok { value: 29 })
}

func BuildNestedResult(): Result<Option<int>, string> {
    return new Result.Ok { value: new Option.Some { value: 31 } }
}

func BuildResultCollection(): List<Result<Option<int>, string>> {
    return [
        new Result.Ok { value: new Option.Some { value: 41 } },
        new Result.Error { error: "missing" }
    ]
}
