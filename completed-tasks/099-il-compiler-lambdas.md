# Task 099: IL Compiler - Lambda Expressions

**Effort:** Large (25-30 hours)
**Depends:** None (IL compiler Phase 7)
**Ships:** Lambdas emit IL directly

## Goal

Emit IL for lambda expressions and closures.

## Deliverable

Lambda expressions compile to delegates with closure support.

## Implementation

### Simple Lambdas (No Closure)

```csharp
void EmitLambda(LambdaExpression lambda, Type delegateType)
{
    var method = typeBuilder.DefineMethod(
        $"<lambda>_{lambdaCounter++}",
        MethodAttributes.Private | MethodAttributes.Static,
        lambda.ReturnType,
        lambda.Parameters.Select(p => p.Type).ToArray());

    var il = method.GetILGenerator();

    // Emit body
    foreach (var stmt in lambda.Body)
    {
        EmitStatement(stmt, il);
    }

    il.Emit(OpCodes.Ret);

    // Create delegate
    il.Emit(OpCodes.Ldnull);
    il.Emit(OpCodes.Ldftn, method);
    il.Emit(OpCodes.Newobj, delegateType.GetConstructor(...));
}
```

### Closures (Capture Variables)

```csharp
// Generate closure class
var closureClass = moduleBuilder.DefineType(
    $"<>c__DisplayClass{closureCounter++}",
    TypeAttributes.NestedPrivate | TypeAttributes.Sealed);

// Add captured variable fields
foreach (var captured in lambda.CapturedVariables)
{
    closureClass.DefineField(
        captured.Name,
        captured.Type,
        FieldAttributes.Public);
}

// Generate lambda method on closure class
var lambdaMethod = closureClass.DefineMethod(
    "<Lambda>",
    MethodAttributes.Public,
    lambda.ReturnType,
    lambda.Parameters.Select(p => p.Type).ToArray());

// ... emit method body with field access for captured vars ...

// Instantiate closure and create delegate
il.Emit(OpCodes.Newobj, closureClass.GetConstructor(Type.EmptyTypes));
il.Emit(OpCodes.Dup);

// Set captured variables
foreach (var captured in lambda.CapturedVariables)
{
    il.Emit(OpCodes.Ldloc, captured.LocalIndex);
    il.Emit(OpCodes.Stfld, closureFields[captured.Name]);
}

il.Emit(OpCodes.Ldftn, lambdaMethod);
il.Emit(OpCodes.Newobj, delegateType.GetConstructor(...));
```

## Testing

```n#
// Simple lambda
add := (x: int, y: int) => x + y

// Closure
multiplier := 5
multiply := (x: int) => x * multiplier  // Captures 'multiplier'
```

## Done When

- [ ] Simple lambdas work
- [ ] Closures capture variables
- [ ] Nested lambdas work
- [ ] Performance acceptable
- [ ] Tests pass
