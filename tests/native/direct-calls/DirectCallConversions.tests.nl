namespace NSharpLang.DirectCalls.Tests

test "fixed-arity product calls preserve admitted numeric widening" {
    intValue := 2
    longValue := 3L
    singleValue := 4.0f

    assert DirectStaticCalls.Scale(2) == 4.0
    assert DirectStaticCalls.Scale(intValue) == 4.0
    assert DirectStaticCalls.Scale(longValue) == 6.0
    assert DirectStaticCalls.Scale(singleValue) == 8.0
}

test "fixed-arity product calls lower target-typed nullable and null arguments" {
    nullableValue: int? = 6

    assert DirectNullableValue(7) == 31
    assert DirectNullableIdentity(nullableValue) == 31
    assert DirectNullableNull() == 31
    assert DirectWidenedNullable(8) == 32
    assert DirectSmallNullableLiteral() == 37
    assert DirectReferenceNull() == 33
}

test "fixed-arity product calls construct span and anonymous-union arguments" {
    values := [1, 2, 3]

    assert DirectSpan(values) == 34
    assert DirectReadOnlySpan(values) == 35
    assert DirectUnionInt(4) == 36
    assert DirectUnionString("arm") == 36
}

test "fixed-arity product calls invoke exact source implicit conversions" {
    assert DirectImplicit(2) == 42
}
