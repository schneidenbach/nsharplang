# PLAN: Elm-Level Error Reporting System

**Status:** Design Phase
**Goal:** Transform Parser from exception-throwing to error-collecting with Elm-quality diagnostics
**Difficulty:** Major refactor (3200 line Parser, 20+ exception throw sites)

---

## Executive Summary

### Current State (What the Previous Developer Did)

**✅ COMPLETED - Output Infrastructure:**
- `CompilerError` record with rich fields: `HumanExplanation`, `ContextualHint`, `Suggestions`, `DocsUrl`
- `ErrorCode` enum (100-999) with categorized error codes
- `ErrorSuggestions` class with Levenshtein distance matching
- Beautiful formatting: `FormatElmStyle()` and `FormatRustStyle()` with ANSI colors
- CLI integration calling `error.Format()`

**✅ COMPLETED - Analyzer Integration:**
- Analyzer has `List<CompilerError> _errors` and collects errors properly
- Analyzer has `ReportError()` and `ReportWarning()` methods
- Analyzer creates errors with source snippets
- Analyzer uses `ErrorSuggestions` for helpful hints

**❌ MISSING - Parser Integration:**
- Parser **throws raw `Exception`** instead of creating `CompilerError` objects
- Parser has **NO error collection mechanism** (`List<CompilerError>`)
- Parser has **NO error recovery** (stops at first error)
- Parser doesn't populate rich error fields
- Language Server catches exceptions and parses location from message strings (HACKY)

**❌ MISSING - Elm-Level Features:**
- No multi-error reporting (show all errors at once)
- No error recovery/synchronization
- No context-aware suggestions in Parser
- No educational explanations for syntax errors
- No documentation links

### Why This Failed

The previous developer built a **beautiful error display system** but never connected the **error source** (Parser) to it. They stopped halfway!

It's like installing a high-end stereo system but still using a broken microphone.

---

## What is "Elm-Level Quality"?

Elm compiler errors are famous for being the best in the industry. Here's what makes them great:

### 1. **Conversational Tone**
❌ Bad: `Expected member name. Got 'return' at 133:9`
✅ Good: `I see a dot (.) operator but no member name after it.`

### 2. **Visual Context**
```
129| employees := await db.Employees.ToArrayAsync()
130| employees.
            ^
I was expecting to see a property or method name here.
```

### 3. **Educational Explanations**
Not just "what's wrong" but **why** it's wrong and **what to do**.

### 4. **Actionable Suggestions**
```
Hint: Did you forget to finish this line? Common members include:
    • Length - get the number of elements
    • Count - get the count (for collections)
    • Select(fn) - transform each element
```

### 5. **Multiple Errors At Once**
Don't stop at first error - show them ALL so users can fix in one pass.

### 6. **Documentation Links**
`Read more: https://docs.nsharp.dev/errors/NL102`

---

## Architecture Design

### Phase 1: Parser Error Collection (FOUNDATION)

**Goal:** Parser collects errors instead of throwing exceptions.

#### Changes to Parser Class

```csharp
public class Parser
{
    private readonly List<Token> _tokens;
    private readonly string? _fileName;
    private readonly string? _sourceCode;  // NEW: For error snippets
    private readonly string[]? _sourceLines; // NEW: Split source
    private readonly List<CompilerError> _errors = new(); // NEW: Error collection
    private int _position;

    public Parser(List<Token> tokens, string? fileName = null, string? sourceCode = null)
    {
        _tokens = tokens.Where(t => t.Type != TokenType.Newline).ToList();
        _fileName = fileName;
        _sourceCode = sourceCode;
        _sourceLines = sourceCode?.Split('\n');
    }
}
```

#### New Error Reporting Method

