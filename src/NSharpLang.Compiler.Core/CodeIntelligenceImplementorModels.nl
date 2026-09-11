namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

record ImplementorResult(TypeName: string, Kind: string, File: string?, Line: int, Column: int) {
}

record ImplementorsResult(Interface: string, Results: List<ImplementorResult>) {
}
