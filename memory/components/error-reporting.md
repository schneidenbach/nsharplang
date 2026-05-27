# Error Reporting Component

**File:** `src/NSharpLang.Compiler/ErrorReporting.cs`

## Responsibility

Elm-level error messages with rich context, source snippets, type information, and actionable suggestions.

## Architecture

### Two-Tier Error Reporting

1. **Rich errors (via `ErrorMessageBuilder`)** — Elm-style with `HumanExplanation`, `ContextualHint`, type info, and docs URLs. Used for common errors.
2. **Simple errors (via `Analyzer.Error()`)** — Rust-style with source snippet and caret. Used for less common errors.

Rich errors automatically get Elm-style formatting. Simple errors get Rust-style formatting.

### Key Classes

- **`CompilerError`** — Record with rich context fields (`HumanExplanation`, `ActualType`, `ExpectedType`, `ContextualHint`, `Suggestions`, `DocsUrl`)
- **`ErrorMessageBuilder`** — Static factory methods that create Elm-style errors: `TypeMismatch`, `ReturnValueRequiresReturnType`, `ReturnValueInVoidFunction`, `ReturnTypeMismatch`, `UndefinedVariable`, `UndefinedType`, `NonExhaustiveMatch`, `WrongArgumentCount`, `WrongArgumentType`, `ImportNotFound`, `UnexpectedToken`, `MissingReturn`, `DuplicateDeclaration`, `UndefinedMember`
- **`TypeConversionSuggester`** — Context-aware hints for type mismatches (string↔int, nullable, arrays)
- **`SmartSuggester`** — Typo detection via Levenshtein distance with scoring
- **`ErrorSuggestions`** — Fallback suggestions keyed by error code

### Formatting Paths

| Method | Used By | Colors | "Hint:" prefix |
|--------|---------|--------|---------------|
| `Format()` → `FormatElmStyle()` | Direct use | ANSI | Yes |
| `Format()` → `FormatRustStyle()` | Direct use (no HumanExplanation) | ANSI | No (uses "help:") |
| `FormatForTooling()` | LSP, MSBuild task | No | No (raw text) |
| `FormatForMsBuild()` | MSBuild single-line | No | No (inline) |
| `OutputFormatter.DiagnosticsToText()` | CLI `--text` | No | Yes |
| `OutputFormatter.DiagnosticsToJson()` | CLI JSON (default) | No | Raw field |

**Important:** `ContextualHint` values must NOT include "Hint: " prefix — formatters add it when needed.

### Tooling Span Contract

- Compiler diagnostics carry authoritative `Line`, `Column`, and `Length` through `CompilerError`; LSP and Playground markers use those exact spans.
- Linter diagnostics carry `Location` plus `Length`; VS Code, `nlc check`, `nlc lint`, and Playground markers must use the stored linter span instead of re-searching message text in the source line.
- Shorthand declarations such as `Message := "hi"` store the identifier column, so style diagnostics like `NL008` underline `Message`, not the `:=` operator or the tail of the identifier.
- Semantic diagnostics should mark the smallest useful token or expression: wrong argument type (`NL202`) underlines the offending argument expression, wrong argument count (`NL401`) underlines the callable name, and possible null access (`NL905`) underlines the nullable receiver path instead of punctuation such as `.` or `(`.
- General type mismatch diagnostics (`NL202`) should underline the value that has the wrong type, including local/field/assignment values, enum member initializer values, expression-bodied function/property values, non-boolean `if`/`while`/`for`/ternary conditions, mismatched array elements, mismatched match arm values, assigned void calls, and invalid returned values.
- Operator type diagnostics (`NL202`) underline the single bad operand when only one side violates the operator contract, and underline the operator token when both sides make the operator itself the smallest useful location.
- Missing required expressions after visible statement keywords (`if`, `while`, `print`, `throw`, `yield`, `using`, `lock`, `switch`, and `in`) underline the owning keyword so VS Code shows a visible squiggle on the actionable keyword. Missing required expressions after operators or assignment anchors still use insertion spans after the anchor.
- Loop-control placement diagnostics underline the full invalid control keyword (`break` or `continue`) when it appears outside a loop.
- Unreachable-statement diagnostics underline the first unreachable statement token, so keyword-led statements such as `print`, `return`, or `throw` get full-keyword squiggles instead of a one-character marker.
- Pattern diagnostics should underline the invalid pattern part, not the whole match arm: unknown union cases underline the qualified case name, missing property patterns underline the property name, and list-pattern type mismatches underline the list pattern on the first line when available.
- Declaration diagnostics should underline the duplicate or invalid declaration token, not the declaration keyword: duplicate symbols/types/cases/members underline the duplicate name, invalid local variable declarations such as `const answer: int` or `let value` underline the full variable name, `params` ordering/type errors underline the params parameter name, required-after-optional errors underline the required parameter name, and invalid default values underline the default expression.

