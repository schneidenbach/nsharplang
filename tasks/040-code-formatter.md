# Task 040: Code Formatter

**Priority:** 🔴 P0-Critical (Essential for team collaboration)
**Dependencies:** Task 039 (.NET CLI Integration)
**Estimated Effort:** Medium (15-20 hours)
**Status:** Not started

## Goal

Implement a code formatter for N# that integrates with `dotnet format` and IDE format-on-save, enabling consistent code style across teams.

## Why Critical

> **No formatter = style debates in every PR**

Without automatic formatting:
- Teams waste time debating indentation, spacing, brace style
- PRs get cluttered with style changes
- Code reviews focus on formatting instead of logic
- Inconsistent style reduces code readability
- Blocks enterprise adoption (teams require consistent style)

**Real-world impact:** C# became professional when formatting tools matured. N# needs the same.

## Requirements

### Core Functionality

- [ ] **Parse N# AST** - Understand N# syntax completely
- [ ] **Format preservation** - Don't change semantics
- [ ] **Fast formatting** - < 100ms for typical files
- [ ] **Idempotent** - Formatting twice = no changes

### CLI Integration

- [ ] `dotnet format` recognizes `.nl` files
- [ ] `dotnet format MyFile.nl` - Format specific file
- [ ] `dotnet format MyProject/` - Format directory
- [ ] `dotnet format --verify-no-changes` - CI mode (exit code 1 if unformatted)
- [ ] `dotnet format --include *.nl` - Filter by pattern

### Configuration (`.editorconfig`)

```ini
[*.nl]
# Indentation
indent_style = space
indent_size = 4
tab_width = 4

# Line width
max_line_length = 120

# Braces
csharp_new_line_before_open_brace = none  # Go-style same-line braces
csharp_new_line_before_else = false
csharp_new_line_before_catch = false
csharp_new_line_before_finally = false

# Spacing
csharp_space_after_keywords_in_control_flow_statements = true
csharp_space_between_method_call_parameter_list_parentheses = false
csharp_space_between_method_declaration_parameter_list_parentheses = false
csharp_space_after_colon_in_inheritance_clause = true
csharp_space_before_colon_in_inheritance_clause = true

# Imports
dotnet_sort_system_directives_first = true
dotnet_separate_import_directive_groups = false

# N#-specific (custom)
nsharp_align_colons_in_object_literals = true
nsharp_space_after_walrus_operator = true  # x := 5
```

### IDE Integration

- [ ] **VS Code** - Format on save
- [ ] **Rider** - Reformat code action
- [ ] **Visual Studio** - Ctrl+K, Ctrl+D

### Format on Save

**VS Code** (`.vscode/settings.json`):
```json
{
  "editor.formatOnSave": true,
  "[nsharp]": {
    "editor.defaultFormatter": "nsharp.nsharp",
    "editor.formatOnSave": true
  }
}
```

**Rider**:
- Settings → Editor → Code Style → N# → Enable formatter
- Settings → Tools → Actions on Save → Reformat code

## Implementation Options

### Option 1: Roslyn-Style Formatter (Recommended)

**Approach:**
- Use N# parser to build AST
- Walk AST and emit formatted code
- Use trivia (whitespace/comments) for preservation
- Leverage existing `Transpiler` as reference

**Pros:**
- ✅ Full control over formatting
- ✅ Consistent with N# parser
- ✅ Can handle N#-specific syntax (walrus operator, etc.)

**Cons:**
- ❌ More work (15-20 hours)
- ❌ Need to maintain separately

**Implementation Path:**
```
src/Formatter/
├── Formatter.cs         // Main entry point
├── FormattingVisitor.cs // AST visitor for formatting
├── FormattingRules.cs   // Configurable rules
└── EditorConfigReader.cs // Parse .editorconfig
```

### Option 2: Transpile → CSharpier → Back

**Approach:**
- Transpile N# → C#
- Run CSharpier on C#
- Parse formatted C# back to N# (lossy)

**Pros:**
- ✅ Quick implementation (5-8 hours)
- ✅ Leverages existing tools

