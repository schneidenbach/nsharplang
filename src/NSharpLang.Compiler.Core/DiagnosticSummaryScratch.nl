namespace NSharpLang.Compiler.CodeIntelligence

class DiagnosticSummaryScratch {
    Counts: int[]
    Severities: string[]

    func EnsureCapacity(count: int) {
        EnsureInitialized()
        if Severities.Length < count {
            Severities = new string[](count)
        }
    }

    func EnsureInitialized() {
        if Counts != null {
            return
        }

        Counts = new int[](3)
        Severities = new string[](0)
    }
}
