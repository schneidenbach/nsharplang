namespace NSharpLang.Compiler.TestStubs

import System.Collections.Generic
import NSharpLang.Compiler.Ast

// Declaration stand-ins for the AnalyzerDeclarationContext tests. The context takes declarations as
// `object` and dispatches on the REFLECTED SIMPLE TYPE NAME (DeclarationFacts.DeclarationKind and
// friends compare GetType().Name against "ClassDeclaration"/"FieldDeclaration"/"TypeAliasDeclaration"),
// so these stubs MUST keep the exact simple names of the real Ast nodes to be recognized. They live in
// this dedicated namespace — NOT NSharpLang.Compiler — so a file importing both NSharpLang.Compiler and
// NSharpLang.Compiler.Ast never sees an ambiguous simple name (the tests-enabled-build collision that
// forced fully-qualified `new NSharpLang.Compiler.Ast.*` construction in the parser owner).

public class ClassDeclaration {
    Name: string
    Line: int
    Column: int
    Modifiers: int
    BaseClass: TypeReference?
    Interfaces: List<TypeReference>
    TypeParameters: List<TypeParameter>
    PrimaryConstructorParameters: List<object>
    Members: List<object>

    constructor(name: string, baseClass: TypeReference?) {
        Name = name
        Line = 1
        Column = 1
        Modifiers = 0
        BaseClass = baseClass
        Interfaces = new List<TypeReference>()
        TypeParameters = new List<TypeParameter>()
        PrimaryConstructorParameters = new List<object>()
        Members = new List<object>()
    }
}

public class TypeAliasDeclaration {
    Name: string
    Type: TypeReference
    Line: int
    Column: int

    constructor(name: string, typeReference: TypeReference) {
        Name = name
        Type = typeReference
        Line = 1
        Column = 1
    }
}

public class FieldDeclaration {
    Name: string
    Type: TypeReference
    Modifiers: int
    Line: int
    Column: int

    constructor(
        name: string,
        typeReference: TypeReference,
        modifiers: int) {
        Name = name
        Type = typeReference
        Modifiers = modifiers
        Line = 1
        Column = 1
    }
}
