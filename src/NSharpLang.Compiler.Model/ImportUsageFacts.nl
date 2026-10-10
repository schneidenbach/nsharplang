namespace NSharpLang.Compiler.Ast

import System
import System.Collections.Generic


// WHAT A FILE'S IMPORTS ACTUALLY SUPPLIED — the binding facts NL010 and NL002 are both answered from.
//
// THE RULE IS ONE MEASUREMENT WITH TWO READINGS, AND THAT IS THE POINT OF PUTTING THEM IN ONE OBJECT.
// When a simple name resolves, the namespace that supplied it is known exactly: it is the prefix
// that, with the written spelling, spells the resolved type's full name. If the file imports that
// namespace, the import is USED and NL010 must stay quiet about it; if it does not, the name is used
// WITHOUT the import that provides it and NL002 must say so. The two rules cannot disagree, because
// they are the same measurement read from two sides.
//
// IT REPLACES TWO TABLES, AND THE TABLES ARE WHY THIS EXISTS. NL010 answered from a hand-written
// closed-world list of names per namespace — 112 spellings for `System` alone — and NL002 from a
// 25-name whitelist. Every gap in the first was a FALSE POSITIVE on an ERROR whose `nlc fix` deletes
// the import; every gap in the second was silence. `OperatingSystem` was in neither, so
// `import System` beside `OperatingSystem.IsWindows()` was reported dead, and the same file without
// the import was accepted without a word. Neither failure is possible here: nothing is listed, and
// the only evidence is what the file BOUND.
//
// WHAT IS CREDITED. Every channel through which a written name becomes a type or a member credits the
// namespace that answered — a type reference anywhere a type may be written, a static receiver, an
// attribute, an extension method's declaring type, a name the declaration context resolved for a
// declared member, and a name a namespace declared but refused to export. An ALIAS-QUALIFIED spelling
// credits the namespace it is an alias OF, because an N# aliased import does both things at once: it
// binds `Txt` and it brings `StringBuilder` into scope unqualified.
//
// A NAME IS CREDITED ONCE, BY THE FIRST NAMESPACE THAT SUPPLIED IT. NL002 asks "which import does
// this spelling need", and a spelling that resolves through two namespaces in one file is an
// ambiguity NL209 reports; this rule does not get a second opinion about it.
//
// `Analyzed` IS A GATE, NOT A DETAIL. A file whose analysis did not complete has partial facts, and
// partial facts would report live imports as dead. NL010 asks this first and stays silent when it is
// false — an import whose use cannot be proven is not an import that has been proven dead.
class ImportUsageFacts {
    supplied: HashSet<string>
    suppliersByName: Dictionary<string, string>

    // Set once, by the analyzer, when the file's analysis has run to completion.
    Analyzed: bool

    constructor() {
        supplied = new HashSet<string>(StringComparer.Ordinal)
        suppliersByName = new Dictionary<string, string>(StringComparer.Ordinal)
        Analyzed = false
    }

    // Every namespace some written name resolved through, in no particular order: membership is the
    // only question asked of it.
    SuppliedNamespaces: HashSet<string> => supplied

    func CreditNamespace(namespaceName: string?) {
        if namespaceName == null {
            return
        }

        value := namespaceName ?? ""
        if value.Length > 0 {
            supplied.Add(value)
        }
    }

    // A written spelling that resolved to a METADATA type, with the namespace that supplied it. The
    // namespace is credited either way — an import that supplied a name is used whatever else is true
    // of it — and the name is remembered so NL002 can say which import to add when it is missing.
    func CreditName(name: string, namespaceName: string?) {
        CreditNamespace(namespaceName)
        if namespaceName == null {
            return
        }

        supplier := namespaceName ?? ""
        if supplier.Length == 0 || name.Length == 0 {
            return
        }

        if !suppliersByName.ContainsKey(name) {
            suppliersByName[name] = supplier
        }
    }

    func SuppliedBy(namespaceName: string): bool {
        return supplied.Contains(namespaceName)
    }

    // Which namespace supplied this written spelling, or nothing when no metadata type answered for
    // it. "Nothing" is the answer for a name that resolved to a local, a member, a type parameter or
    // a source declaration — none of which needs an import — and for a name that did not resolve at
    // all, which is a different diagnostic's business.
    func SupplierFor(name: string): string? {
        found := ""
        if suppliersByName.TryGetValue(name, out found) {
            return found
        }

        return null
    }
}