## Error Codes

### Syntax Errors (100-199)
- `NL101`: UnexpectedToken
- `NL102`: ExpectedToken
- `NL103`: InvalidSyntax
- `NL104`: UnexpectedEndOfFile
- `NL105`: InvalidLiteral, including unterminated string, character, triple-quoted, and interpolated raw string literals with spans on the literal opener/token
- `NL106-108`: Missing closing brace/paren/bracket, with line-break and empty-list recovery pointing at the insertion position when possible
- Required-expression `NL102` diagnostics after `:=`, `=`, `print`, `throw`, `if`, `while`, `foreach in`, and similar anchors recover without consuming the next statement, including statements that VS Code auto-indents after a dangling anchor. Operator and initializer anchors point at the insertion position; keyword anchors underline the visible keyword.

### Type Errors (200-299)
- `NL201`: TypeNotFound
- `NL202`: TypeMismatch (assignment, return, argument; return diagnostics distinguish omitted return type, explicit void, and wrong non-void return type)
- `NL203`: CannotInferType
- `NL204-208`: InvalidCast, AmbiguousType, CannotResolveType, InvalidTypeArgument, GenericConstraintViolation

### Semantic Errors (300-399)
- `NL301`: UndefinedVariable
- `NL302`: UndefinedType
- `NL303`: UndefinedMember
- `NL304`: DefiniteAssignmentError
- `NL305`: MissingReturn
- `NL306`: DuplicateDeclaration
- `NL307-311`: CircularDependency, InaccessibleMember, ReadonlyAssignment, ConstantRequired, InvalidModifier
- `NL312`: UnreachableStatement (code after return/throw/exhaustive branches)
- `NL313`: InvalidExpressionStatement (value/member expression written as a statement with no side effect)

### Function/Method Errors (400-499)
- `NL401`: WrongArgumentCount
- `NL402`: NoMatchingOverload
- `NL403-410`: Various parameter errors

### Pattern Matching Errors (500-599)
- `NL501`: NonExhaustiveMatch
- `NL502-505`: UnreachablePattern, InvalidPattern, PatternTypeMismatch, GuardNotBoolean

### Import/Using Errors (700-799)
- `NL701`: ImportNotFound
- `NL702-704`: ImportCollision, CircularImport, NamespaceNotFound

### Warnings (900-999)
- `NL901`: UnusedVariable
- `NL902-906`: UnreachableCode, VisibilityConvention, ObsoleteUsage, Nullability, UnnecessaryTypeAnnotation

## Example Output (Elm-style)

```
── [NL305] ERROR ───────────────────────────── Program.nl:7:1 ──

    7 | func GetName(): string {
      | ^^^^^^^^^^^^

Not all code paths return a value of type 'string'

This function is declared to return `string`, but not all code paths return a value:

Expected: `string`

Hint: Every code path through this function must end with a `return` statement that
provides a `string` value. If you don't need to return anything, change the
return type to `void`.

Suggestion: Add a `return` statement, or change the return type to `void`

See: https://docs.n-sharp.dev/errors/NL305
```

## Testing

Error reporting tests are in `tests/ErrorReportingTests.cs` covering:
- Error code formatting and DiagnosticId
- Source snippet rendering with caret markers
- All formatting paths (Elm, Rust, Tooling, MSBuild)
- ErrorSuggestions, SmartSuggester, TypeConversionSuggester
- Levenshtein distance accuracy
- ANSI color codes
