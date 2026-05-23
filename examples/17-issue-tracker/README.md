# Issue Tracker — N# Full-Stack Flagship Demo

A polished full-stack issue tracker with an N# backend (ASP.NET Minimal API) and a React/TypeScript frontend. This example is deliberately a proof path, not a toy snippet: build it from the CLI, run it from VS Code tasks, hit the backend directly, then show the browser app served by ASP.NET.

## The fastest demo

```bash
cd examples/17-issue-tracker
./scripts/demo.sh
```

The script does the whole path:

1. installs root and frontend npm dependencies
2. builds the React app into `backend/wwwroot/`
3. packs the local N# SDK for this repo, runs `nlc restore`, and runs `dotnet build` for the N# backend
4. runs `nlc test` through the same local-aware wrapper
5. starts ASP.NET on `http://localhost:5167`
6. curls `/api/health` and `/api/issues`, then creates an issue through the N# API

Evidence artifacts land in `examples/17-issue-tracker/.demo-artifacts/`:

- `backend.log`
- `health.txt`
- `issues-before.json`
- `create-response.json`
- `issues-after.json`

Keep the script running while you capture browser screenshots. Press Ctrl-C when done.
For CI-style smoke checks, run `ISSUE_TRACKER_HOLD=0 ./scripts/demo.sh`; it exits after the build/test/API proof path succeeds.

## Manual path

```bash
npm run setup
npm run build
npm run test:backend
npm run dev
```

Frontend dev server: `http://localhost:3000`
Backend/API: `http://localhost:5167`

The backend defaults to port 5167 because port 5000 often conflicts with AirPlay on macOS. To change it, set `ISSUE_TRACKER_PORT` for `scripts/demo.sh`, or update the `--urls` value in `package.json` and `backendPort` in `frontend/vite.config.ts`.

## VS Code path

Copy `examples/17-issue-tracker/vscode-tasks.example.json` to `.vscode/tasks.json`, or open it and paste the task entries into your existing workspace tasks. Then run one of these tasks from the repo root:

- `N#: issue tracker build`
- `N#: issue tracker backend tests`
- `N#: issue tracker flagship demo`

That makes the editor story explicit: this example is meant to work from the CLI, browser, backend API, and VS Code task runner.

## What to look for

Each backend file showcases specific N# features. This is not C# with a different coat of paint; the app leans on N# semantics.

### `Models.nl` — Records and unions

- `record Issue`, `User`, and `Comment` are concise immutable domain values.
- `union IssueStatus` is not an enum. `Open` carries no data, `InProgress` carries an assignee, and `Closed` carries a resolution and timestamp.
- `union IssueError` models typed domain failures without stringly exception matching.
- `FormatError()` uses an exhaustive match. Add a new error variant and unhandled matches stop compiling.

### `Workflow.nl` — Visibility by casing and pattern matching

- `Transition` is PascalCase, so it is public.
- `isValid` and `describe` are camelCase, so they are private.
- There are zero access-modifier keywords in the file.
- Status transitions use nested matches on union variants, not casts or string comparisons.

### `Notifier.nl` — Duck interfaces wired end-to-end

- `duck interface INotifier` describes the required shape.
- `ConsoleNotifier` and `SlackNotifier` satisfy it without writing `implements` or `: INotifier`.
- `NotifierHub` stores the duck interface in a private field and broadcasts when issues are created or transitioned.

### `Service.nl` — Error tuples and private helpers

- Throwing functions can be called as error tuples: `issue, err := service.CreateIssue(...)`.
- `validate()` is a camelCase private helper.
- Query helpers use normal .NET LINQ, because N# is real CLR interop.

### `Endpoints.nl` — ASP.NET Minimal API

- Routes are wired to `IssueService`, not fake fixtures.
- Request DTOs are N# records.
- The frontend and backend share a boring JSON contract on purpose: the language is new; the deployment model is ordinary .NET.

### `Program.nl` — Static files and SPA fallback

- ASP.NET serves the built frontend from `wwwroot/`.
- `/api/*` is handled by Minimal API routes.
- Client routes fall back to `index.html`.

### `frontend/src/types.ts` — TypeScript mirror

- N# unions map naturally to TypeScript discriminated unions.
- `statusLabel()` and `statusColor()` use exhaustive switches so the frontend breaks loudly when the backend union grows.

## Project structure

```text
17-issue-tracker/
├── package.json              # npm scripts for setup/build/dev/test
├── scripts/demo.sh           # one-command flagship demo path
├── backend/
│   ├── Models.nl             # records, unions, typed errors
│   ├── Workflow.nl           # visibility-by-casing + pattern matching
│   ├── Notifier.nl           # duck interfaces
│   ├── Service.nl            # business logic + error tuples
│   ├── Database.nl           # in-memory store
│   ├── Endpoints.nl          # Minimal API routes
│   ├── Program.nl            # ASP.NET app bootstrap
│   └── project.yml           # N# project config
└── frontend/
    ├── src/types.ts          # TypeScript union mirror
    ├── src/App.tsx           # polished browser demo
    ├── src/App.css           # demo styling
    └── package.json
```

Flat backend files are intentional. No `Models/`, `Services/`, `Data/` ceremony for a small package; code that changes together lives together.
