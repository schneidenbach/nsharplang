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
