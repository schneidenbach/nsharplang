namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic

public class DiagnosticClusterGrouping {
    GroupCount: int
    RootIndices: int[]
    Counts: int[]
    MemberStarts: int[]
    MemberIndices: int[]

    constructor(
        groupCount: int,
        rootIndices: int[],
        counts: int[],
        memberStarts: int[],
        memberIndices: int[]) {
        GroupCount = groupCount
        RootIndices = rootIndices
        Counts = counts
        MemberStarts = memberStarts
        MemberIndices = memberIndices
    }
}

public class DiagnosticClusterGroupingScratch {
    CodeIdsByText: Dictionary<string, int> = new Dictionary<string, int>(StringComparer.Ordinal)
    MessagePatternIdsByText: Dictionary<string, int> = new Dictionary<string, int>(StringComparer.Ordinal)
    SeverityIdsByText: Dictionary<string, int> = new Dictionary<string, int>(StringComparer.Ordinal)

    CategoryIds: int[] = new int[](0)
    CodeIds: int[] = new int[](0)
    Columns: int[] = new int[](0)
    Files: string[] = new string[](0)
    Counts: int[] = new int[](0)
    GroupFirstMemberIndices: int[] = new int[](0)
    GroupKeyIndices: int[] = new int[](0)
    Lines: int[] = new int[](0)
    MemberIndices: int[] = new int[](0)
    MemberNextIndices: int[] = new int[](0)
    MemberStarts: int[] = new int[](0)
    MessagePatternIds: int[] = new int[](0)
    RecipeIds: int[] = new int[](0)
    RiskIds: int[] = new int[](0)
    RootIndices: int[] = new int[](0)
    SeverityIds: int[] = new int[](0)
    SlotGroups: int[] = new int[](0)
    SourceConstructIds: int[] = new int[](0)

    public func EnsureCapacity(count: int) {
        if CodeIds.Length != count {
            CodeIds = new int[](count)
            SeverityIds = new int[](count)
            CategoryIds = new int[](count)
            SourceConstructIds = new int[](count)
            RecipeIds = new int[](count)
            RiskIds = new int[](count)
            MessagePatternIds = new int[](count)
            Files = new string[](count)
            Lines = new int[](count)
            Columns = new int[](count)
            GroupKeyIndices = new int[](count)
            GroupFirstMemberIndices = new int[](count)
            MemberIndices = new int[](count)
            MemberNextIndices = new int[](count)
            MemberStarts = new int[](count)
            RootIndices = new int[](count)
            Counts = new int[](count)
        }

        slotCapacity := count * 2 + 1
        if SlotGroups.Length != slotCapacity {
            SlotGroups = new int[](slotCapacity)
        }
    }

    public func GetCodeId(text: string): int {
        return GetId(CodeIdsByText, text)
    }

    public func GetSeverityId(text: string): int {
        return GetId(SeverityIdsByText, text)
    }

    public func GetMessagePatternId(text: string): int {
        return GetId(MessagePatternIdsByText, text)
    }

    public func ClearFiles(count: int) {
        Array.Clear(Files, 0, count)
    }

    public func ResetIds() {
        CodeIdsByText.Clear()
        SeverityIdsByText.Clear()
        MessagePatternIdsByText.Clear()
    }

    static func GetId(ids: Dictionary<string, int>, text: string): int {
        if ids.ContainsKey(text) {
            return ids[text]
        }

        id := ids.Count + 1
        ids.Add(text, id)
        return id
    }
}
