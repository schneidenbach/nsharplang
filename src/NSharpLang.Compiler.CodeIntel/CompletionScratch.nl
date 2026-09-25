namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

class CompletionReceiverScratch {
    Contexts: int[]
    Prefixes: string[]
    Receivers: string[]

    constructor() {
        Contexts = new int[](1)
        Prefixes = new string[](1)
        Receivers = new string[](1)
        Prefixes[0] = ""
        Receivers[0] = ""
    }
}

class CompletionItemGroupingScratch {
    kindIds: Dictionary<string, int>

    KindCounts: int[]
    KindIds: int[]
    KindNames: string[]
    KindOffsets: int[]
    ResultCounts: int[]
    ResultIndices: int[]
    ResultKindIds: int[]
    ResultStarts: int[]

    func EnsureCapacity(count: int) {
        EnsureInitialized()
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

    func GetKindId(kind: string): int {
        EnsureInitialized()
        id := 0
        if kindIds.TryGetValue(kind, out id) {
            return id
        }

        id = kindIds.Count + 1
        kindIds.Add(kind, id)
        KindNames[id] = kind
        return id
    }

    func GetKindName(id: int): string {
        EnsureInitialized()
        if id > 0 && id < KindNames.Length {
            name := KindNames[id]
            if name != null {
                return name
            }
        }

        return ""
    }

    func ResetKindIds() {
        EnsureInitialized()
        if kindIds.Count > 0 {
            Array.Clear(KindNames, 1, kindIds.Count)
            kindIds.Clear()
        }
    }

    func EnsureInitialized() {
        if kindIds != null {
            return
        }

        kindIds = new Dictionary<string, int>(StringComparer.Ordinal)
        KindCounts = new int[](0)
        KindIds = new int[](0)
        KindNames = new string[](0)
        KindOffsets = new int[](0)
        ResultCounts = new int[](0)
        ResultIndices = new int[](0)
        ResultKindIds = new int[](0)
        ResultStarts = new int[](0)
    }
}
