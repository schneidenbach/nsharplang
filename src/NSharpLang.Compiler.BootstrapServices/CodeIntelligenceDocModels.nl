namespace NSharpLang.Compiler.CodeIntelligence

record DocMemberResult(Name: string, Kind: string, Type: string?, Summary: string?, Parameters: string?) {
}

record DocParameterResult(Name: string, Type: string, Summary: string?) {
}

record DocResult(Name: string, FullName: string, Kind: string, Summary: string?, Namespace: string?, Members: DocMemberResult[]?, Parameters: DocParameterResult[]?, ReturnType: string?, ReturnDoc: string?, BaseTypes: string[]?) {
}