```csharp
private void ReportError(
    ErrorCode code,
    string message,
    int line,
    int column,
    string? humanExplanation = null,
    string? hint = null,
    List<string>? suggestions = null,
    int length = 1)
{
    var snippet = GetSourceSnippet(line);

    var error = CompilerError.WithSnippet(
        code,
        message,
        _fileName ?? "unknown",
        line,
        column,
        snippet,
        length,
        suggestions?.FirstOrDefault()
    ) {
        HumanExplanation = humanExplanation,
        ContextualHint = hint,
        Suggestions = suggestions,
        DocsUrl = $"https://docs.nsharp.dev/errors/NL{(int)code:D3}"
    };

    _errors.Add(error);
}

private string? GetSourceSnippet(int line)
{
    if (_sourceLines == null || line < 1 || line > _sourceLines.Length)
        return null;
    return _sourceLines[line - 1];
}
```

#### New Return Type: ParseResult

```csharp
public class ParseResult
{
    public CompilationUnit? CompilationUnit { get; init; }
    public List<CompilerError> Errors { get; init; } = new();
    public bool Success => !Errors.Any(e => e.Severity == ErrorSeverity.Error);
    public bool HasWarnings => Errors.Any(e => e.Severity == ErrorSeverity.Warning);
}
```

#### Updated ParseCompilationUnit

```csharp
public ParseResult ParseCompilationUnit()
{
    CompilationUnit? unit = null;

    try
    {
        // ... existing parsing logic ...
        unit = new CompilationUnit(/*...*/);
    }
    catch (Exception ex)
    {
        // Shouldn't happen anymore, but safety net
        ReportError(
            ErrorCode.InvalidSyntax,
            ex.Message,
            Current.Line,
            Current.Column,
            humanExplanation: "An unexpected error occurred while parsing."
        );
    }

    return new ParseResult
    {
        CompilationUnit = unit,
        Errors = _errors
    };
}
```

---

### Phase 2: Error Recovery (ELM-LEVEL ESSENTIAL)

**Goal:** Parser continues after errors and reports ALL errors in one pass.

#### Synchronization Strategy

When Parser encounters an error:
1. Report the error
2. Skip tokens until reaching a "synchronization point"
3. Continue parsing from there

**Synchronization points:**
- Statement boundaries: `;`, `}`
- Declaration keywords: `func`, `class`, `struct`, `enum`, `interface`
- Block keywords: `if`, `for`, `while`, `match`, `return`

#### Implementation

```csharp
private void Synchronize()
{
    // Skip tokens until we reach a good recovery point
    while (!IsAtEnd())
    {
        // After semicolon is safe
        if (Previous.Type == TokenType.Semicolon) return;

        // Before any of these keywords is safe
        switch (Current.Type)
        {
            case TokenType.Class:
            case TokenType.Struct:
            case TokenType.Enum:
            case TokenType.Interface:
            case TokenType.Func:
            case TokenType.If:
            case TokenType.For:
            case TokenType.While:
            case TokenType.Match:
            case TokenType.Return:
            case TokenType.RightBrace: // End of block
                return;
        }

        Advance();
    }
}
```

#### Error Placeholder Nodes

Create AST nodes to represent parse errors:

```csharp
// In Ast.cs
public record ErrorExpression(int Line, int Column) : Expression(Line, Column);
public record ErrorStatement(int Line, int Column) : Statement(Line, Column);
public record ErrorDeclaration(int Line, int Column) : Declaration(Line, Column);
```

These allow parsing to continue with a valid (but marked) AST.

#### Updated Parsing with Recovery

**BEFORE:**
```csharp
private string ConsumeIdentifier(string message)
{
    if (!Check(TokenType.Identifier))
        throw new Exception($"{message}. Got '{Current.Value}' at {Current.Line}:{Current.Column}");
    return Advance().Value;
}
```

**AFTER:**
```csharp
private string ConsumeIdentifier(string message, string? hint = null)
{
    if (!Check(TokenType.Identifier))
    {
        ReportError(
            ErrorCode.ExpectedToken,
            message,
            Current.Line,
            Current.Column,
            humanExplanation: $"I was expecting an identifier here, but I found '{Current.Value}' instead.",
            hint: hint
        );
        Synchronize();
        return "<error>"; // Return placeholder
    }
    return Advance().Value;
}
```

