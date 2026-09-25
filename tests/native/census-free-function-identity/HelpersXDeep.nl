namespace Census.FreeFunctionIdentity.X.Deep


// A NESTED NAMESPACE THAT DECLARES ITS OWN `Helper`: rule 1 beats rule 2, so the bare call here
// reaches this declaration rather than the enclosing `X.Helper`.
func Helper(): string {
    return "X.Deep"
}

func UseOwnHelper(): string {
    return Helper()
}
