# Task 037: Comprehensive IntelliSense Support

**Priority:** High (Critical for developer experience)
**Dependencies:** Language Server (Task 036) - Partially complete
**Estimated Effort:** Large (10-15 hours)
**Status:** Not started

## Goal

Implement comprehensive IntelliSense that rivals C#'s quality, making N# feel like a first-class .NET language with top-notch tooling and ergonomics.

## Background

The current language server provides basic completions (keywords, local variables). To make N# truly productive, we need IntelliSense that's nearly as good as C#'s:
- Member completion for all types (local, imported, external)
- Method signature help with parameter info
- Hover documentation from XML docs
- Go to definition across files and assemblies
- Smart context-aware suggestions
- Import suggestions for unresolved types

## Current State

✅ **Working:**
- Keyword completion
- Local variable completion
- Basic member completion for known types
- File diagnostics (errors/warnings)

❌ **Missing:**
- External type member completion (e.g., `WebApplication.`)
- XML documentation in hover tooltips
- Signature help for methods
- Go to definition
- Import suggestions
- Workspace-wide symbol search

## Requirements

### 1. Member Completion (Critical)

**Current:**
```n#
builder := WebApplication.CreateBuilder(args)
builder. // ❌ No completions shown
```

**Target:**
```n#
builder := WebApplication.CreateBuilder(args)
builder. // ✅ Shows: Services, Configuration, Environment, Build(), etc.
```

**Implementation:**
- Load assembly metadata for imported namespaces
- Extract type members using reflection
- Filter by accessibility (public, internal if same assembly)
- Provide completion items with:
  - Member name
  - Member type (method, property, field)
  - Return type or property type
  - XML documentation summary
  - Appropriate completion kind (Method, Property, Field, etc.)

### 2. Signature Help (Critical)

**Current:**
```n#
builder.Services.AddDbContext<AppDbContext>( // ❌ No signature help
```

**Target:**
```n#
builder.Services.AddDbContext<AppDbContext>(
  // ✅ Shows: AddDbContext<TContext>(Action<DbContextOptionsBuilder<TContext>> optionsAction)
  //          Parameters: optionsAction - A builder for configuration
```

**Implementation:**
- Detect method call context
- Load method overloads from reflection
- Show signature with:
  - Method name with type parameters
  - Parameter list with types and names
  - XML documentation for each parameter
  - Current parameter highlighted
  - Overload count (1 of 3)

### 3. Hover Documentation (High Priority)

**Current:**
```n#
app.UseSwagger()  // ❌ Hover shows nothing
```

**Target:**
```n#
app.UseSwagger()  // ✅ Hover shows:
                   // Enables Swagger middleware
                   // Returns: IApplicationBuilder
                   // [From XML docs in Swashbuckle assembly]
```

**Implementation:**
- Load XML documentation files for referenced assemblies
- Match symbols to XML doc IDs
- Format documentation as Markdown
- Show in hover tooltips:
  - Summary
  - Parameters (for methods)
  - Return value
  - Remarks
  - Example code (if present)

### 4. Go To Definition (High Priority)

**Current:**
```n#
func ProcessEmployee(emp: Employee) {
  // F12 on Employee ❌ Does nothing
}
```

**Target:**
```n#
func ProcessEmployee(emp: Employee) {
  // F12 on Employee ✅ Jumps to definition:
  //   - Same file: Jump to class
  //   - Another file: Open and jump
  //   - External assembly: Show metadata (or decompiled source)
}
```

**Implementation:**
- Track definition locations during parsing
- Store symbol → location mapping
- Handle cross-file references
- For external types:
  - Show assembly metadata
  - Optionally integrate decompiler (ILSpy/ICSharpCode.Decompiler)

### 5. Import Suggestions (Medium Priority)

**Current:**
```n#
builder := WebApplication.CreateBuilder(args)
           ~~~~~~~~~~~~~~
           // ❌ Error: Undefined identifier 'WebApplication'
```