---

### Phase 3: Rich Error Messages (ELM-LEVEL QUALITY)

**Goal:** Every Parser error has human explanation, hints, and suggestions.

#### Error Message Templates

Create explanation for each error context:

```csharp
private static class ParserErrorMessages
{
    public static (string explanation, string hint, List<string> suggestions)
        IncompleteMemberAccess(string token)
    {
        return (
            explanation: "I see a dot (.) operator but no member name after it.",
            hint: "After a dot, I need to see a property or method name.",
            suggestions: new List<string>
            {
                "Check if you forgot to finish this line",
                "If accessing a member, add the member name after the dot",
                "If this is end of statement, remove the trailing dot"
            }
        );
    }

    public static (string explanation, string hint, List<string> suggestions)
        UnexpectedToken(string expected, string got, ParserContext context)
    {
        var explanation = context switch
        {
            ParserContext.InFunctionSignature =>
                $"I was parsing a function signature and expected {expected}, but found '{got}'.",
            ParserContext.InExpression =>
                $"I was parsing an expression and expected {expected}, but found '{got}'.",
            ParserContext.InTypeAnnotation =>
                $"I was parsing a type and expected {expected}, but found '{got}'.",
            _ =>
                $"I expected {expected} here, but found '{got}'."
        };

        var hint = GetContextualHint(context, expected, got);
        var suggestions = GetSuggestionsForContext(context, expected);

        return (explanation, hint, suggestions);
    }

    public static string GetContextualHint(ParserContext context, string expected, string got)
    {
        return context switch
        {
            ParserContext.InFunctionSignature when expected == "identifier" =>
                "Function parameters need names. Did you forget to add a parameter name?",
            ParserContext.InExpression when expected == ")" =>
                "Every opening parenthesis '(' needs a matching closing parenthesis ')'.",
            ParserContext.InTypeAnnotation when expected == "type" =>
                "Type annotations require a valid type name like 'int', 'string', or a custom type.",
            _ => null
        };
    }
}

enum ParserContext
{
    Global,
    InClass,
    InFunction,
    InFunctionSignature,
    InExpression,
    InStatement,
    InTypeAnnotation,
    InPattern
}
```

#### Context Tracking

Add field to Parser:

```csharp
private ParserContext _currentContext = ParserContext.Global;
```

Update context as we parse:

```csharp
private FunctionDeclaration ParseFunction()
{
    var previousContext = _currentContext;
    _currentContext = ParserContext.InFunction;

    try
    {
        // ... parsing ...

        _currentContext = ParserContext.InFunctionSignature;
        var parameters = ParseParameters();

        _currentContext = ParserContext.InFunction;
        var body = ParseBlock();

        return new FunctionDeclaration(/*...*/);
    }
    finally
    {
        _currentContext = previousContext;
    }
}
```

#### Example: Incomplete Member Access

**BEFORE:**
```csharp
var memberName = ConsumeIdentifier("Expected member name");
```

**AFTER:**
```csharp
if (!Check(TokenType.Identifier))
{
    var (explanation, hint, suggestions) =
        ParserErrorMessages.IncompleteMemberAccess(Current.Value);

    ReportError(
        ErrorCode.ExpectedToken,
        "Expected member name after dot operator",
        Current.Line,
        Current.Column,
        humanExplanation: explanation,
        hint: hint,
        suggestions: suggestions,
        length: Current.Value.Length
    );

    Synchronize();
    return new ErrorExpression(Current.Line, Current.Column);
}

var memberName = Advance().Value;
```

#### Example: Type Mismatch

