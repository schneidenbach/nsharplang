# N# Syntax Highlighting Improvements (v0.3.0)

## What's New

This update significantly improves the TextMate grammar for N# with comprehensive syntax highlighting support.

### New Features

#### 1. **Missing Keywords Added**
- `package` - Package declarations
- `constructor` - Constructor definitions
- `print` - Print statements
- `test` - Test blocks
- `assert` - Assertions

#### 2. **Generic Type Parameters**
Now properly highlights generic types with full nesting support:
```nsharp
Result<T>
Dictionary<string, List<int>>
AddDbContext<AppDbContext>
```

#### 3. **Enhanced String Interpolation**
Better highlighting of interpolated strings with distinct colors for:
- The `$` prefix
- `{` and `}` delimiters
- Embedded expressions

```nsharp
$"Hello {name}, value = {x + 10}"
```

#### 4. **Declaration Highlighting**
Special highlighting for type and function declarations:
```nsharp
package EmployeeApi              // namespace highlighted
import System.Collections.Generic // import path highlighted

class Person { }                  // class name highlighted
func ProcessData(x: int) { }      // function name highlighted
type UserId = int                 // type alias highlighted
```

#### 5. **Property/Field Type Annotations**
Variables and properties with type annotations are now highlighted:
```nsharp
FirstName: string   // property name and type highlighted
age: int            // field name and type highlighted
```

#### 6. **Preprocessor Directives**
Support for C#-style preprocessor directives:
```nsharp
#region Type Declarations
#if DEBUG
#warning This is a warning
#endregion
```

#### 7. **Enhanced Number Literals**
- Hexadecimal: `0xFF`, `0xDEADBEEF`
- Binary: `0b1010`, `0b11111111`
- Float suffixes: `3.14f`, `2.5d`, `100m`
- Integer suffixes: `100L`, `50u`, `25ul`

#### 8. **Better Operator Highlighting**
Distinct colors for different operator types:
- Assignment: `:=`, `=`
- Comparison: `==`, `!=`, `<`, `>`, `<=`, `>=`
- Arithmetic: `+`, `-`, `*`, `/`, `%`
- Logical: `&&`, `||`, `!`
- Nullable: `??`, `?.`, `?[`, `!.`
- Lambda: `=>`
- Spread: `...`

## Installation

### Option 1: Install from VSIX

```bash
# Navigate to the VS Code extension directory
cd editors/vscode

# Install the extension
code --install-extension nsharp-0.3.0.vsix
```

### Option 2: Manual Installation

1. Open VS Code
2. Press `Cmd+Shift+P` (macOS) or `Ctrl+Shift+P` (Windows/Linux)
3. Type "Extensions: Install from VSIX"
4. Select `editors/vscode/nsharp-0.3.0.vsix`

## Testing the Syntax Highlighting

Open any `.nl` file in VS Code to see the improved syntax highlighting. A comprehensive test file is available at `/tmp/syntax-test.nl`.

### Example Highlighted Features

```nsharp
// All these features now have proper highlighting:

package MyApp                     // ✓ package keyword + namespace
import System.Collections.Generic // ✓ import + dotted path

#region Types                     // ✓ preprocessor directive

union Result<T> {                 // ✓ union keyword + generic type
    Success { value: T }          // ✓ nested generic parameter
    Failure { error: string }
}

class Person {
    FirstName: string             // ✓ property with type annotation
    age: int                      // ✓ field with type annotation

    // ✓ constructor keyword
    constructor(name: string) {
        FirstName = name
    }

    // ✓ expression-bodied member with string interpolation
    FullName: string => $"{FirstName}"
}

type UserId = int                 // ✓ type alias

#endregion

func Main() {
    x := 42                       // ✓ := operator
    hex := 0xFF                   // ✓ hexadecimal
    bin := 0b1010                 // ✓ binary

    message := $"Value: {x}"      // ✓ string interpolation
    print message                 // ✓ print keyword

    test "Addition works" {       // ✓ test keyword
        assert x > 0              // ✓ assert keyword
    }

    // ✓ Generic method call
    builder.Services.AddDbContext<AppDbContext>()
}
```

## Color Theme Support

The syntax highlighting uses standard TextMate scopes, which work with all VS Code color themes. Different themes will display the colors differently, but all features will be highlighted.

