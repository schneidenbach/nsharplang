namespace NSharpLang.Compiler

import System.Collections.Generic

// CONTRACTS FOR THE BINDING-USAGE POLICY KERNEL (020 slice 8).
//
// These came out of `tests/LinterTests.cs`, which is deleted. That file was this kernel's ONLY
// assertion layer anywhere in the repo, and it SAMPLED the policy: four of the eight
// variable rows, three of the four parameter rows, and none of the name predicate. The kernel is
// six pure functions over strings and bools, so the sample is replaced here by the CROSS — every
// row of both truth tables, and the name predicate that both of them delegate to.
//
// WHY THE CROSS MATTERS. `ShouldReportUnusedVariable` and `ShouldReportUnusedParameter` are the two
// gates that decide whether a build FAILS (NL001 and NL012 are both build-blocking errors), and
// each is a conjunction of three independent reasons to stay silent. A sample can pass while any
// one of them is inverted; the cross cannot.

func LbuNames(): List<string> {
    names := new List<string>()
    names.Add("value")
    names.Add("options")
    names.Add("x")
    return names
}

func LbuIntentionalNames(): List<string> {
    names := new List<string>()
    names.Add("_")
    names.Add("_value")
    names.Add("_options")
    names.Add("__x")
    return names
}

// ── the variable gate, crossed ────────────────────────────────────────────────────────────────

test "an ORDINARY name is reported only when it is neither scope-used nor externally used" {
    // The whole 2x2 for a name the convention does not exempt. One row reports; three are silent,
    // and each of the three is silent for its OWN reason.
    for name in LbuNames() {
        assert LinterBindingUsageCore.ShouldReportUnusedVariable(name, false, false)
        assert !LinterBindingUsageCore.ShouldReportUnusedVariable(name, true, false)
        assert !LinterBindingUsageCore.ShouldReportUnusedVariable(name, false, true)
        assert !LinterBindingUsageCore.ShouldReportUnusedVariable(name, true, true)
    }
}

test "an UNDERSCORE-PREFIXED name is never reported, on any of the four rows" {
    // The convention is an unconditional exemption, not a fourth reason weighed against the others.
    for name in LbuIntentionalNames() {
        assert !LinterBindingUsageCore.ShouldReportUnusedVariable(name, false, false)
        assert !LinterBindingUsageCore.ShouldReportUnusedVariable(name, true, false)
        assert !LinterBindingUsageCore.ShouldReportUnusedVariable(name, false, true)
        assert !LinterBindingUsageCore.ShouldReportUnusedVariable(name, true, true)
    }
}

// ── the parameter gate, crossed ───────────────────────────────────────────────────────────────

test "a parameter has ONE use flag, and the same underscore exemption" {
    for name in LbuNames() {
        assert LinterBindingUsageCore.ShouldReportUnusedParameter(name, false)
        assert !LinterBindingUsageCore.ShouldReportUnusedParameter(name, true)
    }

    for intentional in LbuIntentionalNames() {
        assert !LinterBindingUsageCore.ShouldReportUnusedParameter(intentional, false)
        assert !LinterBindingUsageCore.ShouldReportUnusedParameter(intentional, true)
    }
}

// ── the predicate both gates delegate to ──────────────────────────────────────────────────────

test "the intentionally-unused predicate is a LEADING underscore, and the bare underscore" {
    assert LinterBindingUsageCore.IsIntentionallyUnusedName("_")
    assert LinterBindingUsageCore.IsIntentionallyUnusedName("_value")
    assert LinterBindingUsageCore.IsIntentionallyUnusedName("__x")
    assert !LinterBindingUsageCore.IsIntentionallyUnusedName("value")
    assert !LinterBindingUsageCore.IsIntentionallyUnusedName("")
    // A TRAILING or INTERIOR underscore is an ordinary name. The predicate is a prefix test, and
    // the difference is invisible to any sample that only ever asks about `_value`.
    assert !LinterBindingUsageCore.IsIntentionallyUnusedName("value_")
    assert !LinterBindingUsageCore.IsIntentionallyUnusedName("my_value")
}

// ── the four sentences ────────────────────────────────────────────────────────────────────────

test "the unused-variable sentence and its suggestion" {
    assert LinterBindingUsageCore.UnusedVariableMessage("value") == "Variable 'value' is declared but never read"
    assert LinterBindingUsageCore.UnusedVariableMessage("counter") == "Variable 'counter' is declared but never read"
    assert LinterBindingUsageCore.UnusedVariableSuggestion("value").Contains("'_value'")
    assert LinterBindingUsageCore.UnusedVariableSuggestion("value") == "If this is intentional, prefix it with '_' to indicate it's unused: '_value'"
}

test "the unused-parameter sentence names the FUNCTION as well as the parameter" {
    assert LinterBindingUsageCore.UnusedParameterMessage("options", "Run") == "Parameter 'options' in 'Run' is never read — is it needed?"
    assert LinterBindingUsageCore.UnusedParameterMessage("b", "add") == "Parameter 'b' in 'add' is never read — is it needed?"
    assert LinterBindingUsageCore.UnusedParameterSuggestion("options").Contains("'_options'")
    assert LinterBindingUsageCore.UnusedParameterSuggestion("options") == "If the parameter is required by an interface or override, prefix with '_' to suppress this: '_options'"
}
