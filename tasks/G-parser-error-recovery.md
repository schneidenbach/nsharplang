# Task G: Parser Error Recovery (Multi-Error Reporting)

## Context

The parser (`src/NSharpLang.Compiler/Parser.cs`) currently stops on the first error in some cases. Users only see one error at a time, which is terrible UX — especially when there are 5 errors and they have to fix-compile-fix-compile 5 times.

## What to do

Implement error recovery so the parser reports multiple diagnostics from a single parse.

### Step 1: Understand the current error model

Read `Parser.cs` and identify where errors halt parsing:
- Look for `throw` statements after parse errors
- Look for `return null` that abandons the current parse
- Look for early exits that prevent continuing to the next declaration
- Check how `ErrorReporting.cs` collects/reports errors

### Step 2: Add synchronization points

When the parser hits an error mid-declaration or mid-statement:
1. Record the error in a diagnostics list
2. Skip tokens until reaching a **synchronization point** — a token that reliably starts a new construct:
   - `func` keyword (new function)
   - `class`, `struct`, `record`, `union`, `enum`, `interface` (new type)
   - `}` (end of block — try to resume after it)
   - A newline-aligned keyword at the same indentation level
3. Resume parsing from the synchronization point

### Step 3: Return partial AST + all errors

The parser should return:
- A `CompilationUnit` with as many valid declarations as it could parse
- A list of ALL diagnostics encountered, not just the first

### Step 4: Ensure downstream consumers handle partial ASTs

- The Analyzer should gracefully handle null/missing nodes in the AST
- The LSP diagnostic publisher should emit all errors, not just the first
- `nlc check` should display all errors

### Reference

Look at how Roslyn handles error recovery:
- `/Users/claude/repos/roslyn` — search for `SkipBadTokens`, `ParseWithRecovery`, `AddError`
- Roslyn creates "missing" tokens and "skipped" trivia to represent recovery points

### Test cases:
- File with 3 syntax errors in 3 different functions → all 3 reported
- File with error in first function, valid second function → second function still parsed
- Missing closing brace → error reported, next declaration still parsed
- Invalid expression inside a valid function → function boundary recovered
- Empty/malformed file → helpful error, no crash

### IMPORTANT

- Existing valid code must parse identically — zero behavior change for correct programs
- Error positions/messages must be accurate — don't report the wrong line
- The LSP must benefit: a file with 3 errors should show all 3 in VS Code's Problems panel

## Follow the standard verification protocol in tasks/STANDARD-SUFFIX.md
