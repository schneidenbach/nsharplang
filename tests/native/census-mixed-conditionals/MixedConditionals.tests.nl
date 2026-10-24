namespace NSharpLang.CensusMixedConditionals.Tests


// Every row runs BOTH paths of its conditional, because each arm is written and converted on its own:
// a row that took only one path would prove only one arm's conversion.

test "with no target, a conditional of a class and its base is the base, on both paths" {
    assert MixedConditionals.NaturalReference(true) == "Animal:Dog:animal"
    assert MixedConditionals.NaturalReference(false) == "Animal:Animal:animal"
}

test "with no target, an int and a double are a double, on both paths" {
    assert MixedConditionals.NaturalNumeric(true) == "Double:1"
    assert MixedConditionals.NaturalNumeric(false) == "Double:2.5"
}

test "with no target, a byte and a short promote to an int" {
    assert MixedConditionals.NaturalPromoted(true) == "Int32:3"
    assert MixedConditionals.NaturalPromoted(false) == "Int32:4"
}

test "an unannotated `let`, with `=` or `:=`, is an inferred local" {
    assert MixedConditionals.LetInferred(true) == "5:pets:Animal"
    assert MixedConditionals.LetInferred(false) == "5:pets:Animal"
}

test "a declared local is the target each branch converts to" {
    assert MixedConditionals.TypedLocal(true) == "Int32:1:Animal:Dog"
    assert MixedConditionals.TypedLocal(false) == "String:x:Animal:Cat"
}

test "the local being assigned is the target" {
    assert MixedConditionals.Assigned(true) == "7"
    assert MixedConditionals.Assigned(false) == "seven"
}

test "a declared return type is the target" {
    assert MixedConditionals.Returned(true).ToString() == "1"
    assert MixedConditionals.Returned(false).ToString() == "x"
}

test "a parameter, in source or in a referenced assembly, is the target" {
    assert MixedConditionals.PassedToSource(true) == "Int32:2"
    assert MixedConditionals.PassedToSource(false) == "String:two"
    assert MixedConditionals.PassedToFramework(true) == "a1"
    assert MixedConditionals.PassedToFramework(false) == "ax"
}

test "an overload group takes the overload both branches fit, and a same-typed conditional keeps its own" {
    assert MixedConditionals.Overloaded(true) == "object:int"
    assert MixedConditionals.Overloaded(false) == "object:int"
}

test "a mixed conditional nested in a target-typed one converts under the outer target" {
    assert MixedConditionals.Nested(true, true).ToString() == "1"
    assert MixedConditionals.Nested(true, false).ToString() == "inner"
    assert MixedConditionals.Nested(false, true) == null
}
