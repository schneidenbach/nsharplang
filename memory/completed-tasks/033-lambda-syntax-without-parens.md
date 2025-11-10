# Task 033: Lambda Syntax Without Parentheses

**Priority:** Medium (Developer experience - syntax improvement)
**Dependencies:** None
**Estimated Effort:** Small (2-3 hours)
**Status:** Not started

## Goal

Allow and encourage lambda expressions with single parameters to omit parentheses, following modern language conventions (JavaScript, Scala, Kotlin).

## Current State

Lambdas currently require parentheses around all parameters:

```n#
// Current: parens required
tasks := db.Tasks.Where((t) => t.Status == status)
builder.Services.AddDbContext<AppDbContext>((options) => {
    options.UseSqlite("Data Source=tasks.db")
})

// Current: empty parens for no params (this is fine)
Task.Run(() => { DoWork() })
```

## Desired State

Single-parameter lambdas should allow omitting parentheses:

```n#
// Proposed: no parens for single param (preferred)
tasks := db.Tasks.Where(t => t.Status == status)
builder.Services.AddDbContext<AppDbContext>(options => {
    options.UseSqlite("Data Source=tasks.db")
})

// Still support parens (for backwards compatibility)
tasks := db.Tasks.Where((t) => t.Status == status)  // Still valid

// Multiple params: still require parens
.Select((t, i) => new { Task: t, Index: i })

// No params: still require parens
Task.Run(() => { DoWork() })
```

## Benefits

1. **More concise** - Reduces visual noise
2. **Modern conventions** - Matches JavaScript, Kotlin, Scala
3. **Common case optimization** - Single-param lambdas are most common
4. **Optional** - Keeps backwards compatibility with parens

## Implementation Steps

### 1. Update Lexer/Parser

**File:** `src/Compiler/Parser.cs`

Modify lambda parsing to handle both forms:

```csharp
private LambdaExpression ParseLambdaExpression()
{
    var parameters = new List<Parameter>();

    // Case 1: () => expr (no params)
    if (Current.Type == TokenType.LeftParen && Peek().Type == TokenType.RightParen)
    {
        Consume(TokenType.LeftParen);
        Consume(TokenType.RightParen);
        // parameters remains empty
    }
    // Case 2: (x, y) => expr (multiple params with parens)
    else if (Current.Type == TokenType.LeftParen)
    {
        Consume(TokenType.LeftParen);
        parameters = ParseParameterList();
        Consume(TokenType.RightParen);
    }
    // Case 3: x => expr (single param without parens) - NEW!
    else if (Current.Type == TokenType.Identifier && Peek().Type == TokenType.Arrow)
    {
        var paramName = Consume(TokenType.Identifier).Value;
        parameters.Add(new Parameter(paramName, null)); // Type inferred
    }
    else
    {
        throw new ParseError("Expected lambda parameters");
    }

    Consume(TokenType.Arrow); // =>

    var body = ParseExpression();

    return new LambdaExpression(parameters, body);
}
```

### 2. Update Type Inference

Ensure type inference works for parameters without explicit types:

```csharp
private TypeDescriptor InferLambdaParameterType(LambdaExpression lambda, TypeDescriptor delegateType)
{
    // If delegate type is Func<T, TResult> or Action<T>, infer T for param
    if (delegateType.IsGenericDelegate)
    {
        var paramTypes = delegateType.GetDelegateParameterTypes();

        for (int i = 0; i < lambda.Parameters.Count; i++)
        {
            if (lambda.Parameters[i].Type == null)
            {
                lambda.Parameters[i].Type = paramTypes[i];
            }
        }
    }
}
```

### 3. Update Transpiler

Transpiler should emit parens in C# (C# always requires them):

```csharp
private string TranspileLambda(LambdaExpression lambda)
{
    // Always emit with parens in C# for consistency
    var parameters = string.Join(", ", lambda.Parameters.Select(p =>
        p.Type != null ? $"{TranspileType(p.Type)} {p.Name}" : p.Name
    ));

    var body = TranspileExpression(lambda.Body);

    // Always use parens in C# output
    return $"({parameters}) => {body}";
}
```

### 4. Update Examples

Update all examples to use paren-less syntax for single parameters:

**Before:**
```n#
tasks := db.Tasks
    .Where((t) => t.Status == status)
    .OrderBy((t) => t.DueDate)
    .Select((t) => t.Title)
```

**After:**
```n#
tasks := db.Tasks
    .Where(t => t.Status == status)
    .OrderBy(t => t.DueDate)
    .Select(t => t.Title)
```

**Files to update:**
- `examples/13-aspnet-demo/TaskManagementApi/Tasks.nl`
- `examples/13-aspnet-demo/TaskManagementApi/Program.nl`
- `examples/13-aspnet-demo/TaskManagementApi/README.md`
- Any other examples using lambdas

