namespace Census.Lookup.Rival


// A SOURCE `TypeInfo` in a namespace the consumer IMPORTS. An import is farther than the consumer's
// enclosing namespace, so this loses to the referenced assembly's `Census.Lookup.TypeInfo` even though
// it is declared in the consumer's own project.
class TypeInfo {
    func Side(): string {
        return "rival"
    }
}
