namespace Census.Imports.Shadow


// A SOURCE GENERIC SPELLED LIKE A BCL ONE, IN A NAMESPACE NOTHING IMPORTS. Project-wide
// auto-discovery would offer this type to any file that writes `List<T>`; an explicit
// `import System.Collections.Generic` has to outrank it, and the companion test executes that.
class List<T> {
    func Side(): string {
        return "shadow"
    }
}
