namespace NSharpLang.QualifiedNames


// A SOURCE TYPE IN THE TEST FILE'S ENCLOSING NAMESPACE, sharing a name with an imported CLR type.
//
// The test file declares `namespace NSharpLang.QualifiedNames.Tests`, so this namespace encloses it
// and this declaration is in scope there WITHOUT an import. `import System` brings `System.Random`
// into that same file, and the rule says the lexically nearer declaration wins outright — no
// ambiguity, no diagnostic, and the same answer from the analyzer and from emission.
//
// This is the mirror of `Shadow.nl`: there the source type is in a SIBLING namespace and loses to
// the import; here it is in an ENCLOSING one and wins.
class Random {
    Marker: string

    constructor() {
        Marker = "enclosing-random"
    }

    static func Origin(): string {
        return "enclosing"
    }
}
