# Task 021: Public Playground

Priority: P2.

Decide and implement the public website playground scope. The local `nlc tutorial` covers much of the interactive learning experience, but there is no public hosted playground.

## User Outcome

A first-time user either has a clear no-install browser experience with examples and diagnostics, or public docs honestly say the hosted playground is deferred.

## Scope

- Audit website, docs, tutorial server, Monaco assets, compiler execution model, and deployment constraints.
- Make an explicit product decision: public playground in scope or deferred.
- If in scope, reuse current tutorial/compiler infrastructure where practical.
- If deferred, update docs and launch materials so nobody implies it exists.

## Likely Files

- `website`
- `docs`
- `src/NSharpLang.Cli/Commands/TutorialCommand.cs`
- `docs/talk`
- `tests/CliCommandTests.cs`

## Acceptance

- Playground scope is explicitly decided.
- If implemented, the playground supports examples, diagnostics, sharing, and a clear no-install first-run experience.
- If deferred, public docs and launch materials do not imply a hosted playground exists.
- Tutorial and website claims do not conflict.

## Verification

- Run website/docs build or tests if website/docs change.
- Run focused tutorial/playground tests if code changes.
- Run `./scripts/test-all.sh` before committing if code changes.
