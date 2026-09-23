namespace NSharpLang.Compiler.Ast

// `In` IS APPENDED RATHER THAN INSERTED. The columnar pipeline encodes the same concept as an int
// (`ParamModifierKinds`: 1 ref, 2 out, 3 params, 4 the extension `this`) and several owners compare
// against those literals, so the three that already exist keep their ordinals and `in` takes the next
// free one. The two encodings therefore still agree member-for-member.
enum ParameterModifier {
    None,
    Ref,
    Out,
    Params,
    In
}

enum EnumType {
    Int,
    String
}

enum SpecialConstraintKind {
    None = 0,
    Class = 1,
    Struct = 2,
    New = 4
}

enum PropertyModifier {
    None = 0,
    Required = 1,
    Init = 2,
    Readonly = 4
}

enum Modifiers {
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
