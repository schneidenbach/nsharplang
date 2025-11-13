# Task 031: Fix 'doubled' Variable Showing as Unused Bug

## Problem
The linter incorrectly reports the `doubled` variable as unused even though it's used in a foreach loop.

### Code Example
```nsharp
let numbers: int[] = [1, 2, 3, 4, 5]
doubled := numbers.Select(x => x * 2).ToList()

foreach num in doubled {
    Console.WriteLine(num)
}
```

**Expected**: No unused variable warning for `doubled`
**Actual**: Warning "Variable 'doubled' is declared but never used"

## Root Cause Analysis
The linter code in `src/NSharpLang.Compiler/Linter.cs` lines 422-429 appears correct:
```csharp
case ForeachStatement foreachStmt:
    VisitExpression(foreachStmt.Collection); // Visit collection in outer scope FIRST
    PushScope();
    DeclareVariable(foreachStmt.VariableName, foreachStmt.Line, foreachStmt.Column);
    MarkVariableUsed(foreachStmt.VariableName); // Loop variables are considered used
    VisitStatement(foreachStmt.Body);
    PopScope();
    break;
```

**Hypothesis**: The issue is likely in how class-level scopes are handled. The variable `doubled` is declared in a method body, and when the linter processes the class, it may be checking unused variables at the wrong scope level.

**Alternative Hypothesis**: The VisitExpression for foreach.Collection may not be properly traversing IdentifierExpression nodes when they appear in certain contexts.

## Investigation Steps
1. Add debug logging to `VisitExpression` when handling `IdentifierExpression`
2. Add debug logging to `MarkVariableUsed` to see when variables are marked as used
3. Check the order of operations - are unused variable diagnostics generated before the foreach is visited?
4. Examine how Roslyn's DataFlowAnalysis handles this case

## Proposed Fix
Need to trace through the linter execution to identify where the breakdown occurs:
- Check if `VisitExpression(foreachStmt.Collection)` is being called
- Check if `MarkVariableUsed("doubled")` is being called
- Check the scope stack when the variable is checked for usage

## Reference Implementation
Look at Roslyn's implementation in:
- `Microsoft.CodeAnalysis.CSharp/FlowAnalysis/DataFlowPass.cs`
- How it handles foreach statement collection expressions

## Test Case
Add test to `tests/LinterUnusedVariableTests.cs`:
```csharp
[Fact]
public void Linter_ForeachWithLINQResult_DoesNotReportUnused()
{
    var source = @"
import System.Linq

func test() {
    let numbers: int[] = [1, 2, 3]
    doubled := numbers.Select(x => x * 2).ToList()

    foreach num in doubled {
        print(num)
    }
}";
    var diagnostics = Lint(source);

    var unusedDoubled = diagnostics.Where(d => d.Code == "NL001" && d.Message.Contains("'doubled'")).ToList();
    Assert.Empty(unusedDoubled);
}
```

## Files to Modify
- `src/NSharpLang.Compiler/Linter.cs` - Fix the scoping/visiting issue
- `tests/LinterUnusedVariableTests.cs` - Add test case

## Priority
HIGH - This is a false positive that will annoy users

## Resolution
**Status**: FIXED

The bug was in the `PushScope`/`PopScope` implementation in `Linter.cs`. The root cause was that `PushScope` was creating a COPY of the parent scope's variables, which meant when child scopes (like lambda expressions) popped, they would check parent variables for unused status, generating false positives.

### The Bug
When the linter visited this code:
```nsharp
doubled := numbers.Select(x => x * 2).ToList()

foreach num in doubled {
    Console.WriteLine(num)
}
```

The sequence was:
1. `doubled` was declared
2. The initializer expression contains a lambda `x => x * 2`
3. The lambda pushed a scope with a COPY of parent variables (including `doubled`)
4. The lambda popped its scope, checking `doubled` for usage → FALSE POSITIVE!
5. Then the foreach visited `doubled` and marked it as used (too late!)

### The Fix
Changed `PushScope` and `PopScope` to use a different approach:

**Before (BUGGY)**:
```csharp
private void PushScope()
{
    // Creates a COPY of current variables
    _scopeStack.Push(new Dictionary<string, (int Line, int Column, bool Used)>(_declaredVariables));
}

private void PopScope()
{
    CheckUnusedVariables(); // Checks ALL variables including copied parent ones!
    _declaredVariables.Clear();
    if (_scopeStack.Count > 0)
    {
        var parent = _scopeStack.Pop();
        foreach (var kvp in parent)
            _declaredVariables[kvp.Key] = kvp.Value;
    }
}
```

**After (FIXED)**:
```csharp
private void PushScope()
{
    // Save current scope reference to stack
    _scopeStack.Push(_declaredVariables);
    // Create new EMPTY scope for child
    _declaredVariables = new Dictionary<string, (int Line, int Column, bool Used)>();
}

private void PopScope()
{
    if (_scopeStack.Count > 0)
    {
        // Check only variables declared in THIS scope
        CheckUnusedVariables();
        // Restore parent scope
        _declaredVariables = _scopeStack.Pop();
    }
}
```

Now each scope only tracks variables DECLARED in that scope, not inherited from parents. Parent scope lookups still work through the stack in `MarkVariableUsed`.

### Changes Made
- `src/NSharpLang.Compiler/Linter.cs:175` - Removed `readonly` from `_declaredVariables`
- `src/NSharpLang.Compiler/Linter.cs:215-221` - Fixed `PushScope` to create empty child scopes
- `src/NSharpLang.Compiler/Linter.cs:223-231` - Fixed `PopScope` to restore parent scope reference

### Test Results
All Linter tests pass:
- NL001 tests: 9/9 passed
- NL002 tests: 8/8 passed
- NL003 tests: 6/6 passed
- NL004 tests: 4/4 passed
- Total: 27/27 Linter tests passing
