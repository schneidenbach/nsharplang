# Known Limitations

This document lists current limitations and planned improvements.

## Type System

### 1. Lambda Type Inference from Context (RESOLVED)
**Current:** ✅ Lambda parameters inferred from contextual delegate types.

```
// All of these now infer parameter types correctly:
let handler: Func<int, int> = x => x * 2          // x inferred as int
numbers.Select(x => x * 2)                         // x inferred from element type
Apply(x => x * 2)                                  // x inferred from Func<int, int> param
handler = x => x * 2                               // x inferred from handler's type
return x => x * 2                                  // x inferred from function return type
class Foo { Doubler: Func<int, int> = x => x * 2 } // x inferred from field type

// Still requires explicit types (no context available):
f := x => x * 2  // x is Unknown — no declared type to infer from
```

**Status:** Fully implemented. Contextual type flows through variable declarations, assignments, return statements, field initializers, function call arguments, and LINQ methods.

### 2. Generic Type Inference
**Current:** Generic type parameters must be explicit.

```
// Must specify type
let result := Identity<int>(42)

// Can't infer:
// let result := Identity(42)  // Error
```

**Why:** Generic constraint solving not implemented.

**Future:** Implement full generic type inference algorithm.

### 3. Property Type Inference (RESOLVED - Task 025)
**Current:** ✅ Properties support type inference with `:=` syntax.

```
class Person {
    Name: string = "Alice"    // Explicit type
    Age := 30                 // Inferred as int
    Items := [1, 2, 3]        // Inferred as int[]
}
```

**Status:** Fully implemented in Task 025.

## Method Resolution

### 4. Overload Resolution by Type (RESOLVED)
**Current:** ✅ Method overloads resolved by argument type with scoring system.

```
// All of these now work correctly:
func Process(x: int)
func Process(x: string)       // Same count, different types ✅
func Handle(x: int)
func Handle(x: long)          // Exact match preferred over implicit widening ✅
5.Format("pre")               // Extension method overload resolution ✅
5.Format(3)                   // Selects correct overload by arg type ✅
```

**Status:** Fully implemented. Scoring: exact match (8), implicit numeric (6), assignable (4). Tie-breaking: non-generic > generic, non-params > params.

## Pattern Matching

### 5. Exhaustiveness with Guards
**Current:** Guarded arms do not count toward exhaustiveness coverage. Unguarded arms
(including wildcard `_` and plain identifier bindings like `other`) still count as full coverage.
If all union cases have only guarded arms and no wildcard/catch-all fallback, the compiler
reports a non-exhaustive match error.

```
// This is now correctly flagged as non-exhaustive:
result := value match {
    Result.Ok { v } when v > 0 => "positive",
    Result.Ok { v } when v <= 0 => "non-positive",
    // Missing: Result.Err case — no unguarded arm covers it
}
```

**Limitation:** Guard conditions are not analyzed semantically. The compiler cannot
determine that `when x > 0` and `when x <= 0` together cover all integers.

### 6. Nested Union Matching
**Current:** Deep pattern matching on nested unions limited.

```
union Result<T> {
    Success { value: T }
    Failure { error: Error }
}

union Error {
    Network { message: string }
    Validation { errors: string[] }
}

// Limited nested matching support
```

**Future:** Full nested union pattern matching.

## Extension Methods

### 7. Extension Methods on Literals (RESOLVED)
**Current:** ✅ Extension methods work on all expressions including literals.

```
5.Double()                    // ✅ Extension on int literal
"hello".IsEmpty()             // ✅ Extension on string literal
3.14.Negate()                 // ✅ Extension on double literal
true.Toggle()                 // ✅ Extension on bool literal
5.ToString().Length            // ✅ Chained member access on literal
let s: string = 5.Double()   // ✅ Return type properly checked (errors if wrong type)
```

**Status:** Fully implemented. Fixed cross-assembly type comparison bug in IsAssignable (MLC types vs runtime types). Extension method overload groups now return NSharpMethodGroupInfo for proper resolution.

## Import System

### 8. Circular Import Detection
**Current:** No detection of circular imports.

```
// File A imports B
// File B imports A
// May cause issues
```

**Future:** Detect and report circular imports.

### 9. Implicit Symbol Resolution
**Current:** Requires explicit file imports.

```
// Must import:
import "Models/Person"

// Can't auto-discover from namespace
```

**Future:** Automatic symbol resolution from project namespace.

## Error Recovery

