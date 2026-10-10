namespace NSharpLang.CensusConversions.Tests

import System
import System.Collections.Generic
import System.Reflection

test "a user-defined implicit conversion reaches an argument, and it is the type's own operator" {
    element := BuildResult("passed")

    byString := AttributeByString(element)
    assert byString != null

    // `XName::op_Implicit(string)` interns the name, so the two spellings reach the SAME attribute
    // object — which is what proves the conversion is the declared operator and not a lookup that
    // happens to agree with it.
    byName := AttributeByName(element)
    assert byName != null
    assert Object.ReferenceEquals(byString, byName)
}

test "the explicit conversion reads the value, and a missing attribute converts to null" {
    element := BuildResult("passed")

    assert OutcomeOf(element) == "passed"
    assert MissingOf(element) == null

    // Reading it back after a second write is the same call, so nothing here is a one-shot.
    element.SetAttributeValue("outcome", "failed")
    assert OutcomeOf(element) == "failed"
}

test "an array literal picks the overload its elements fit" {
    assert PickInts() == "int[] 3"
    assert PickObjectsFromStrings() == "object[] 2"
    assert PickMixed() == "only 3"
}

test "a lone array literal in a params position is still the array itself" {
    assert PickParamsLiteral() == "params 2"
    assert PickParamsExpanded() == "params 2"
}

test "an array literal is applicable to a reflected overload before the candidate is chosen" {
    join := FreeFunctionOf("JoinValues")
    assert join != null

    names: string[] = ["census", "conv2"]
    joined := must InvokeWith(join, names)
    assert joined.Equals("census|conv2")

    // A literal whose elements have NO common type is an ordinary `object?[]`: inferring it from its
    // first element used to report "all elements in an array must be the same type" about a call
    // that is correct.
    describe := FreeFunctionOf("DescribePair")
    assert describe != null

    described := must InvokeWithMixed(describe, 7, "seven")
    assert described.Equals("7:seven")
}

test "the emitted argument conversions do not change the signatures they serve" {
    // `Accept` is three methods, not one widened one: the overload set survives emission, and no
    // argument conversion was implemented by changing a declaration.
    accepts := new List<Type>()
    for method in typeof(Sink).GetMethods(BindingFlags.Public | BindingFlags.Static) {
        if method.Name == "Accept" {
            parameters := method.GetParameters()
            assert parameters.Length == 1
            accepts.Add(parameters[0].get_ParameterType())
        }
    }

    assert accepts.Count == 2
    assert accepts.Contains(typeof(int[]))
    assert accepts.Contains(typeof(object[]))
}
