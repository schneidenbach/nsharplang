namespace NSharpLang.Compiler.CodeIntelligence

public class BindingCandidateColumnScratch {
    QueryColumns: int[] = new int[](1)
    ResultColumns: int[] = new int[](0)
    ResultCounts: int[] = new int[](1)
    ResultStarts: int[] = new int[](1)
    SpanEndColumns: int[] = new int[](1)
    SpanStartColumns: int[] = new int[](1)

    public func EnsureCapacity(resultCapacity: int) {
        if ResultColumns.Length < resultCapacity {
            ResultColumns = new int[](resultCapacity)
        }
    }
}
