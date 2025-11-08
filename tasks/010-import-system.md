# Task 010: Import System

**Priority:** CRITICAL (Required for multi-file projects)
**Dependencies:** None
**Estimated Effort:** Large (8-10 hours)

## Goal
Implement dual import system: file-based imports and namespace imports with aliasing support.

## Syntax

### File-Based Imports
```
import "Models/Person"           // relative to project root
import "./Helpers"                // relative to current file
import "../Shared/Utils"          // parent directory
import "Services/Auth" as AuthService  // with alias
```

### Namespace Imports
```
import System.Collections.Generic
import System.Linq
import Newtonsoft.Json as Json   // with alias
```

### Collision Handling
```
// ERROR: Person imported from two sources
import "Models/Person"
import Entities.Person

// FIXED: Use aliasing
import "Models/Person" as ModelPerson
import Entities.Person as EntityPerson
```

## Implementation Steps

### 1. Lexer
- Add `Import` keyword token
- Add `As` keyword token (if not already exists)

### 2. Parser
- Add `ParseImportStatement()` method
- Detect import type:
  - String literal → file-based
  - Qualified name → namespace
- Parse optional `as Alias`
- Create `ImportStatement` AST nodes:
  ```csharp
  public record FileImport(
      string Path,
      string? Alias,
      int Line,
      int Column
  ) : Statement(Line, Column);

  public record NamespaceImport(
      string Namespace,
      string? Alias,
      int Line,
      int Column
  ) : Statement(Line, Column);
  ```

### 3. File Resolution
- Implement path resolution in Compiler:
  - Relative paths: `./`, `../`
  - Project-root paths: `Models/Person`
  - Add `.nl` extension if not present
  - Validate file exists
- Create `FileResolver` class:
  ```csharp
  public class FileResolver {
      string ProjectRoot { get; }
      string CurrentFile { get; }

      string ResolveFilePath(string importPath);
      bool FileExists(string path);
  }
  ```

### 4. Symbol Import
- Parse imported file (if file-based)
- Extract all public symbols from:
  - File-based: top-level declarations in target file
  - Namespace: .NET types via reflection
- Add symbols to current file's scope
- Handle aliasing:
  - No alias: symbols directly available
  - With alias: symbols accessed via `Alias.Symbol`

### 5. Collision Detection
- Track imported symbols and their sources
- Detect when same symbol name imported twice
- Report error with both source locations
- Suggest aliasing as fix

### 6. Analyzer Integration
- Process imports before analyzing file
- Build symbol table from all imports
- Resolve identifier lookups:
  1. Local scope
  2. Imported symbols (direct)
  3. Aliased symbols (`Alias.Symbol`)
  4. .NET types from namespace imports

### 7. Transpiler
- File imports: Don't emit anything (symbols inlined)
- Namespace imports: Emit as C# `using` statements
  ```csharp
  using System.Collections.Generic;
  using Json = Newtonsoft.Json;
  ```

### 8. Circular Import Detection
- Track import graph during compilation
- Detect cycles: A imports B, B imports A
- Report error with import chain

### 9. Tests
- Parser tests:
  - File import syntax
  - Namespace import syntax
  - Import with alias
- File resolver tests:
  - Relative paths
  - Project-root paths
  - Missing file errors
- Analyzer tests:
  - Symbol resolution from imports
  - Collision detection
  - Aliased access
- Integration tests:
  - Multi-file project with imports
  - Circular import detection

## Success Criteria
- [x] `import "Models/Person"` resolves and imports symbols
- [x] `import System.Linq` works for .NET namespaces
- [x] `import X as Y` creates alias
- [x] Collision detection works and suggests fixes
- [x] Circular imports detected and reported
- [x] All tests pass

## Notes
- Similar to Python import semantics
- File imports enable code splitting
- Namespace imports maintain .NET interop
- Foundation for multi-file compilation
- Import order matters (dependencies first)
