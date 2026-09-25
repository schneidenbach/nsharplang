namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast


// NL010 ASKS ONE QUESTION OF EVERY IMPORT: DID ANYTHING IN THIS FILE BIND THROUGH IT?
//
// The FILE arm is `LinterFileImportUsage`; this is the NAMESPACE arm, and the two together are the
// whole rule.
//
// THE ANSWER IS AN ANALYSIS, AND IT USED TO BE A TABLE. This owner carried a hand-written list of the
// names each of ten namespaces provides — 112 spellings for `System` alone — and read it as a CLOSED
// WORLD: a namespace the table named supplied exactly those names and nothing else, and a namespace
// it did not name was reported USED no matter what. Both readings were wrong in a way that shipped:
//
//   * A GAP IN A ROW WAS A FALSE POSITIVE ON AN ERROR WHOSE FIX DELETES CODE. `import System` beside
//     `OperatingSystem.IsWindows()` was reported unused, because the row had never heard of
//     `OperatingSystem`, and `nlc fix` offered to delete the import the build needs. Every spelling
//     the BCL has and the row did not was that bug waiting to happen, and the row could never be
//     finished: the namespace has thousands of public types and grows every release.
//   * A NAMESPACE WITH NO ROW WAS NEVER REPORTED AT ALL. A dead `import System.Runtime.CompilerServices`
//     — or a dead import of any project's own namespace — was invisible, so the rule was silent
//     exactly where a developer's own code is.
//
// What replaces it is the analyzer's own answer: `ImportUsageFacts` records the namespace that
// SUPPLIED each name the file wrote, measured from the identity the name resolved to. A namespace
// that supplied nothing supplied nothing, whatever its name is, and a namespace that supplied one
// thing is used — no list, no arity, no BCL knowledge anywhere in this rule.
//
// AN UNANALYSED FILE ANSWERS NOTHING, AND THAT IS THE HONEST ANSWER RATHER THAN A DEGRADED ONE. An
// import's use is a binding fact; a file that was never bound has none, and guessing is what the
// table was. `CheckUnusedImports` asks `HasFacts` first and reports no namespace import without them.
class LinterNamespaceImportUsage {

    // Whether this file's imports can be judged at all: the unit carries facts and its analysis ran
    // to completion. A partial ledger would report live imports as dead, which is the one failure
    // mode this rule must never have.
    static func HasFacts(usage: ImportUsageFacts?): bool {
        if usage == null {
            return false
        }

        facts := usage ?? new ImportUsageFacts()
        return facts.Analyzed
    }

    // WHETHER AN IMPORT IS USED AT ALL, ALIASED OR NOT.
    //
    // An aliased import in N# does two things at once: `import System.Text as Txt` binds the name
    // `Txt` AND brings `StringBuilder` into scope unqualified, so a file carrying only that import
    // compiles `new StringBuilder()`. Both spellings are uses of the same import, so both credit the
    // same NAMESPACE while the name is being resolved, and this rule has one question to ask rather
    // than two. C#'s `using Txt = System.Text;` binds only the alias, which is the rule an earlier
    // alias-only arm was asked under — and under it a converted file whose only use of an aliased
    // namespace was a bare `new CompletionEngine()` was told to delete the import its build needs.
    //
    // A file with no facts answers USED for every import, because an import whose use cannot be
    // proven has not been proven dead. `CheckUnusedImports` asks `HasFacts` before it gets here, so
    // that arm is a guarantee rather than a path.
    static func IsImportUsed(namespaceName: string, usage: ImportUsageFacts?): bool {
        if !HasFacts(usage) {
            return true
        }

        facts := usage ?? new ImportUsageFacts()
        return facts.SuppliedBy(namespaceName)
    }
}
