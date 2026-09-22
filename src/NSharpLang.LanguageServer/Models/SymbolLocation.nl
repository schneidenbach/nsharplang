namespace NSharpLang.LanguageServer.Models

record SymbolLocation(Name: string, Kind: SymbolKind, Uri: string, Line: int, Column: int, Length: int) {
}
