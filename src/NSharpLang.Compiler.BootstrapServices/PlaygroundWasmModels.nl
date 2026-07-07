namespace NSharpLang.Playground.Wasm

public record PlaygroundVersionResponse(
    SchemaVersion: int,
    Compiler: string,
    WasmHost: string) {
}
