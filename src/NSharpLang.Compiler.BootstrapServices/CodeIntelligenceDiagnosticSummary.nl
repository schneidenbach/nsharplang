namespace NSharpLang.Compiler.CodeIntelligence

public record DiagnosticSummary(
    Errors: int,
    Warnings: int,
    Info: int) {
}