```csharp
private void ReportTypeMismatchError(string expected, string actual, int line, int column)
{
    var explanation = $"This expression has type '{actual}', but I need it to be '{expected}'.";

    var hint = (expected, actual) switch
    {
        ("int", "string") => "You can't use a string where a number is expected. Did you mean to parse it?",
        ("string", "int") => "You can't use a number where a string is expected. Try .ToString() to convert.",
        ("bool", _) => "This expression should be true or false, but it's not a boolean.",
        _ => null
    };

    var suggestions = new List<string>();
    if (expected == "int" && actual == "string")
    {
        suggestions.Add("Use int.Parse(value) to convert string to int");
        suggestions.Add("Use int.TryParse(value, out result) for safe conversion");
    }

    ReportError(
        ErrorCode.TypeMismatch,
        $"Type mismatch: expected '{expected}', got '{actual}'",
        line,
        column,
        humanExplanation: explanation,
        hint: hint,
        suggestions: suggestions
    );
}
```

---

### Phase 4: Update All Callers

**Goal:** Update everything that calls Parser to use new ParseResult.

#### 1. MultiFileCompiler

**BEFORE:**
```csharp
var parser = new Parser(tokens, filePath);
var compilationUnit = parser.ParseCompilationUnit();
```

**AFTER:**
```csharp
var parser = new Parser(tokens, filePath, sourceCode);
var parseResult = parser.ParseCompilationUnit();

// Collect parse errors
foreach (var error in parseResult.Errors)
{
    _errors.Add(error);
}

// Only continue if parsing succeeded
if (!parseResult.Success || parseResult.CompilationUnit == null)
{
    return; // Skip this file, continue with others
}

var compilationUnit = parseResult.CompilationUnit;
```

#### 2. DocumentManager (Language Server)

**BEFORE (with hacky regex parsing):**
```csharp
try
{
    var parser = new Parser(tokens, uri);
    var unit = parser.ParseCompilationUnit();
    // ...
}
catch (Exception ex)
{
    var (line, column) = ParseLocationFromMessage(ex.Message); // HACKY!
    state.Diagnostics = new List<CompilerError> { /* ... */ };
}
```

**AFTER (clean):**
```csharp
var parser = new Parser(tokens, uri, text); // Pass source code
var parseResult = parser.ParseCompilationUnit();

// Start with parse errors
state.Diagnostics = new List<CompilerError>(parseResult.Errors);

// Only run analyzer if parsing succeeded
if (parseResult.Success && parseResult.CompilationUnit != null)
{
    var analyzer = new Analyzer();
    // ... analyzer setup ...
    var analysisResult = analyzer.Analyze(parseResult.CompilationUnit, uri, projectDir, text);
    state.Diagnostics.AddRange(analysisResult.Errors);
}

// No more try/catch! No more regex parsing!
```

#### 3. CLI

**BEFORE:**
```csharp
try
{
    var parser = new Parser(tokens, fileName);
    var unit = parser.ParseCompilationUnit();
}
catch (Exception ex)
{
    Console.Error.WriteLine($"Parse error: {ex.Message}");
    return 1;
}
```

**AFTER:**
```csharp
var parser = new Parser(tokens, fileName, sourceCode);
var parseResult = parser.ParseCompilationUnit();

// Display all parse errors
foreach (var error in parseResult.Errors)
{
    Console.Error.WriteLine(error.Format());
}

if (!parseResult.Success)
{
    var errorCount = parseResult.Errors.Count(e => e.Severity == ErrorSeverity.Error);
    return Error($"Parsing failed with {errorCount} error(s)");
}
```

---

### Phase 5: Implementation Steps

#### Step 1: Create Infrastructure (Low Risk)
- [ ] Add `ParseResult` class
- [ ] Add `ParserContext` enum
- [ ] Add error placeholder AST nodes (`ErrorExpression`, etc.)
- [ ] Add `ParserErrorMessages` static class

#### Step 2: Update Parser Constructor (Low Risk)
- [ ] Add `_sourceCode` and `_sourceLines` fields
- [ ] Add `_errors` list
- [ ] Update constructor signature
- [ ] Add `ReportError()` method
- [ ] Add `GetSourceSnippet()` method
- [ ] Add `Synchronize()` method

