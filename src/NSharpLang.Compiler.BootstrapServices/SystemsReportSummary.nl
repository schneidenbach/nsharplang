namespace NSharpLang.Compiler.Performance

public record SystemsReportSummary(
    Functions: int,
    HotFunctions: int,
    BoundaryFunctions: int,
    Findings: int,
    Errors: int,
    Warnings: int,
    TrustedSites: int) {
}
