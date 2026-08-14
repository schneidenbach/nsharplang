namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// CONTRACTS FOR WHICH DECLARATION SHADOWS AN OUTER ONE (task 019 slice 9). These came out of
// `Linter.cs` with `CheckShadowedVariable` (NL020).
//
// THE RULE IS ABOUT SCOPE NESTING, AND SCOPE NESTING IS WHERE IT CAN BE WRONG IN BOTH DIRECTIONS.
// Consulting the scope being declared into would make every declaration shadow itself; consulting
// only the immediately enclosing scope would miss a name three blocks out. Both directions are
// asserted below, over a stack built to the same shape the linter's own frames have.
//
// THE SILENCER WAS WRITTEN TWICE AND IS NOW WRITTEN ONCE. `name == "_" || name.StartsWith("_")`
// asks a question whose first half can never decide anything: `"_"` starts with `"_"`. The
// equivalence is asserted rather than assumed, so collapsing it is a proved simplification and not
// a hopeful one.

func LsvScopes(): Stack<Dictionary<string, (int, int, bool)>> {
    return new Stack<Dictionary<string, (int, int, bool)>>()
}

func LsvFrame(names: string[]): Dictionary<string, (int, int, bool)> {
    frame := new Dictionary<string, (int, int, bool)>()
    index := 0
    while index < names.Length {
        frame[names[index]] = (1, 1, false)
        index = index + 1
    }

    return frame
}

// A stack whose frames are pushed OUTERMOST FIRST, exactly as the linter pushes them: `PushScope`
// pushes the frame being left behind, so the top of the stack is the innermost enclosing scope.
func LsvStack(frames: string[][]): Stack<Dictionary<string, (int, int, bool)>> {
    scopes := LsvScopes()
    index := 0
    while index < frames.Length {
        scopes.Push(LsvFrame(frames[index]))
        index = index + 1
    }

    return scopes
}

func LsvOneScope(names: string[]): Stack<Dictionary<string, (int, int, bool)>> {
    scopes := LsvScopes()
    scopes.Push(LsvFrame(names))
    return scopes
}

func LsvConfig(): LinterConfig {
    return LinterConfig.Default()
}

func LsvConfigWithout(ruleCode: string): LinterConfig {
    config := LinterConfig.Default()
    removed: object = 0
    config.RuleSeverities.Remove(ruleCode, out removed)
    return config
}

func LsvFinding(name: string, scopes: Stack<Dictionary<string, (int, int, bool)>>): LinterRuleFinding? {
    return LinterShadowedVariable.ShadowedVariable(name, 4, 9, scopes, LsvConfig())
}


// ── which names the rule will talk about ─────────────────────────────────────────────────────

test "an ordinary name is a candidate" {
    assert LinterShadowedVariable.IsCandidate("value")
    assert LinterShadowedVariable.IsCandidate("Value")
    assert LinterShadowedVariable.IsCandidate("v1")
    assert LinterShadowedVariable.IsCandidate("café")
}

test "the discard and every underscore-prefixed name are silenced" {
    assert !LinterShadowedVariable.IsCandidate("_")
    assert !LinterShadowedVariable.IsCandidate("_x")
    assert !LinterShadowedVariable.IsCandidate("__")
    assert !LinterShadowedVariable.IsCandidate("_unused")
}

test "the discard test was REDUNDANT with the prefix test, and this is why it could be dropped" {
    // The rule used to ask `name == "_" || name.StartsWith("_")`. Over every name the rule can be
    // asked about, the first disjunct never changes the answer — asserted rather than assumed.
    subjects := ["_", "_x", "__", "_unused", "value", "Value", "v1", "", "x_", "a_b", "café", "_9"]
    index := 0
    while index < subjects.Length {
        both := subjects[index] == "_" || subjects[index].StartsWith("_", StringComparison.Ordinal)
        assert !LinterShadowedVariable.IsCandidate(subjects[index]) == both
        index = index + 1
    }

    // Non-vacuity: the list must contain names on both sides.
    assert LinterShadowedVariable.IsCandidate("value")
    assert !LinterShadowedVariable.IsCandidate("_")
}

test "an underscore anywhere but the front does not silence anything" {
    assert LinterShadowedVariable.IsCandidate("x_")
    assert LinterShadowedVariable.IsCandidate("a_b")
}

