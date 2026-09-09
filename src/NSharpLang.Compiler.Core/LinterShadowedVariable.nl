namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// WHICH DECLARATION SHADOWS AN OUTER ONE (NL020).
//
// The rule fires when a name being declared is ALREADY declared in some enclosing scope. "Enclosing"
// is the whole content of the rule and it is easy to get wrong in both directions: the scope being
// declared INTO must not be consulted — a variable does not shadow itself, and a redeclaration in
// the same scope is a different error entirely — and every enclosing scope must be, not just the
// immediately enclosing one, so a name three blocks out still shadows.
//
// THE SILENCER IS ONE TEST, NOT TWO. The C# this replaces asked `name == "_" || name.StartsWith("_")`,
// and the first disjunct can never decide anything the second does not: `"_"` starts with `"_"`.
// Written once, the rule is "a name the developer marked as deliberately uninteresting does not
// shadow" — which covers the discard `_` and every `_prefixed` name, and covers them for the same
// reason.
//
// THE GATE IS PRESENCE, NOT SEVERITY. Like NL016, NL020 stays silent unless its code is present in
// the configuration's severity table, so a project that has never heard of the rule never sees it.
class LinterShadowedVariable {

    // Whether a name is one the rule is willing to talk about at all.
    static func IsCandidate(name: string): bool {
        if name == null {
            return false
        }

        return !name.StartsWith("_", StringComparison.Ordinal)
    }

    // Whether any ENCLOSING scope already declares this name. The stack holds the enclosing scopes
    // only — the scope being declared into is the linter's current frame and is not on it — so
    // every entry here is genuinely outer, and the first hit is enough.
    static func ShadowsOuterScope(name: string, outerScopes: Stack<Dictionary<string, (int, int, bool)>>): bool {
        for scope in outerScopes {
            if scope.ContainsKey(name) {
                return true
            }
        }

        return false
    }

    // NL020. Silent unless the rule's code is present in the configuration's severity table.
    static func ShadowedVariable(name: string, line: int, column: int, outerScopes: Stack<Dictionary<string, (int, int, bool)>>, config: LinterConfig): LinterRuleFinding? {
        if !config.RuleSeverities.ContainsKey("NL020") {
            return null
        }

        if !IsCandidate(name) {
            return null
        }

        if !ShadowsOuterScope(name, outerScopes) {
            return null
        }

        return new LinterRuleFinding("NL020", "Variable '" + name + "' shadows another '" + name + "' from an outer scope — this can lead to confusing bugs", "Consider renaming to avoid confusion with the outer '" + name + "'", config.GetSeverity("NL020"), line, column)
    }
}
