namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

public class CompletionReceiverScratch {
    Contexts: int[] = new int[](1)
    Prefixes: string[] = new string[](1)
    Receivers: string[] = new string[](1)

    constructor() {
        Prefixes[0] = ""
        Receivers[0] = ""
    }
}

public class CompletionItemGroupingScratch {
    kindIds: Dictionary<string, int> = new Dictionary<string, int>(StringComparer.Ordinal)

    KindCounts: int[] = new int[](0)
    KindIds: int[] = new int[](0)
    KindNames: string[] = new string[](0)
    KindOffsets: int[] = new int[](0)
    ResultCounts: int[] = new int[](0)
    ResultIndices: int[] = new int[](0)
    ResultKindIds: int[] = new int[](0)
    ResultStarts: int[] = new int[](0)

    public func EnsureCapacity(count: int) {
        if KindIds.Length != count {
            KindIds = new int[](count)
            ResultKindIds = new int[](count)
            ResultStarts = new int[](count)
            ResultCounts = new int[](count)
            ResultIndices = new int[](count)
        }

        bucketCapacity := count + 1
        if KindCounts.Length < bucketCapacity {
            KindCounts = new int[](bucketCapacity)
            KindOffsets = new int[](bucketCapacity)
            KindNames = new string[](bucketCapacity)
        }
    }

    public func GetKindId(kind: string): int {
        id := 0
        if kindIds.TryGetValue(kind, out id) {
            return id
        }

        id = kindIds.Count + 1
        kindIds.Add(kind, id)
        KindNames[id] = kind
        return id
    }

    public func GetKindName(id: int): string {
        if id > 0 && id < KindNames.Length {
            name := KindNames[id]
            if name != null {
                return name
            }
        }

        return ""
    }

    public func ResetKindIds() {
        if kindIds.Count > 0 {
            Array.Clear(KindNames, 1, kindIds.Count)
            kindIds.Clear()
        }
    }
}
