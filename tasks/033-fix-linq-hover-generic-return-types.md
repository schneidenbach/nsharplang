# Task 033: Fix LINQ Hover to Show Generic Collection Types

## Problem
Hovering over LINQ method calls like `.Select()` and `.ToList()` shows the element type `int` instead of the collection type `IEnumerable<int>` or `List<int>`.

### Code Example
```nsharp
let numbers: int[] = [1, 2, 3, 4, 5]
doubled := numbers.Select(x => x * 2).ToList()
```

**Expected Hover on `Select`**: Shows `IEnumerable<int> Select<int, int>(this IEnumerable<int>, Func<int, int>)`
**Actual Hover**: Shows `int Select(...)`

**Expected Hover on `ToList`**: Shows `List<int> ToList<int>(this IEnumerable<int>)`
**Actual Hover**: Shows `int ToList(...)`

## Root Cause
The `ExpressionTypeResolver` in `src/NSharpLang.Compiler/ExpressionTypeResolver.cs` is using `.NET` reflection to get method return types, but when it encounters generic methods, it's returning the unbound generic type or extracting the element type instead of the constructed generic type.

### Current Code (lines 120-130)
```csharp
private Type? ResolveCallType(CallExpression call)
{
    // If calling a member access like numbers.Select(...)
    if (call.Callee is MemberAccessExpression memberAccess)
    {
        var memberInfo = ResolveMemberInfo(memberAccess);
        if (memberInfo is MethodInfo method)
        {
            return method.ReturnType;  // <-- This returns the UNBOUND generic type!
        }
    }
    ...
}
```

### The Problem
When you call `GetMethods()` on a type and find a method like `Select`, you get back a **generic method definition**:
```csharp
IEnumerable<TResult> Select<TSource, TResult>(this IEnumerable<TSource> source, Func<TSource, TResult> selector)
```

The `method.ReturnType` for this is `IEnumerable<TResult>` where `TResult` is an **unbound type parameter**.

To get the actual return type, you need to:
1. Determine the type arguments (`int` for `TSource`, `int` for `TResult`)
2. Call `method.MakeGenericMethod(typeof(int), typeof(int))`
3. Then get `.ReturnType` which will be `IEnumerable<int>`

## Reference Implementation: Roslyn
Look at how Roslyn handles this in `Microsoft.CodeAnalysis.CSharp`:
- **OverloadResolution.cs**: How it infers generic type arguments
- **MethodTypeInference.cs**: Algorithm for inferring type arguments from usage
- **BoundCall.cs**: How it stores the constructed method after type inference

### Key Concepts
- **Type Inference**: From `numbers` (type `int[]` = `IEnumerable<int>`), infer `TSource = int`
- **Return Type Inference**: From lambda `x => x * 2` (returns `int`), infer `TResult = int`
- **Construction**: `MakeGenericMethod(typeof(int), typeof(int))` to get the constructed method

## Proposed Fix

### Step 1: Detect Generic Methods
```csharp
private Type? ResolveCallType(CallExpression call)
{
    if (call.Callee is MemberAccessExpression memberAccess)
    {
        var memberInfo = ResolveMemberInfo(memberAccess);
        if (memberInfo is MethodInfo method)
        {
            // Check if it's a generic method
            if (method.IsGenericMethodDefinition)
            {
                // Need to infer type arguments and construct the method
                var constructedMethod = TryConstructGenericMethod(method, memberAccess, call);
                return constructedMethod?.ReturnType ?? method.ReturnType;
            }

            return method.ReturnType;
        }
    }
    ...
}
```

### Step 2: Implement Type Argument Inference (Simplified)
```csharp
private MethodInfo? TryConstructGenericMethod(MethodInfo genericMethod, MemberAccessExpression memberAccess, CallExpression call)
{
    // Get the type of the object (e.g., int[] for numbers.Select)
    var objectType = ResolveExpressionType(memberAccess.Object);
    if (objectType == null) return null;

    var typeArgs = new List<Type>();
    var genericParams = genericMethod.GetGenericArguments();

    // For LINQ methods, try to infer from:
    // 1. The source collection type (IEnumerable<T>)
    // 2. The delegate parameter type or return type

    // Simple heuristic for common LINQ methods
    if (genericMethod.Name == "Select" || genericMethod.Name == "Where" ||
        genericMethod.Name == "ToList" || genericMethod.Name == "ToArray")
    {
        // Infer TSource from the collection
        if (TryGetEnumerableElementType(objectType, out var elementType))
        {
            typeArgs.Add(elementType);

            // For Select, infer TResult from lambda or keep same type
            if (genericMethod.Name == "Select" && genericParams.Length == 2)
            {
                // TODO: Analyze lambda to determine result type
                // For now, assume same type (Select<int, int>)
                typeArgs.Add(elementType);
            }
        }
    }

    if (typeArgs.Count == genericParams.Length)
    {
        try
        {
            return genericMethod.MakeGenericMethod(typeArgs.ToArray());
        }
        catch
        {
            return null;
        }
    }

    return null;
}

private bool TryGetEnumerableElementType(Type type, out Type elementType)
{
    // Check if it's an array
    if (type.IsArray)
    {
        elementType = type.GetElementType()!;
        return true;
    }

    // Check if it implements IEnumerable<T>
    var enumerableInterface = type.GetInterfaces()
        .FirstOrDefault(i => i.IsGenericType &&
                           i.GetGenericTypeDefinition() == typeof(IEnumerable<>));

    if (enumerableInterface != null)
    {
        elementType = enumerableInterface.GetGenericArguments()[0];
        return true;
    }

    elementType = null!;
    return false;
}
```

## Simplified Approach (Phase 1)
For a quicker fix that handles common cases:
1. **ToList/ToArray**: Always returns `List<T>` / `T[]` where `T` is the element type of the input
2. **Select**: Returns `IEnumerable<T>` where `T` is inferred from the collection
3. **Where**: Returns same type as input (`IEnumerable<T>`)

## Test Cases
Add to `tests/LanguageServerTests.cs`:
```csharp
[Fact]
public async Task Hover_LINQ_Select_ShowsIEnumerableType()
{
    var source = @"
import System.Linq

func test() {
    let numbers: int[] = [1, 2, 3]
    result := numbers.Select(x => x * 2)
}";

    harness.OpenDocument(uri, source);
    var hover = await harness.GetHoverAsync(uri, line, col); // On "Select"

    Assert.Contains("IEnumerable", hover.Contents.MarkupContent.Value);
    Assert.Contains("<int>", hover.Contents.MarkupContent.Value);
}

[Fact]
public async Task Hover_LINQ_ToList_ShowsListType()
{
    var source = @"
import System.Linq

func test() {
    let numbers: int[] = [1, 2, 3]
    result := numbers.ToList()
}";

    harness.OpenDocument(uri, source);
    var hover = await harness.GetHoverAsync(uri, line, col); // On "ToList"

    Assert.Contains("List", hover.Contents.MarkupContent.Value);
    Assert.Contains("<int>", hover.Contents.MarkupContent.Value);
}
```

## Files to Modify
- `src/NSharpLang.Compiler/ExpressionTypeResolver.cs` - Add generic method construction
- `tests/LanguageServerTests.cs` - Add test cases

## References
- Roslyn MethodTypeInference: https://github.com/dotnet/roslyn/blob/main/src/Compilers/CSharp/Portable/Binder/Semantics/OverloadResolution/MethodTypeInference.cs
- C# Spec §7.5.2: Type inference for generic methods

## Priority
HIGH - This significantly impacts IntelliSense usefulness for LINQ code
