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

test "a typed lambda rejects the instance delegate overload and selects the receiver-style extension" {
    target := new DelegateTarget()
    assert delegateExtensionCall(target) == "extension:extension"
}

test "an applicable instance delegate overload wins over the matching receiver-style extension" {
    assert delegateInstanceCall(new DelegateTarget()) == "instance:42"
}

test "a lambda is not applicable to an overload with a concrete non-delegate parameter" {
    assert lambdaCandidateRejectsNonDelegate() == "delegate:73"
}
