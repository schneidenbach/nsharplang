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

    public SourceSpan OperatorKeywordSpan { get; init; } = SourceSpan.None;

    public SourceSpan OperatorSymbolSpan { get; init; } = SourceSpan.None;

    public string? ReturnLifetime { get; init; }
};

public record Parameter(
    string Name,
    TypeReference Type,
    Expression? DefaultValue,
    bool IsThis, // For extension methods
    ParameterModifier Modifier = ParameterModifier.None,
    List<AttributeNode>? Attributes = null,
    int Line = 0,
    int Column = 0,
    bool IsScoped = false,
    string? Lifetime = null);

public record GenericConstraint(
    string TypeParameter,
    List<TypeReference> Constraints,
    SpecialConstraintKind SpecialConstraints = SpecialConstraintKind.None);

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
    int Column,
    bool IsRefStruct = false) : Declaration(Line, Column);

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

// Struct-of-arrays record declaration. This is the syntax-level carrier for the
// compiler table model; lowering is gated separately until the ABI is implemented.
public record SoaRecordDeclaration(
    string Name,
    List<SoaColumnDeclaration> Columns,
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
    List<TypeParameter>? TypeParameters,
    List<UnionCase> Cases,
    Modifiers Modifiers,
    List<AttributeNode> Attributes,
    int Line,
    int Column) : Declaration(Line, Column);

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

// Newtype declaration (distinct wrapper type)
// `type UserId = newtype int` → `readonly record struct UserId(int Value);`
public record NewtypeDeclaration(
    string Name,
    TypeReference UnderlyingType,
    int Line,
    int Column) : Declaration(Line, Column);

// Preprocessor directive wrapper (for top-level preprocessor directives)
public record PreprocessorDeclaration(
    string Directive,  // Full directive text including # (e.g., "#if DEBUG", "#region Helpers")
    int Line,
    int Column) : Declaration(Line, Column);

// Attributes
public record AttributeNode(
    string Name,
    List<Argument> Arguments,
    int Line = 1,
    int Column = 1);

public class GenericTypeReference : TypeReference
{
    public string Name { get; }
    public List<TypeReference> TypeArguments { get; }
    public int Line { get; init; }
    public int Column { get; init; }
    public SourceSpan NameSpan => SourceSpan.FromStartAndLength(Line, Column, Name.Length);

    public GenericTypeReference(string name, List<TypeReference> typeArguments)
    {
        Name = name;
        TypeArguments = typeArguments;
    }
}

public class UnionTypeReference : TypeReference
{
    public List<TypeReference> Arms { get; }

    public UnionTypeReference(List<TypeReference> arms)
    {
        Arms = arms;
    }

    public override string ToString() => string.Join(" | ", Arms);
}

public class FunctionTypeReference : TypeReference
{
    public List<TypeReference> ParameterTypes { get; }
    public TypeReference ReturnType { get; }

    public FunctionTypeReference(List<TypeReference> parameterTypes, TypeReference returnType)
    {
        ParameterTypes = parameterTypes;
        ReturnType = returnType;
    }
}

// Test declaration (for .tests.nl files)
public record TestDeclaration(
    string Description,
    BlockStatement Body,
    List<Parameter>? TableParameters,
    List<List<Expression>>? TableCases,
    string? SkipReason,
    int Line,
    int Column) : Declaration(Line, Column);

// Setup block declaration (for .tests.nl files) - shared setup for all tests in a file
public record SetupDeclaration(
    BlockStatement Body,
    int Line,
    int Column) : Declaration(Line, Column);

// Teardown block declaration (for .tests.nl files) - shared cleanup for all tests in a file
public record TeardownDeclaration(
    BlockStatement Body,
    int Line,
    int Column) : Declaration(Line, Column);
