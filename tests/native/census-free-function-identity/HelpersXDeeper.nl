namespace Census.FreeFunctionIdentity.X.Deeper


// A NESTED NAMESPACE THAT DECLARES NO `Helper`: rule 2 climbs outward to the ENCLOSING namespace
// and finds `X.Helper`, with no import written anywhere in this file.
func UseEnclosingHelper(): string {
    return Helper()
}
