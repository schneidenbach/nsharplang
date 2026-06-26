namespace NSharpLang.Compiler.Performance

public record SystemsAotReport(
    Target: string,
    Analysis: string,
    NativeImageEmitted: bool,
    TrimSafe: bool) {
}
