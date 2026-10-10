namespace NSharpLang.Compiler.Performance

record SystemsAotReport(Target: string, Analysis: string, NativeImageEmitted: bool, TrimSafe: bool) {
}
