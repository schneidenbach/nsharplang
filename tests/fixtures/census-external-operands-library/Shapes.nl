namespace Census.Operands

import System.Collections.Generic
import System.Reflection


// THE OPERAND AND ARGUMENT TYPES, COMPILED INTO ANOTHER ASSEMBLY. `tests/native/census-external-operands`
// writes its use sites in this same namespace, which is the shape `Compiler.Core` meets once
// `Compiler.Model` is carved out of it: every type below used to be a SOURCE type of the program that
// uses it, and each one now arrives from a REFERENCED assembly. The shapes mirror the compiler's own
// (`TypeInfo`/`AliasTypeInfo`, `ByRefTypeInfo`, `CompilerError`, `GenericConstraint`,
// `SimpleTypeReference`, the statement nodes, `ExternalAssemblyScanResult`).
enum Modifier {
    None,
    Ref,
    Out,
    In,
    Params
}

enum SpecialFlags {
    None = 0,
    Class = 1,
    Struct = 2,
    New = 4
}

enum Severity {
    Error,
    Warning
}

class Shape {
    Name: string

    constructor(name: string) {
        Name = name
    }
}

class AliasShape: Shape {
    Target: Shape

    constructor(name: string, target: Shape): base(name) {
        Target = target
    }
}

// A trailing optional after the argument that decides it, as `ByRefTypeInfo(innerType, isOutArgument = false)`.
class ByRefShape: Shape {
    Inner: Shape
    IsOut: bool

    constructor(inner: Shape, isOut: bool = false): base("&" + inner.Name) {
        Inner = inner
        IsOut = isOut
    }
}

// Every parameter required, as `CommentTrivia(line, column, text, isMultiLine)`.
class Note {
    Line: int
    Column: int
    Text: string
    IsMultiLine: bool

    constructor(line: int, column: int, text: string, isMultiLine: bool) {
        Line = line
        Column = column
        Text = text
        IsMultiLine = isMultiLine
    }
}

// A positional record built with an object initializer, as `CompilerError`.
record Report(code: Modifier, message: string, line: int, column: int, severity: Severity) {
    FileName: string?
    Length: int
    Explanation: string?
}

// An enum-typed optional, as `GenericConstraint(typeParameter, constraints, specialConstraints = 0)`.
class Constraint {
    Parameter: string
    Bounds: List<string>
    Flags: SpecialFlags

    constructor(parameter: string, bounds: List<string>, flags: SpecialFlags = 0) {
        Parameter = parameter
        Bounds = bounds
        Flags = flags
    }
}

// Two trailing optionals, as `SimpleTypeReference(name, line = 0, column = 0)`.
class TypeRef {
    Name: string
    Line: int
    Column: int

    constructor(name: string, line: int = 0, column: int = 0) {
        Name = name
        Line = line
        Column = column
    }
}

class Node {
    Line: int
    Column: int

    constructor(line: int, column: int) {
        Line = line
        Column = column
    }
}

class Expr: Node {
    constructor(line: int, column: int): base(line, column) {
    }
}

class Ident: Expr {
    Name: string

    constructor(name: string, line: int, column: int): base(line, column) {
        Name = name
    }
}

class Stmt: Node {
    constructor(line: int, column: int): base(line, column) {
    }
}

class ExprStmt: Stmt {
    Expression: Expr

    constructor(expression: Expr, line: int, column: int): base(line, column) {
        Expression = expression
    }
}

class Block: Stmt {
    Statements: List<Stmt>

    constructor(statements: List<Stmt>, line: int, column: int): base(line, column) {
        Statements = statements
    }
}

// A trailing optional after derived-typed arguments, as `ForeachStatement(..., VariableType = null)`.
class Loop: Stmt {
    Variable: string
    Collection: Expr
    Body: Stmt
    Declared: TypeRef?

    constructor(variable: string, collection: Expr, body: Stmt, line: int, column: int, declared: TypeRef? = null): base(line, column) {
        Variable = variable
        Collection = collection
        Body = body
        Declared = declared
    }
}

// As `TryStatement(TryBlock: BlockStatement, CatchClauses, FinallyBlock, Line, Column)`.
class TryStmt: Stmt {
    Body: Block
    Handlers: List<string>
    Finally: Block?

    constructor(body: Block, handlers: List<string>, finallyBlock: Block?, line: int, column: int): base(line, column) {
        Body = body
        Handlers = handlers
        Finally = finallyBlock
    }
}

// Two public constructors of one arity, so a construction whose written arguments fit only one of
// them has to be decided by those arguments.
class Pick {
    Chosen: string

    constructor(text: string) {
        Chosen = "text:" + text
    }

    constructor(count: int) {
        Chosen = "count:" + count.ToString()
    }
}

// A nullable member of a THIRD assembly's type, as `ExternalAssemblyScanResult.Context`.
class Scan {
    Context: MetadataLoadContext?
    Label: string?

    constructor(context: MetadataLoadContext?, label: string?) {
        Context = context
        Label = label
    }
}

// A referenced type that DECLARES `==`/`!=`: identity must not be chosen over them.
class Tally {
    Count: int

    constructor(count: int) {
        Count = count
    }

    static func operator ==(left: Tally, right: Tally): bool => left.Count == right.Count

    static func operator !=(left: Tally, right: Tally): bool => left.Count != right.Count
}
