namespace NSharpLang.CensusFlowRules.Tests

import System.Collections.Generic

func postconditionEntries(): List<Entry> {
    entries := new List<Entry>()
    entries.Add(new Entry("alpha"))
    entries.Add(new Entry("beta"))
    return entries
}

func postconditionMap(): Dictionary<string, Entry> {
    map := new Dictionary<string, Entry>()
    map["alpha"] = new Entry("alpha")
    return map
}

test "a nullable variable is a legal out argument and takes the parameter's nullability" {
    assert HeadOrEmpty("one two") == "one|two"
    assert HeadOrEmpty("solo") == "solo"
}

test "a nullable out parameter leaves the variable maybe-null" {
    assert FoundLabelOrNone(postconditionEntries(), "beta") == "beta"
    assert FoundLabelOrNone(postconditionEntries(), "gamma") == "none"
}

test "a source-declared NotNullWhen(true) narrows the branch it names" {
    assert LookupLabelOrNone(postconditionEntries(), "alpha") == "alpha"
    assert LookupLabelOrNone(postconditionEntries(), "gamma") == "none"
}

test "the same attribute read through a negated guard narrows the surviving flow" {
    assert LookupLabelGuarded(postconditionEntries(), "beta") == "beta"
    assert LookupLabelGuarded(postconditionEntries(), "gamma") == "none"
}

test "a source-declared NotNull on an input parameter holds on every path" {
    assert RequiredLabel(new Entry("solo")) == "solo"
}

test "MaybeNullWhen names one branch and the declaration answers for the other" {
    assert MissLabel(postconditionEntries(), "alpha") == "alpha"
    assert MissLabel(postconditionEntries(), "gamma") == "missed"
}

test "Dictionary TryGetValue is present in the branch it answered true on" {
    assert DictionaryLabel(postconditionMap(), "alpha") == "alpha"
    assert DictionaryLabel(postconditionMap(), "gamma") == "none"
    assert DictionaryLabelGuarded(postconditionMap(), "alpha") == "alpha"
    assert DictionaryLabelGuarded(null, "alpha") == "none"
    assert DictionaryLabelInverted(postconditionMap(), "alpha") == "alpha"
    assert DictionaryLabelInverted(postconditionMap(), "gamma") == "none"
}

test "string.IsNullOrEmpty proves its argument in the branch it answered false on" {
    assert TextLengthOrZero("abcd") == 4
    assert TextLengthOrZero(null) == 0
    assert TextLengthOrZero("") == 0
    assert TextLengthOrZeroInverted("abc") == 3
    assert TextLengthOrZeroInverted(null) == 0
    assert TextLengthOrZeroInverted("   ") == 0
}

test "NotNullIfNotNull makes the result as null as the argument was" {
    assert FileNameOf("/tmp/report.txt") == "report.txt"
    assert FileNameOfMaybe("/tmp/report.txt") == "report.txt"
    assert FileNameOfMaybe(null) == "<none>"
}

test "a negated HasValue guard narrows the flow that survives it" {
    assert TimeoutOrDefault(500) == 500
    assert TimeoutOrDefault(null) == 30
    assert TimeoutOrDefaultUnwrapped(90) == 90
    assert TimeoutOrDefaultUnwrapped(null) == 30
}
