namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

public record CallSiteResult(
    Name: string,
    File: string?,
    Line: int,
    Column: int) {
}

public record CallGraphResult(
    Function: string?,
    Callers: List<CallSiteResult>,
    Callees: List<CallSiteResult>,
    Truncated: bool) {
}
