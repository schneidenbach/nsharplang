# Task 013: Harden Workspace Diagnostics Scheduling And Coverage

Priority: P1 IDE tooling.

Work in the N# repository and make project-scope diagnostics reliable in VS Code. Workspace diagnostics exist, but scheduling and update behavior need confidence across normal editor file lifecycle events.

## Scope

- Audit language server document management, workspace scanning, watched-file handling, diagnostics publication, and open-buffer overlays.
- Make diagnostics update reliably on open, save, change, create, delete, and watched-file events.
- Ensure open-buffer text participates in diagnostics without waiting for disk writes.
- Avoid noisy full rescans and stale diagnostics in larger workspaces.

## Likely Files

- `src/NSharpLang.LanguageServer/Services/DocumentManager.cs`
- `src/NSharpLang.LanguageServer/Handlers/DidChangeWatchedFilesHandler.cs`
- `src/NSharpLang.LanguageServer`
- `tests/LanguageServerWorkspaceDiagnosticsTests.cs`
- `tests/LanguageServerDiagnosticsTests.cs`

## Acceptance

- Diagnostics update reliably on open, save, change, create, delete, and watched-file events.
- Open-buffer text participates in diagnostics without waiting for disk writes.
- Large workspaces avoid noisy full rescans and stale diagnostics.
- LSP tests cover cross-file errors and file lifecycle events.

## Verification

- Run focused workspace diagnostics and language server tests while developing.
- Run `./scripts/test-all.sh` before committing.
- Run `./scripts/reload-vscode-extension.sh` and visually verify diagnostics in real VS Code across edit/save/create/delete flows.
