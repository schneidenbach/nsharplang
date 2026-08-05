namespace NSharpLang.Compiler.CodeIntelligence

record PerfReportSite(Code: string, Effect: string, File: string, Line: int, Column: int, Message: string, Function: string?, Suggestion: string?) {
}

record PerfReportTrustedSite(Function: string, File: string, Line: int, Column: int, Owner: string?, Review: string?, Expires: string?, HasUnsafe: bool, BodyStatementCount: int) {
}
