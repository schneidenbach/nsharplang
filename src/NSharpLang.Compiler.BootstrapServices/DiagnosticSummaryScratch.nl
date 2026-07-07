namespace NSharpLang.Compiler.CodeIntelligence

public class DiagnosticSummaryScratch {
    Counts: int[]
    Severities: string[]

    public func EnsureCapacity(count: int) {
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