### Recommended Themes for N#
- **Dark+** (default) - Good contrast
- **Monokai** - Vibrant colors
- **Solarized Dark** - Easy on eyes
- **GitHub Dark** - Clean, modern look

## Technical Details

### TextMate Scopes Used

| Feature | Scope |
|---------|-------|
| Keywords | `keyword.control.nsharp`, `keyword.other.nsharp` |
| Special keywords | `keyword.other.special.nsharp` |
| Types | `entity.name.type.nsharp`, `support.type.primitive.nsharp` |
| Functions | `entity.name.function.nsharp` |
| Namespaces | `entity.name.namespace.nsharp` |
| Properties | `variable.other.property.nsharp` |
| Numbers | `constant.numeric.nsharp` |
| Strings | `string.quoted.double.nsharp` |
| Interpolation | `meta.interpolation.nsharp` |
| Comments | `comment.line.nsharp`, `comment.block.nsharp` |
| Operators | `keyword.operator.*.nsharp` |
| Preprocessor | `meta.preprocessor.nsharp` |

### Semantic Tokens

The language server also contributes semantic tokens where TextMate cannot safely infer meaning from syntax alone.

| Feature | Semantic token |
|---------|----------------|
| Error tuple catch result | `variable.catchResult` |

### Pattern Ordering

Patterns are applied in this order for optimal matching:
1. Preprocessor directives (must be first for line-start matching)
2. Comments
3. Strings (with interpolation)
4. Attributes
5. Declarations (class, func, type, etc.)
6. Keywords
7. Types (including generics)
8. Numbers
9. Operators
10. Functions
11. Identifiers

## Comparison with v0.2.0

| Feature | v0.2.0 | v0.3.0 |
|---------|--------|--------|
| Basic keywords | ✓ | ✓ |
| `package` keyword | ✗ | ✓ |
| `constructor` keyword | ✗ | ✓ |
| `print`/`test`/`assert` | ✗ | ✓ |
| Generic types | ✗ | ✓ |
| String interpolation | Basic | Enhanced |
| Declaration highlighting | ✗ | ✓ |
| Property type annotations | ✗ | ✓ |
| Preprocessor directives | ✗ | ✓ |
| Binary literals | ✗ | ✓ |
| Number suffixes | Partial | Full |
| Import path highlighting | ✗ | ✓ |

## Future Improvements

Potential enhancements for future versions:
- Semantic highlighting (requires LSP)
- Error highlighting (requires LSP)
- Parameter hints in function calls
- Bracket colorization rules

## Troubleshooting

### Colors look wrong
- Try a different color theme
- Restart VS Code after installing
- Check that the file extension is `.nl`

### Highlighting not working
```bash
# Verify extension is installed
code --list-extensions | grep nsharp

# Reinstall if needed
code --uninstall-extension nsharp.nsharp
code --install-extension nsharp-0.3.0.vsix
```

### Want to see the raw scopes
1. Press `Cmd+Shift+P` → "Developer: Inspect Editor Tokens and Scopes"
2. Hover over any token to see its scope

## Contributing

Found a highlighting bug? Here's how to fix it:

1. Edit `editors/vscode/syntaxes/nsharp.tmLanguage.json`
2. Test with `npm run compile`
3. Package with `npm run package`
4. Install and test

The grammar uses standard TextMate patterns. Reference:
- [TextMate Language Grammars](https://macromates.com/manual/en/language_grammars)
- [VS Code Syntax Highlight Guide](https://code.visualstudio.com/api/language-extensions/syntax-highlight-guide)

## Changelog

### v0.3.0 (2025-11-08)
- Added missing keywords: `package`, `constructor`, `print`, `test`, `assert`
- Implemented generic type parameter highlighting with full nesting
- Enhanced string interpolation with distinct punctuation highlighting
- Added declaration highlighting for classes, functions, imports, etc.
- Implemented property/field type annotation highlighting
- Added preprocessor directive support (#region, #if, etc.)
- Enhanced number literal support (binary, hex, suffixes)
- Improved operator categorization and highlighting
- Added import path highlighting
- Better pattern ordering for optimal matching

### v0.2.0
- Initial release with basic syntax highlighting
- Keywords, strings, comments, basic types
- Simple function and class highlighting
