# Task 010: Import System ✅ COMPLETE - Phase 1 & 2 Done!

**Priority:** CRITICAL (Required for multi-file projects)
**Dependencies:** None
**Estimated Effort:** Large (8-10 hours total, ~6 hours Phase 1 & 2 complete)
**Status:** Phase 1 & 2 complete in v1.22 - Syntax, Parsing, Symbol Resolution, Analysis, and Transpilation working!

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
- [x] **Phase 1 (v1.21):** Import syntax parsing ✅
  - [x] `import "path"` and `import Namespace` syntax works
  - [x] `import X as Y` creates alias (both file and namespace)
  - [x] Lexer recognizes import keyword
  - [x] Parser tests pass (6 new tests)
- [x] **Phase 2 (v1.22):** Symbol resolution and analysis ✅
  - [x] FileResolver class for path resolution
  - [x] `import "./Models"` resolves and imports symbols from .nl files
  - [x] `import System.Linq` works for .NET namespaces (transpiles to using)
  - [x] Collision detection works and reports errors
  - [x] Aliased imports work (Alias.Symbol access)
  - [x] Transpiler emits C# using statements for namespace imports
  - [x] 2 new transpiler tests, all 251 tests passing
- [ ] **Phase 3 (Future):** Full multi-file compilation
  - [ ] Compiler processes all .nl files in project directory
  - [ ] Circular import detection
  - [ ] Integration with project.yml
  - [ ] Complete end-to-end multi-file examples

## Progress

### Phase 1: Syntax and Parsing ✅ (v1.21)
**Completed:**
- Import keyword token added to Lexer
- FileImport and NamespaceImport AST nodes created
- ParseImport() method implemented in Parser
- CompilationUnit updated with Imports list
- 6 new tests (1 lexer + 5 parser), all passing
- Total: 249 tests passing

**What works:**
- Parsing file imports: `import "path/to/file"`
- Parsing namespace imports: `import System.Linq`
- Aliasing support: `import X as Y`
- Multiple imports in a file

**Next phase:**
See Phase 2 below.

### Phase 2: Symbol Resolution and Analysis ✅ (v1.22)
**Completed:**
1. ✅ Create FileResolver class for path resolution
   - Handles relative paths (./,  ../)
   - Handles project-root paths (Models/Person)
   - Adds .nl extension if not present
   - Validates file exists with helpful error messages
2. ✅ Implement symbol import logic in Analyzer
   - Parses imported files (for file imports)
   - Extracts public symbols from imported files (PascalCase only)
   - Adds symbols to global scope
   - Handles aliasing (Alias.Symbol member access)
   - Namespace imports work like using statements
3. ✅ Add collision detection
   - Tracks imported symbols and their sources
   - Detects duplicate symbol names from multiple imports
   - Reports error with source file paths
   - Suggests aliasing to resolve conflicts
4. ✅ Transpiler integration
   - Namespace imports transpile to C# using statements
   - File imports are inlined (symbols already in scope)
   - Aliased imports: `import X as Y` → `using Y = X;`
5. ✅ CLI integration
   - Updated CLI to pass file paths to Analyzer
   - Enables import resolution in actual compilation
6. ✅ Test coverage
   - 2 new transpiler tests (namespace imports with/without aliases)
   - All 251 tests passing

**Known Limitations (Phase 3 work):**
- Circular import detection not yet implemented
- Full multi-file compilation (transpiling all imported files) not yet implemented
- Currently: Analyzer validates imports work, but transpiler only emits current file

### Phase 3: Code Generation ⏭️ (Future)
**TODO:**
1. Update Transpiler to handle imports
   - Namespace imports → emit as C# using statements
   - File imports → don't emit (symbols inlined)
2. Write integration tests
   - Multi-file project compilation
   - Symbol resolution across files
   - Namespace imports working with .NET types
   - Error cases (circular imports, collisions, missing files)

## Notes
- Similar to Python import semantics
- File imports enable code splitting
- Namespace imports maintain .NET interop
- Foundation for multi-file compilation (Task 011)
- Import order matters (dependencies first)
