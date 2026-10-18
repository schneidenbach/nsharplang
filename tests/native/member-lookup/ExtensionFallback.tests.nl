namespace NSharpLang.MemberLookup.Tests

import System.Collections.Generic

func sampleValues(): List<int> {
    values := new List<int>()
    values.Add(10)
    values.Add(20)
    values.Add(30)
    return values
}

test "a referenced extension is chosen when the instance overload takes no comparer" {
    assert comparerExtension(sampleValues())
    assert !comparerExtensionMissing(sampleValues())
}

test "an applicable instance overload still wins over an extension of the same name" {
    assert instanceContains(sampleValues())
    assert instanceByLambdaShape(sampleValues()) == 2
    assert instanceByDelegate(sampleValues()) == 20
}
