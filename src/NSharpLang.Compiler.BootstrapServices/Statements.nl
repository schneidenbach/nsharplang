namespace NSharpLang.Compiler.Ast

import System.Collections.Generic


// Base class for all statements
class Statement: AstNode {
    constructor(Line: int, Column: int): base(Line, Column) {
    }
}

// Expression statement
class ExpressionStatement: Statement {
    Expression: Expression

    constructor(Expression: Expression, Line: int, Column: int): base(Line, Column) {
        this.Expression = Expression
    }
}

// Variable declaration
class VariableDeclarationStatement: Statement {
    Name: string
    Type: TypeReference?
    Initializer: Expression?
    Kind: VariableKind

    constructor(Name: string, Type: TypeReference?, Initializer: Expression?, Kind: VariableKind, Line: int, Column: int): base(Line, Column) {
        this.Name = Name
        this.Type = Type
        this.Initializer = Initializer
        this.Kind = Kind
    }
}

// Tuple deconstruction: (x, y) := GetPair()
class TupleDeconstructionStatement: Statement {
    Names: List<string>
    Initializer: Expression
    Kind: VariableKind

    constructor(Names: List<string>, Initializer: Expression, Kind: VariableKind, Line: int, Column: int): base(Line, Column) {
        this.Names = Names
        this.Initializer = Initializer
        this.Kind = Kind
    }
}

// Block statement
class BlockStatement: Statement {
    Statements: List<Statement>

    constructor(Statements: List<Statement>, Line: int, Column: int): base(Line, Column) {
        this.Statements = Statements
    }
}

// Explicit systems allocation zone: alloc { ... }
class AllocBlockStatement: Statement {
    Body: BlockStatement

    constructor(Body: BlockStatement, Line: int, Column: int): base(Line, Column) {
        this.Body = Body
    }
}

// Systems policy escape zone: allow(alloc, reason: "...") { ... }
class AllowStatement: Statement {
    Effects: List<string>
    Reason: string?
    Owner: string?
    Body: BlockStatement

    constructor(Effects: List<string>, Reason: string?, Owner: string?, Body: BlockStatement, Line: int, Column: int): base(Line, Column) {
        this.Effects = Effects
        this.Reason = Reason
        this.Owner = Owner
        this.Body = Body
    }
}

// Restricted unsafe zone for systems code.
class UnsafeBlockStatement: Statement {
    Body: BlockStatement

    constructor(Body: BlockStatement, Line: int, Column: int): base(Line, Column) {
        this.Body = Body
    }
}

// If statement
class IfStatement: Statement {
    Condition: Expression
    ThenStatement: Statement
    ElseStatement: Statement?

    constructor(Condition: Expression, ThenStatement: Statement, ElseStatement: Statement?, Line: int, Column: int): base(Line, Column) {
        this.Condition = Condition
        this.ThenStatement = ThenStatement
        this.ElseStatement = ElseStatement
    }
}

// For loop
class ForStatement: Statement {
    Initializer: Statement?
    Condition: Expression?
    Iterator: Expression?
    Body: Statement

    constructor(Initializer: Statement?, Condition: Expression?, Iterator: Expression?, Body: Statement, Line: int, Column: int): base(Line, Column) {
        this.Initializer = Initializer
        this.Condition = Condition
        this.Iterator = Iterator
        this.Body = Body
    }
}

// Foreach loop
class ForeachStatement: Statement {
    VariableName: string
    Collection: Expression
    Body: Statement

    constructor(VariableName: string, Collection: Expression, Body: Statement, Line: int, Column: int): base(Line, Column) {
        this.VariableName = VariableName
        this.Collection = Collection
        this.Body = Body
    }
}

// Await foreach loop (async iteration - C# 8+)
class AwaitForEachStatement: Statement {
    VariableName: string
    Collection: Expression
    Body: Statement

    constructor(VariableName: string, Collection: Expression, Body: Statement, Line: int, Column: int): base(Line, Column) {
        this.VariableName = VariableName
        this.Collection = Collection
        this.Body = Body
    }
}

// While loop
class WhileStatement: Statement {
    Condition: Expression
    Body: Statement

    constructor(Condition: Expression, Body: Statement, Line: int, Column: int): base(Line, Column) {
        this.Condition = Condition
        this.Body = Body
    }
}

// Return statement
class ReturnStatement: Statement {
    Value: Expression?

    constructor(Value: Expression?, Line: int, Column: int): base(Line, Column) {
        this.Value = Value
    }
}

// Yield statement (Value is null for "yield break")
class YieldStatement: Statement {
    Value: Expression?

    constructor(Value: Expression?, Line: int, Column: int): base(Line, Column) {
        this.Value = Value
    }
}

// Break statement
class BreakStatement: Statement {
    constructor(Line: int, Column: int): base(Line, Column) {
    }
}

