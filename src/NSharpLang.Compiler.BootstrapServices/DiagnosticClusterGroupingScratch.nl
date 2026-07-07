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
    CodeIdsByText: Dictionary<string, int>
    MessagePatternIdsByText: Dictionary<string, int>
    SeverityIdsByText: Dictionary<string, int>

    CategoryIds: int[]
    CodeIds: int[]
    Columns: int[]
    Files: string[]
    Counts: int[]
    GroupFirstMemberIndices: int[]
    GroupKeyIndices: int[]
    Lines: int[]
    MemberIndices: int[]
    MemberNextIndices: int[]
    MemberStarts: int[]
    MessagePatternIds: int[]
    RecipeIds: int[]
    RiskIds: int[]
    RootIndices: int[]
    SeverityIds: int[]
    SlotGroups: int[]
    SourceConstructIds: int[]

    public func EnsureCapacity(count: int) {
        EnsureInitialized()
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
        EnsureInitialized()
        return GetId(CodeIdsByText, text)
    }

    public func GetSeverityId(text: string): int {
        EnsureInitialized()
        return GetId(SeverityIdsByText, text)
    }

    public func GetMessagePatternId(text: string): int {
        EnsureInitialized()
        return GetId(MessagePatternIdsByText, text)
    }

    public func ClearFiles(count: int) {
        EnsureInitialized()
        Array.Clear(Files, 0, count)
    }

    public func ResetIds() {
        EnsureInitialized()
        CodeIdsByText.Clear()
        SeverityIdsByText.Clear()
        MessagePatternIdsByText.Clear()
    }

    func EnsureInitialized() {
        if CodeIdsByText != null {
            return
        }

        CodeIdsByText = new Dictionary<string, int>(StringComparer.Ordinal)
        MessagePatternIdsByText = new Dictionary<string, int>(StringComparer.Ordinal)
        SeverityIdsByText = new Dictionary<string, int>(StringComparer.Ordinal)
        CategoryIds = new int[](0)
        CodeIds = new int[](0)
        Columns = new int[](0)
        Files = new string[](0)
        Counts = new int[](0)
        GroupFirstMemberIndices = new int[](0)
        GroupKeyIndices = new int[](0)
        Lines = new int[](0)
        MemberIndices = new int[](0)
        MemberNextIndices = new int[](0)
        MemberStarts = new int[](0)
        MessagePatternIds = new int[](0)
        RecipeIds = new int[](0)
        RiskIds = new int[](0)
        RootIndices = new int[](0)
        SeverityIds = new int[](0)
        SlotGroups = new int[](0)
        SourceConstructIds = new int[](0)
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
