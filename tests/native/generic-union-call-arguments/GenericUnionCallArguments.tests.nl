namespace NSharpLang.GenericUnionCallArguments.Tests

test "a generic union case adopts a non-generic call parameter" {
    assert AcceptIntResult(new Result.Ok { value: 11 }) == 11
    assert AcceptIntResult(new Result.Ok(13)) == 13
    assert AcceptIntResult(new Result.Error { error: "bad" }) == -1
}

test "generic call inference closes a union argument from another argument" {
    forwarded := Forward(7, new Result.Ok { value: 17 })
    assert AcceptIntResult(forwarded) == 17
    assert BuildCallResult() == 29
}

test "generic call inference is independent of argument order" {
    forwarded := ForwardUnionFirst(new Result.Ok { value: 19 }, 7)
    assert AcceptIntResult(forwarded) == 19
}

test "generic union cases adopt constructor parameter types" {
    assert AcceptIntResult(BuildWrappedResult()) == 23
}

test "nested generic union cases adopt return and payload types" {
    assert AcceptNestedResult(BuildNestedResult()) == 31
}

test "nested generic union cases adopt collection element types" {
    values := BuildResultCollection()
    assert values.Count == 2
    assert AcceptNestedResult(values[0]) == 41
    assert AcceptNestedResult(values[1]) == -1
}
