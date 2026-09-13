namespace NSharpLang.Compiler.Ast

import System
import System.Collections.Generic


// ONE NAME THE FILE WROTE AND THE NAMESPACE THAT SUPPLIED IT, with the columns it occupies.
//
// The POSITION is the whole reason this is a record rather than a set entry: NL002 reports at the
// name, and the analyzer is the only owner that knows both which namespace answered and where the
// spelling that asked is written. A rule that had to re-derive the span from the source line ran a
// dotted chain together and squiggled `StringBuilder.ToString` for a finding about `StringBuilder`.
class ImportUsageReference {
    Name: string
    NamespaceName: string
    Line: int
    Column: int
    Length: int

    constructor(name: string, namespaceName: string, line: int, column: int, length: int) {
        Name = name
        NamespaceName = namespaceName
        Line = line
        Column = column
        Length = length
    }
}

// WHAT A FILE'S IMPORTS ACTUALLY SUPPLIED — the binding facts NL010 and NL002 are both answered from.
//
// THE RULE IS ONE FACT WITH TWO READINGS, AND THAT IS THE POINT OF PUTTING THEM IN ONE OBJECT. When a
// simple name resolves, the namespace that supplied it is known exactly: it is the prefix that, with
// the written spelling, spells the resolved type's full name. If the file imports that namespace, the
// import is USED and NL010 must stay quiet about it; if it does not, the name is used WITHOUT the
// import that provides it and NL002 must say so. The two rules cannot disagree because they are the
// same measurement read from two sides.
//
// IT REPLACES A TABLE, AND THE TABLE IS WHY THIS EXISTS. NL010 used to answer from a hand-written
// closed-world list of names per namespace — 112 spellings for `System` alone — which made every gap
// in the list a FALSE POSITIVE on an ERROR whose `nlc fix` deletes the import. `import System` beside
// `OperatingSystem.IsWindows()` was reported unused and the fix broke the build, because the list had
// never heard of `OperatingSystem`. A namespace the list did not name at all was reported USED, so
// every genuinely dead import outside the ten listed namespaces went unreported. Neither failure is
// possible here: nothing is listed, and the only evidence is what the file BOUND.
//
// WHAT IS CREDITED. Every channel through which a written name becomes a type or a member credits
// the namespace that answered — a type reference anywhere a type may be written, a static receiver,
// an attribute, an extension method's declaring type, a name the declaration context resolved for a
// declared member. An ALIAS-QUALIFIED spelling credits the namespace it is an alias OF, because an
// N# aliased import does both things at once: it binds `Txt` and it brings `StringBuilder` into
// scope unqualified, so both spellings are uses of one import.
//
// `Analyzed` IS A GATE, NOT A DETAIL. A file whose analysis did not complete has partial facts, and
// partial facts would report live imports as dead. NL010 therefore asks this first and stays silent
// when it is false — an import whose use cannot be proven is not an import that has been proven dead.
class ImportUsageFacts {
    supplied: HashSet<string>
    references: List<ImportUsageReference>
    referenceKeys: HashSet<string>

    // Set once, by the analyzer, when the file's analysis has run to completion.
    Analyzed: bool

    constructor() {
        supplied = new HashSet<string>(StringComparer.Ordinal)
        references = new List<ImportUsageReference>()
        referenceKeys = new HashSet<string>(StringComparer.Ordinal)
        Analyzed = false
    }

    // Every namespace some written name resolved through, in no particular order: membership is the
    // only question asked of it.
    SuppliedNamespaces: HashSet<string> => supplied

    // Every written name that resolved to a metadata type, with the namespace that supplied it and
    // the columns the spelling occupies. NL002 walks these; NL010 does not need them.
    References: List<ImportUsageReference> => references

    func CreditNamespace(namespaceName: string?) {
        if namespaceName == null {
            return
        }

        value := namespaceName ?? ""
        if value.Length > 0 {
            supplied.Add(value)
        }
    }

    // A written spelling that resolved to a metadata type. The namespace is credited either way —
    // an import that supplied the name is used whether or not anything else is true of it — and the
    // POSITION is kept so NL002 can report on the name when the import is missing.
    //
    // Deduped by name AND position: one spelling asked at one place is one finding, however many
    // times the walk resolves it.
    func CreditReference(name: string, namespaceName: string?, line: int, column: int, length: int) {
        CreditNamespace(namespaceName)
        if namespaceName == null {
            return
        }

        supplier := namespaceName ?? ""
        if supplier.Length == 0 || line <= 0 || column <= 0 || name.Length == 0 {
            return
        }

        key := name + "|" + line.ToString() + "|" + column.ToString()
        if !referenceKeys.Add(key) {
            return
        }

        references.Add(new ImportUsageReference(name, supplier, line, column, length))
    }

    func SuppliedBy(namespaceName: string): bool {
        return supplied.Contains(namespaceName)
    }
}
