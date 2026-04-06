# Issue Tracker — N# Full-Stack Example

A full-stack issue tracker with an N# backend (ASP.NET Minimal API) and a React/TypeScript frontend. This example demonstrates what makes N# different from C# — not just syntax, but semantics.

## Quick Start

```bash
npm run setup    # Install all dependencies
npm run dev      # Start backend + frontend concurrently
```

Frontend: http://localhost:3000 (proxies API calls to backend)
Backend: http://localhost:5167

The backend defaults to port 5167 (not 5000, which conflicts with AirPlay on macOS). To change it, edit the `--urls` value in `package.json` and the `backendPort` default in `frontend/vite.config.ts`.

## Production Build

```bash
npm run build    # Builds frontend first, then backend
```

The `build` script enforces correct ordering: frontend assets are compiled into `backend/wwwroot/` before the backend build runs. Do not run `dotnet build` directly in the backend directory unless you have already built the frontend — the backend serves the frontend from `wwwroot/` via static file middleware.

## What to Look For

Each backend file showcases specific N# features. This isn't C# with different syntax — these are semantic differences that change how you think about code.

### `Models.nl` — All types in one file
- **`union IssueStatus`** — Not an enum. Each variant carries different data (InProgress has an assignee, Closed has a resolution). This is what unions are for.
- **`union IssueError`** — Typed domain errors. Match on the variant, not on exception message substrings.
- **`record` types** — Immutable value types for Issue, User, Comment.
- **`Errors.Format()`** — Exhaustive match. Add a new IssueError variant and the compiler breaks every unhandled match.

### `Workflow.nl` — Visibility by casing
- **`Transition`** (PascalCase) is public. **`isValid`**, **`describe`** (camelCase) are private.
- Zero access modifier keywords anywhere in this file. The casing IS the modifier.
- State machine transitions with clean match expressions.

### `Notifier.nl` — Duck interfaces (wired end-to-end)
- **`duck interface INotifier`** — Define what you need, not what implements it.
- `ConsoleNotifier` and `SlackNotifier` satisfy `INotifier` without writing `implements` or `: INotifier`.
- `NotifierHub` collects notifiers and broadcasts — the duck interface type stays in **private fields** (camelCase), never public signatures.
- `Program.nl` registers concrete notifiers; `Service.nl` broadcasts on create/transition. The duck interface is a real, working part of the app.

### `Service.nl` — Error tuples + private helpers
- Functions that `throw` produce error tuples at the call site: `issue, err := service.CreateIssue(...)`.
- **camelCase `validate()`** — Private helper, invisible outside this class.
- LINQ for queries — N# has full .NET interop, no compromises.

### `Endpoints.nl` — Minimal API routes
- Routes wired to `IssueService` — live API, not stubs.
- Request DTOs as records — one-line immutable types.

### `Program.nl` — Entry point
- The entire app bootstrap in ~20 lines.
- Static file middleware serves the built frontend from `wwwroot/`.
- SPA fallback routes unmatched paths to `index.html` for client-side routing.

### `frontend/src/types.ts` — TypeScript mirror
- N# unions map naturally to TypeScript discriminated unions.
- `statusLabel()` uses exhaustive switch — add a variant in N#, TypeScript breaks too.

## Project Structure

```
17-issue-tracker/
├── package.json          ← npm run dev starts everything
├── backend/
│   ├── Models.nl         ← All domain types (unions, records, enums)
│   ├── Workflow.nl       ← State machine (visibility-by-casing showcase)
│   ├── Notifier.nl       ← Duck interfaces (structural typing)
│   ├── Service.nl        ← Business logic (error tuples, private helpers)
│   ├── Database.nl       ← In-memory store
│   ├── Endpoints.nl      ← Minimal API routes
│   ├── Program.nl        ← Entry point (static files + SPA fallback)
│   └── project.yml       ← Project config (not .csproj properties)
└── frontend/
    ├── src/
    │   ├── types.ts      ← TypeScript unions mirroring N# unions
    │   ├── App.tsx        ← React UI
    │   └── main.tsx       ← Entry point
    └── package.json
```

No `Models/`, `Services/`, `Data/` directories. Flat, like a Go package. Types that belong together live together.
