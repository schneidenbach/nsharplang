namespace NSharpLang.Compiler.CodeIntelligence

record ParameterResult(Name: string, Type: string, HasDefault: bool, DefaultValue: string?) {
}
