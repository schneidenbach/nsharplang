namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Collections.Generic

class DictionarySequencePrerequisiteState {
    EvaluationCount: int
    AcquisitionCount: int
    FinallyCount: int

    constructor() {
        EvaluationCount = 0
        AcquisitionCount = 0
        FinallyCount = 0
    }
}

class DictionarySequencePrerequisiteEmitFacts {
    static func Copy(source: IDictionary<string, string>): Dictionary<string, string> {
        return new Dictionary<string, string>(source)
    }

    static func EvaluatedSource(
        state: DictionarySequencePrerequisiteState,
        source: IDictionary<string, string>
    ): IDictionary<string, string> {
        state.EvaluationCount = state.EvaluationCount + 1
        return source
    }

    static func CopyEvaluated(
        state: DictionarySequencePrerequisiteState,
        source: IDictionary<string, string>
    ): Dictionary<string, string> {
        return new Dictionary<string, string>(EvaluatedSource(state, source))
    }

    static func Walk(source: IReadOnlyDictionary<string, string>): string {
        entries: IEnumerable<KeyValuePair<string, string>> = source
        enumerator := entries.GetEnumerator()
        result := ""
        try {
            while enumerator.MoveNext() {
                entry := enumerator.get_Current()
                if result.Length > 0 {
                    result = result + "|"
                }
                result = result + entry.get_Key() + "=" + entry.get_Value()
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return result
    }

    static func WalkThenThrow(
        source: IReadOnlyDictionary<string, string>,
        state: DictionarySequencePrerequisiteState
    ): string {
        entries: IEnumerable<KeyValuePair<string, string>> = source
        enumerator := entries.GetEnumerator()
        state.AcquisitionCount = state.AcquisitionCount + 1
        try {
            while enumerator.MoveNext() {
                _entry := enumerator.get_Current()
                throw new InvalidOperationException("dictionary sequence body failure")
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
            state.FinallyCount = state.FinallyCount + 1
        }
        return "empty"
    }

    static func WalkThenMutate(
        source: IReadOnlyDictionary<string, string>,
        mutableSource: Dictionary<string, string>,
        state: DictionarySequencePrerequisiteState
    ): string {
        entries: IEnumerable<KeyValuePair<string, string>> = source
        enumerator := entries.GetEnumerator()
        state.AcquisitionCount = state.AcquisitionCount + 1
        result := ""
        try {
            while enumerator.MoveNext() {
                entry := enumerator.get_Current()
                result = entry.get_Key()
                mutableSource["late"] = "mutation"
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
            state.FinallyCount = state.FinallyCount + 1
        }
        return result
    }
}