### 10. Single Error Reporting
**Current:** Parser stops on first error in some cases.

**Why:** Error recovery not fully implemented.

**Future:** Continue parsing after errors to report multiple issues.

## Transpiler

### 11. Type Aliases — Same-Namespace and Nullable Limitations
**Current:** Type aliases now emit as C# file-scoped `using` directives. However, two edge cases remain:

1. **Same-namespace types:** `type Foo = MyLocalClass` where `MyLocalClass` is in the same file's namespace will fail because `using` aliases appear before the namespace declaration and can't see types declared later.
2. **Nullable reference types:** `type MaybeString = string?` will fail with CS9132 — C# does not allow nullable reference types in `using` aliases.

**Why:** C# `using` alias restrictions.

**Future:** Consider emitting these edge cases as comments with a compiler warning diagnostic.

## Performance

### 12. Incremental Compilation
**Current:** Full recompilation on every build.

**Future:** Track changes, recompile only modified files.

### 13. Parallel File Processing
**Current:** Files compiled sequentially.

**Future:** Parallel compilation for large projects.

## IDE Support

### 14. Language Server Protocol - Limited Features
**Current:** LSP Phase 1 & 2 complete (syntax highlighting, diagnostics).

**Not yet:**
- Go-to-definition
- Find all references
- Rename symbol
- Signature help

**Future:** LSP Phase 3+ implementation.

### 15. Debugger Support (RESOLVED)
**Current:** Full debugging support in VS Code and any IDE with coreclr debugger.
- Breakpoints in `.nl` files work directly
- Step through, step over, step into
- Variable inspection and watch window
- Call stack shows N# source files
- Generated scaffolding hidden from debugger via `#line hidden` directives

## ASP.NET Core Support

### 16. Parameter Attributes
**Current:** Parameter-level attributes not supported.

```
// Doesn't work:
func Create([FromBody] dto: TaskDto): IActionResult

// Workaround: ASP.NET Core infers [FromBody] automatically for complex types
func Create(dto: TaskDto): IActionResult  // ✅ Works
```

**Why:** Parser doesn't support attributes on parameters yet.

**Priority:** Low - ASP.NET Core's implicit binding works for most scenarios.

### 17. Null-Forgiving Operator
**Current:** The `!` null-forgiving operator is not supported.

```
// Doesn't work:
length := name!.Length

// Workaround: Use null-coalescing or explicit null check
length := (name ?? "").Length  // ✅ Works
```

**Why:** Parser doesn't recognize `!` as a postfix operator.

**Priority:** Low - workaround is simple and more explicit.

**Note:** All critical ASP.NET Core gaps (external type resolution, boolean inference) were resolved in Task 030. See GAPS.md for full status.

## Tooling

### 18. Code Formatter
**Current:** No auto-formatter.

**Future:** `nlc fmt` command (gofmt/rustfmt style).

### 17. REPL
**Current:** No interactive shell.

**Future:** N# REPL for experimentation.

## Testing

### 18. N# Test Files
**Current:** Tests written in C# (xUnit).

**Future:** `.tests.nl` files with `nlc test` command.

## Documentation

### 19. API Documentation Generator
**Current:** No automatic doc generation from code.

**Future:** Tool to generate docs from N# source and comments.

## Workarounds

Most limitations have workarounds:

1. **Lambda types**: Use explicit type annotations
2. **Generic inference**: Specify type parameters explicitly
3. ~~**Overload resolution**: Use unique method names or param counts~~ (RESOLVED)
4. ~~**Extension on literals**: Assign to variable first~~ (RESOLVED)
5. **Circular imports**: Refactor to eliminate cycles
6. **Type aliases**: Use `using` statements where needed

## Priority for Fixes

**High Priority:**
- ~~Method overload resolution by type~~ (RESOLVED)
- ~~Extension methods on literals~~ (RESOLVED)
- SemanticModel field/property recording (completions use AST fallback currently)
- BindingMap for cross-file type references (import path doesn't record bindings)

**Medium Priority:**
- Generic type inference
- Exhaustiveness with guards
- Circular import detection
- Position-aware SemanticModel (for shadowing, scope-correct lookups)

**Low Priority:**
- REPL
- Nested union matching

**Done (previously listed):**
- ✅ Code formatter (`nlc format`)
- ✅ LSP Phase 3 features (completion, hover, definition, rename, code actions)
- ✅ API doc generator (partial — `nlc query` provides structured symbol/type info)
- ✅ Incremental compilation (daemon mode caches analysis)
