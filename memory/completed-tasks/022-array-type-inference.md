# Task 022: Implicit Array Type Inference for var Declarations

**Version:** v1.69
**Status:** ✅ COMPLETE
**Dependencies:** None
**Estimated Effort:** Small (completed in 1 session)

## Goal
Fix the issue where array literals with `var` declarations don't compile in C# because collection expressions need a target type.

## Problem
C# 12 collection expressions `[1, 2, 3]` are target-typed, which means:
- `int[] arr = [1, 2, 3]` ✅ Works (explicit type)
- `List<int> list = [1, 2, 3]` ✅ Works (target-typed to List)
- `var arr = [1, 2, 3]` ❌ ERROR: No target type

N# was transpiling ALL array literals to collection expressions, which broke var declarations.

## Solution Implemented

### 1. Added Context Tracking
- Added `_needsExplicitArrayType` flag to Transpiler
- Flag set to `true` when transpiling initializer for var declarations
- Flag set to `false` when transpiling initializer for explicit type declarations

### 2. Smart Array Literal Transpilation
When transpiling array literals:
- If `_needsExplicitArrayType == true`: Emit `new T[] { elements }`
- If `_needsExplicitArrayType == false`: Emit `[elements]` (collection expression)

### 3. Element Type Inference
Added `InferArrayElementType()` method to infer type from first element:
- `IntLiteralExpression` → `int` or `long` (if has L suffix)
- `FloatLiteralExpression` → `float` or `double` (based on suffix)
- `StringLiteralExpression` → `string`
- `BoolLiteralExpression` → `bool`
- `NullLiteralExpression` → `object`
- `NewExpression` → Extract type from expression
- `ArrayLiteralExpression` → Recursive (for nested arrays)
- Default → `var` (fallback)

### 4. Code Changes
**Files Modified:**
- `src/Compiler/Transpiler.cs` - Added flag, updated TranspileArrayLiteral, added InferArrayElementType
- `tests/TranspilerTests.cs` - Updated 1 test, added 9 new tests

**Lines of Code:** ~60 lines added

## Examples

### Before (Broken)
```nsharp
x := [1, 2, 3]
```
Transpiled to:
```csharp
var x = [1, 2, 3];  // ERROR: No target type
```

### After (Fixed)
```nsharp
x := [1, 2, 3]
```
Transpiled to:
```csharp
var x = new int[] { 1, 2, 3 };  // Works!
```

### Collection Expressions Still Work
```nsharp
let numbers: int[] = [1, 2, 3]
let list: List<int> = [1, 2, 3]
```
Transpiled to:
```csharp
int[] numbers = [1, 2, 3];        // Collection expression
List<int> list = [1, 2, 3];       // Collection expression (target-typed!)
```

## Test Coverage

### Tests Added (9 total)
1. `TestArrayLiteralWithVarUsesExplicitType` - var declarations use explicit syntax
2. `TestArrayLiteralWithExplicitTypeUsesCollectionExpression` - explicit types use collection expressions
3. `TestStringArrayInference` - infers string[]
4. `TestBoolArrayInference` - infers bool[]
5. `TestDoubleArrayInference` - infers double[]
6. `TestNestedArrayInference` - infers int[][] correctly
7. `TestEmptyArrayInference` - empty arrays default to object[]
8. `TestListCollectionExpressionStillWorks` - List<T> still uses collection expressions
9. `TestMixedVarAndExplicitTypes` - comprehensive test of both scenarios

### Tests Updated
1. `TestSpreadOperatorTranspilation` - Updated to expect explicit array syntax for var

### Test Results
- Before: 497 passing
- After: 506 passing (9 new tests)
- **100% pass rate** ✅

## Benefits

### 1. Ergonomics
N# now MORE ergonomic than C# for array creation:
```nsharp
// N# - just works
x := [1, 2, 3]

// C# - requires explicit type
var x = new int[] { 1, 2, 3 };
// OR explicit type annotation
int[] x = [1, 2, 3];
```

### 2. Best of Both Worlds
- **var declarations**: Use explicit syntax for compatibility
- **Explicit types**: Use collection expressions for modern C# features
- **Target-typed collections**: Automatically create List, HashSet, etc.

### 3. Type Safety
Type inference from first element ensures type safety:
- `[1, 2, 3]` → `int[]`
- `["a", "b"]` → `string[]`
- `[[1, 2], [3, 4]]` → `int[][]`

## Technical Details

### Context Propagation
The flag is saved/restored to handle nested contexts:
```csharp
var previousFlag = _needsExplicitArrayType;
_needsExplicitArrayType = (varDecl.Type == null);
var initializer = TranspileExpression(varDecl.Initializer);
_needsExplicitArrayType = previousFlag; // restore
```

### Recursive Handling
Nested arrays automatically handled:
```nsharp
matrix := [[1, 2], [3, 4]]
```
Transpiles to:
```csharp
var matrix = new int[][] { 
    new int[] { 1, 2 }, 
    new int[] { 3, 4 } 
};
```

## Success Criteria
- [x] `var x = [1, 2, 3]` compiles and runs
- [x] Explicit types still use collection expressions
- [x] List/HashSet/etc. still work with collection expressions
- [x] Nested arrays work correctly
- [x] Empty arrays have fallback type
- [x] All existing tests pass
- [x] Comprehensive test coverage added
- [x] Documentation updated

## Impact
**HIGH** - This makes N# significantly more ergonomic for everyday array usage. Developers can now use the natural `x := [1, 2, 3]` syntax without worrying about C# limitations.

## Notes
- This is a transpiler-only change - no changes to Lexer, Parser, or Analyzer
- The solution is elegant: context-aware transpilation based on variable declaration type
- Empty arrays default to `object[]` which may need refinement in the future
- Long literals (42L) and float literals (3.14f) are not yet supported by the Lexer, so inference for those types is present but not testable yet
