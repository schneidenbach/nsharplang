namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func ClosureCollectionExerciseProductionKeyViews(): bool {
    localBuilders := new Dictionary<string, LocalBuilder>(StringComparer.Ordinal)
    ordinals := new Dictionary<string, int>(StringComparer.Ordinal)
    lifted := new Dictionary<string, (Box: LocalBuilder, ValueType: Type)>(StringComparer.Ordinal)
    boxed := new Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>(StringComparer.Ordinal)

    localCopy := new HashSet<string>(localBuilders.Keys, StringComparer.Ordinal)
    ordinalCopy := new HashSet<string>(ordinals.Keys, StringComparer.Ordinal)
    liftedCopy := new HashSet<string>(lifted.Keys, StringComparer.Ordinal)
    boxedCopy := new HashSet<string>(boxed.Keys, StringComparer.Ordinal)
    localList := new List<string>(localBuilders.Keys)
    ordinalList := new List<string>(ordinals.Keys)
    liftedList := new List<string>(lifted.Keys)
    boxedList := new List<string>(boxed.Keys)

    names := new HashSet<string>(StringComparer.Ordinal)
    names.UnionWith(localBuilders.Keys)
    names.UnionWith(ordinals.Keys)
    names.UnionWith(lifted.Keys)
    names.UnionWith(boxed.Keys)

    return localCopy.get_Count() == 0 && ordinalCopy.get_Count() == 0 && liftedCopy.get_Count() == 0 && boxedCopy.get_Count() == 0 && localList.get_Count() == 0 && ordinalList.get_Count() == 0 && liftedList.get_Count() == 0 && boxedList.get_Count() == 0 && names.get_Count() == 0
}

class ClosureCollectionPrerequisiteEmitFacts {
    static func SortedWords(values: SortedSet<string>): string {
        enumerator := values.GetEnumerator()
        result := ""
        try {
            while enumerator.MoveNext() {
                if result.Length > 0 {
                    result = result + "|"
                }
                result = result + enumerator.get_Current()
            }
        } finally {
            enumerator.Dispose()
        }
        return result
    }

    static func AdvanceAfterMutation(values: SortedSet<string>): bool {
        enumerator := values.GetEnumerator()
        advanced := false
        try {
            if !enumerator.MoveNext() {
                throw new InvalidOperationException("The mutation control requires an initial value.")
            }
            if !values.Add("late") {
                throw new InvalidOperationException("The mutation control requires a new value.")
            }
            advanced = enumerator.MoveNext()
        } finally {
            enumerator.Dispose()
        }
        return advanced
    }
}

test "packaged collection constructors preserve comparer order and duplicate semantics" {
    source := new HashSet<string>(StringComparer.Ordinal)
    assert source.Add("b")
    assert source.Add("A")
    assert source.Add("a")

    ordinalHash := new HashSet<string>(source, StringComparer.Ordinal)
    ignoreCaseHash := new HashSet<string>(source, StringComparer.OrdinalIgnoreCase)
    assert ordinalHash.get_Count() == 3
    assert ignoreCaseHash.get_Count() == 2
    assert !ignoreCaseHash.Add("a")

    copiedSorted := new SortedSet<string>(source, StringComparer.Ordinal)
    assert copiedSorted.get_Count() == 3
    assert !copiedSorted.Add("a")
    assert ClosureCollectionPrerequisiteEmitFacts.SortedWords(copiedSorted) == "A|a|b"

    directSorted := new SortedSet<string>(StringComparer.OrdinalIgnoreCase)
    assert directSorted.Add("b")
    assert directSorted.Add("A")
    assert !directSorted.Add("a")
    assert ClosureCollectionPrerequisiteEmitFacts.SortedWords(directSorted) == "A|b"

    assert throws InvalidOperationException {
        ClosureCollectionPrerequisiteEmitFacts.AdvanceAfterMutation(copiedSorted)
    }
    assert copiedSorted.Contains("late")
}

test "packaged Dictionary Keys remain live through copy and union operations" {
    values := new Dictionary<string, int>(StringComparer.Ordinal)
    liveKeys := values.Keys
    values["first"] = 1

    copied := new HashSet<string>(liveKeys, StringComparer.Ordinal)
    assert copied.get_Count() == 1
    assert copied.Contains("first")

    values["second"] = 2
    copied.UnionWith(liveKeys)
    assert copied.get_Count() == 2
    assert copied.Contains("second")
}

test "List construction snapshots the live Dictionary Keys view" {
    values := new Dictionary<string, int>(StringComparer.Ordinal)
    values["first"] = 1
    values["second"] = 2
    liveKeys := values.Keys

    snapshot := new List<string>(liveKeys)
    assert snapshot.get_Count() == 2
    assert snapshot.Contains("first")
    assert snapshot.Contains("second")

    assert values.Remove("first")
    values["third"] = 3
    assert liveKeys.get_Count() == 2
    assert !liveKeys.Contains("first")
    assert liveKeys.Contains("third")
    assert snapshot.get_Count() == 2
    assert snapshot.Contains("first")
    assert snapshot.Contains("second")
    assert !snapshot.Contains("third")
}

test "every production Dictionary Keys shape flows unchanged into HashSet operations" {
    assert ClosureCollectionExerciseProductionKeyViews()

    values := new Dictionary<string, int>(StringComparer.Ordinal)
    liveKeys := values.Keys
    values["first"] = 1
    copied := new HashSet<string>(liveKeys, StringComparer.Ordinal)
    assert copied.get_Count() == 1
    assert copied.Contains("first")

    values["second"] = 2
    copied.UnionWith(liveKeys)
    assert copied.get_Count() == 2
    assert copied.Contains("second")
}

test "HashSet copy construction uses the supplied comparer before duplicate insertion" {
    source := new HashSet<string>(StringComparer.Ordinal)
    assert source.Add("A")
    assert source.Add("a")

    ordinal := new HashSet<string>(source, StringComparer.Ordinal)
    ignoreCase := new HashSet<string>(source, StringComparer.OrdinalIgnoreCase)
    assert ordinal.get_Count() == 2
    assert ignoreCase.get_Count() == 1
    assert !ignoreCase.Add("a")
}

test "SortedSet constructors retain comparer ordering duplicates mutation and disposal" {
    source := new HashSet<string>(StringComparer.Ordinal)
    assert source.Add("b")
    assert source.Add("A")
    assert source.Add("a")

    copied := new SortedSet<string>(source, StringComparer.Ordinal)
    assert copied.get_Count() == 3
    assert !copied.Add("a")
    assert ClosureCollectionPrerequisiteEmitFacts.SortedWords(copied) == "A|a|b"

    direct := new SortedSet<string>(StringComparer.OrdinalIgnoreCase)
    assert direct.Add("b")
    assert direct.Add("A")
    assert !direct.Add("a")
    assert ClosureCollectionPrerequisiteEmitFacts.SortedWords(direct) == "A|b"

    assert throws InvalidOperationException {
        ClosureCollectionPrerequisiteEmitFacts.AdvanceAfterMutation(copied)
    }
    assert copied.Contains("late")
}
