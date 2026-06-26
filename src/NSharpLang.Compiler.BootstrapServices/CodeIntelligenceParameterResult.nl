namespace NSharpLang.Compiler.CodeIntelligence

public record ParameterResult(
    Name: string,
    Type: string,
    HasDefault: bool,
    DefaultValue: string?) {
}
