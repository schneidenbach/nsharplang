# Known Limitations

This document lists current limitations and planned improvements.

## Type System

### 1. Lambda Type Inference from Context
**Current:** Lambda parameters typed as `Unknown` without explicit types.

```
// Works but limited
let handler := (x) => x * 2  // x is Unknown type

// Workaround: explicit types
let handler := (x: int) => x * 2
```

**Why:** Context-based type inference not implemented. LINQ method signatures not analyzed to infer lambda parameter types.

**Future:** Analyze call site context to infer lambda types.

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

### 4. Overload Resolution by Type
**Current:** Method overloads resolved by argument COUNT only.

```
// Can distinguish:
func Process(x: int)
func Process(x: int, y: int)  // Different count ✅

// Can't distinguish:
func Process(x: int)
func Process(x: string)  // Same count, different types ❌
```

**Why:** Type-based overload resolution not implemented.

**Future:** Implement full overload resolution with type matching.

## Pattern Matching

### 5. Exhaustiveness with Guards
**Current:** Exhaustiveness checking skipped when guards present.

```
result := value match {
    x when x > 0 => "positive",
    // Missing: x <= 0 case, but no warning
}
```

**Why:** Static analysis of guard conditions is complex.

**Future:** Conservative exhaustiveness checking with warnings.

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

### 7. Extension Methods on Literals
**Current:** Extension methods work on variables, not literals.

```
let count := 5
result := count.Times(() => print "hi")  // ✅ Works

// result := 5.Times(() => print "hi")   // ❌ Doesn't work
```

**Why:** Literal handling in member access resolution incomplete.

**Future:** Support extension methods on all expressions.

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

### 15. Debugger Support
**Current:** Debug generated C# code, not N# source.

**Why:** No source maps yet.

**Future:** Source map generation for N# debugging.

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
3. **Overload resolution**: Use unique method names or param counts
4. **Extension on literals**: Assign to variable first
5. **Circular imports**: Refactor to eliminate cycles
6. **Type aliases**: Use `using` statements where needed

## Priority for Fixes

**High Priority:**
- Method overload resolution by type
- Extension methods on literals
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
