namespace NSharpLang.Compiler.Performance

import System.Collections.Generic

public class PerformanceFactStore {
    facts: Dictionary<(File: string?, Line: int, Column: int), PerformanceFacts>?

    public Count: int => Facts.Count

    public All: Dictionary<(File: string?, Line: int, Column: int), PerformanceFacts> => Facts

    public func Record(filePath: string?, line: int, column: int, fact: PerformanceFacts) {
        key := (File: filePath, Line: line, Column: column)
        Facts.Remove(key)
        Facts.Add(key, fact)
    }

    public func Lookup(filePath: string?, line: int, column: int): PerformanceFacts? {
        value := PerformanceFacts.Default
        if Facts.TryGetValue((File: filePath, Line: line, Column: column), out value) {
            return value
        }

        return null
    }

    public func Merge(other: PerformanceFactStore) {
        foreach entry in other.All {
            Facts.Remove(entry.Key)
            Facts.Add(entry.Key, entry.Value)
        }
    }

    Facts: Dictionary<(File: string?, Line: int, Column: int), PerformanceFacts> {
        get {
            if facts == null {
                facts = new Dictionary<(File: string?, Line: int, Column: int), PerformanceFacts>()
            }

            return facts
        }
    }
}