**Target:**
```n#
builder := WebApplication.CreateBuilder(args)
           ~~~~~~~~~~~~~~
           // 💡 Quick fix: Add "import Microsoft.AspNetCore.Builder"
```

**Implementation:**
- Maintain index of type → namespace mappings
- On undefined identifier error:
  - Search all loaded assemblies for matching types
  - Suggest imports as code actions
  - Auto-add import when accepted
- Prioritize:
  - Already imported namespaces
  - Common namespaces (System, System.Collections.Generic)
  - Recently used namespaces

### 6. Workspace Symbol Search (Medium Priority)

**Current:**
```
Ctrl+T (Go to Symbol) ❌ Not implemented
```

**Target:**
```
Ctrl+T → "Employee"
✅ Shows:
  - class Employee (Employees.nl)
  - func ProcessEmployee (Employees.nl)
  - record EmployeeEntity (Database.nl)
```

**Implementation:**
- Build workspace-wide symbol index
- Update on file changes
- Provide fuzzy search
- Show with file location and kind

## Implementation Plan

### Phase 1: Member Completion (Week 1)

**Files:**
- `src/LanguageServer/CompletionProvider.cs` - Enhance with reflection
- `src/LanguageServer/TypeResolver.cs` - NEW - Resolve types from assemblies

**Steps:**
1. Load assemblies for all imports in current file
2. When user types `.`, get left-hand expression type
3. Use reflection to get members of that type
4. Filter by accessibility
5. Return completion items with:
   - Label (member name)
   - Kind (Method/Property/Field/Event)
   - Detail (type signature)
   - Documentation (from XML docs if available)

**Tests:**
```csharp
[Fact]
public void MemberCompletion_ExternalType_ShowsPublicMembers()
{
    var source = "builder := WebApplication.CreateBuilder(args)\nbuilder.";
    var completions = GetCompletions(source, line: 1, col: 8);

    Assert.Contains(completions, c => c.Label == "Services");
    Assert.Contains(completions, c => c.Label == "Configuration");
    Assert.Contains(completions, c => c.Label == "Build");
}
```

### Phase 2: Signature Help (Week 1)

**Files:**
- `src/LanguageServer/SignatureHelpProvider.cs` - NEW
- Integrate with LSP `textDocument/signatureHelp`

**Steps:**
1. Detect `(` trigger character
2. Parse to find method being called
3. Resolve method type
4. Load all overloads via reflection
5. Format signatures with parameter info
6. Highlight current parameter based on comma count

**Tests:**
```csharp
[Fact]
public void SignatureHelp_MethodCall_ShowsOverloads()
{
    var source = "services.AddDbContext<AppDbContext>(";
    var help = GetSignatureHelp(source, line: 0, col: 40);

    Assert.NotEmpty(help.Signatures);
    Assert.Contains("optionsAction", help.Signatures[0].Parameters[0].Label);
}
```

### Phase 3: Hover Documentation (Week 2)

**Files:**
- `src/LanguageServer/HoverProvider.cs` - Enhance with XML docs
- `src/LanguageServer/XmlDocReader.cs` - NEW - Read XML documentation

**Steps:**
1. Load XML doc files for referenced assemblies
2. Build symbol ID → documentation map
3. On hover:
   - Resolve symbol at cursor
   - Look up XML doc
   - Format as Markdown
   - Return hover content

**XML Doc Location Strategy:**
```csharp
// For assembly: Microsoft.AspNetCore.dll
// Look for: Microsoft.AspNetCore.xml in:
// 1. Same directory as assembly
// 2. ref/ subdirectory
// 3. NuGet package cache
```

### Phase 4: Go To Definition (Week 2)

**Files:**
- `src/LanguageServer/DefinitionProvider.cs` - Enhance cross-file support
- Track all symbol definitions during analysis

**Steps:**
1. Build symbol table with locations during analysis
2. On definition request:
   - Look up symbol in current file scope
   - Check imported files
   - Check referenced assemblies
