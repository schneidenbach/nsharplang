# Task 004: Async/Await Implicit Wrapping ✅ COMPLETED

**Priority:** Medium
**Dependencies:** project.yml parsing (for config)
**Estimated Effort:** Medium (3-4 hours)
**Completed:** v1.28

## Goal
Support implicit Task/ValueTask wrapping for async methods - user writes unwrapped return type, compiler adds wrapper based on configuration.

## Syntax

### Implicit Wrapping (Recommended)
```
func async FetchData(): string {
    return await LoadFromDb()
}
// Transpiles to: async ValueTask<string> FetchData() { ... }
```

### Explicit (For Nested Task Types)
```
func async GetTask(): Task<string> {
    return Task.FromResult("value")
}
// Transpiles to: async Task<Task<string>> GetTask() { ... }
```

### Configuration
In `project.yml`:
```yaml
language:
  asyncDefaultType: ValueTask  # or "Task"
```

## Implementation Steps

### 1. project.yml Parsing
- Add `LanguageConfig` class to `ProjectFile.cs`:
  ```csharp
  public class LanguageConfig {
      public string AsyncDefaultType { get; set; } = "ValueTask";
  }
  ```
- Parse `language` section from project.yml
- Validate: must be "Task" or "ValueTask"

### 2. Parser
- No changes needed - already parses async functions with return types

### 3. Analyzer
- Read language config from project settings
- When analyzing async function:
  - If return type is NOT Task/ValueTask → implicit wrapping mode
  - If return type IS Task/ValueTask → explicit mode (nested scenarios)
- Track whether wrapping needed in function metadata

### 4. Transpiler
- Check if function is async and needs wrapping
- If implicit mode:
  - Wrap return type in configured wrapper (Task or ValueTask)
  - `string` → `ValueTask<string>`
  - `void` → `ValueTask`
- If explicit mode:
  - Keep as-is (user wrote Task/ValueTask explicitly)

### 5. Tests
- Parser tests: Async functions with various return types
- Analyzer tests:
  - Implicit wrapping detection
  - Explicit Task type detection
- Transpiler tests:
  - `func async Foo(): string` → `async ValueTask<string> Foo()`
  - `func async Bar(): Task<string>` → `async Task<Task<string>> Bar()`
  - Config: Task mode → `async Task<string>`
- Integration test: Read config from project.yml

## Success Criteria
- [x] `func async Foo(): string` transpiles with ValueTask wrapper by default
- [x] project.yml config changes default wrapper type
- [x] Explicit Task/ValueTask types work for nested scenarios
- [x] Void async functions work: `func async DoWork() { }`
- [x] All tests pass

## Notes
- Default: ValueTask (better performance for hot paths)
- Allow Task for interface compatibility
- Follows Rust/Kotlin/Swift implicit wrapping pattern
- Cleaner syntax than C# explicit wrapping
