namespace NSharpLang.Compiler.Performance

import System.Collections.Generic

public class PerformanceFactStore {
    facts: Dictionary<(File: string?, Line: int, Column: int), PerformanceFacts> = new Dictionary<(File: string?, Line: int, Column: int), PerformanceFacts>()

    public Count: int => facts.Count

    public All: Dictionary<(File: string?, Line: int, Column: int), PerformanceFacts> => facts

    public func Record(filePath: string?, line: int, column: int, fact: PerformanceFacts) {
        key := (File: filePath, Line: line, Column: column)
        facts.Remove(key)
        facts.Add(key, fact)
    }

    public func Lookup(filePath: string?, line: int, column: int): PerformanceFacts? {
        value := PerformanceFacts.Default
        if facts.TryGetValue((File: filePath, Line: line, Column: column), out value) {
            return value
        }

        return null
    }

    public func Merge(other: PerformanceFactStore) {
        foreach entry in other.facts {
            facts.Remove(entry.Key)
            facts.Add(entry.Key, entry.Value)
        }
    }
}
