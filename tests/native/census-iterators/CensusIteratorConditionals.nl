namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic
import System.Threading.Tasks


// `??`, THE TERNARY AND `throw` AS AN EXPRESSION, INSIDE A GENERATOR.
//
// All three are BRANCH-MERGES rather than arithmetic, and until this slice only the emitter knew how
// to lower them — so an iterator body, which plans every value through the plan-IR, declined them.
// They now have ONE owner (`ColumnarConditionalPlanner` plus `ColumnarThrowExpressionPlanner`), which
// is why a plain `func`, a `func*` and an `async func*` all produce the same answers below.
//
// The throw arm is the shape that makes the merge interesting: it produces NO value, so the whole
// expression is worth the OTHER side — `x ?? throw e` is worth `x` with its nullability removed, and
// `cond ? v : throw e` is worth `v`.

// A REFERENCE `??` inside a generator: the non-null left is the result and the fallback never runs.
func* CoalescedNames(names: string?[]): IEnumerable<string> {
    for i := 0; i < names.Length; i += 1 {
        yield names[i] ?? "(none)"
    }
}

// A `Nullable<T>` `??`: the result is the ELEMENT type, so this yields `int` and not `int?`.
func* CoalescedCounts(counts: int?[]): IEnumerable<int> {
    for i := 0; i < counts.Length; i += 1 {
        yield counts[i] ?? -1
    }
}

// A TERNARY whose arms are both ordinary values.
func* Labelled(values: int[]): IEnumerable<string> {
    for i := 0; i < values.Length; i += 1 {
        yield values[i] > 0 ? "positive" : "other"
    }
}

// `x ?? throw e` — the reference form. The absent element raises from the `MoveNext` that reaches it,
// and the elements before it have already been produced.
func* RequiredNames(names: string?[]): IEnumerable<string> {
    for i := 0; i < names.Length; i += 1 {
        yield names[i] ?? throw new InvalidOperationException("name " + i.ToString() + " is absent")
    }
}

// `n ?? throw e` — the `Nullable<T>` form, whose present path unwraps with `GetValueOrDefault()`.
func* RequiredCounts(counts: int?[]): IEnumerable<int> {
    for i := 0; i < counts.Length; i += 1 {
        yield counts[i] ?? throw new InvalidOperationException("count " + i.ToString() + " is absent")
    }
}

// `cond ? v : throw e` — a throwing conditional arm, and the fallback side is the one that raises.
func* CheckedValues(values: int[]): IEnumerable<int> {
    for i := 0; i < values.Length; i += 1 {
        yield values[i] >= 0 ? values[i] : throw new ArgumentOutOfRangeException("values")
    }
}

// A THROWING THEN-ARM, so the merge is reached from the else side instead.
func* RejectedValues(values: int[]): IEnumerable<int> {
    for i := 0; i < values.Length; i += 1 {
        yield values[i] < 0 ? throw new ArgumentOutOfRangeException("values") : values[i] * 2
    }
}

// `??` CHAINED — right-associative, so the second fallback is reached only when both are absent.
func* FirstPresent(a: string?, b: string?): IEnumerable<string> {
    yield a ?? b ?? "(neither)"
}

// A `??` HOISTED INTO A LOCAL, so the machine stores the merged value in one of its own fields.
func* MergedThroughLocal(name: string?, count: int?): IEnumerable<string> {
    resolved := name ?? "anonymous"
    total := count ?? 0
    yield resolved
    yield total.ToString()
}

// A `??` OVER A TYPE PARAMETER: the nullness question is asked of the boxed value while the result
// stays `T`, so a value-type instantiation always takes the left branch.
func* OrElse<T>(value: T, fallback: T): IEnumerable<T> {
    yield value ?? fallback
}

// THE SAME THREE FORMS INSIDE AN `async func*`, which shares the plan-IR owner with the synchronous
// machine — the whole point of putting them on the plan side.
async func* CoalescedAsync(names: string?[]): IAsyncEnumerable<string> {
    for i := 0; i < names.Length; i += 1 {
        await Task.Delay(1)
        yield names[i] ?? "(none)"
    }
}

async func* RequiredAsync(names: string?[]): IAsyncEnumerable<string> {
    for i := 0; i < names.Length; i += 1 {
        await Task.Delay(1)
        yield names[i] ?? throw new InvalidOperationException("absent")
    }
}

async func* LabelledAsync(values: int[]): IAsyncEnumerable<string> {
    for i := 0; i < values.Length; i += 1 {
        await Task.Delay(1)
        yield values[i] > 0 ? "positive" : throw new ArgumentOutOfRangeException("values")
    }
}

