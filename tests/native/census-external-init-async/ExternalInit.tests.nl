namespace NSharpLang.CensusExternalInitAsync.Tests

test "two external init-only initializers compile in a synchronous function" {
    assert BuildSync() == 34
}

test "two external init-only initializers of different types compile in an async function" {
    assert await BuildTwoInAsync() == 35
}

test "one external init-only initializer compiles in an async function" {
    assert await BuildOneInAsync() == 3
}

test "two initializers of one external type compile in an async function" {
    assert await BuildSameTypeTwiceInAsync() == 56
}

test "external init-only initializers nested in a collection literal compile in an async function" {
    assert await BuildNestedInListInAsync() == 22
}
