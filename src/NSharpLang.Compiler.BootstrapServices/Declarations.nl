namespace NSharpLang.Compiler.Ast

import System.Collections.Generic


// Base class for declarations
class Declaration: AstNode {
    constructor(Line: int, Column: int): base(Line, Column) {
    }
}

// Compilation unit (file)
class CompilationUnit: AstNode {
    Namespace: NamespaceDeclaration?
    Imports: List<ImportDirective>
    FileImports: List<Statement>
    Package: PackageDeclaration?
    Declarations: List<Declaration>

    constructor(Namespace: NamespaceDeclaration?, Imports: List<ImportDirective>, FileImports: List<Statement>, Package: PackageDeclaration?, Declarations: List<Declaration>, Line: int, Column: int): base(Line, Column) {
        this.Namespace = Namespace
        this.Imports = Imports
        this.FileImports = FileImports
        this.Package = Package
        this.Declarations = Declarations
    }
}

// Function declaration
class FunctionDeclaration: Declaration {
    Name: string
    Parameters: List<Parameter>
    ReturnType: TypeReference?
    Body: BlockStatement?
    ExpressionBody: Expression?
    TypeParameters: List<TypeParameter>?
    Constraints: List<GenericConstraint>?
    Modifiers: Modifiers
    Attributes: List<AttributeNode>
    IsOperatorOverload: bool
    OperatorSymbol: string?
    IsConversionOperator: bool
    IsImplicitConversion: bool
    OperatorKeywordSpan: SourceSpan
    OperatorSymbolSpan: SourceSpan
    ReturnLifetime: string?

    constructor(Name: string, Parameters: List<Parameter>, ReturnType: TypeReference?, Body: BlockStatement?, ExpressionBody: Expression?, TypeParameters: List<TypeParameter>?, Constraints: List<GenericConstraint>?, Modifiers: Modifiers, Attributes: List<AttributeNode>, IsOperatorOverload: bool, OperatorSymbol: string?, IsConversionOperator: bool, IsImplicitConversion: bool, Line: int, Column: int): base(Line, Column) {
        this.Name = Name
        this.Parameters = Parameters
        this.ReturnType = ReturnType
        this.Body = Body
        this.ExpressionBody = ExpressionBody
        this.TypeParameters = TypeParameters
        this.Constraints = Constraints
        this.Modifiers = Modifiers
        this.Attributes = Attributes
        this.IsOperatorOverload = IsOperatorOverload
        this.OperatorSymbol = OperatorSymbol
        this.IsConversionOperator = IsConversionOperator
        this.IsImplicitConversion = IsImplicitConversion
    }
}

class Parameter {
    Name: string
    Type: TypeReference
    DefaultValue: Expression?
    IsThis: bool
    Modifier: ParameterModifier
    Attributes: List<AttributeNode>?
    Line: int
    Column: int
    IsScoped: bool
    Lifetime: string?

    constructor(Name: string, Type: TypeReference, DefaultValue: Expression?, IsThis: bool, Modifier: ParameterModifier = ParameterModifier.None, Attributes: List<AttributeNode>? = null, Line: int = 0, Column: int = 0, IsScoped: bool = false, Lifetime: string? = null) {
        this.Name = Name
        this.Type = Type
        this.DefaultValue = DefaultValue
        this.IsThis = IsThis
        this.Modifier = Modifier
        this.Attributes = Attributes
        this.Line = Line
        this.Column = Column
        this.IsScoped = IsScoped
        this.Lifetime = Lifetime
    }
}

// Class declaration
class ClassDeclaration: Declaration {
    Name: string
    TypeParameters: List<TypeParameter>?
    BaseClass: TypeReference?
    Interfaces: List<TypeReference>
    Members: List<Declaration>
    PrimaryConstructorParameters: List<Parameter>?
    Modifiers: Modifiers
    Attributes: List<AttributeNode>

    constructor(Name: string, TypeParameters: List<TypeParameter>?, BaseClass: TypeReference?, Interfaces: List<TypeReference>, Members: List<Declaration>, PrimaryConstructorParameters: List<Parameter>?, Modifiers: Modifiers, Attributes: List<AttributeNode>, Line: int, Column: int): base(Line, Column) {
        this.Name = Name
        this.TypeParameters = TypeParameters
        this.BaseClass = BaseClass
        this.Interfaces = Interfaces
        this.Members = Members
        this.PrimaryConstructorParameters = PrimaryConstructorParameters
        this.Modifiers = Modifiers
        this.Attributes = Attributes
    }
}

// Struct declaration
class StructDeclaration: Declaration {
    Name: string
    TypeParameters: List<TypeParameter>?
    Interfaces: List<TypeReference>
    Members: List<Declaration>
    PrimaryConstructorParameters: List<Parameter>?
    Modifiers: Modifiers
    Attributes: List<AttributeNode>
    IsRefStruct: bool