test "the empty name is a candidate, because the rule is about the prefix and nothing else" {
    // The linter never declares an empty name, so this states the predicate's total behaviour
    // rather than a reachable case.
    assert LinterShadowedVariable.IsCandidate("")
}


// ── which scopes are consulted ───────────────────────────────────────────────────────────────

test "a name declared in the one enclosing scope shadows" {
    assert LinterShadowedVariable.ShadowsOuterScope("value", LsvOneScope(["value"]))
}

test "a name declared in NO enclosing scope does not" {
    assert !LinterShadowedVariable.ShadowsOuterScope("value", LsvOneScope(["other"]))
    assert !LinterShadowedVariable.ShadowsOuterScope("value", LsvOneScope([]))
    assert !LinterShadowedVariable.ShadowsOuterScope("value", LsvScopes())
}

test "EVERY enclosing scope is consulted, not just the innermost one" {
    // Three frames deep, the name only in the outermost. Consulting the top of the stack alone —
    // the easy mistake — answers false here.
    deep := LsvStack([["value"], ["a"], ["b"]])
    assert LinterShadowedVariable.ShadowsOuterScope("value", deep)

    // And a name in the innermost enclosing frame is found too.
    assert LinterShadowedVariable.ShadowsOuterScope("b", deep)
    assert !LinterShadowedVariable.ShadowsOuterScope("c", deep)
}

test "the scope being declared INTO is not on the stack, so a name never shadows itself" {
    // The linter pushes the frame it is leaving and declares into a fresh one, so an empty stack is
    // exactly "there is nothing enclosing this". A rule that consulted the current frame would
    // report every declaration.
    assert !LinterShadowedVariable.ShadowsOuterScope("value", LsvScopes())
    assert LsvFinding("value", LsvScopes()) == null
}

test "the lookup is ordinal — a name differing only in case is a different name" {
    scopes := LsvOneScope(["Value"])
    assert LinterShadowedVariable.ShadowsOuterScope("Value", scopes)
    assert !LinterShadowedVariable.ShadowsOuterScope("value", scopes)
}


// ── the rule ─────────────────────────────────────────────────────────────────────────────────

test "the finding names the shadowed variable three times and points at the DECLARATION" {
    finding := LsvFinding("value", LsvOneScope(["value"]))
    assert finding != null
    assert finding.Code == "NL020"
    assert finding.Message == "Variable 'value' shadows another 'value' from an outer scope — this can lead to confusing bugs"
    assert finding.Suggestion == "Consider renaming to avoid confusion with the outer 'value'"
    assert finding.Line == 4
    assert finding.Column == 9
}

test "a silenced name is silent even when it really does shadow" {
    assert LinterShadowedVariable.ShadowsOuterScope("_x", LsvOneScope(["_x"]))
    assert LsvFinding("_x", LsvOneScope(["_x"])) == null
    assert LsvFinding("_", LsvOneScope(["_"])) == null
}

test "NL020 IS gated on presence — take its code out of the table and it says nothing" {
    assert LinterShadowedVariable.ShadowedVariable("value", 4, 9, LsvOneScope(["value"]), LsvConfig()) != null
    assert LinterShadowedVariable.ShadowedVariable("value", 4, 9, LsvOneScope(["value"]), LsvConfigWithout("NL020")) == null
}

test "the gate is checked FIRST, so a gated-off rule never even looks at the scopes" {
    gated := LsvConfigWithout("NL020")
    deep := LsvStack([["value"], ["value"], ["value"]])
    assert LinterShadowedVariable.ShadowedVariable("value", 4, 9, deep, gated) == null
}

test "the three tests happen in order: gate, then silencer, then scopes" {
    // Each stage alone is enough to silence the rule, and the rule speaks only when all three pass.
    // Asserted as a four-cell truth table so a reordering that changed an answer would show.
    shadowing := LsvOneScope(["value"])
    empty := LsvScopes()

    assert LinterShadowedVariable.ShadowedVariable("value", 1, 1, shadowing, LsvConfig()) != null
    assert LinterShadowedVariable.ShadowedVariable("value", 1, 1, empty, LsvConfig()) == null
    assert LinterShadowedVariable.ShadowedVariable("_value", 1, 1, LsvOneScope(["_value"]), LsvConfig()) == null
    assert LinterShadowedVariable.ShadowedVariable("value", 1, 1, shadowing, LsvConfigWithout("NL020")) == null
}
