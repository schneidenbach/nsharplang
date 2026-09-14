namespace NSharpLang.CensusEmitShapes.Tests


// THE COMMON TYPE OF A CONDITIONAL IS WHAT BOTH ARMS ARE AT ONCE. The rule used to be reference
// identity for everything that was not numeric, so two SEPARATELY CONSTRUCTED answers for one type —
// an interpolated string beside a plain `string`, a field read beside a call result — came back
// `unknown` and every use of the result reported against a type the conditional plainly had.
func Outcome(code: int, stderr: string): (bool, string) {
    return (false, string.IsNullOrWhiteSpace(stderr) ? $"exited {code}" : stderr)
}

func Describe(flag: bool, name: string): string {
    return flag ? $"<{name}>" : name
}

// The two arms differ only in NULLABILITY, so the conditional is the nullable one: the non-null arm
// converts to it and the reverse does not.
func Maybe(flag: bool, name: string, other: string?): string? {
    return flag ? name : other
}
