namespace NSharpLang.Playground.Wasm

record PlaygroundVersionResponse(SchemaVersion: int, Compiler: string, WasmHost: string) {
}
