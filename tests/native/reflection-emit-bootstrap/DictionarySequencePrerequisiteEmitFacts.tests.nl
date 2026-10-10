namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Collections.Generic

func DictionarySequencePrerequisiteInvocationFailure(
    methodName: string,
    arguments: object?[]
): int {
    method := typeof(DictionarySequencePrerequisiteEmitFacts).GetMethod(methodName)
    if method == null {
        throw new InvalidOperationException("Dictionary sequence prerequisite method was not found: " + methodName)
    }
    try {
        _result := method.Invoke(null, arguments)
    } catch ex: Exception {
        innerBox: object? = ex.get_InnerException()
        if innerBox != null && innerBox.GetType() == typeof(ArgumentNullException) {
            return 1
        }
        if innerBox != null && innerBox.GetType() == typeof(NullReferenceException) {
            return 2
        }
        return -1
    }
    return 0
}

func DictionarySequencePrerequisiteSetObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

test "Dictionary IReadOnlyDictionary copy preserves populated values comparer identity and independence" {
    source := DictionarySequencePrerequisiteEmitFacts.CreateReadOnlyCopySource()
    method := typeof(DictionarySequencePrerequisiteEmitFacts).GetMethod(
        "VerifyReadOnlyCopy"
    )
    if method == null {
        throw new InvalidOperationException("Dictionary read-only copy verification method was not found.")
    }
    invocationArguments := new object?[](1)
    invocationArguments[0] = source
    result := method.Invoke(null, invocationArguments)
    if result == null {
        throw new InvalidOperationException("Dictionary read-only copy verification returned null.")
    }
    assert result.ToString() == "copy-ok"

    arguments := new object?[](1)
    arguments[0] = null
    assert DictionarySequencePrerequisiteInvocationFailure(
        "CopyReadOnly",
        arguments
    ) == 1
}

test "Dictionary IDictionary copy uses interface-constructor comparer evaluation and independence" {
    source := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    source["Alpha"] = "one"
    source["Second"] = "two"
    view: IDictionary<string, string> = source

    state := new DictionarySequencePrerequisiteState()
    copied := DictionarySequencePrerequisiteEmitFacts.CopyEvaluated(state, view)
    assert state.EvaluationCount == 1
    assert copied.get_Count() == 2
    assert copied["Alpha"] == "one"
    assert !copied.ContainsKey("alpha")

    copied["ALPHA"] = "updated"
    assert copied.get_Count() == 3
    assert copied["Alpha"] == "one"
    assert copied["ALPHA"] == "updated"

    source["source-only"] = "source"
    assert !copied.ContainsKey("source-only")
    copied["copy-only"] = "copy"
    assert !source.ContainsKey("copy-only")
}

test "Dictionary IDictionary copy preserves the typed null constructor failure" {
    arguments := new object?[](1)
    arguments[0] = null
    assert DictionarySequencePrerequisiteInvocationFailure(
        "Copy",
        arguments
    ) == 1
}

test "string dictionary entry enumeration preserves insertion and value order" {
    source := new Dictionary<string, string>(StringComparer.Ordinal)
    source["second"] = "2"
    source["first"] = "1"

    assert DictionarySequencePrerequisiteEmitFacts.Walk(source) == "second=2|first=1"
}

test "dictionary entry enumeration acquires before try and disposes on body and movement failure" {
    acquisitionState := new DictionarySequencePrerequisiteState()
    acquisitionArguments := new object?[](2)
    acquisitionArguments[0] = null
    DictionarySequencePrerequisiteSetObject(
        acquisitionArguments,
        1,
        acquisitionState
    )
    assert DictionarySequencePrerequisiteInvocationFailure(
        "WalkThenThrow",
        acquisitionArguments
    ) == 2
    assert acquisitionState.AcquisitionCount == 0
    assert acquisitionState.FinallyCount == 0

    source := new Dictionary<string, string>(StringComparer.Ordinal)
    source["first"] = "1"

    bodyState := new DictionarySequencePrerequisiteState()
    assert throws InvalidOperationException {
        _result := DictionarySequencePrerequisiteEmitFacts.WalkThenThrow(
            source,
            bodyState
        )
    }
    assert bodyState.AcquisitionCount == 1
    assert bodyState.FinallyCount == 1

    mutationState := new DictionarySequencePrerequisiteState()
    assert throws InvalidOperationException {
        _result := DictionarySequencePrerequisiteEmitFacts.WalkThenMutate(
            source,
            source,
            mutationState
        )
    }
    assert mutationState.AcquisitionCount == 1
    assert mutationState.FinallyCount == 1
    assert source["late"] == "mutation"
}