#### Step 3: Change Return Type (Medium Risk)
- [ ] Change `ParseCompilationUnit()` to return `ParseResult`
- [ ] Wrap existing logic in try/catch for safety net
- [ ] Return `ParseResult` with errors

#### Step 4: Replace Exception Throws (HIGH RISK - BIGGEST TASK)

**Strategy:** Replace incrementally by category

##### 4a. Start with Simple Cases (10-15 throw sites)
Replace simple throws in helpers:
- [ ] `ConsumeIdentifier()`
- [ ] `Consume(TokenType, message)`
- [ ] `ConsumeToken()`

##### 4b. Expression Parsing (~5 throw sites)
- [ ] Member access errors
- [ ] Invalid operator errors
- [ ] Unexpected token in expression

##### 4c. Statement Parsing (~3 throw sites)
- [ ] Invalid statement syntax

##### 4d. Declaration Parsing (~5 throw sites)
- [ ] Function declaration errors
- [ ] Class/struct errors
- [ ] Property accessor errors

##### 4e. Add Rich Messages
For each replacement:
- [ ] Use proper `ErrorCode`
- [ ] Add `humanExplanation`
- [ ] Add contextual `hint`
- [ ] Add actionable `suggestions`

#### Step 5: Update All Callers (Medium Risk)
- [ ] Update `MultiFileCompiler.cs`
- [ ] Update `DocumentManager.cs` (Language Server)
- [ ] Update `Program.cs` (CLI)
- [ ] Update any other Parser callers

#### Step 6: Update Tests (High Risk)
- [ ] Update parser tests to use `ParseResult`
- [ ] Update integration tests
- [ ] Add tests for error recovery
- [ ] Add tests for multiple errors
- [ ] Add tests for error message quality

#### Step 7: Documentation
- [ ] Update `memory/components/parser.md`
- [ ] Update `memory/components/error-reporting.md`
- [ ] Create error documentation at `docs.nsharp.dev`

---

## Testing Strategy

### 1. Unit Tests for Error Collection

```csharp
[Fact]
public void Parser_CollectsMultipleErrors()
{
    var source = @"
        func test() {
            x.     // Incomplete member access
            y =    // Incomplete assignment
            return // Missing value
        }
    ";

    var parser = new Parser(Tokenize(source), "test.nl", source);
    var result = parser.ParseCompilationUnit();

    Assert.False(result.Success);
    Assert.Equal(3, result.Errors.Count);
    Assert.All(result.Errors, e => Assert.Equal(ErrorSeverity.Error, e.Severity));
}
```

### 2. Error Message Quality Tests

```csharp
[Fact]
public void Parser_ProvesRichErrorMessage_ForIncompleteMemberAccess()
{
    var source = "x.";
    var parser = new Parser(Tokenize(source), "test.nl", source);
    var result = parser.ParseCompilationUnit();

    var error = result.Errors.Single();

    Assert.Equal(ErrorCode.ExpectedToken, error.Code);
    Assert.NotNull(error.HumanExplanation);
    Assert.NotNull(error.ContextualHint);
    Assert.NotEmpty(error.Suggestions);
    Assert.Contains("https://docs.nsharp.dev/errors/", error.DocsUrl);
}
```

### 3. Error Recovery Tests

```csharp
[Fact]
public void Parser_RecoversAfterError_ContinuesParsing()
{
    var source = @"
        func bad() {
            x.   // Error here
        }

        func good() {  // Should still parse this
            return 42
        }
    ";

    var parser = new Parser(Tokenize(source), "test.nl", source);
    var result = parser.ParseCompilationUnit();

    Assert.False(result.Success); // Has errors
    Assert.Single(result.Errors); // But only one
    Assert.NotNull(result.CompilationUnit); // AST was still built
    Assert.Equal(2, result.CompilationUnit.Declarations.Count); // Both functions parsed
}
```

### 4. Integration Test with Language Server

