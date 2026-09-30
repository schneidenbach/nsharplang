namespace Census.FreeFunctionIdentity.X


// A `test` BLOCK IS A FREE FUNCTION IN ITS FILE'S NAMESPACE, so the bare names it writes resolve
// through exactly the order every other body's do — this one sees `X.Helper` without an import.
test "a test block in a namespace calls that namespace's helper" {
    assert Helper() == "X"
    assert UseHelperFromX() == "X"
}
