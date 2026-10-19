namespace NSharpLang.Compiler.Columnar

// THE SHAPES A PARAMETER DEFAULT IS CAPTURED IN, by token kind (`Token.nl`'s ordinals): 0 identifier,
// 1 integer, 2 floating, 3 character, 4 string, 34 `default`, 44/45 `true`/`false`, 46 `null`,
// 88 `+`, 89 `-`, 90 `*`, 107 `&`, 108 `|`, 110 `~`, 111 `<<`, 124 `.`, 127/128 parentheses.
func DefaultKindOf(kinds: int[]): int {
    return ParameterDefaultConstantKind(kinds, 0, kinds.Length)
}

test "a single literal or keyword default is captured as its own token kind" {
    assert DefaultKindOf([1]) == 1
    assert DefaultKindOf([3]) == 3
    assert DefaultKindOf([34]) == 34
    assert DefaultKindOf([46]) == 46
}

test "a signed numeric literal is captured as the literal's kind" {
    assert DefaultKindOf([89, 1]) == 1
    assert DefaultKindOf([89, 2]) == 2
    assert DefaultKindOf([89, 3]) == ParameterDefaultConstantExpressionKind()
}

test "an expression over literals and member names is captured as a constant expression" {
    assert DefaultKindOf([1, 90, 1]) == ParameterDefaultConstantExpressionKind()
    assert DefaultKindOf([127, 1, 111, 1, 128, 89, 1]) == ParameterDefaultConstantExpressionKind()
    assert DefaultKindOf([0, 124, 0, 108, 0, 124, 0]) == ParameterDefaultConstantExpressionKind()
    assert DefaultKindOf([110, 0, 124, 0]) == ParameterDefaultConstantExpressionKind()
}

// The capture is deliberately permissive about WHICH names and parentheses appear: a call such as
// `Size()` is captured too, because the analyzer has already refused it (NL410) before emission is
// reached. What the capture refuses is a token no constant can contain, such as `new`.
test "a lone member name, a new expression or an empty span is not a constant expression" {
    assert DefaultKindOf([0, 124, 0]) == -1
    assert DefaultKindOf([41, 0, 127, 128]) == -1
    assert ParameterDefaultConstantKind([1], 0, 0) == -1
}
