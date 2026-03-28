# Task F: Type Aliases → Real `using` Directives

## Context

Currently `type UserId = int` parses correctly but the Transpiler emits it as a comment: `// type UserId = int`. This means type aliases have zero compile-time or runtime effect. The feature is syntactically present but functionally broken.

## What to do

Fix the transpiler to emit C# file-scoped `using` aliases instead of comments.

### Mapping:
```
type UserId = int                        →  using UserId = int;
type Handler = Func<string, void>        →  using Handler = System.Action<string>;
type StringDict = Dictionary<string, string>  →  using StringDict = System.Collections.Generic.Dictionary<string, string>;
```

### Where to read first:
- `src/NSharpLang.Compiler/Ast/Declarations.cs` — `TypeAliasDeclaration` node structure
- `src/NSharpLang.Compiler/Parser.cs` — how type aliases are parsed (~line 900)
- `src/NSharpLang.Compiler/Transpiler.cs` — current comment emission (~line 771-775)
- `src/NSharpLang.Compiler/Transpiler.cs` — how `using` directives are emitted for imports (for placement reference)

### Key considerations:

1. **Placement**: `using` aliases must appear at the top of the generated C# file, after namespace imports but before namespace/class declarations. You'll likely need to:
   - Collect all type alias declarations during the first pass
   - Emit them in a header block before other declarations

2. **Func<void> mapping**: `type Callback = Func<void>` must emit as `using Callback = System.Action;` since N# maps `Func<void>` to `Action`.

3. **Fully qualified names**: The `using` directive needs fully qualified type names. `Dictionary<string, string>` must become `System.Collections.Generic.Dictionary<string, string>`.

4. **Generic aliases**: C# `using` supports generic aliases as of C# 12:
   ```csharp
   using StringDict = System.Collections.Generic.Dictionary<string, string>;
   ```
   But `type Result<T> = (T, Exception?)` (generic alias with type parameter) does NOT have a C# equivalent before C# 12's `using` aliases with generics. Handle gracefully — emit if C# 12+, otherwise emit comment + warning diagnostic.

5. **Usage verification**: Code that uses the alias must still compile. After emitting `using UserId = int;`, any function parameter `id: UserId` should transpile correctly.

### Test cases:
- Simple alias: `type UserId = int` → verify C# output has `using UserId = int;`
- Complex alias: `type StringDict = Dictionary<string, string>` → verify fully qualified
- Func<void> alias: `type Callback = Func<void>` → verify maps to Action
- Usage: function with `param: UserId` compiles and runs
- Multiple aliases in one file
- Alias used across files in a multi-file project

## Follow the standard verification protocol in tasks/STANDARD-SUFFIX.md