// Continue statement
class ContinueStatement: Statement {
    constructor(Line: int, Column: int): base(Line, Column) {
    }
}

// Throw statement
class ThrowStatement: Statement {
    Expression: Expression

    constructor(Expression: Expression, Line: int, Column: int): base(Line, Column) {
        this.Expression = Expression
    }
}

// Try-catch-finally statement
class TryStatement: Statement {
    TryBlock: BlockStatement
    CatchClauses: List<CatchClause>
    FinallyBlock: BlockStatement?

    constructor(TryBlock: BlockStatement, CatchClauses: List<CatchClause>, FinallyBlock: BlockStatement?, Line: int, Column: int): base(Line, Column) {
        this.TryBlock = TryBlock
        this.CatchClauses = CatchClauses
        this.FinallyBlock = FinallyBlock
    }
}

class CatchClause {
    ExceptionType: TypeReference?
    VariableName: string?
    Block: BlockStatement

    constructor(ExceptionType: TypeReference?, VariableName: string?, Block: BlockStatement) {
        this.ExceptionType = ExceptionType
        this.VariableName = VariableName
        this.Block = Block
    }
}

// Using statement
class UsingStatement: Statement {
    Declaration: VariableDeclarationStatement?
    Expression: Expression?
    Body: Statement?

    constructor(Declaration: VariableDeclarationStatement?, Expression: Expression?, Body: Statement?, Line: int, Column: int): base(Line, Column) {
        this.Declaration = Declaration
        this.Expression = Expression
        this.Body = Body
    }
}

// Lock statement for thread synchronization
class LockStatement: Statement {
    LockObject: Expression
    Body: BlockStatement

    constructor(LockObject: Expression, Body: BlockStatement, Line: int, Column: int): base(Line, Column) {
        this.LockObject = LockObject
        this.Body = Body
    }
}

// Switch statement (non-exhaustive)
class SwitchStatement: Statement {
    Value: Expression
    Cases: List<SwitchCase>

    constructor(Value: Expression, Cases: List<SwitchCase>, Line: int, Column: int): base(Line, Column) {
        this.Value = Value
        this.Cases = Cases
    }
}

class SwitchCase {
    Pattern: Pattern?
    Statements: List<Statement>
    Line: int
    Column: int

    constructor(Pattern: Pattern?, Statements: List<Statement>, Line: int, Column: int) {
        this.Pattern = Pattern
        this.Statements = Statements
        this.Line = Line
        this.Column = Column
    }
}

// Empty statement
class EmptyStatement: Statement {
    constructor(Line: int, Column: int): base(Line, Column) {
    }
}

// Print statement
class PrintStatement: Statement {
    Value: Expression

    constructor(Value: Expression, Line: int, Column: int): base(Line, Column) {
        this.Value = Value
    }
}

// Event unsubscription: `off subscription`
class OffStatement: Statement {
    Handle: Expression

    constructor(Handle: Expression, Line: int, Column: int): base(Line, Column) {
        this.Handle = Handle
    }
}

// Preprocessor directive (pass-through to C#)
class PreprocessorDirective: Statement {
    Directive: string

    constructor(Directive: string, Line: int, Column: int): base(Line, Column) {
        this.Directive = Directive
    }
}

// File-based import: import "path/to/file" [as Alias]
class FileImport: Statement {
    Path: string
    Alias: string?
    PathColumn: int
    PathLength: int

    DiagnosticColumn: int => PathColumn > 0 ? PathColumn : Column
    DiagnosticLength: int => PathLength > 0 ? PathLength : 1

    constructor(Path: string, Alias: string?, Line: int, Column: int): base(Line, Column) {
        this.Path = Path
        this.Alias = Alias
    }
}

// Namespace import: import System.Collections.Generic [as Alias]
class NamespaceImport: Statement {
    Namespace: string
    Alias: string?

    constructor(Namespace: string, Alias: string?, Line: int, Column: int): base(Line, Column) {
        this.Namespace = Namespace
        this.Alias = Alias
    }
}

// Assert statement (for test files)
class AssertStatement: Statement {
    Condition: Expression
    Message: Expression?

    constructor(Condition: Expression, Message: Expression?, Line: int, Column: int): base(Line, Column) {
        this.Condition = Condition
        this.Message = Message
    }
}

// Assert throws statement (for test files) - assert throws ExceptionType { body }
class AssertThrowsStatement: Statement {
    ExceptionType: TypeReference
    Body: BlockStatement

    constructor(ExceptionType: TypeReference, Body: BlockStatement, Line: int, Column: int): base(Line, Column) {
        this.ExceptionType = ExceptionType
        this.Body = Body
    }
}

// Local function statement (C# 7) - function declared inside another function
class LocalFunctionStatement: Statement {
    Function: FunctionDeclaration

    constructor(Function: FunctionDeclaration, Line: int, Column: int): base(Line, Column) {
        this.Function = Function
    }
}
