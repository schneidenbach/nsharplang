# Parser Component

**File:** `src/NSharpLang.Compiler/Parser.cs`

## Responsibility

Converts token stream into an Abstract Syntax Tree (AST).

## Parsing Strategy

**Recursive Descent Parser** with **Operator Precedence Climbing** for expressions.

### Why This Approach?
- Simple to understand and maintain
- Easy to add new syntax
- Good error recovery
- Natural mapping from grammar to code

## Key Design Decisions

### Lambda Parsing
**Critical detail:** Lambdas must be parsed at assignment-expression level, NOT at primary level.

```
ParseLambdaOrAssignmentExpression():
    if current is identifier and next is '=>':
        return ParseLambda()
    if current is '(' and contains '=>':
        return ParseLambda()
    else:
        return ParseAssignment()
```

This ensures `x := y => expr` parses correctly as assignment, not lambda.

### For Loop Shorthand
Parser detects `:=` in for-init position and creates `VariableDeclarationStatement`.

Supports both forms:
```
for let i = 0; i < 10; i++ { }   // Explicit
for i := 0; i < 10; i++ { }       // Shorthand
```

### Operator Precedence
From highest to lowest:
1. Primary (literals, identifiers, parens)
2. Postfix (calls, indexing, member access, `?.`, `?[]`)
3. Unary (`!`, `-`, `^`, `await`)
4. Multiplicative (`*`, `/`, `%`)
5. Additive (`+`, `-`)
6. Range (`..`)
7. Relational (`<`, `>`, `<=`, `>=`)
8. Equality (`==`, `!=`)
9. Logical AND (`&&`)
10. Logical OR (`||`)
11. Null-coalescing (`??`)
12. Conditional (`? :`)
13. Lambda/Assignment (`=>`, `=`, `+=`, etc.)

## AST Node Types

See `src/NSharpLang.Compiler/Ast/` folder:

### Expressions (`Expressions.cs`)
- **BinaryExpression**: `a + b`, `a && b`
- **UnaryExpression**: `!x`, `-n`, `^index`
- **CallExpression**: `Foo(a, b)`
- **MemberAccessExpression**: `obj.Property`, `obj?.Property`
- **IndexAccessExpression**: `arr[0]`, `dict?["key"]`
- **LambdaExpression**: `x => x * 2`, `(a, b) => a + b`
- **MatchExpression**: Pattern matching with guards
- **LiteralExpression**: `42`, `"hello"`, `true`

### Statements (`Statements.cs`)
- **VariableDeclarationStatement**: `let x = 42`, `x := 42`
- **IfStatement**: `if cond { } else { }`
- **ForStatement**: `for i := 0; i < 10; i++ { }`
- **ForeachStatement**: `for item in items { }`
- **WhileStatement**: `while cond { }`
- **ReturnStatement**: `return expr`
- **YieldStatement**: `yield value`, `yield break`
- **TryCatchStatement**: `try { } catch e { }`
- **UsingStatement**: `using resource { }`
- **LockStatement**: `lock obj { }`

### Declarations (`Declarations.cs`)
- **FunctionDeclaration**: Functions with modifiers (async, generator, etc.)
- **ClassDeclaration**: Classes with members
- **RecordDeclaration**: Records (reference or struct)
- **StructDeclaration**: Value types
- **InterfaceDeclaration**: Interfaces (regular or duck)
- **UnionDeclaration**: Discriminated unions
- **EnumDeclaration**: Int or string enums

## Important Parsing Details

### Attribute Parsing
Attributes must be parsed BEFORE checking for type keywords in member declarations.

Order matters:
1. Check for attributes `[...]`
2. Check for type keywords (`class`, `struct`, `record`, etc.)
3. Fall back to field/property/method parsing

### Nested Type Support
`ParseMemberDeclaration` handles nested types (classes, structs, records inside other types).

### Pattern Parsing
Patterns in match expressions support:
- Identifier patterns: `x`, `Result.Success`
- Literal patterns: `42`, `"hello"`
- Union case patterns: `Result.Success { value: x }`
- Positional patterns: `(x, y)`
- List patterns: `[first, .., last]`
- Type patterns: `int x`, `string s`

### Guard Clauses
Match patterns can have guards:
```
value match {
    x when x > 0 => "positive",
    _ => "other"
}
```

## Error Recovery

Parser uses `Consume()` and `Expect()` methods:
- `Consume(TokenType)`: Advances if match, throws if not
- `Expect(TokenType)`: Same as Consume (for readability)
- Errors include line/column from token

Currently: **Stop on first error** (no panic mode recovery).

## Testing

Parser has 86 unit tests covering:
- All statement types
- All expression types
- All declaration types
- Operator precedence
- Error cases

See `tests/ParserTests.cs`.

## Usage Example

```csharp
var tokens = lexer.Tokenize();
var parser = new Parser(tokens, "example.nl");
var ast = parser.ParseCompilationUnit();

// ast is CompilationUnit with:
// - Declarations: List<Declaration>
// - Statements: List<Statement> (top-level)
```
