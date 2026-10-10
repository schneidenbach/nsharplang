namespace Census.FreeFunctions

import System

// THE ENCLOSING NAMESPACE'S FREE FUNCTIONS. A consumer in `Census.FreeFunctions.Consumer` reaches
// these with no import: `Census.FreeFunctions` encloses it, and an enclosing namespace's members are
// in scope wherever they were compiled.
func Twice(value: int): int => value * 2

// A defaulted parameter, omitted or named at the call site.
func Describe(value: int, suffix: string = "units"): string => value.ToString() + " " + suffix

// An `out` parameter.
func TryParseCount(text: string, out value: int): bool {
    return Int32.TryParse(text, out value)
}

// The lexically nearer answer: a consumer that also imports a SOURCE `Nearest` must still bind this.
func Nearest(): string => "enclosing-referenced"

// Not exported: a camelCase free function is emitted CLR `assembly`, so no other assembly reaches it.
func hiddenHelper(): int => 7
