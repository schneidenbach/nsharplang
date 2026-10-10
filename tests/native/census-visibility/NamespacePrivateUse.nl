namespace NSharpLang.CensusVisibility.Tests

import System
import System.Collections.Generic
import System.Linq


// FILE TWO OF TWO, and the whole point of the project: not one line here imports, qualifies or
// re-declares anything. `formatTypeRef`, `shoutTypeRef` and `helperBox` are all declared in
// `NamespacePrivateHelpers.nl`, and every one of them is camelCase.
//
// Before the 2026-09-02 ruling was implemented at the function channel, the DIRECT CALL below
// reported NL412 "Function 'formatTypeRef' not found" and the METHOD GROUP reported NL402 plus
// NL301, while `helperBox` in the same file already resolved — the type half of the rule was right
// and the function half was not.

// A direct call across the file boundary.
func DescribeAcrossFiles(t: string): string {
    return formatTypeRef(t)
}

// A METHOD GROUP across the file boundary: the name is converted to a delegate rather than called.
func DescribeAllAcrossFiles(names: List<string>): List<string> {
    return names.Select(formatTypeRef).ToList()
}

// The SECOND namespace-private function of the same shape, so the delegate the group builds is
// selected by the name written and not by there being only one candidate.
func ShoutAllAcrossFiles(names: List<string>): List<string> {
    return names.Select(shoutTypeRef).ToList()
}

// The same name stored in a delegate-typed local first, which is the other shape a method group
// reaches the emitter in.
func DescribeViaDelegate(t: string): string {
    formatter: Func<string, string> = formatTypeRef
    return formatter(t)
}

// The type half, constructed and used across the same boundary.
func BoxAcrossFiles(value: string): string {
    box := new helperBox(value)
    return box.Describe()
}
