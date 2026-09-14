namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System.Collections.Generic

class SourceRecordDictionaryKeyEmitFacts {
    private readonly Values: Dictionary<Site, List<Entry>> = new Dictionary<SourceRecordDictionaryKeyEmitFacts.Site, List<SourceRecordDictionaryKeyEmitFacts.Entry>>()
    private readonly Units: IReadOnlyDictionary<string, Entry> = new Dictionary<string, SourceRecordDictionaryKeyEmitFacts.Entry>()

    public constructor() {
        units := new Dictionary<string, SourceRecordDictionaryKeyEmitFacts.Entry>()
        units["first"] = new SourceRecordDictionaryKeyEmitFacts.Entry("one")
        units["second"] = new SourceRecordDictionaryKeyEmitFacts.Entry("two")
        Units = units
    }

    func Put(name: string, containingType: string?, line: int, column: int, parameterCount: int, value: string) {
        site := new SourceRecordDictionaryKeyEmitFacts.Site(name, containingType, line, column, parameterCount)
        entries := new List<SourceRecordDictionaryKeyEmitFacts.Entry>()
        entries.Add(new Entry(value))
        Values[site] = entries
    }

    func TryRead(name: string, containingType: string?, line: int, column: int, parameterCount: int): string {
        entries: List<Entry>? = null
        if !Values.TryGetValue(new Site(name, containingType, line, column, parameterCount), out entries) || entries == null {
            return "missing"
        }
        return entries[0].Value
    }

    func Read(name: string, containingType: string?, line: int, column: int, parameterCount: int): string {
        return Values[new Site(name, containingType, line, column, parameterCount)][0].Value
    }

    func Contains(name: string, containingType: string?, line: int, column: int, parameterCount: int): bool {
        return Values.ContainsKey(new Site(name, containingType, line, column, parameterCount))
    }

    func Count(): int {
        return Values.Count
    }

    func Clear() {
        Values.Clear()
    }

    func ReadUnits(): string {
        enumerator := Units.GetEnumerator()
        movement := enumerator as System.Collections.IEnumerator
        result := ""
        try {
            while movement.MoveNext() {
                entry := enumerator.get_Current()
                if result.Length > 0 {
                    result = result + "|"
                }
                result = result + entry.get_Key() + "=" + entry.get_Value().Value
            }
        } finally {
            disposable := enumerator as System.IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
        return result
    }

    private sealed record Entry(Value: string) {
    }

    private record struct Site {
        readonly Name: string
        readonly ContainingType: string?
        readonly Line: int
        readonly Column: int
        readonly ParameterCount: int

        public constructor(name: string, containingType: string?, line: int, column: int, parameterCount: int) {
            Name = name
            ContainingType = containingType
            Line = line
            Column = column
            ParameterCount = parameterCount
        }
    }
}
