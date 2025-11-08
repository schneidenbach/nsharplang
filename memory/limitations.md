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

### 3. Property Type Inference
**Current:** Properties require explicit types.

```
class Person {
    Name: string        // ✅ Type required
    // Name := "Alice"  // ❌ Not supported (C# limitation)
}
```

**Why:** C# doesn't allow `var` for class/struct members, only local variables.

**Future:** None (C# limitation).

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

### 11. Type Aliases in Transpiled Code
**Current:** Type aliases emitted as comments (no runtime representation).

```
type StringList = List<string>

// Transpiles to:
// // type alias: StringList = List<string>
```

**Why:** C# doesn't support type aliases at type level (only `using` aliases).

**Future:** None (C# limitation). Consider preprocessor approach.

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

## Tooling

### 16. Code Formatter
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
- LSP Phase 3 features

**Medium Priority:**
- Generic type inference
- Exhaustiveness with guards
- Circular import detection
- Incremental compilation

**Low Priority:**
- REPL
- Code formatter
- Nested union matching
- API doc generator
