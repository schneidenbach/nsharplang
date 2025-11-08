# Lexer Component

**File:** `src/Compiler/Lexer.cs`

## Responsibility

Converts raw source code text into a stream of tokens for the parser.

## Key Features

### String Interpolation
- Handles both regular strings (`"hello"`) and interpolated strings (`$"hello {name}"`)
- **Important:** Token values include the quotes
  - Regular string: `"hello"` (not `hello`)
  - Interpolated: `$"hello {x}"` (full string)
- This simplifies transpiler logic (no need to re-add quotes)

### Newline Filtering
- Newlines are tokenized but filtered out before returning to parser
- Makes parsing simpler (no need to handle newlines everywhere)
- Line/column tracking still accurate

### Comment Handling
- Single-line comments: `// comment`
- Multi-line comments: `/* comment */`
- Comments are filtered out during tokenization
- Not preserved in token stream (not needed for transpilation)

### Numeric Literals
- Integer literals: `42`, `1_000_000`
- Float literals: `3.14`, `1.5e10`
- Underscores allowed for readability (transpiled as-is to C#)

### Operator Recognition
- Single-char: `+`, `-`, `*`, `/`, `=`, `<`, `>`, etc.
- Multi-char: `==`, `!=`, `<=`, `>=`, `&&`, `||`, `=>`, `?.`, `??`, etc.
- Context-dependent: `?[` (null-conditional indexing)

## Token Types

See `src/Compiler/Token.cs` for complete list (50+ token types).

Notable tokens:
- **QuestionDot**: `?.` for null-conditional member access
- **QuestionBracket**: `?[` for null-conditional indexing
- **Arrow**: `=>` for lambdas and expression-bodied members
- **ColonEquals**: `:=` for variable inference
- **DotDot**: `..` for ranges
- **Caret**: `^` for index-from-end

## Implementation Details

### Character Scanning
- Single-pass, forward-only scanning
- Lookahead by 1 character for multi-char operators
- No backtracking needed

### Line/Column Tracking
- Every token has `Line` and `Column` fields
- Used for error reporting
- Lines start at 1, columns start at 1

### String Literal Storage
Strings are stored with quotes included:
```csharp
// Source: "hello"
// Token value: "hello" (includes quotes)

// Source: $"hello {x}"
// Token value: $"hello {x}" (includes $ and quotes)
```

This design decision simplifies the transpiler - it can emit token values directly without quote wrapping.

## Error Handling

Lexer errors are rare but include:
- Unterminated strings
- Invalid escape sequences
- Malformed numeric literals

Errors include file name, line, and column for precise reporting.

## Usage Example

```csharp
var source = "let x := 42";
var lexer = new Lexer(source, "example.nl");
var tokens = lexer.Tokenize(); // Returns List<Token>

// tokens[0] = { Type: Let, Value: "let", Line: 1, Column: 1 }
// tokens[1] = { Type: Identifier, Value: "x", Line: 1, Column: 5 }
// tokens[2] = { Type: ColonEquals, Value: ":=", Line: 1, Column: 7 }
// tokens[3] = { Type: IntLiteral, Value: "42", Line: 1, Column: 10 }
```

## Testing

Lexer has 33 unit tests covering:
- All keywords
- All operators
- String interpolation
- Numeric literals
- Comments
- Error cases

See `tests/LexerTests.cs`.
