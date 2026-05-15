---
sidebar_label: Debugging
title: Debugging
---

# Debugging N# Code

## Current status

N# debugging is not exposed in the VS Code extension yet.

The extension intentionally does not contribute an N# debug command, breakpoint language contribution, debug test profile, or zero-config F5 configuration. Pressing F5 in a fresh N# workspace should not be treated as a supported N# workflow until a real debugger-backed `.nl` source experience exists and is visually verified.

## Supported VS Code workflow today

Use the N# tasks and test explorer paths instead:

1. Create or open a template-generated project with `project.yml`.
2. Use **Terminal: Run Build Task** / `nsharp: build` to run `nlc build`.
3. Use **Tasks: Run Task** / `nsharp: run` to run `nlc run`.
4. Use **Tasks: Run Task** / `nsharp: test` or the N# Test Explorer run profile to run `nlc test`.

The task provider honors the `nsharp.cli.path` VS Code setting. Leave it empty to use `nlc` from `PATH`, or set it to an absolute path to a repo-local/compiler-built `nlc` executable.

## Why debugging is hidden

Earlier docs described zero-config CoreCLR debugging, but the extension did not have enough validated behavior to make that a professional first-five-minutes promise for fresh projects. Until N# can provide a real debugger-backed workflow for `.nl` files, the safer product behavior is to hide F5/debug entry points rather than advertise a path that may not work.

## What must exist before this page becomes a how-to

Before restoring a debugging quick start, capture evidence for all of the following:

- Fresh `dotnet new nsharp-console` project opens in VS Code without manual generated C# or custom `.csproj` edits.
- F5 launches through a supported debug adapter with the same minimal `project.yml`/minimal `.csproj` story as the CLI.
- Breakpoints in `.nl` files bind and hit in real VS Code.
- Step over/into/out and call stack behavior stay in user-visible `.nl` source as much as the runtime permits.
- Variable inspection and debug console behavior are documented with honest limitations.
- `./scripts/reload-vscode-extension.sh`, `./scripts/test-vscode-headless.sh`, `./scripts/test-all.sh`, and real VS Code screenshots/recordings back the claim.

Until then, use `nlc build`, `nlc run`, `nlc test`, diagnostics, hover, completions, and code actions as the supported IDE story.
