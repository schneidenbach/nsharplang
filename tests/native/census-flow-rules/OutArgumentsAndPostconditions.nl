namespace NSharpLang.CensusFlowRules.Tests

import System.Collections.Generic
import System.Diagnostics.CodeAnalysis


// CENSUS §FLOW3 — WHAT A CALL LEAVES BEHIND, AND WHOSE NULLABILITY DECIDES IT.
//
// AN `out` ARGUMENT'S INCOMING NULLABILITY IS NOT PART OF THE CONTRACT. The callee assigns the
// variable before it returns and never reads what was there, so a `string?` variable is a legal
// `out string` argument and holds a non-null string once the call returns. N# used to refuse that
// outright — "Cannot pass `&string?` as argument for parameter of type `&string`" — which is why a
// mechanically converted `invalid: string? = default` followed by `tryGet(..., out invalid)`
// produced a diagnostic per site and then a second one on the `return invalid` that followed.
//
// A `ref` ARGUMENT IS THE OPPOSITE and still has to match, because the callee can READ it; that
// direction is a diagnostic and is pinned in the estate beside the assignability owner.
//
// AND SOME SIGNATURES SAY MORE THAN THEIR TYPES CAN. `Dictionary<K, V>.TryGetValue` hands back a
// value that is present only when it answered TRUE, and `string.IsNullOrEmpty` proves its argument
// non-null in the branch where it answered FALSE. Both are written as nullability postcondition
// attributes, and N# now reads them off reflected metadata AND off its own source declarations —
// every function below that declares one is exercised through the branch the attribute names, with
// the value actually dereferenced, so a rule that narrowed the wrong branch throws.
class Entry {
    Label: string

    constructor(label: string) {
        Label = label
    }
}

// ── `out` and the declared nullability of the parameter ────────────────────────────────────────

// The parameter is non-nullable, so the variable holds a non-null string afterwards — whatever it
// was declared as.
func TrySplit(text: string, out head: string, out tail: string): bool {
    index := text.IndexOf(' ')
    if index < 0 {
        head = text
        tail = ""
        return false
    }

    head = text.Substring(0, index)
    tail = text.Substring(index + 1)
    return true
}

func HeadOrEmpty(text: string): string {
    head: string? = default
    tail: string? = default
    if !TrySplit(text, out head, out tail) {
        return head
    }

    return head + "|" + tail
}

// The parameter is NULLABLE, so the variable is maybe-null afterwards and the caller has to check.
func TryFindEntry(entries: List<Entry>, label: string, out found: Entry?): bool {
    for entry in entries {
        if entry.Label == label {
            found = entry
            return true
        }
    }

    found = null
    return false
}

func FoundLabelOrNone(entries: List<Entry>, label: string): string {
    found: Entry? = default
    TryFindEntry(entries, label, out found)
    if found == null {
        return "none"
    }

    return found.Label
}

// ── source-declared postcondition attributes ───────────────────────────────────────────────────

// `[NotNullWhen(true)]` on a nullable `out`: present in the TRUE branch, maybe-null in the false one.
func TryLookup(entries: List<Entry>, label: string, [NotNullWhen(true)] out found: Entry?): bool {
    for entry in entries {
        if entry.Label == label {
            found = entry
            return true
        }
    }

    found = null
    return false
}

func LookupLabelOrNone(entries: List<Entry>, label: string): string {
    found: Entry? = default
    if TryLookup(entries, label, out found) {
        return found.Label
    }

    return "none"
}

// The same attribute read through a GUARD, which is where the converted CLI spells it.
func LookupLabelGuarded(entries: List<Entry>, label: string): string {
    found: Entry? = default
    if !TryLookup(entries, label, out found) {
        return "none"
    }

    return found.Label
}

// `[NotNull]` on an input parameter is the `Assert.NotNull` guarantee: not-null once the call
// returns, on every path.
func RequireEntry([NotNull] entry: Entry?) {
    if entry == null {
        throw new System.InvalidOperationException("entry is null")
    }
}

func RequiredLabel(entry: Entry?): string {
    RequireEntry(entry)
    return entry.Label
}

// `[MaybeNullWhen(true)]` names the other branch, and the branch it does not name keeps the
// declaration's own answer — a non-nullable `out`, so not-null.
func TryMiss(entries: List<Entry>, label: string, [MaybeNullWhen(true)] out missing: Entry): bool {
    for entry in entries {
        if entry.Label == label {
            missing = entry
            return false
        }
    }

    missing = new Entry("<none>")
    return true
}

func MissLabel(entries: List<Entry>, label: string): string {
    missing: Entry? = default
    if TryMiss(entries, label, out missing) {
        return "missed"
    }

    return missing.Label
}

// ── reflected postcondition attributes ─────────────────────────────────────────────────────────

// `Dictionary<K, V>.TryGetValue` is `[MaybeNullWhen(false)] out TValue`.
func DictionaryLabel(map: Dictionary<string, Entry>, key: string): string {
    found: Entry? = default
    if map.TryGetValue(key, out found) {
        return found.Label
    }

    return "none"
}

// The same call reached through an `&&` chain, which is the shape the converted LanguageServer uses.
func DictionaryLabelGuarded(map: Dictionary<string, Entry>?, key: string): string {
    found: Entry? = default
    if map != null && map.TryGetValue(key, out found) {
        return found.Label
    }

    return "none"
}

// And through a negated guard, whose surviving flow is the true branch's facts.
func DictionaryLabelInverted(map: Dictionary<string, Entry>, key: string): string {
    found: Entry? = default
    if !map.TryGetValue(key, out found) {
        return "none"
    }

    return found.Label
}

// `string.IsNullOrEmpty` is `[NotNullWhen(false)]`: the FALSE branch proves the argument non-null.
func TextLengthOrZero(text: string?): int {
    if string.IsNullOrEmpty(text) {
        return 0
    }

    return text.Length
}

func TextLengthOrZeroInverted(text: string?): int {
    if !string.IsNullOrWhiteSpace(text) {
        return text.Length
    }

    return 0
}

// `[NotNullIfNotNull("path")]` ON A RETURN. `Path.GetFileName` is declared `string?` and is null only
// when its argument is, so the call's result is as null as the argument was.
func FileNameOf(path: string): string {
    return System.IO.Path.GetFileName(path)
}

func FileNameOfMaybe(path: string?): string {
    return System.IO.Path.GetFileName(path) ?? "<none>"
}

// ── `!` over a nullable value type ─────────────────────────────────────────────────────────────

// `!x.HasValue` and `!(x != null)` are the two spellings a converter leaves behind, and both narrow
// the flow that survives the guard.
func TimeoutOrDefault(timeoutMs: int?): int {
    if !timeoutMs.HasValue {
        return 30
    }

    return timeoutMs.Value
}

func TimeoutOrDefaultUnwrapped(timeoutMs: int?): int {
    if !(timeoutMs != null) {
        return 30
    }

    return must timeoutMs
}