### 5. Add Tests

```csharp
[Fact]
public void Lambda_SingleParamWithoutParens_Parses()
{
    var source = @"
import System.Linq

func Test() {
    items := [1, 2, 3, 4, 5]
    evens := items.Where(x => x % 2 == 0)
}";

    var result = Parse(source);

    Assert.NotNull(result);
    // Verify lambda was parsed correctly
}

[Fact]
public void Lambda_SingleParamWithParens_StillWorks()
{
    var source = @"
import System.Linq

func Test() {
    items := [1, 2, 3, 4, 5]
    evens := items.Where((x) => x % 2 == 0)
}";

    var result = Parse(source);

    Assert.NotNull(result);
    // Both forms should work
}

[Fact]
public void Lambda_MultipleParams_RequiresParens()
{
    var source = @"
func Test() {
    items := [1, 2, 3]
    indexed := items.Select((item, index) => new { Item: item, Index: index })
}";

    var result = Parse(source);

    Assert.NotNull(result);
}

[Fact]
public void Lambda_NoParams_RequiresParens()
{
    var source = @"
func Test() {
    Task.Run(() => { print "Hello" })
}";

    var result = Parse(source);

    Assert.NotNull(result);
}

[Fact]
public void Lambda_SingleParamWithType_WithParens()
{
    var source = @"
func Test() {
    items := [1, 2, 3]
    evens := items.Where((x: int) => x % 2 == 0)
}";

    var result = Parse(source);

    Assert.NotNull(result);
}

[Fact]
public void Transpile_SingleParamLambda_EmitsParens()
{
    var source = @"
import System.Linq

func Test() {
    items := [1, 2, 3]
    evens := items.Where(x => x % 2 == 0)
}";

    var cs = Transpile(source);

    // C# output should have parens
    Assert.Contains("(x) =>", cs);
}
```

### 6. Update Documentation

**DESIGN.md:**
```markdown
### Lambda Expressions

Lambda expressions support multiple syntaxes:

**Single parameter (no type annotation):**
```n#
items.Where(x => x > 10)              // Preferred
items.Where((x) => x > 10)            // Also valid
```

**Single parameter (with type annotation):**
```n#
items.Where((x: int) => x > 10)       // Parens required with type
```

**Multiple parameters:**
```n#
items.Select((x, i) => new { Value: x, Index: i })  // Parens required
```

**No parameters:**
```n#
Task.Run(() => { DoWork() })          // Parens required
```

**Type inference:**
Parameter types are inferred from the delegate type when not specified.
```

## Grammar Changes

**Before:**
```
lambda_expression := '(' parameter_list ')' '=>' expression
                  |  '(' ')' '=>' expression
```

**After:**
```
lambda_expression := '(' parameter_list ')' '=>' expression     # Multiple params
                  |  '(' identifier ':' type ')' '=>' expression  # Single param with type
                  |  '(' ')' '=>' expression                      # No params
                  |  identifier '=>' expression                   # Single param (NEW!)
```

## Success Criteria

- [ ] Parser accepts single-param lambdas without parens
- [ ] Parser still accepts lambdas with parens (backwards compatible)
- [ ] Multi-param lambdas require parens (error if missing)
- [ ] No-param lambdas require parens (error if missing)
- [ ] Type inference works for untyped parameters
- [ ] Transpiler emits valid C# (always with parens)
- [ ] At least 6 tests covering all cases
- [ ] All existing tests still pass
- [ ] Examples updated to use paren-less syntax
- [ ] DESIGN.md updated with lambda syntax rules

## Compatibility

This change is **100% backwards compatible**. All existing code with parentheses will continue to work. The paren-less syntax is purely additive.

## Style Recommendation

After this change, the style guide should recommend:

✅ **Preferred:**
```n#
items.Where(x => x > 10)
```

⚠️ **Discouraged (but valid):**
```n#
items.Where((x) => x > 10)
```

## Examples in the Wild

**JavaScript:**
```javascript
items.filter(x => x > 10)              // Single param, no parens
items.filter((x, i) => x > i)          // Multiple params, parens required
```

**Kotlin:**
```kotlin
items.filter { x -> x > 10 }           // Single param (different syntax)
items.filter { it > 10 }               // Implicit 'it'
```

**Scala:**
```scala
items.filter(x => x > 10)              // Single param, no parens
items.filter(_ > 10)                   // Underscore shorthand
```

**Rust:**
```rust
items.filter(|x| x > 10)               // Single param (different delimiters)
```

N# follows the JavaScript/Scala convention of allowing paren omission for single parameters.

## Notes

- This is a quality-of-life improvement that makes N# feel more modern
- Single-parameter lambdas are by far the most common case in LINQ and functional code
- The syntax aligns with popular modern languages
- C# doesn't support this, but that's fine - our transpiler adds parens
- Very low risk change - purely additive to the parser
