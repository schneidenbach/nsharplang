namespace NSharpLang.CensusEmitShapes.Tests


// `T?[]` IS A LOCAL'S ANNOTATION LIKE ANY OTHER.
//
// The lexer folds the `?` and `[` of `string?[]` into ONE `?[` token — the null-conditional indexer's
// spelling — and the delimiter walk that reads a typed local's annotation counted only `[`. It
// therefore saw the closing `]` with nothing open, drove its depth negative and refused the whole
// FUNCTION, while the same spelling in a parameter or a return type, which the type kernel scans,
// parsed. Both spellings the nullability rules give are here: `string?[]` is an array whose ELEMENTS
// may be null, and `string[]?` is an array reference that may itself be null.
func WidenElements(values: string[]): int {
    widened: string?[] = values
    return widened.Length
}

func CountNonNull(values: string?[]): int {
    total := 0
    for value in values {
        if value != null {
            total = total + 1
        }
    }
    return total
}

func ElementsOrEmpty(values: string?[]): string {
    joined := ""
    for value in values {
        joined = joined + (value ?? "-")
    }
    return joined
}

func NullableArrayLocal(values: string[]): int {
    maybe: string[]? = values
    if maybe == null {
        return -1
    }
    return maybe.Length
}

// The loop variable's annotation is delimited by the same structural walk, at its `in` rather than
// at its `=`, so the same spelling has to read the same way there.
func FirstNonNull(rows: string?[][]): int {
    seen := 0
    for row: string?[] in rows {
        seen = seen + CountNonNull(row)
    }
    return seen
}
