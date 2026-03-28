using System;
using System.Collections.Generic;

namespace NSharpLang.Compiler.Ast;

// Base class for declarations
public abstract record Declaration(int Line, int Column) : AstNode(Line, Column);

// Compilation unit (file)
public record CompilationUnit(
    NamespaceDeclaration? Namespace,
    List<ImportDirective> Imports,
    List<Statement> FileImports,
    PackageDeclaration? Package,
    List<Declaration> Declarations,
    int Line,
    int Column) : AstNode(Line, Column);

// Import directive
public record ImportDirective(
    string Namespace,
    string? Alias,
    int Line,
    int Column);

// Package declaration
public record PackageDeclaration(
    string Name,
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
    bool IsConversionOperator,     // For implicit/explicit conversion operators
    bool IsImplicitConversion,     // true = implicit, false = explicit
    int Line,
    int Column) : Declaration(Line, Column)
{
    // Convenience property: true if both Async and Generator modifiers are set (async*)
    public bool IsAsyncIterator => Modifiers.HasFlag(Modifiers.Async) && Modifiers.HasFlag(Modifiers.Generator);
};

public enum ParameterModifier
{
    None,
    Ref,
    Out,
    Params
}

public record Parameter(
    string Name,
    TypeReference Type,
    Expression? DefaultValue,
    bool IsThis, // For extension methods
    ParameterModifier Modifier = ParameterModifier.None);

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
    List<Parameter>? PrimaryConstructorParameters, // C# 12 primary constructor
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
    List<Parameter>? PrimaryConstructorParameters, // C# 12 primary constructor
    Modifiers Modifiers,
    List<AttributeNode> Attributes,
    int Line,
    int Column) : Declaration(Line, Column);

// Record declaration (can be record class or record struct - C# 10)
public record RecordDeclaration(
    string Name,
    List<TypeParameter>? TypeParameters,
    List<TypeReference> Interfaces,
    List<Declaration> Members,
    List<Parameter>? PrimaryConstructorParameters, // C# 12 primary constructor
    bool IsStruct, // C# 10: record struct (value type) vs record class (reference type, default)
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
    List<UnionCaseProperty>? Properties,
    int Line = 0,
    int Column = 0);

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
    Expression? Value,
    int Line = 0,
    int Column = 0);

public enum EnumType
{
    Int,
    String
}

// Field/Property declaration (auto-property)
[Flags]
public enum PropertyModifier
{
    None = 0,
    Required = 1 << 0,   // C# 11 - property must be set during initialization
    Init = 1 << 1,       // C# 9 - property can only be set during initialization
    Readonly = 1 << 2    // Readonly fields (can only be set in constructor)
}

public record FieldDeclaration(
    string Name,
    TypeReference? Type,  // Nullable to support type inference with :=
    Expression? Initializer,
    Modifiers Modifiers,
    PropertyModifier PropertyModifier,
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
    PropertyModifier PropertyModifier,
    List<AttributeNode> Attributes,
    int Line,
    int Column) : Declaration(Line, Column);

// Constructor declaration
public record ConstructorDeclaration(
    List<Parameter> Parameters,
    BlockStatement Body,
    Expression? Initializer,  // this() or base() call
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
    Required = 1 << 13,  // C# 11 required properties
    Init = 1 << 14,      // C# 9 init-only properties
    File = 1 << 15,      // C# 11 file-scoped types
    Override = 1 << 16,  // C# override methods
}

// Attributes
public record AttributeNode(
    string Name,
    List<Argument> Arguments);

// Type references
public abstract record TypeReference;

public record SimpleTypeReference(string Name, int Line = 0, int Column = 0) : TypeReference;

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