3. Return location or show metadata

### Phase 5: Import Suggestions (Week 3)

**Files:**
- `src/LanguageServer/CodeActionProvider.cs` - Add import suggestions
- `src/LanguageServer/TypeIndex.cs` - NEW - Index all types

**Steps:**
1. Build type → namespace index from all loaded assemblies
2. On diagnostic (undefined identifier):
   - Search index for matching types
   - Generate code actions to add imports
3. Apply edit when user accepts suggestion

### Phase 6: Symbol Search (Week 3)

**Files:**
- `src/LanguageServer/SymbolProvider.cs` - NEW - Workspace symbols

**Steps:**
1. Index all symbols in workspace on initialization
2. Update index on file changes
3. Implement fuzzy matching
4. Return ranked results

## Success Criteria

- [ ] Member completion works for external types (WebApplication, DbContext, etc.)
- [ ] Signature help shows parameter info with XML docs
- [ ] Hover displays XML documentation for all members
- [ ] Go to definition works across files and shows metadata for external types
- [ ] Import suggestions appear for undefined identifiers
- [ ] Workspace symbol search finds all symbols with fuzzy matching
- [ ] Performance: Completions appear <100ms, even with many assemblies
- [ ] All existing language server tests still pass
- [ ] 20+ new tests for IntelliSense features
- [ ] Developer experience comparable to C#

## Performance Considerations

**Assembly Loading:**
- Cache loaded assemblies and their members
- Lazy-load XML documentation
- Index types once on startup

**Completion Performance:**
- Filter members client-side when possible
- Return max 100 items initially
- Implement incremental filtering

**Memory:**
- Don't keep all XML docs in memory
- Weak references for cached reflection data
- Dispose assemblies not in use

## Testing Strategy

**Unit Tests:**
- Each provider has dedicated test suite
- Mock assemblies for testing
- Test with real .NET BCL types

**Integration Tests:**
- Full LSP protocol tests
- Test with real projects (EmployeeApi)
- Measure completion latency

**Manual Testing:**
- VS Code extension testing
- Real-world usage scenarios
- Performance profiling

## Documentation

**User Documentation:**
- Update VS Code extension README with features
- Add IntelliSense demo GIF
- Document keyboard shortcuts

**Developer Documentation:**
- Architecture doc for type resolution
- XML doc loading strategy
- Adding new completion providers

## Deliverables

1. **Member Completion** - Works for all imported types
2. **Signature Help** - Parameter info for all methods
3. **Hover Documentation** - XML docs shown for all symbols
4. **Go To Definition** - Cross-file and assembly navigation
5. **Import Suggestions** - Quick fixes for undefined types
6. **Symbol Search** - Workspace-wide fuzzy search
7. **Test Suite** - 20+ new IntelliSense tests
8. **Performance** - Sub-100ms completions
9. **Documentation** - Updated README with demos

## Timeline

- **Phase 1 (Member Completion):** 3 days
- **Phase 2 (Signature Help):** 2 days
- **Phase 3 (Hover Docs):** 3 days
- **Phase 4 (Go To Definition):** 2 days
- **Phase 5 (Import Suggestions):** 3 days
- **Phase 6 (Symbol Search):** 2 days
- **Testing & Polish:** 3 days

**Total:** ~18 days (3-4 weeks)

## Notes

This is a **critical task** for developer experience. Without good IntelliSense, N# will feel incomplete compared to C#. This investment will pay off massively in productivity and adoption.

The language server architecture is already in place (Task 036), so this builds on that foundation. Most work is integrating .NET's reflection and XML documentation systems.

## Future Enhancements (Not in scope)

- Code refactoring (rename, extract method)
- Code lens (references, implementations)
- Semantic highlighting
- Inlay hints (parameter names, type hints)
- Call hierarchy
- Type hierarchy

These can be separate tasks after core IntelliSense is solid.
