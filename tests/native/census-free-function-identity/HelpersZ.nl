namespace Census.FreeFunctionIdentity.Z

import Census.FreeFunctionIdentity.Y


// A THIRD NAMESPACE THAT DECLARES NO `Helper` AT ALL and reaches Y's through an import. This is
// `SimpleNamePrecedence` rule 3 — the only tier that can bring a free function in from a namespace
// that is neither this file's own nor an enclosing one.
func UseImportedHelper(): string {
    return Helper()
}

// The same namespace ALSO declares a bare `Local` that nothing else declares, so the view a file
// gets is not merely "everything exported", it is everything this file can see.
func ZOnly(): string {
    return "Z"
}