    constructor(Name: string, TypeParameters: List<TypeParameter>?, Interfaces: List<TypeReference>, Members: List<Declaration>, PrimaryConstructorParameters: List<Parameter>?, Modifiers: Modifiers, Attributes: List<AttributeNode>, Line: int, Column: int, IsRefStruct: bool = false): base(Line, Column) {
        this.Name = Name
        this.TypeParameters = TypeParameters
        this.Interfaces = Interfaces
        this.Members = Members
        this.PrimaryConstructorParameters = PrimaryConstructorParameters
        this.Modifiers = Modifiers
        this.Attributes = Attributes
        this.IsRefStruct = IsRefStruct
    }
}

// Record declaration (can be record class or record struct - C# 10)
class RecordDeclaration: Declaration {
    Name: string
    TypeParameters: List<TypeParameter>?
    Interfaces: List<TypeReference>
    Members: List<Declaration>
    PrimaryConstructorParameters: List<Parameter>?
    IsStruct: bool
    Modifiers: Modifiers
    Attributes: List<AttributeNode>

    constructor(Name: string, TypeParameters: List<TypeParameter>?, Interfaces: List<TypeReference>, Members: List<Declaration>, PrimaryConstructorParameters: List<Parameter>?, IsStruct: bool, Modifiers: Modifiers, Attributes: List<AttributeNode>, Line: int, Column: int): base(Line, Column) {
        this.Name = Name
        this.TypeParameters = TypeParameters
        this.Interfaces = Interfaces
        this.Members = Members
        this.PrimaryConstructorParameters = PrimaryConstructorParameters
        this.IsStruct = IsStruct
        this.Modifiers = Modifiers
        this.Attributes = Attributes
    }
}

// Struct-of-arrays record declaration.
class SoaRecordDeclaration: Declaration {
    Name: string
    Columns: List<SoaColumnDeclaration>
    Modifiers: Modifiers
    Attributes: List<AttributeNode>

    constructor(Name: string, Columns: List<SoaColumnDeclaration>, Modifiers: Modifiers, Attributes: List<AttributeNode>, Line: int, Column: int): base(Line, Column) {
        this.Name = Name
        this.Columns = Columns
        this.Modifiers = Modifiers
        this.Attributes = Attributes
    }
}

// Interface declaration
class InterfaceDeclaration: Declaration {
    Name: string
    TypeParameters: List<TypeParameter>?
    BaseInterfaces: List<TypeReference>
    Members: List<Declaration>
    Modifiers: Modifiers
    IsDuckInterface: bool
    Attributes: List<AttributeNode>

    constructor(Name: string, TypeParameters: List<TypeParameter>?, BaseInterfaces: List<TypeReference>, Members: List<Declaration>, Modifiers: Modifiers, IsDuckInterface: bool, Attributes: List<AttributeNode>, Line: int, Column: int): base(Line, Column) {
        this.Name = Name
        this.TypeParameters = TypeParameters
        this.BaseInterfaces = BaseInterfaces
        this.Members = Members
        this.Modifiers = Modifiers
        this.IsDuckInterface = IsDuckInterface
        this.Attributes = Attributes
    }
}

// Union declaration
class UnionDeclaration: Declaration {
    Name: string
    TypeParameters: List<TypeParameter>?
    Cases: List<UnionCase>
    Modifiers: Modifiers
    Attributes: List<AttributeNode>

    constructor(Name: string, TypeParameters: List<TypeParameter>?, Cases: List<UnionCase>, Modifiers: Modifiers, Attributes: List<AttributeNode>, Line: int, Column: int): base(Line, Column) {
        this.Name = Name
        this.TypeParameters = TypeParameters
        this.Cases = Cases
        this.Modifiers = Modifiers
        this.Attributes = Attributes
    }
}

// Enum declaration
class EnumDeclaration: Declaration {
    Name: string
    Members: List<EnumMember>
    Type: EnumType
    Modifiers: Modifiers
    Attributes: List<AttributeNode>

    constructor(Name: string, Members: List<EnumMember>, Type: EnumType, Modifiers: Modifiers, Attributes: List<AttributeNode>, Line: int, Column: int): base(Line, Column) {
        this.Name = Name
        this.Members = Members
        this.Type = Type
        this.Modifiers = Modifiers
        this.Attributes = Attributes
    }
}

class EnumMember {
    Name: string
    Value: Expression?
    Line: int
    Column: int

    constructor(Name: string, Value: Expression?, Line: int = 0, Column: int = 0) {
        this.Name = Name
        this.Value = Value
        this.Line = Line
        this.Column = Column
    }
}

class FieldDeclaration: Declaration {
    Name: string
    Type: TypeReference?
    Initializer: Expression?
    Modifiers: Modifiers
    PropertyModifier: PropertyModifier
    Attributes: List<AttributeNode>