// THE PLAIN-BODY ANSWERS, so the tests can assert that one lowering serves all three body shapes.
func PlainCoalesce(name: string?): string {
    return name ?? "(none)"
}

func PlainNullableCoalesce(count: int?): int {
    return count ?? -1
}

func PlainRequired(name: string?): string {
    return name ?? throw new InvalidOperationException("absent")
}

func PlainCheckedTernary(value: int): int {
    return value >= 0 ? value : throw new ArgumentOutOfRangeException("value")
}

// A `??` WHOSE FALLBACK IS ITSELF NULL, which keeps the annotation and produces the left unchanged.
func PlainCoalesceNull(name: string?): string? {
    return name ?? null
}

// A LAZINESS WITNESS: the fallback side of a `??` runs only when the left is absent, and nothing at
// all runs until the sequence is enumerated.
func* TracedCoalesce(trace: CensusTrace, name: string?): IEnumerable<string> {
    trace.Add("start")
    yield name ?? Fallback(trace)
    trace.Add("end")
}

func Fallback(trace: CensusTrace): string {
    trace.Add("fallback")
    return "(computed)"
}

// A BRANCH-MERGE AS A CALL ARGUMENT. The plan-side owner has lowered all three forms in every value
// position since the previous slice, but the call owner's SYNTAX PREFLIGHT — the gate that types an
// argument before the call is claimed — knew nothing about them, so `list.Add(flag ? "a" : "b")`
// inside a `func*` declined the whole generator. In a plain body the same refusal was invisible: the
// call fell back to the legacy emitter arm, which has its own lowering. These are the shapes that
// separated the two.
func* TernaryArgument(flags: bool[], sink: List<string>): IEnumerable<int> {
    for i := 0; i < flags.Length; i += 1 {
        sink.Add(flags[i] ? "yes" : "no")
        yield sink.Count
    }
}

// The condition is itself a short-circuit over a comparison, so the operand surface the gate admits
// has to be the WIDE one the conditional owner actually plans its operands through.
func* CompoundConditionArgument(values: int[], sink: List<string>): IEnumerable<int> {
    for i := 0; i < values.Length; i += 1 {
        sink.Add(values[i] > 0 && values[i] < 10 ? "small" : "other")
        yield sink.Count
    }
}

// A REFERENCE `??` as an argument. Its lowering is `dup; brtrue; pop; <fallback>`, and `pop` is a
// method-body opcode — the reason the argument's TYPE is discovered through a method-body scratch.
func* CoalescedArgument(names: string?[], sink: List<string>): IEnumerable<int> {
    for i := 0; i < names.Length; i += 1 {
        sink.Add(names[i] ?? "(none)")
        yield sink.Count
    }
}

// A `Nullable<T>` `??` as an argument: the argument's type is the ELEMENT type.
func* CoalescedNullableArgument(counts: int?[], sink: List<int>): IEnumerable<int> {
    for i := 0; i < counts.Length; i += 1 {
        sink.Add(counts[i] ?? -1)
        yield sink.Count
    }
}

// `&&` and `||` as arguments in their own right, where the argument IS the Boolean.
func* ShortCircuitArgument(left: bool[], right: bool[], sink: List<bool>): IEnumerable<int> {
    for i := 0; i < left.Length; i += 1 {
        sink.Add(left[i] && right[i])
        sink.Add(left[i] || right[i])
        yield sink.Count
    }
}

// A BRANCH-MERGE AS A RECEIVER, which types through the same seam an argument does.
func* TernaryReceiver(flags: bool[]): IEnumerable<string> {
    for i := 0; i < flags.Length; i += 1 {
        yield (flags[i] ? "alpha" : "beta").ToUpperInvariant()
    }
}

// A NESTED branch-merge: the argument of a call that is itself an argument.
func* NestedBranchArgument(values: int[], sink: List<string>): IEnumerable<int> {
    for i := 0; i < values.Length; i += 1 {
        sink.Add(Tagged(values[i] > 0 ? "p" : "n"))
        yield sink.Count
    }
}

func Tagged(label: string): string {
    return "[" + label + "]"
}

// A SHORT-CIRCUIT ARGUMENT IS STILL LAZY: the right operand runs only when the left does not decide.
func* TracedShortCircuitArgument(trace: CensusTrace, flag: bool, sink: List<bool>): IEnumerable<int> {
    sink.Add(flag && Records(trace))
    yield sink.Count
}

func Records(trace: CensusTrace): bool {
    trace.Add("right")
    return true
}