```csharp
[Fact]
public void LanguageServer_ShowsErrorAtCorrectLocation()
{
    var source = @"
        func test() {
            employees.
            return
        }
    ";

    var docManager = new DocumentManager(logger);
    docManager.UpdateDocument("file:///test.nl", source, 1);

    var doc = docManager.GetDocument("file:///test.nl");

    Assert.Single(doc.Diagnostics);
    var diagnostic = doc.Diagnostics[0];

    Assert.Equal(3, diagnostic.Line); // Line 3 (1-indexed)
    Assert.Contains("member name", diagnostic.Message);
}
```

---

## Risks & Mitigation

### Risk 1: Breaking 765 Existing Tests
**Impact:** HIGH
**Probability:** HIGH

**Mitigation:**
- Implement incrementally - one helper method at a time
- Run tests after each small change
- Use feature flag if needed: `ENABLE_ERROR_COLLECTION`
- Keep both code paths temporarily during transition

### Risk 2: Error Recovery Creates Invalid AST
**Impact:** MEDIUM
**Probability:** MEDIUM

**Mitigation:**
- Use explicit error placeholder nodes
- Analyzer must check for and skip error nodes
- Transpiler must handle error nodes gracefully
- Document error node behavior

### Risk 3: Performance Degradation
**Impact:** LOW
**Probability:** LOW

**Mitigation:**
- Error collection is only list operations (cheap)
- Source line splitting happens once
- Benchmark before/after with large files

### Risk 4: Incomplete Error Messages
**Impact:** MEDIUM
**Probability:** HIGH

**Mitigation:**
- Start with basic messages, enhance iteratively
- Collect feedback from real usage
- Create error message guidelines document

---

## Success Criteria

### Phase 1 Success
- [ ] Parser has `_errors` list
- [ ] Parser has `ReportError()` method
- [ ] `ParseResult` class exists and is returned
- [ ] At least ONE throw replaced with ReportError
- [ ] Tests pass

### Phase 2 Success
- [ ] Parser reports multiple errors in one pass
- [ ] `Synchronize()` method works
- [ ] Error placeholder nodes exist
- [ ] Parser recovers from common errors
- [ ] Tests demonstrate recovery

### Phase 3 Success
- [ ] All errors have `humanExplanation`
- [ ] All errors have contextual `hint`
- [ ] All errors have actionable `suggestions`
- [ ] Error formatting looks beautiful
- [ ] Documentation links work

### Phase 4 Success
- [ ] All callers updated (MultiFileCompiler, DocumentManager, CLI)
- [ ] Language Server shows errors at correct location
- [ ] No more hacky regex parsing
- [ ] All tests pass

### Final Success (Elm-Level Quality)
- [ ] Parser NEVER throws exceptions for parse errors
- [ ] Parser reports ALL errors in one pass
- [ ] Error messages are conversational and educational
- [ ] Suggestions are context-aware and actionable
- [ ] Errors display beautifully in terminal with colors
- [ ] Errors show at correct location in VS Code
- [ ] Documentation links are helpful
- [ ] Zero test failures
- [ ] Real users say "Wow, these error messages are great!"

---

## Estimated Effort

- **Phase 1 (Infrastructure):** 2-3 hours
- **Phase 2 (Error Recovery):** 3-4 hours
- **Phase 3 (Rich Messages):** 5-8 hours (20+ error sites)
- **Phase 4 (Update Callers):** 2-3 hours
- **Testing & Polish:** 3-4 hours

**Total:** 15-22 hours of focused work

---

## References

### Similar Systems
- **Elm Compiler:** https://elm-lang.org/news/compiler-errors-for-humans
- **Rust Compiler:** https://blog.rust-lang.org/2016/08/10/Shape-of-errors-to-come.html
- **TypeScript:** Contextual error messages
- **Roslyn (C#):** Error recovery and error nodes

### Internal Documentation
- `memory/components/parser.md` - Current parser documentation
- `memory/components/error-reporting.md` - Error system documentation
- `src/Compiler/ErrorReporting.cs` - Existing error infrastructure

---

**Created:** 2025-11-12
**Last Updated:** 2025-11-12
**Status:** Ready for implementation
