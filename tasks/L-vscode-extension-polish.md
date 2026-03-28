# Task L: VS Code Extension Polish

## Context

The VS Code extension exists and works (LSP handlers are solid after the PR merges), but first impressions matter. The extension needs polish to feel like a first-class language, not an experiment.

## What to do

### 1. Syntax highlighting grammar

Read `editors/vscode/syntaxes/` for the current TextMate grammar.

Audit and fix:
- All keywords from DESIGN.md are highlighted
- String interpolation `$"...{expr}..."` highlights the expressions differently from the string
- Raw strings `"""..."""` and interpolated raw strings `$"""..."""` are handled
- Comments (`//`, `/* */`, `/// <summary>`) are styled correctly
- Union case declarations get type coloring
- `duck interface` highlights both keywords
- `test "name" { }` blocks get special coloring
- `assert` keyword is highlighted
- Attributes `[...]` are highlighted
- `:=` operator is distinguishable from `=`

### 2. Snippet improvements

Check `editors/vscode/snippets/` for existing snippets.

Add/improve snippets for:
- `func` → function with params and return type (tab stops)
- `class` → class with constructor
- `record` → record with fields
- `union` → union with cases
- `match` → match expression with cases
- `test` → test block with assert
- `for` → for-in loop
- `if` → if block
- `import` → import statement
- `async` → async function
- `err` → error handling pattern (`result, err := ...`)

### 3. Extension metadata

Check `editors/vscode/package.json`:
- Icon: does the extension have a good icon? If not, create one (simple N# logo, SVG)
- Description: should be compelling, not generic
- Categories: `["Programming Languages"]`
- Keywords: `["nsharp", "n#", "dotnet", "clr", "go"]`
- Repository URL: correct?
- README: the extension's README.md should have:
  - Screenshot of N# code with syntax highlighting
  - Feature list (completions, hover, go-to-def, find refs, etc.)
  - Installation instructions
  - Keyboard shortcuts for key features

### 4. File icon

VS Code shows file icons in the explorer. Configure:
- `.nl` files get a distinctive icon
- `.tests.nl` files get a test variant
- `project.yml` gets a config icon

Check if the extension contributes file icons via `package.json` `contributes.iconThemes` or similar.

### 5. Bracket matching and auto-close

Verify these work correctly:
- `{` auto-inserts `}`
- `(` auto-inserts `)`
- `[` auto-inserts `]`
- `"` auto-inserts `"`
- `$"` starts an interpolated string context
- Comment toggling with Ctrl+/ works

Check `editors/vscode/language-configuration.json`.

### 6. Build after changes

After making changes:
```bash
./scripts/reload-vscode-extension.sh
```

Then open a real N# project in VS Code and verify VISUALLY:
- Syntax highlighting looks correct and professional
- Snippets work (type prefix, tab through)
- Completions appear (Ctrl+Space)
- Hover shows type info
- Go to definition works (F12)
- Find references works (Shift+F12)
- Error squigglies appear for invalid code
- Outline panel shows document symbols

## Follow the standard verification protocol in tasks/STANDARD-SUFFIX.md

(For this task, the "test" step includes visual verification in VS Code, not just unit tests.)
