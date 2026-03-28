# Task Q: `nlc format` Audit — One Canonical Style

## Context

Like `gofmt` and `rustfmt`, N# promises zero-config formatting. "One canonical style, no arguments." But has anyone actually verified the formatter works well? Does it handle all syntax? Does the output look good?

## What to do

### 1. Run `nlc format` on every example project

```bash
for dir in examples/*/; do
    echo "=== $dir ==="
    find "$dir" -name "*.nl" -exec nlc format --check {} \;
done
```

Document:
- Which files are already formatted?
- Which files get reformatted? Is the diff an improvement?
- Does `nlc format` crash on any file?
- Does formatted output still compile?

### 2. Audit formatting decisions

Read `src/NSharpLang.Compiler/Formatter.cs` (or wherever the formatter lives).

For each construct, verify the formatted output matches the language style guide:

- **Indentation**: 4 spaces? Tabs? Is it consistent?
- **Braces**: Same line or next line? (`func main() {` vs `func main()\n{`)
- **Trailing commas**: Allowed? Required? Stripped?
- **Import sorting**: Are imports sorted alphabetically?
- **Blank lines**: Between functions? Between classes? How many?
- **Line length**: Is there a max? Does the formatter wrap long lines?
- **Match expressions**: How are cases formatted?
- **Chained method calls**: One per line? Aligned?
- **Lambda formatting**: Short lambdas inline, long ones on new lines?

### 3. Compare against Go and Rust

The gold standard:
- `gofmt`: tabs, braces on same line, no config
- `rustfmt`: 4 spaces, reasonable defaults, minimal config

N# should feel like `gofmt` — run it and forget about it.

### 4. Fix formatting issues

If the formatter:
- Produces ugly output for any construct → fix the formatting rules
- Crashes on valid syntax → fix the crash
- Doesn't handle a construct → add support
- Makes inconsistent choices → standardize

### 5. Enforce formatting in CI (optional)

Add to `.github/workflows/build.yml`:
```yaml
- name: Check formatting
  run: nlc format --check src/ examples/
```

This ensures all code in the repo is always formatted.

### Test cases:

Create a `tests/FormatterTests.cs` (or add to existing) with:
- Round-trip: format → format again → output is identical (idempotent)
- Every syntax construct formatted correctly
- Comments preserved in correct position
- String literals not mangled
- Interpolated strings not broken
- Long lines wrapped sensibly

## Follow the standard verification protocol in tasks/STANDARD-SUFFIX.md
