using System;
using System.Collections.Generic;

namespace NewCLILang.Compiler.Ast;

// Base class for declarations
public abstract record Declaration(int Line, int Column) : AstNode(Line, Column);

// Compilation unit (file)
public record CompilationUnit(
    NamespaceDeclaration? Namespace,
    List<UsingDirective> Usings,
    List<Statement> Imports,
    List<Declaration> Declarations,
    int Line,
    int Column) : AstNode(Line, Column);

// Using directive
public record UsingDirective(
    string Namespace,
    string? Alias,
    int Line,
    int Column);

// Namespace declaration
public record NamespaceDeclaration(
    string Name,
    int Line,
    int Column);

// Function declaration
public record FunctionDeclaration(
    string Name,
    List<Parameter> Parameters,
    TypeReference? ReturnType,
    BlockStatement? Body,
    Expression? ExpressionBody,  // For expression-bodied methods (func Foo() => expr)
    List<TypeParameter>? TypeParameters,
    List<GenericConstraint>? Constraints,
    Modifiers Modifiers,
    List<AttributeNode> Attributes,
    bool IsOperatorOverload,      // For operator overloads
    string? OperatorSymbol,        // The operator symbol (+, -, *, etc.)
    int Line,
    int Column) : Declaration(Line, Column);

public record Parameter(
    string Name,
    TypeReference Type,
    Expression? DefaultValue,
    bool IsThis); // For extension methods

public record TypeParameter(string Name);

public record GenericConstraint(
    string TypeParameter,
    List<TypeReference> Constraints);

// Class declaration
public record ClassDeclaration(
    string Name,
    List<TypeParameter>? TypeParameters,
    TypeReference? BaseClass,
    List<TypeReference> Interfaces,
    List<Declaration> Members,
    Modifiers Modifiers,
    List<AttributeNode> Attributes,
    int Line,
    int Column) : Declaration(Line, Column);

// Struct declaration
public record StructDeclaration(
    string Name,
    List<TypeParameter>? TypeParameters,
    List<TypeReference> Interfaces,
    List<Declaration> Members,
    Modifiers Modifiers,
    List<AttributeNode> Attributes,
    int Line,
    int Column) : Declaration(Line, Column);

// Record declaration
public record RecordDeclaration(
    string Name,
    List<TypeParameter>? TypeParameters,
    List<TypeReference> Interfaces,
    List<Declaration> Members,
    Modifiers Modifiers,
    List<AttributeNode> Attributes,
    int Line,
    int Column) : Declaration(Line, Column);

// Interface declaration
public record InterfaceDeclaration(
    string Name,
    List<TypeParameter>? TypeParameters,
    List<TypeReference> BaseInterfaces,
    List<Declaration> Members,
    Modifiers Modifiers,
    bool IsDuckInterface,
    List<AttributeNode> Attributes,
    int Line,
    int Column) : Declaration(Line, Column);

// Union declaration
public record UnionDeclaration(
    string Name,
    List<UnionCase> Cases,
    Modifiers Modifiers,
    List<AttributeNode> Attributes,
    int Line,
    int Column) : Declaration(Line, Column);

public record UnionCase(
    string Name,
    List<UnionCaseProperty>? Properties);

public record UnionCaseProperty(
    string Name,
    TypeReference Type);

// Enum declaration
public record EnumDeclaration(
    string Name,
    List<EnumMember> Members,
    EnumType Type,
    Modifiers Modifiers,
    List<AttributeNode> Attributes,
    int Line,
    int Column) : Declaration(Line, Column);

public record EnumMember(
    string Name,
    Expression? Value);

public enum EnumType
{
    Int,
    String
}

// Field/Property declaration (auto-property)
public record FieldDeclaration(
    string Name,
    TypeReference Type,
    Expression? Initializer,
    Modifiers Modifiers,
    List<AttributeNode> Attributes,
    int Line,
    int Column) : Declaration(Line, Column);

// Property declaration with custom get/set
public record PropertyDeclaration(
    string Name,
    TypeReference Type,
    BlockStatement? GetBody,
    BlockStatement? SetBody,
    Expression? ExpressionBody,  // For expression-bodied properties (Prop: type => expr)
    Modifiers Modifiers,
    List<AttributeNode> Attributes,
    int Line,
    int Column) : Declaration(Line, Column);

// Constructor declaration
public record ConstructorDeclaration(
    List<Parameter> Parameters,
    BlockStatement Body,
    Modifiers Modifiers,
    List<AttributeNode> Attributes,
    int Line,
    int Column) : Declaration(Line, Column);

// Indexer declaration
public record IndexerDeclaration(
    List<Parameter> Parameters,
    TypeReference Type,
    BlockStatement? GetBody,
    BlockStatement? SetBody,
    Modifiers Modifiers,
    List<AttributeNode> Attributes,
    int Line,
    int Column) : Declaration(Line, Column);

// Type alias
public record TypeAliasDeclaration(
    string Name,
    TypeReference Type,
    int Line,
    int Column) : Declaration(Line, Column);

// Preprocessor directive wrapper (for top-level preprocessor directives)
public record PreprocessorDeclaration(
    string Directive,  // Full directive text including # (e.g., "#if DEBUG", "#region Helpers")
    int Line,
    int Column) : Declaration(Line, Column);

// Modifiers
[Flags]
public enum Modifiers
{
    None = 0,
    Public = 1 << 0,
    Private = 1 << 1,
    Internal = 1 << 2,
    Protected = 1 << 3,
    Static = 1 << 4,
    Virtual = 1 << 5,
    Abstract = 1 << 6,
    Sealed = 1 << 7,
    Partial = 1 << 8,
    Readonly = 1 << 9,
    Const = 1 << 10,
    Async = 1 << 11,
    Generator = 1 << 12, // For func* (yield)
}

// Attributes
public record AttributeNode(
    string Name,
    List<Argument> Arguments);

// Type references
public abstract record TypeReference;

public record SimpleTypeReference(string Name) : TypeReference;

public record GenericTypeReference(
    string Name,
    List<TypeReference> TypeArguments) : TypeReference;

public record ArrayTypeReference(TypeReference ElementType) : TypeReference;

public record NullableTypeReference(TypeReference InnerType) : TypeReference;

public record TupleTypeReference(List<TupleTypeElement> Elements) : TypeReference;

public record TupleTypeElement(TypeReference Type, string? Name);

public record FunctionTypeReference(
    List<TypeReference> ParameterTypes,
    TypeReference ReturnType) : TypeReference;

// Test declaration (for .tests.nl files)
public record TestDeclaration(
    string Description,
    BlockStatement Body,
    int Line,
    int Column) : Declaration(Line, Column);
