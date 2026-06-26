namespace NSharpLang.Compiler.Ast

public enum ParameterModifier {
    None,
    Ref,
    Out,
    Params
}

public enum EnumType {
    Int,
    String
}

public enum SpecialConstraintKind {
    None = 0,
    Class = 1,
    Struct = 2,
    New = 4
}

public enum PropertyModifier {
    None = 0,
    Required = 1,
    Init = 2,
    Readonly = 4
}

public enum Modifiers {
    None = 0,
    Public = 1,
    Private = 2,
    Internal = 4,
    Protected = 8,
    Static = 16,
    Virtual = 32,
    Abstract = 64,
    Sealed = 128,
    Partial = 256,
    Readonly = 512,
    Const = 1024,
    Async = 2048,
    Generator = 4096,
    Required = 8192,
    Init = 16384,
    File = 32768,
    Override = 65536
}
