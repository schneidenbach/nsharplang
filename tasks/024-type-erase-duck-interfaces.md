# Task 024: Type-Erase Duck Interfaces

**Status:** 🔲 TODO
**Priority:** Medium
**Dependencies:** None
**Estimated Effort:** Small (2-3 hours)

## Goal

Duck interfaces should be completely type-erased during transpilation - they're purely for N# compile-time type checking and shouldn't appear in generated C# code.

## Current Behavior

Duck interfaces currently transpile as:
```csharp
internal interface IReader {
    string Read();
}

// Classes that match structurally auto-implement:
public class FileReader : IReader {  // <- auto-added
    public string Read() => "contents";
}
```

## Desired Behavior

Duck interfaces should be completely skipped:
```csharp
// Duck interface declaration: SKIP IT

// Classes just emit their own code:
public class FileReader {  // <- no interface
    public string Read() => "contents";
}
```

## Implementation

### 1. Transpiler Changes

**File:** `src/Compiler/Transpiler.cs`

```csharp
private void TranspileInterfaceDeclaration(InterfaceDeclaration iface)
{
    // Duck interfaces are type-erased - skip entirely
    if (iface.IsDuckInterface)
        return;

    // ... rest of normal interface transpilation
}
```

**Remove:**
- `_duckInterfaces` field
- Duck interface collection in `Transpile()`
- Auto-implementation logic in `TranspileClassDeclaration`
- Auto-implementation logic in `TranspileStructDeclaration`
- Auto-implementation logic in `TranspileRecordDeclaration`
- `ClassImplementsDuckInterface()` helper method
- `MethodSignaturesMatch()` helper method (if only used for duck interfaces)
- `TypeReferencesMatch()` helper method (if only used for duck interfaces)

### 2. Analyzer (NO CHANGES)

Keep structural type checking in Analyzer:
- `ImplementsDuckInterface()` method still validates at compile-time
- `IsAssignable()` still checks duck interface compatibility
- Errors reported if type doesn't structurally match

**The Analyzer is WHERE duck typing happens** - Transpiler just ignores them.

### 3. Tests to Update

Check these test files:
- `tests/TranspilerTests.cs` - Duck interface transpilation tests
  - Update expectations: duck interfaces should NOT appear in output
  - Classes should NOT auto-implement duck interfaces

Look for tests like:
```csharp
TestDuckInterfaceTranspilation()
TestDuckInterfaceAutoImplementation()
```

Update them to verify:
- Duck interface declarations are omitted
- Classes don't have duck interfaces in base list

### 4. Documentation Updates

**Files to update:**
- `memory/components/transpiler.md` - Update duck interface section
- `memory/features/type-system.md` - Clarify duck interfaces are type-erased
- `DESIGN.md` - Update duck interface documentation

**New wording:**
> Duck interfaces are type-erased during transpilation. They exist only for N# compile-time structural type checking and do not appear in generated C# code. The Analyzer validates that types structurally match duck interfaces, but the Transpiler completely omits them.

### 5. Example Files

Check if any examples rely on duck interfaces being in C# output:
- `examples/duck_interfaces.nl`

Update comments if needed to clarify that duck interfaces don't appear in C#.

## Testing

After implementation:

```bash
# Build compiler
dotnet build src/Compiler/Compiler.csproj

# Run all tests
dotnet test

# Transpile duck interface example and check C# output
dotnet run --project src/Cli/Cli.csproj -- transpile examples/duck_interfaces.nl

# Verify:
# 1. No "internal interface IReader" in output
# 2. Classes don't have ": IReader" in their declarations
# 3. Classes still compile (structural typing was compile-time only)
```

## Success Criteria

- [ ] Duck interface declarations completely omitted from C# output
- [ ] Classes/structs/records don't auto-implement duck interfaces
- [ ] Analyzer still validates structural compatibility (compile-time)
- [ ] All tests pass
- [ ] Documentation updated
- [ ] Example transpiles correctly

## Rationale

Duck interfaces are an **N# language feature** for better ergonomics and type safety. C# doesn't need to know about them - they're purely for helping N# developers write type-safe code without explicit interface declarations.

By type-erasing them:
- Cleaner C# output
- No internal implementation details leaked
- Simpler mental model
- Still get all the benefits at N# compile-time
