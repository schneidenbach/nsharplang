# Task 029: Decide And Build Public Website Playground Scope

Priority: P2 product surface.

Work in the N# repository and decide whether a public website playground is still part of launch strategy. The local `nlc tutorial` covers much of the interactive learning experience, but there is no public website playground.

## Scope

- Audit current website, docs, tutorial server, Monaco assets, compiler execution model, and any deployment constraints.
- Make an explicit product decision: public playground in scope or deferred.
- If in scope, reuse current tutorial/compiler infrastructure where practical.
- If deferred, update docs/tasks/launch claims so nobody implies it exists.

## Likely Files

- `website`
- `docs`
- `src/NSharpLang.Cli/Commands/TutorialCommand.cs`
- `docs/talk`
- `tests/CliCommandTests.cs`

## Acceptance

- Product decision is made: public playground is either in launch scope or explicitly deferred.
- If in scope, the playground reuses current tutorial/compiler infrastructure where practical.
- It supports examples, diagnostics, sharing, and a clear no-install first-run experience.
- If deferred, public docs and launch materials do not imply a hosted playground exists.

## Verification

- Run website/docs build or tests if website/docs change.
- Run focused tutorial/playground tests if code changes.
- Run `./scripts/test-all.sh` before committing if code changes.