**Cons:**
- ❌ Lossy (N#-specific syntax lost)
- ❌ Requires round-trip parsing
- ❌ Can't handle N# idioms properly

**Verdict:** Not recommended.

### Option 3: Custom Formatter from Scratch

**Approach:**
- Write formatter without AST parsing
- Use regex/text manipulation

**Pros:**
- ✅ Potentially faster

**Cons:**
- ❌ Fragile (breaks on edge cases)
- ❌ Hard to maintain
- ❌ Can corrupt code

**Verdict:** Don't do this.

## Recommended: Option 1 (Roslyn-Style)

## Detailed Design

### 1. Parse N# File

```csharp
var source = File.ReadAllText("Program.nl");
var lexer = new Lexer(source);
var parser = new Parser(lexer);
var ast = parser.ParseCompilationUnit();
```

### 2. Format AST

```csharp
var config = EditorConfigReader.Read(".editorconfig");
var formatter = new Formatter(config);
var formatted = formatter.Format(ast);
```

### 3. Emit Formatted Code

```csharp
File.WriteAllText("Program.nl", formatted);
```

### Formatting Rules

#### Indentation
```n#
// Before
func main() {
x := 5
if x > 3 {
print x
}
}

// After
func main() {
    x := 5
    if x > 3 {
        print x
    }
}
```

#### Spacing
```n#
// Before
func add(a:int,b:int):int{
return a+b
}

// After
func add(a: int, b: int): int {
    return a + b
}
```

#### Object Literals (N#-specific)
```n#
// Before (inconsistent colons)
person := new { name:"Alice", age:30 }

// After (aligned colons)
person := new {
    name: "Alice",
    age:  30
}
```

#### Imports
```n#
// Before (random order)
import System.Threading.Tasks
import System
import System.Collections.Generic

// After (sorted)
import System
import System.Collections.Generic
import System.Threading.Tasks
```

### Comment Preservation

**Critical:** Don't lose comments!

```n#
// Before
func add(a: int, b: int): int {
    // Add two numbers
    return a + b  // Return result
}

// After (MUST preserve)
func add(a: int, b: int): int {
    // Add two numbers
    return a + b  // Return result
}
```

**Implementation:** Store comments as trivia attached to AST nodes.

## Testing Strategy

### Unit Tests

```csharp
[Theory]
[InlineData("func main(){print 5}", "func main() {\n    print 5\n}")]
[InlineData("x:=5", "x := 5")]
[InlineData("if x>3{}", "if x > 3 {\n}")]
public void Format_ProducesExpectedOutput(string input, string expected)
{
    var result = Formatter.Format(input);
    Assert.Equal(expected, result);
}
```

### Integration Tests

1. Format entire N# codebase
2. Verify compilation still works
3. Verify tests still pass
4. Verify output matches expected

### Golden Tests

```bash
# Format examples and compare
dotnet format examples/
git diff  # Should show expected changes
```

## CI Integration

### GitHub Actions

```yaml
name: Format Check

on: [push, pull_request]

jobs:
  format:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-dotnet@v3
      - name: Check formatting
        run: dotnet format --verify-no-changes
```

### Pre-commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Format staged .nl files
git diff --cached --name-only --diff-filter=ACMR | grep "\.nl$" | xargs dotnet format

# Re-add formatted files
git add -u
```

## Success Criteria

### Must Have
- [ ] `dotnet format` works for `.nl` files
- [ ] Format on save works in VS Code
- [ ] `.editorconfig` rules respected
- [ ] Comments preserved
- [ ] Semantics unchanged
- [ ] CI check mode works

### Nice to Have
- [ ] Configuration UI in VS Code
- [ ] Format selection (partial file)
- [ ] Format on paste
- [ ] Format on type (e.g., after `}`)

## User Experience

### Before Formatter

```
Developer: "Should I use spaces or tabs?"
Team Lead: "Spaces, 4 width."
Developer: "What about brace style?"
Team Lead: "Same line like Go."
Developer: "Line width?"
Team Lead: "120 characters."
// ... 30 minutes later ...
Code Review: "You missed indentation on line 47."
```

### After Formatter

```
Developer: *Writes code however*
Developer: *Saves file* (auto-formatted)
Code Review: "Logic looks good! ✅"
```

**Result:** 30 minutes saved per dev per week = 26 hours/year per dev

## Timeline

| Phase | Effort | Description |
|-------|--------|-------------|
| **Phase 1** | 4 hours | Basic formatter (indentation + spacing) |
| **Phase 2** | 3 hours | .editorconfig support |
| **Phase 3** | 3 hours | Comment preservation |
| **Phase 4** | 2 hours | CLI integration (`dotnet format`) |
| **Phase 5** | 2 hours | VS Code format-on-save |
| **Phase 6** | 2 hours | Testing + CI integration |
| **Total** | **16 hours** | |

## Dependencies

- **Task 039** (.NET CLI Integration) - Provides `dotnet` command infrastructure
- N# Parser - Already exists
- .editorconfig library - Use existing .NET library

## Deliverables

1. `src/Formatter/` - Formatter implementation
2. `dotnet format` command for `.nl` files
3. VS Code extension integration
4. Documentation (formatting guide)
5. CI templates with format check
6. Default `.editorconfig` for N# projects

## Future Enhancements (Post-1.0)

- [ ] Format on paste
- [ ] Partial file formatting (selection)
- [ ] Multi-line alignment for complex expressions
- [ ] Import organization rules
- [ ] Custom formatting profiles
- [ ] Diff-aware formatting (only format changed lines)

---

## Next Steps

1. **Start with Phase 1** - Basic formatter (indentation + spacing)
2. **Test on examples/** - Verify formatting works
3. **Integrate with dotnet format** - Make it accessible
4. **Add VS Code integration** - Format on save
5. **Ship it!** 🚀

**Estimated completion:** 2 weeks at 8 hours/week or 1 week full-time
