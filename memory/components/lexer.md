# Lexer Component

**File:** `src/NSharpLang.Compiler.BootstrapServices/Lexer.nl`

## Responsibility

Converts raw source code text into a stream of tokens for the parser.

## Key Features

### String Interpolation
- Handles both regular strings (`"hello"`) and interpolated strings (`$"hello {name}"`)
- **Important:** Token values include the quotes
  - Regular string: `"hello"` (not `hello`)
  - Interpolated: `$"hello {x}"` (full string)
- The parser and semantic pipeline receive the source spelling unchanged.

### Newlines and indentation
- Newline tokens are retained in the returned token list.
- `InsertIndentationBraces` uses line starts and indentation to synthesize brace tokens outside
  explicit braces/parentheses/brackets.
- Line/column tracking remains 1-based.

### Comment Handling
- Single-line comments: `// comment`
- Multi-line comments: `/* comment */`
- Comment tokens are removed from the main token list.
- Comment trivia is preserved separately in `Lexer.Comments`, including line, column, text, and
  multi-line classification.

### Numeric Literals
- Integer literals: `42`, `1_000_000`
- Float literals: `3.14`, `1.5e10`
- Underscores allowed for readability

### Operator Recognition
- Single-char: `+`, `-`, `*`, `/`, `=`, `<`, `>`, etc.
- Multi-char: `==`, `!=`, `<=`, `>=`, `&&`, `||`, `=>`, `?.`, `??`, etc.
- Context-dependent: `?[` (null-conditional indexing)

## Token Types

See `src/NSharpLang.Compiler.BootstrapServices/Token.nl` for the complete live token model and
token-type enum.

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
```text
// Source: "hello"
// Token value: "hello" (includes quotes)

// Source: $"hello {x}"
// Token value: $"hello {x}" (includes $ and quotes)
```

This design decision preserves source spelling for downstream compiler phases.

## Error Handling

Lexer errors are rare but include:
- Unterminated strings
- Invalid escape sequences
- Malformed numeric literals

Errors include file name, line, and column for precise reporting.

## Usage Example

```text
var source = "let x := 42";
var lexer = new Lexer(source, "example.nl");
var tokens = lexer.Tokenize(); // Returns List<Token>

// tokens[0] = { Type: Let, Value: "let", Line: 1, Column: 1 }
// tokens[1] = { Type: Identifier, Value: "x", Line: 1, Column: 5 }
// tokens[2] = { Type: ColonEquals, Value: ":=", Line: 1, Column: 7 }
// tokens[3] = { Type: IntLiteral, Value: "42", Line: 1, Column: 10 }
```

## Testing

The lexer's canonical contracts are **N#, not C#**: `src/NSharpLang.Compiler.BootstrapServices/Lexer.tests.nl`,
which replaced `tests/LexerTests.cs` in 020 slice 7. They cover:
- **Every keyword** — all 85 are lexed individually and crossed through `KeywordTypeForText` and
  back through `KeywordTextForType`; the remaining 63 `TokenType` members are proved reserved by
  neither, and the two tables are proved to partition the whole 148-member enum
- All operators and delimiters, by kind *and* by spelling (which is what pins the longest-match order)
- String, triple-quote, interpolated and interpolated-raw literals, terminated and unterminated
- Numeric literals: hex, binary, exponent, every float and integer suffix, underscore stripping,
  and every malformed form that must answer `Unknown`
- Comments — filtered out of the token stream and preserved on `Comments` as positioned trivia
- Preprocessor directives, newline normalisation, and line/column tracking
- Apostrophe disambiguation: `Lifetime` in a systems header, `CharLiteral` everywhere else

Run them with `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release -p:NSharpExcludeTests=false`
(restore with `-p:NSharpExcludeTests=false --force-evaluate` first).
