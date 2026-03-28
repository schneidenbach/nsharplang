# Task P: Interactive Playground on Website

## Context

Every successful language has a playground (Go, Rust, TypeScript, Elm). An in-browser playground where people can try N# without installing anything is the single highest-impact marketing tool.

Since N# transpiles to C#, we can show the transpilation live — "type N# on the left, see C# on the right." This is unique and immediately demonstrates the value proposition.

## What to build

A page at `website/playground.html` with:

### Layout

```
┌─────────────────────────────────────────────────────┐
│  N# Playground                    [Examples ▾] [Share]│
├──────────────────────┬──────────────────────────────┤
│                      │                              │
│   N# Source          │   Generated C#               │
│   (editable)         │   (read-only)                │
│                      │                              │
│                      │                              │
│                      │                              │
├──────────────────────┴──────────────────────────────┤
│  Diagnostics / Errors                               │
│  ✓ No errors                                        │
└─────────────────────────────────────────────────────┘
```

### How it works

**Option A — Server-side (simpler, recommended for v1):**

Create a lightweight API endpoint that accepts N# source and returns:
- Transpiled C# output
- Any compiler diagnostics (errors, warnings)

This could be:
- A GitHub Actions-powered API (too slow)
- A small Azure Function / AWS Lambda
- **Best for v1**: A client-side WASM build of the N# compiler

**Option B — Client-side WASM (ideal, more work):**

Compile the N# compiler to WebAssembly using `dotnet publish -r browser-wasm` (Blazor WASM or NativeAOT-LLVM). The compiler runs entirely in the browser — no server needed.

**Option C — Fake it with examples (MVP):**

For an immediate MVP: pre-compile a set of examples and cache the C# output. The "editor" lets you pick examples but not type arbitrary code. Still valuable for demos.

**Recommendation**: Start with Option C (pre-compiled examples), upgrade to Option B (WASM) later.

### MVP Implementation (Option C):

```javascript
const examples = {
  "Hello World": {
    nsharp: `import System\n\nfunc main() {\n    print "Hello, N#!"\n}`,
    csharp: `using System;\n\nclass Program {\n    static void Main() {\n        Console.WriteLine("Hello, N#!");\n    }\n}`
  },
  "Unions & Matching": {
    nsharp: `union Shape {\n    Circle { Radius: double }\n    Rectangle { Width: double, Height: double }\n}\n\nfunc Area(s: Shape): double {\n    return match s {\n        Circle { Radius } => Math.PI * Radius * Radius,\n        Rectangle { Width, Height } => Width * Height\n    }\n}`,
    csharp: `// generated C# equivalent...`
  },
  // ... more examples
};
```

### Editor component

Use CodeMirror 6 (lightweight, modern) or Monaco Editor (VS Code's editor — heavier but more features):
- Left pane: editable N# with syntax highlighting
- Right pane: read-only C# output with syntax highlighting
- Bottom: error/diagnostic panel
- Responsive: stacks vertically on mobile

### Pre-compiled examples to include:

1. Hello World
2. Variables and type inference
3. Functions with default params
4. Classes and records
5. Discriminated unions
6. Pattern matching (all types)
7. Duck interfaces
8. Async/await
9. Error handling (result, err)
10. LINQ pipeline
11. Extension methods
12. Testing syntax

### Share button

Generate a URL with the code base64-encoded in the hash:
```
https://nsharplang.dev/playground#code=aW1wb3J0IFN5c3Rl...
```

This lets people share playground links without any server.

### Files

```
website/
├── playground.html
├── playground.js          # Editor setup, example switching, transpilation
├── playground.css          # Editor layout, responsive
├── examples.json          # Pre-compiled examples with N# + C# pairs
└── vendor/
    └── codemirror/        # CodeMirror 6 bundle (or Monaco)
```

### Generate the examples

Write a script that:
1. Takes each `.nl` example file
2. Runs the N# compiler to get the transpiled C# output
3. Writes both to `examples.json`

```bash
# scripts/build-playground-examples.sh
for file in website/playground-examples/*.nl; do
    nlc transpile "$file" > "${file%.nl}.cs"
done
# Then combine into examples.json
```

## Follow the standard verification protocol in tasks/STANDARD-SUFFIX.md

(For this task, "test" means: open playground.html in a browser, try every example, verify syntax highlighting works, verify the C# output is correct.)
