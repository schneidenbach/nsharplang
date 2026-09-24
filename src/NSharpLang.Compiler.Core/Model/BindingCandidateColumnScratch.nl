namespace NSharpLang.Compiler.CodeIntelligence

class BindingCandidateColumnScratch {
    QueryColumns: int[]
    ResultColumns: int[]
    ResultCounts: int[]
    ResultStarts: int[]
    SpanEndColumns: int[]
    SpanStartColumns: int[]

    func EnsureCapacity(resultCapacity: int) {
        EnsureInitialized()
        if ResultColumns.Length < resultCapacity {
            ResultColumns = new int[](resultCapacity)
        }
    }

    func EnsureInitialized() {
        if QueryColumns != null {
            return
        }

        QueryColumns = new int[](1)
        ResultColumns = new int[](0)
        ResultCounts = new int[](1)
        ResultStarts = new int[](1)
        SpanEndColumns = new int[](1)
        SpanStartColumns = new int[](1)
    }
}
