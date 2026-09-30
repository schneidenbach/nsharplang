namespace NSharpLang.Compiler

enum ScopeKind {
    Global,
    Class,
    Struct,
    Record,
    Interface,
    Function,
    Block
}

enum UnknownKind {
    ErrorRecovery,
    InferenceHole,
    DeferredExternal
}