    constructor(Name: string, Type: TypeReference?, Initializer: Expression?, Modifiers: Modifiers, PropertyModifier: PropertyModifier, Attributes: List<AttributeNode>, Line: int, Column: int): base(Line, Column) {
        this.Name = Name
        this.Type = Type
        this.Initializer = Initializer
        this.Modifiers = Modifiers
        this.PropertyModifier = PropertyModifier
        this.Attributes = Attributes
    }
}

// Property declaration with custom get/set
class PropertyDeclaration: Declaration {
    Name: string
    Type: TypeReference
    GetBody: BlockStatement?
    SetBody: BlockStatement?
    ExpressionBody: Expression?
    Modifiers: Modifiers
    PropertyModifier: PropertyModifier
    Attributes: List<AttributeNode>

    constructor(Name: string, Type: TypeReference, GetBody: BlockStatement?, SetBody: BlockStatement?, ExpressionBody: Expression?, Modifiers: Modifiers, PropertyModifier: PropertyModifier, Attributes: List<AttributeNode>, Line: int, Column: int): base(Line, Column) {
        this.Name = Name
        this.Type = Type
        this.GetBody = GetBody
        this.SetBody = SetBody
        this.ExpressionBody = ExpressionBody
        this.Modifiers = Modifiers
        this.PropertyModifier = PropertyModifier
        this.Attributes = Attributes
    }
}

// Constructor declaration
class ConstructorDeclaration: Declaration {
    Parameters: List<Parameter>
    Body: BlockStatement
    Initializer: Expression?
    Modifiers: Modifiers
    Attributes: List<AttributeNode>

    constructor(Parameters: List<Parameter>, Body: BlockStatement, Initializer: Expression?, Modifiers: Modifiers, Attributes: List<AttributeNode>, Line: int, Column: int): base(Line, Column) {
        this.Parameters = Parameters
        this.Body = Body
        this.Initializer = Initializer
        this.Modifiers = Modifiers
        this.Attributes = Attributes
    }
}

// Indexer declaration
class IndexerDeclaration: Declaration {
    Parameters: List<Parameter>
    Type: TypeReference
    GetBody: BlockStatement?
    SetBody: BlockStatement?
    Modifiers: Modifiers
    Attributes: List<AttributeNode>

    constructor(Parameters: List<Parameter>, Type: TypeReference, GetBody: BlockStatement?, SetBody: BlockStatement?, Modifiers: Modifiers, Attributes: List<AttributeNode>, Line: int, Column: int): base(Line, Column) {
        this.Parameters = Parameters
        this.Type = Type
        this.GetBody = GetBody
        this.SetBody = SetBody
        this.Modifiers = Modifiers
        this.Attributes = Attributes
    }
}

// Type alias
class TypeAliasDeclaration: Declaration {
    Name: string
    Type: TypeReference

    constructor(Name: string, Type: TypeReference, Line: int, Column: int): base(Line, Column) {
        this.Name = Name
        this.Type = Type
    }
}

// Newtype declaration (distinct wrapper type)
class NewtypeDeclaration: Declaration {
    Name: string
    UnderlyingType: TypeReference

    constructor(Name: string, UnderlyingType: TypeReference, Line: int, Column: int): base(Line, Column) {
        this.Name = Name
        this.UnderlyingType = UnderlyingType
    }
}

// Preprocessor directive wrapper (for top-level preprocessor directives)
class PreprocessorDeclaration: Declaration {
    Directive: string

    constructor(Directive: string, Line: int, Column: int): base(Line, Column) {
        this.Directive = Directive
    }
}

// Attributes
class AttributeNode {
    Name: string
    Arguments: List<Argument>
    Line: int
    Column: int

    constructor(Name: string, Arguments: List<Argument>, Line: int = 1, Column: int = 1) {
        this.Name = Name
        this.Arguments = Arguments
        this.Line = Line
        this.Column = Column
    }
}

// Test declaration (for .tests.nl files)
class TestDeclaration: Declaration {
    Description: string
    Body: BlockStatement
    TableParameters: List<Parameter>?
    TableCases: List<List<Expression>>?
    SkipReason: string?

    constructor(Description: string, Body: BlockStatement, TableParameters: List<Parameter>?, TableCases: List<List<Expression>>?, SkipReason: string?, Line: int, Column: int): base(Line, Column) {
        this.Description = Description
        this.Body = Body
        this.TableParameters = TableParameters
        this.TableCases = TableCases
        this.SkipReason = SkipReason
    }
}

// Setup block declaration (for .tests.nl files) - shared setup for all tests in a file
class SetupDeclaration: Declaration {
    Body: BlockStatement

    constructor(Body: BlockStatement, Line: int, Column: int): base(Line, Column) {
        this.Body = Body
    }
}

// Teardown block declaration (for .tests.nl files) - shared cleanup for all tests in a file
class TeardownDeclaration: Declaration {
    Body: BlockStatement

    constructor(Body: BlockStatement, Line: int, Column: int): base(Line, Column) {
        this.Body = Body
    }
}
