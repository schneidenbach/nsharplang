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

    static func CopyReadOnly(
        source: IReadOnlyDictionary<string, Type>
    ): Dictionary<string, Type> {
        return new Dictionary<string, Type>(source, StringComparer.Ordinal)
    }

    static func CreateReadOnlyCopySource(): object {
        source := new Dictionary<string, Type>(StringComparer.OrdinalIgnoreCase)
        source["Alpha"] = typeof(int)
        source["Second"] = typeof(string)
        return source
    }

    static func VerifyReadOnlyCopy(
        source: IReadOnlyDictionary<string, Type>
    ): string {
        copied := new Dictionary<string, Type>(source, StringComparer.Ordinal)
        if copied.get_Count() != 2 {
            throw new InvalidOperationException("Dictionary read-only copy lost populated rows.")
        }

        firstValue := copied["Alpha"]
        expectedFirstValue := typeof(int)
        secondValue := copied["Second"]
        expectedSecondValue := typeof(string)
        if !Object.ReferenceEquals(firstValue, expectedFirstValue) || !Object.ReferenceEquals(secondValue, expectedSecondValue) {
            throw new InvalidOperationException("Dictionary read-only copy lost value identity.")
        }

        comparerProperty := copied.GetType().GetProperty("Comparer")
        if comparerProperty == null {
            throw new InvalidOperationException("Dictionary comparer property was not found.")
        }
        comparer := comparerProperty.GetValue(copied)
        if !Object.ReferenceEquals(comparer, StringComparer.Ordinal) {
            throw new InvalidOperationException("Dictionary read-only copy lost comparer identity.")
        }
        if !copied.ContainsKey("Alpha") || copied.ContainsKey("alpha") {
            throw new InvalidOperationException("Dictionary read-only copy lost ordinal comparison.")
        }

        copied["ALPHA"] = typeof(long)
        retainedValue := copied["Alpha"]
        expectedRetainedValue := typeof(int)
        distinctValue := copied["ALPHA"]
        expectedDistinctValue := typeof(long)
        if copied.get_Count() != 3 || !Object.ReferenceEquals(retainedValue, expectedRetainedValue) || !Object.ReferenceEquals(distinctValue, expectedDistinctValue) {
            throw new InvalidOperationException("Dictionary read-only copy did not retain distinct ordinal keys.")
        }

        copied["copy-only"] = typeof(short)
        if source.ContainsKey("copy-only") {
            throw new InvalidOperationException("Dictionary read-only copy shares later writes with its source.")
        }
        return "copy-ok"
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
