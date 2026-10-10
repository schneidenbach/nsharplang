namespace NSharpLang.CensusNUnitTestBlocks.Tests

import System

test "a `test` block runs under testFramework: nunit" {
    assert Add(2, 3) == 5
    assert Describe(-1) == "negative"
    assert Describe(0) == "zero"
    assert Describe(4) == "positive"
}

test "the lowered method carries NUnit's own test attribute, not xunit's" {
    method := RequiredTestMethod("TheLoweredMethodCarriesNUnitsOwnTestAttributeNotXunits")
    names := AttributeNames(method)
    assert ListContains(names, "NUnit.Framework.TestAttribute")
    assert !ListContains(names, "Xunit.FactAttribute")
}

test "a failing assertion still raises, so a green run means the bodies ran" {
    raised := false
    try {
        assert Add(2, 2) == 5
    } catch failure: InvalidOperationException {
        raised = failure != null
    }
    assert raised
}
