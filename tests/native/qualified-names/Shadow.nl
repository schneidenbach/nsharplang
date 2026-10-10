namespace NSharpLang.QualifiedNames.Shadow


// A SOURCE TYPE THAT SHARES A NAME WITH AN IMPORTED CLR TYPE, in a namespace nothing imports.
//
// `System.Version` is what `import System` brings into a file that never imported this namespace,
// and before the visibility fix this declaration silently won that name project-wide — an explicit
// import quietly replaced by an unrelated source class, with no diagnostic. The test file proves
// the import now wins, and that this declaration is still reachable by its qualified name.
class Version {
    Marker: string

    constructor() {
        Marker = "source-version"
    }

    static func Origin(): string {
        return "shadow"
    }
}
