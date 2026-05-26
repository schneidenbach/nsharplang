# Task 014: Public Playground

Priority: P2. Status: implemented.

Decide and implement the public website playground scope. The guided tour now lives in the hosted website playground.

## User Outcome

A first-time user has a clear no-install browser experience with examples, diagnostics, formatting, syntax highlighting, completions, hover, and share links.

## Scope

- Audit website, docs, Monaco assets, compiler execution model, and deployment constraints.
- Make an explicit product decision: public playground in scope or deferred.
- If in scope, reuse current guided-tour/compiler infrastructure where practical.
- If deferred, update docs and launch materials so nobody implies it exists.

## Likely Files

- `website`
- `docs`
- `docs/talk`
- `tests/CliCommandTests.cs`

## Acceptance

- Playground scope is explicitly decided.
- If implemented, the playground supports examples, diagnostics, sharing, and a clear no-install first-run experience.
- If deferred, public docs and launch materials do not imply a hosted playground exists.
- Website and CLI claims do not conflict.

## Verification

- Run website/docs build or tests if website/docs change.
- Run focused playground tests if code changes.
- Run `./scripts/test-all.sh` before committing if code changes.
