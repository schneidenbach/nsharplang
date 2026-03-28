# Task K: Website Overhaul — GitHub Pages

## Context

The current website (`website/`) is a placeholder with WRONG syntax examples (shows `package main` which isn't N# syntax), links to a wrong GitHub repo, and generic content. This is the first thing people see. It must be stunning.

The site deploys to GitHub Pages via `.github/workflows/deploy-website.yml` which watches `website/**` on main pushes.

## What to build

A modern, fast, static website. NO frameworks — just HTML, CSS, and minimal JS. It must load instantly.

### Pages

**1. Landing page (`index.html`)**

Hero section with:
- Tagline: "N# — Go for .NET" (or similar — make it punchy)
- One-liner: what N# is in 10 words
- Side-by-side code comparison: C# vs N# doing the same thing
- "Get Started" button → links to getting-started guide
- "Try it" button → links to playground (or examples for now)

Feature highlights (3-4 cards):
- **Discriminated Unions**: Show a union + match example
- **Duck Interfaces**: Show structural typing in 5 lines
- **Go-Style Syntax**: Show `:=`, no semicolons, convention visibility
- **Perfect C# Interop**: "C# consumers can't tell the difference"

Quick start section:
```bash
dotnet new install NSharpLang.Templates
dotnet new nsharp-console -o MyApp
cd MyApp && dotnet build && dotnet run
```

Code examples section — 4-6 real examples with syntax highlighting:
- Hello World
- Union + pattern matching
- Async HTTP request
- LINQ pipeline
- Duck interface
- Error handling with `result, err :=`

Footer with GitHub link, docs link, VS Code extension link.

**2. Examples page (`examples.html`)**

Curated gallery of N# code examples, organized by category:
- Basics (variables, functions, control flow)
- Types (classes, records, unions, enums)
- Patterns (match expressions, all pattern types)
- Async (await, async streams)
- Interop (calling C# libraries, ASP.NET)
- Testing (test syntax, assertions)

Each example: title, code block with syntax highlighting, "Copy" button.

**3. Docs page (`docs.html`)**

Links to the `docs/guide/` markdown files. Can either:
- Link directly to GitHub rendered markdown (simplest)
- Render markdown to HTML at build time (nicer but more work)

Start with GitHub links, upgrade later.

### Design requirements

- **Dark mode by default** with light mode toggle (developers prefer dark)
- **Syntax highlighting**: Use a lightweight highlighter (Prism.js or highlight.js) with a custom N# grammar. N# syntax is close enough to Go/TypeScript that you can adapt an existing grammar.
- **Responsive**: Must look great on mobile
- **Fast**: No build step, no bundler, no React. Just HTML/CSS/JS.
- **Professional**: Look at https://go.dev, https://www.rust-lang.org, https://ziglang.org for inspiration. This should feel like a real language site, not a side project.

### Technical

- All files in `website/` directory
- Must work with the existing GitHub Pages deployment workflow
- Fix the GitHub links to point to the correct repo: `https://github.com/schneidenbach/nsharplang`
- Add proper OpenGraph meta tags for social sharing
- Add a favicon (the existing `favicon.svg` can be kept or improved)

### Syntax highlighting for N#

Create a minimal Prism.js or highlight.js language definition for N#:
- Keywords: `func`, `class`, `struct`, `record`, `union`, `enum`, `interface`, `duck`, `match`, `if`, `else`, `for`, `while`, `return`, `import`, `let`, `const`, `async`, `await`, `test`, `assert`, `print`, `new`, `type`, `virtual`, `override`, `abstract`, `sealed`, `static`, `partial`, `required`, `init`, `readonly`, `ref`, `out`, `params`, `yield`, `throw`, `try`, `catch`, `finally`, `using`, `lock`, `is`, `as`, `in`, `not`, `and`, `or`, `where`, `file`
- Types: `int`, `string`, `bool`, `double`, `float`, `void`, `byte`, `short`, `long`, `char`, `decimal`, `object`, `dynamic`
- Strings: `"..."`, `$"..."`, `"""..."""`, `$"""..."""`
- Comments: `//`, `/* */`
- Operators: `:=`, `=>`, `?.`, `??`, `??=`

## Follow the standard verification protocol in tasks/STANDARD-SUFFIX.md

(For website changes, "test" means: open the HTML files locally in a browser and verify they render correctly. Also verify the deploy workflow YAML still points to the right directory.)
