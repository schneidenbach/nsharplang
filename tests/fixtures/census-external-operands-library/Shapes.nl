namespace Census.Operands

import System.Collections.Generic
import System.Reflection
import System.Threading


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

    func Describe(prefix: string): string {
        return prefix + Name
    }
}

// Static helpers a consumer nests one inside another, as the compiler's own
// `AnalyzerVariableDeclaration.IsErrorCaptureForm(count, ColumnarNodeTextFacts.Text(nodes, source, Child(index, count - 1)))`.
class Facts {
    static func Name(shape: Shape): string {
        return shape.Name
    }

    static func Length(text: string): int {
        return text.Length
    }

    static func Twice(value: int): int {
        return value * 2
    }

    static func Join(left: string, right: string, index: int): string {
        return left + right + index.ToString()
    }

    static func Both(count: int, text: string): bool {
        return count == text.Length
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

// Callees a consumer reaches by ASKING WHETHER ITS ARGUMENTS MATCH: the ordinary static and instance
// tiers into a referenced assembly, which choose a member by its declared parameters. A conditional
// with a `null` arm is target-typed by the maybe-null parameter it is passed to, and a `&T` parameter
// is handed a `&T` the consumer was itself given.
class OperandFacts {
    static func Describe(label: string?, count: int): string {
        if label == null {
            return "none:" + count.ToString()
        }
        return label + ":" + count.ToString()
    }

    static func NameOf(shape: Shape?): string {
        if shape == null {
            return "<none>"
        }
        return shape.Name
    }

    static func CountOf(value: int?): int => value ?? -1

    static func Bump(slot: &int, amount: int) {
        Interlocked.Add(ref slot, amount)
    }

    static func Grow(counter: &Counter, amount: int) {
        counter.Value = counter.Value + amount
    }
}

struct Counter {
    Value: int
}

class Labeler {
    Prefix: string

    constructor(prefix: string) {
        Prefix = prefix
    }

    func Label(suffix: string?): string {
        if suffix == null {
            return Prefix
        }
        return Prefix + suffix
    }
}
