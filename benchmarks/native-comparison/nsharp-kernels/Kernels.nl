namespace NSharpLang.NativeComparison


// THE SIX MEASURED KERNELS, PINNED BYTE-FOR-BYTE AGAINST THE RUST AND C PORTS BESIDE THEM.
//
// Each body is the exact loop the `<workload>/main.rs` and `<workload>/main.c` ports in the parent
// directory transcribe, so a number produced here and a number produced there are answers to the same
// question. The bodies are recovered verbatim from the C#-era benchmark source deleted at a50cb4000
// (`benchmarks/SystemsHotPathBenchmarks.cs`); nothing in them may be "improved".
//
// WHY VERBATIM IS A HARD CONSTRAINT AND NOT A STYLE PREFERENCE. The columnar vectorizer matches these
// exact SHAPES — `len := values.Length` hoisted before the loop, `for i := 0; i < len; i++`, a
// `value := values[i]` temp, `count = count + 1` rather than `count++` — and rewrites four of them into
// `SimdReductions` calls. The match is on the loop's form and not on `[hot]`, which is a policy marker
// with no codegen effect, so reshaping a loop silently drops it back to the scalar path and the
// comparison against LLVM/clang stops measuring what it claims to measure. `IlShape.nl` reads the
// emitted IL back at run time so that this claim is checked rather than asserted.
//
// WHY A CLASS AND WHY PASCALCASE. camelCase is file-private in N#, and `Program.nl` and `IlShape.nl`
// both need these six. PascalCase members of a class are public, which is also what gives `IlShape.nl`
// a `typeof` receiver to start its reflection from; free functions land in a synthesised holder whose
// name is not part of any contract.
//
// WHY THE PROJECT IS `systems: audit` AND NOT `strict`. Under `strict` each `values[i]` here is an
// NSYS120 error — "index access in [hot] requires a proven bounds guard or allow(trap)" — and the two
// ways out are both closed. A bounds proof would mean rewriting the loops, which is the one thing this
// file may not do; and `[allow(trap, owner: ..., reason: ...)]` does not survive `nlc format`, which
// rewrites its named arguments to `owner = ...` and leaves source that no longer passes `nlc check`.
// The ports keep their bounds checks too (Rust indexes safely, C indexes naturally), so the trap is
// part of the measured shape rather than something to prove away; `audit` reports it and continues.
class Kernels {
    [hot]
    static func Checksum(values: int[]): int {
        sum := 0
        len := values.Length
        for i := 0; i < len; i++ {
            sum = sum + values[i]
        }

        return sum
    }

    [hot]
    static func CountAscii(values: int[]): int {
        count := 0
        len := values.Length
        for i := 0; i < len; i++ {
            value := values[i]
            if value >= 32 && value <= 126 {
                count = count + 1
            }
        }

        return count
    }

    [hot]
    static func MinMaxDelta(values: int[]): int {
        if values.Length == 0 {
            return 0
        }

        min := values[0]
        max := values[0]
        len := values.Length
        for i := 1; i < len; i++ {
            value := values[i]
            if value < min {
                min = value
            }

            if value > max {
                max = value
            }
        }

        return max - min
    }

    [hot]
    static func RollingHash(values: int[]): int {
        hash := 17
        len := values.Length
        for i := 0; i < len; i++ {
            hash = ((hash * 31) + values[i]) & 65535
        }

        return hash
    }

    [hot]
    static func ParseEightDigits(values: int[]): int {
        if values.Length < 8 {
            return -1
        }

        parsed := 0
        for i := 0; i < 8; i++ {
            value := values[i]
            if value < 48 || value > 57 {
                return -1
            }

            parsed = parsed * 10 + (value - 48)
        }

        return parsed
    }

    [hot]
    static func CountTransitions(values: int[]): int {
        if values.Length == 0 {
            return 0
        }

        transitions := 0
        previous := values[0]
        len := values.Length
        for i := 1; i < len; i++ {
            current := values[i]
            if current != previous {
                transitions = transitions + 1
            }

            previous = current
        }

        return transitions
    }
}
