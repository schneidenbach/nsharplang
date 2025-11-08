# Task 025: Property Type Inference

**Status:** 🔲 TODO
**Priority:** Medium
**Dependencies:** None
**Estimated Effort:** Small-Medium (4-6 hours)

## Goal

Allow properties to use `:=` for type inference, just like variables.

## Current Behavior

Properties require explicit types:
```n#
class Person {
    Name: string = "Alice"    // ✅ Works
    // Name := "Alice"        // ❌ Currently not allowed
}
```

## Desired Behavior

Properties should support `:=` syntax:
```n#
class Person {
    Name := "Alice"           // ✅ Infers string
    Age := 30                 // ✅ Infers int
    Items := [1, 2, 3]        // ✅ Infers int[]

    // Still allow explicit types
    Count: int = 0            // ✅ Also works
}
```

## Implementation

### 1. AST Changes (if needed)

Check `PropertyDeclaration` in `src/Compiler/Ast/Declarations.cs`:
- Does it support nullable `Type`?
- If `Type` is null and `Initializer` exists → infer from initializer

May need to add a flag or check both fields.

### 2. Parser Changes

**File:** `src/Compiler/Parser.cs`

In `ParsePropertyDeclaration()` or similar:

```csharp
// Currently expects: Name: Type = Value
// Should also allow: Name := Value

if (Current.Type == TokenType.ColonEquals) {
    // Property with type inference
    Advance(); // consume :=
    var initializer = ParseExpression();

    return new PropertyDeclaration(
        Name: name,
        Type: null,  // Type will be inferred
        Initializer: initializer,
        ...
    );
}
```

### 3. Analyzer Changes

**File:** `src/Compiler/Analyzer.cs`

In property analysis:

```csharp
if (property.Type == null && property.Initializer != null) {
    // Infer type from initializer
    var initializerType = AnalyzeExpression(property.Initializer);

    // Store inferred type for transpiler
    // (may need to add to symbol table or AnalysisResult)

    // Validate: initializer must have concrete type (not Unknown)
    if (initializerType is UnknownTypeInfo) {
        ReportError($"Cannot infer type for property '{property.Name}'");
    }
}
```

**Challenge:** Need to communicate inferred type to transpiler.

**Options:**
1. Store in symbol table
2. Add to AnalysisResult
3. Re-infer in transpiler (simple but duplicates work)

### 4. Transpiler Changes

**File:** `src/Compiler/Transpiler.cs`

In `TranspilePropertyDeclaration()`:

```csharp
if (property.Type == null && property.Initializer != null) {
    // Infer type from initializer for transpilation
    var inferredType = InferPropertyType(property.Initializer);

    // Emit with explicit type
    Write($"{modifiers}{inferredType} {property.Name}");

    if (property.Initializer != null) {
        _output.Append(" = ");
        TranspileExpression(property.Initializer);
    }
}
```

**Helper method:**
```csharp
private string InferPropertyType(Expression initializer) {
    // Simple version: pattern match on expression type
    return initializer switch {
        LiteralExpression lit => lit.Value switch {
            int => "int",
            string => "string",
            bool => "bool",
            // etc.
        },
        ArrayLiteralExpression arr => InferArrayType(arr),
        // ... other cases
        _ => "object"  // fallback
    };
}
```

**Better version:** Reuse Analyzer's type inference.

### 5. Tests

**File:** `tests/ParserTests.cs`

```csharp
[Fact]
public void TestPropertyWithTypeInference() {
    var source = @"
        class Person {
            Name := ""Alice""
            Age := 30
        }
    ";

    var tokens = new Lexer(source, "test").Tokenize();
    var parser = new Parser(tokens, "test");
    var ast = parser.ParseCompilationUnit();

    var cls = ast.Declarations.OfType<ClassDeclaration>().First();
    var nameProp = cls.Members.OfType<PropertyDeclaration>().First();

    Assert.Null(nameProp.Type);  // Type is null (to be inferred)
    Assert.NotNull(nameProp.Initializer);
}
```

**File:** `tests/AnalyzerTests.cs`

```csharp
[Fact]
public void TestPropertyTypeInference() {
    var source = @"
        class Person {
            Name := ""Alice""
            Age := 30
        }
    ";

    var result = Analyze(source);

    Assert.Empty(result.Errors);
    // Verify type was inferred correctly
}
```

**File:** `tests/TranspilerTests.cs`

```csharp
[Fact]
public void TestPropertyTypeInferenceTranspilation() {
    var source = @"
        class Person {
            Name := ""Alice""
            Age := 30
            Items := [1, 2, 3]
        }
    ";

    var csharp = Transpile(source);

    Assert.Contains("public string Name = \"Alice\"", csharp);
    Assert.Contains("public int Age = 30", csharp);
    Assert.Contains("public int[] Items", csharp);
}
```

### 6. Documentation Updates

**Files to update:**
- `DESIGN.md` - Update property syntax section
- `memory/features/type-system.md` - Note property inference works
- `memory/limitations.md` - Remove property inference from limitations

**New wording:**
```markdown
### Properties

Properties support both explicit types and type inference:

// Explicit type
Name: string = "Alice"

// Type inference
Name := "Alice"  // Infers string
Age := 30        // Infers int
Items := [1, 2, 3]  // Infers int[]
```

## Edge Cases

1. **No initializer, no type:**
   ```n#
   Name  // ❌ Error: need either type or initializer
   ```

2. **Nullable properties:**
   ```n#
   Name: string? = null  // ✅ Explicit nullable
   Name := null          // ❌ Can't infer from null
   ```

3. **Complex initializers:**
   ```n#
   Items := GetDefaultItems()  // Type inferred from function return
   ```

4. **Generic types:**
   ```n#
   List := new List<string>()  // Infers List<string>
   ```

## Testing Checklist

- [ ] Parser accepts `:=` in property declarations
- [ ] Analyzer infers types correctly
- [ ] Transpiler emits explicit types
- [ ] Primitive types (int, string, bool, double)
- [ ] Arrays
- [ ] Complex types (classes, records)
- [ ] Error on null initializer
- [ ] Error on unknown type
- [ ] All existing tests still pass

## Success Criteria

- [ ] Properties can use `:=` for type inference
- [ ] Transpiled C# has correct explicit types
- [ ] All tests pass
- [ ] Documentation updated
- [ ] No regression in existing code

## Notes

This makes the language more consistent - no arbitrary distinction between variables and properties.

We don't accept C# limitations. We work around them.
