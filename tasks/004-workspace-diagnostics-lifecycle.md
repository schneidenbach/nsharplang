# Task 004: Workspace Diagnostics Lifecycle

Priority: P1.

Make diagnostics update reliably through real editor file lifecycle events. This task owns document management, project snapshot updates, watched-file events, LSP publication, and visual verification in VS Code.

## User Outcome

When a developer opens, edits, saves, creates, deletes, or renames `.nl` files, diagnostics should update quickly and accurately. Unsaved buffers should be used for analysis, stale diagnostics should disappear, and large workspaces should not churn unnecessarily.

## Scope

- Audit document management, workspace scanning, watched-file handling, diagnostics publication, and open-buffer overlays.
- Update diagnostics on open, save, change, create, delete, and watched-file events.
- Ensure open-buffer text participates in project diagnostics before disk writes.
- Avoid noisy full rescans and stale diagnostics.

## Likely Files

- `src/NSharpLang.LanguageServer/Services/DocumentManager.cs`
- `src/NSharpLang.LanguageServer/Handlers/DidChangeWatchedFilesHandler.cs`
- `src/NSharpLang.LanguageServer`
- `tests/LanguageServerWorkspaceDiagnosticsTests.cs`
- `tests/LanguageServerDiagnosticsTests.cs`

## Acceptance

- Diagnostics update reliably for normal editor file lifecycle events.
- Open-buffer text overrides disk text in diagnostics.
- Stale diagnostics are cleared when files are fixed or removed.
- Tests cover cross-file errors, unsaved buffers, file creation, file deletion, and watched-file updates.

## Verification

- Run focused workspace diagnostics tests while developing.
- Run `./scripts/test-all.sh` before committing.
- Run `./scripts/reload-vscode-extension.sh` and visually verify diagnostics across open/edit/save/create/delete flows in VS Code.
