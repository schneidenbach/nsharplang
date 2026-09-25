namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

record CallSiteResult(Name: string, File: string?, Line: int, Column: int) {
}

record CallGraphResult(Function: string?, Callers: List<CallSiteResult>, Callees: List<CallSiteResult>, Truncated: bool) {
}
