namespace Census.FreeFunctionIdentity.X

import System
import System.Collections.Generic


// THE X HALF OF THE (NAMESPACE, NAME) PAIR. Every name in this file has a same-named twin in
// `HelpersY.nl`, which is the whole point: two namespaces may each declare `Helper`, and a bare
// `Helper()` written HERE has to reach this one.
func Helper(): string {
    return "X"
}

// A camelCase free function is NAMESPACE-private: every file of `X` may reach it and no other
// namespace can, and `HelpersY.nl` declares one with the same spelling for `Y`.
func helper(): string {
    return "x"
}

func UseHelperFromX(): string {
    return Helper()
}

func UseCamelHelperFromX(): string {
    return helper()
}

// A method group over a same-named function: the delegate has to be made over THIS `Helper`.
func HelperGroupFromX(): Func<string> {
    return Helper
}

// A named-tuple return, so the per-namespace map of return element labels is exercised too: `X` and
// `Y` label their halves differently on purpose.
func Split(): (Head: string, Tail: string) {
    return ("X-head", "X-tail")
}

func SplitHeadFromX(): string {
    parts := Split()
    return parts.Head
}

// A body that declares local functions still resolves its bare SIBLING calls through its own
// namespace: the local-function tier is a different map, and adding one must not put the wrong
// `Helper` back in reach.
func LocalAndSiblingFromX(): string {
    func Marker(): string {
        return "x-local"
    }

    return Marker() + "/" + Helper()
}

// An ITERATOR shares its function's name with the one in `Y`, and its state machine is named after
// that function — so the two namespaces' machines must not collide either.
func* Steps(): IEnumerable<int> {
    yield 1
    yield 2
}

func StepSumFromX(): int {
    total := 0
    for value in Steps() {
        total = total + value
    }
    return total
}

// The marker the metadata assertions reflect the assembly out of.
class XMarker {
    Name: string

    constructor() {
        Name = "X"
    }
}
