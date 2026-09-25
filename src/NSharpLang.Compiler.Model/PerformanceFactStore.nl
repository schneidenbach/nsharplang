namespace NSharpLang.Compiler.Performance

import System.Collections.Generic

class PerformanceFactStore {
    facts: Dictionary<(File: string?, Line: int, Column: int), PerformanceFacts>?

    Count: int => Facts.Count

    All: Dictionary<(File: string?, Line: int, Column: int), PerformanceFacts> => Facts

    func Record(filePath: string?, line: int, column: int, fact: PerformanceFacts) {
        key := (File: filePath, Line: line, Column: column)
        Facts.Remove(key)
        Facts.Add(key, fact)
    }

    func Lookup(filePath: string?, line: int, column: int): PerformanceFacts? {
        value := PerformanceFacts.Default
        if Facts.TryGetValue((File: filePath, Line: line, Column: column), out value) {
            return value
        }

        return null
    }

    func Merge(other: PerformanceFactStore) {
        for entry in other.All {
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
