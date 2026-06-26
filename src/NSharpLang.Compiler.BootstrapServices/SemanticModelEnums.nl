namespace NSharpLang.Compiler

public enum ScopeKind {
    Global,
    Class,
    Struct,
    Record,
    Interface,
    Function,
    Block
}

public enum UnknownKind {
    ErrorRecovery,
    InferenceHole,
    DeferredExternal
}
