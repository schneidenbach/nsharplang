# Task H: Error Message Quality Audit — Elm-Level or Bust

## Context

AGENTS.md promises "Elm-level error messages." This is a **launch differentiator** — if N# error messages are as good as Elm's, developers will talk about it. If they're generic compiler noise, nobody cares.

The bar: https://elm-lang.org/news/compiler-errors-for-humans

Every error should:
1. Show the source line with a visual pointer to the problem
2. Explain WHY it's wrong in plain English
3. Suggest the most likely fix
4. Use color to make it scannable

## What to do

### Phase 1: Audit current state

Read `src/NSharpLang.Compiler/ErrorReporting.cs` to understand the infrastructure.

Then trigger every common error and evaluate the output. Create intentional errors:

```n#
// Type mismatch
x: int = "hello"

// Undefined variable
print unknownVar

// Missing import
list := new List<int>()  // without import System.Collections.Generic

// Wrong argument count
func Add(a: int, b: int): int { return a + b }
Add(1, 2, 3)

// Wrong argument type
Add("hello", "world")

// Missing return
func GetName(): string {
    name := "test"
    // forgot return
}

// Non-exhaustive match
union Color { Red, Green, Blue }
result := match color { Red => 1, Green => 2 }

// Duplicate definition
func Foo() {}
func Foo() {}
```

For EACH error, capture the output and grade it:
- ❌ Bad: `Error: type mismatch on line 5`
- ⚠️ OK: `Error NL042: Cannot assign string to int (line 5, col 12)`
- ✅ Good (Elm-level):
  ```
  -- TYPE MISMATCH --------------------------------- src/Program.nl

  5|    x: int = "hello"
                 ^^^^^^^

  I was expecting an `int` value, but this is a `string`.

  Hint: If you want x to be a string, change the type annotation:

      x: string = "hello"
  ```

### Phase 2: Fix the infrastructure (if needed)

If `ErrorReporting.cs` doesn't support source-line display, add it:
- Accept source text + file path + line/column in error constructors
- Extract the source line and surrounding context
- Format with line numbers, carets, and colors
- Add a `Hint:` or `Suggestion:` field

### Phase 3: Fix the top 10 worst messages

Priority order (most commonly hit errors):
1. Type mismatch (assignment, return, argument)
2. Undefined variable / function / type
3. Missing import (should suggest which import to add!)
4. Wrong number of arguments
5. Wrong argument types
6. Missing return statement
7. Non-exhaustive pattern match
8. Duplicate definition
9. Property not found on type
10. Cannot call non-function

For each, ensure:
- Source line is shown with caret
- Plain English explanation
- Actionable suggestion (not "did you mean?" vagueness — give the actual fix)
- Color output in terminal, plain text in JSON/LSP

### Phase 4: Verify in LSP

The LSP publishes diagnostics to VS Code. Verify that:
- Error messages in the Problems panel are clear (no internal jargon)
- Hover over the squiggly shows the full message with suggestion
- Quick fixes are offered where applicable (auto-import, etc.)

### Reference

- Elm errors: https://elm-lang.org/news/compiler-errors-for-humans
- Rust errors: `rustc --explain E0308`
- `/Users/claude/repos/roslyn` — search for `DiagnosticFormatter` for how Roslyn formats diagnostics

## Follow the standard verification protocol in tasks/STANDARD-SUFFIX.md
