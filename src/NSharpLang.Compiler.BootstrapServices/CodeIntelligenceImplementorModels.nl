namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

public record ImplementorResult(
    TypeName: string,
    Kind: string,
    File: string?,
    Line: int,
    Column: int) {
}

public record ImplementorsResult(
    Interface: string,
    Results: List<ImplementorResult>) {
}
