namespace NSharpLang.CensusConversions.Tests

// CENSUS §CONV/2 — AN ARRAY LITERAL TAKES ITS SHAPE FROM THE POSITION IT IS WRITTEN IN.
//
// `["a", ["b", "c"]]` into an `object[]` reported "All elements in an array must be the same type —
// the first element is 'string' but I found 'string[]'". Where a target element type is KNOWN, C#'s
// rule for `new object[] { "a", new[] { "b" } }` applies instead: each element converts to it —
// boxing a value type, widening a reference, crossing an array by covariance, accepting `null` — and
// the literal's type is the TARGET's, whatever the elements happen to be. Where no target exists, the
// first element still decides and every later one must fit it.
//
// The functions below write the same heterogeneous literal into every position that names an element
// type. The tests read the elements back, because a literal that produced the wrong element type
// would still have the right LENGTH.
class Holder {
    Values: object[] = ["field", 2, null]
}

// The annotated local.
func FromAnnotatedLocal(): object[] {
    values: object[] = ["local", 1, ["nested"], null]
    return values
}

// The return position.
func FromReturn(): object[] {
    return ["return", 2, ["nested"], null]
}

func CountValues(values: object[]): int {
    return values.Length
}

func FirstOfValues(values: object[]): object {
    return values[0]
}

// The argument position. Planning an argument has no target type of its own, so this literal used to
// be inferred from its first element and the whole CALL was declined.
func FromArgument(): int {
    return CountValues(["argument", 3, ["nested"], null])
}

func FromArgumentFirst(): object {
    return FirstOfValues(["argument", 3])
}

// A `params` array written as one literal is the array itself — the normal form — rather than one
// expanded element of it.
func CountParams(params values: object[]): int {
    return values.Length
}

func FromParamsLiteral(): int {
    return CountParams(["params", 4, null])
}

func FromParamsExpanded(): int {
    return CountParams("params", 4)
}

// A `string[]` argument to a `params object[]` is the array itself too, now that `string[]` converts
// to `object[]`: two elements, not one array wrapped in a one-element array.
func FromParamsStringArray(names: string[]): int {
    return CountParams(names)
}

// The field initializer.
func FromField(): object[] {
    holder := new Holder()
    return holder.Values
}

// AND WHERE THERE IS NO TARGET, NOTHING CHANGES: the first element decides, so this literal is an
// `int[]` and its elements are not boxed.
func InferredElementTypeName(): string {
    inferred := [1, 2, 3]
    boxed: object = inferred
    return boxed.GetType().ToString() ?? ""
}
