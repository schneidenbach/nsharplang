namespace NSharpLang.Compiler.CodeIntelligence

public class DiagnosticSummaryScratch {
    Counts: int[] = new int[](3)
    Severities: string[] = new string[](0)

    public func EnsureCapacity(count: int) {
        if Severities.Length < count {
            Severities = new string[](count)
        }
    }
}
