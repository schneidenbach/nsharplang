# Task J: User-Facing Documentation

## Context

The `docs/` directory has internal design docs and specs, but no proper documentation for someone **learning** N#. A language lives or dies by its docs.

## What to create

### 1. `docs/guide/getting-started.md`

**Audience**: .NET developer who just heard about N# and wants to try it.

Cover:
- Prerequisites (dotnet SDK 9.0+)
- Install the N# CLI and templates
- Create a project with `dotnet new nsharp-console`
- Write hello world
- Build and run
- Open in VS Code with the N# extension
- Project structure explained (`project.yml`, `.nl` files, no `.csproj` editing)

Keep it under 5 minutes to complete. No theory — just DO things.

### 2. `docs/guide/language-tour.md`

**Audience**: Developer who finished getting-started and wants to learn the language.

Cover every major feature with runnable examples:
- Variables (`:=`, `let`, `const`)
- Functions (`func`, return types, default params, named args)
- Types (class, struct, record, record struct)
- Unions (discriminated unions with cases)
- Pattern matching (match expression, all pattern types)
- Interfaces (regular + duck interfaces)
- Enums (int and string enums)
- Error handling (try/catch + `result, err := ...`)
- Async/await
- Collections and LINQ
- Generics
- Testing (`.tests.nl` files, `test` keyword, `assert`)
- Extension methods

Each section: 1 paragraph of explanation + 1 code example. This is a TOUR, not a reference.

### 3. `docs/guide/for-csharp-developers.md`

**Audience**: Experienced C# developer.

Side-by-side comparison format:

```
## Variables
C#:    var name = "hello";
N#:    name := "hello"

## Functions
C#:    public int Add(int a, int b) { return a + b; }
N#:    func Add(a: int, b: int): int { return a + b }
```

Cover the top 20 things a C# dev would look up:
1. Variable declaration
2. Function declaration
3. Class definition
4. Properties
5. Constructors
6. Interfaces
7. Inheritance
8. Generics
9. Async/await
10. LINQ
11. Pattern matching (match vs switch)
12. Null handling
13. String interpolation
14. Collections
15. Error handling (the tuple trick!)
16. Enums
17. Records
18. Unions (NEW — C# doesn't have these)
19. Duck interfaces (NEW)
20. Visibility (convention-based)

### 4. `docs/guide/for-go-developers.md`

**Audience**: Go developer who wants to learn N# / understand "Go for .NET".

Show how Go concepts map to N#:
- `package` → `namespace` (implicit from directory)
- `func` → `func` (same keyword!)
- `:=` → `:=` (same syntax!)
- `interface{}` → `duck interface` (structural typing!)
- Goroutines → `async/await` (different model, but here's how)
- `error` returns → `result, err := ...` (same pattern!)
- `struct` → `record` / `struct`
- No generics* → Full generics with constraints
- `go fmt` → `nlc format` (same philosophy — one canonical style)
- `go test` → `nlc test` (similar — tests live near code)
- `go build` → `dotnet build` (the .NET ecosystem)

Highlight what Go developers will love:
- Convention-based visibility (PascalCase = public, like Go!)
- Tight syntax, no semicolons
- Fast compilation
- Strong CLI tooling

### 5. Update `docs/README.md`

Add a "Guides" section linking to all new docs.

### Quality bar

- Every code example must actually compile. Test each by putting it in a temp `.nl` file and running `nlc check`.
- No jargon without explanation.
- No walls of text — use code examples liberally.
- Link between guides where relevant.

## Follow the standard verification protocol in tasks/STANDARD-SUFFIX.md
