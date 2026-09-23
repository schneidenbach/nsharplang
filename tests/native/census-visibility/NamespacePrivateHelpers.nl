namespace NSharpLang.CensusVisibility.Tests


// FILE ONE OF TWO. Everything this file declares is named from `NamespacePrivateUse.nl` and from
// the test blocks beside it — three DIFFERENT files of the SAME namespace — with no import and no
// qualification, because a camelCase top-level declaration in N# is private to its NAMESPACE and
// never to its file (ruling 2026-09-02).
//
// Nothing here is exported except where the name says so, and that is the point: the two spellings
// sit side by side so the pair of claims is made against one namespace.

// Namespace-private: visible to every file of this namespace, and to nothing outside the assembly.
func formatTypeRef(t: string): string {
    return "<" + t + ">"
}

// The same function's exported twin, so a metadata claim about one can be read against the other.
func FormatExported(t: string): string {
    return "[" + t + "]"
}

// A namespace-private function with the SAME SHAPE, so a method group naming it has a real choice
// of two and the one it names is observable in the answer.
func shoutTypeRef(t: string): string {
    return t.ToUpperInvariant()
}

// The EXPORTED twin of the type below, so a metadata claim about one can be read against the other.
// Without it, "camelCase is emitted assembly" would be a claim about the emitter rather than about the
// casing.
class HelperBoxReader {
    static func Read(box: helperBox): string {
        return box.Describe()
    }
}

// The TYPE half of the same rule, which already held before the function half did — in the LANGUAGE.
// It reaches CLR metadata as well now: a camelCase top-level type is emitted `NotPublic`, so another
// assembly cannot name it even by accident.
class helperBox {
    Value: string

    constructor(value: string) {
        Value = value
    }

    func Describe(): string {
        return formatTypeRef(Value)
    }
}
