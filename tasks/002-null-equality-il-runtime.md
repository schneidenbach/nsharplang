# Task 002: Null Equality In The IL Runtime Backend

Priority: P0.

Fix null equality for emitted N# types under .NET 10. The unit suite has a skipped IL compiler test because null equality comparison on user-defined class locals evaluates incorrectly at runtime after a .NET 10 `TypeBuilder` behavior change.

## User Outcome

This program should return `1` when compiled and run through the IL backend:

```nsharp
class Node {
    Value: int
}

func main(): int {
    text: string = null
    node: Node = null
    maybe: int? = null
    value := maybe ?? 42

    if text == null && node == null && value == 42 {
        return 1
    }

    return 0
}
```

## Scope

- Fix IL emission for null equality and inequality involving emitted class types.
- Preserve correct behavior for CLR reference types, nullable value types, and null coalescing.
- Cover both `value == null` and `null == value`.
- Unskip and pass `ILCompiler_CanExecuteNullLiteralsForReferenceAndNullableTypes`.

## Likely Files

- `src/NSharpLang.Compiler/ILCompiler/ILCompiler.cs`
- `tests/ILCompilerCoverageTests.cs`
- `tests/ILCompilerTests.cs`

## Acceptance

- The skipped null literal IL compiler test is enabled and passing.
- Focused tests cover both operand orders for emitted class null comparisons.
- Existing nullable value-type null checks and null-coalescing behavior remain correct.
- The fix does not depend on runtime-version-specific reflection-emitted type identity shortcuts.

## Verification

- Run focused IL compiler tests while developing.
- Run `dotnet test tests/Tests.csproj` and confirm the core unit suite reports no skipped tests unless another task file explicitly owns the remaining skip.
- Run `./scripts/test-all.sh` before committing.
