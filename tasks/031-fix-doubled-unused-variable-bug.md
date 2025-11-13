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
