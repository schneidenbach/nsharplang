namespace NSharpLang.LanguageServer.Models;

public sealed record SymbolLocation(
    string Name,
    SymbolKind Kind,
    string Uri,
    int Line,
    int Column,
    int Length
);

