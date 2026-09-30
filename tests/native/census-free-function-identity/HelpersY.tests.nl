namespace Census.FreeFunctionIdentity.Y


// The same test written in the OTHER namespace: same spelling, different answer, and the two test
// bodies are emitted onto the lowered type of their OWN file and namespace —
// `Census.FreeFunctionIdentity.Y.HelpersYTests` here, `…X.HelpersXTests` next door.
test "a test block in the sibling namespace calls its own helper" {
    assert Helper() == "Y"
    assert UseHelperFromY() == "Y"
}
