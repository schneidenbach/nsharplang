# Task 012: CLI Automation And JSON Contracts

Priority: P2.

Make the LLM-facing CLI contract dependable: `nlc format`, `nlc fix`, stable dry-run JSON, global JSON envelopes, and `nlc tree` behavior should all be documented, versioned, and tested. These belong together because automation consumers experience them as one contract surface.

## User Outcome

Humans, scripts, and agents can run formatting and safe fixes over examples or projects, inspect planned edits as stable JSON, and rely on accurate `nlc` documentation. `nlc tree` should not be documented as future work if it exists, and any missing behavior should be named precisely.

## Scope

- Treat `memory/components/cli-toolchain.md` as the canonical CLI contract reference.
- Audit examples, templates, and representative fixtures with `nlc format --check`.
- Fix unstable or ugly formatter output with regression tests.
- Add a CI or `./scripts/test-all.sh` formatting gate if the repo is expected to stay formatted.
- Expand `nlc fix` only for high-confidence diagnostics with accurate safe/review-needed/suggestion-only classification.
- Keep dry-run JSON stable and complete enough for automation.
- Audit CLI JSON outputs, help text, completion metadata, `docs/guide/cli-reference.md`, website docs, and tests.
- Version any breaking JSON changes and include migration notes.
- Audit `nlc tree` text/JSON output and docs parity.

## Likely Files

- `memory/components/cli-toolchain.md`
- `docs/guide/cli-reference.md`
- `website/docs`
- `src/NSharpLang.Compiler/Formatter.cs`
- `src/NSharpLang.Compiler/CodeFixes`
- `src/NSharpLang.Cli`
- `src/NSharpLang.Cli/Commands/FixCommand.cs`
- `examples`
- `templates`
- `tests/FormatterTests.cs`
- `tests/CodeFixTests.cs`
- `tests/FixCommandTests.cs`
- `tests/CodeIntelligenceOutputTests.cs`
- `tests/CliCommandTests.cs`
- `tests/CliParityAuditTests.cs`
- `scripts/test-all.sh`

## Acceptance

- Examples/templates/representative fixtures have a documented formatting audit or gate.
- New formatter behavior has focused tests for any changed layout.
- More diagnostics provide safe or review-needed fixes where edits are reliable.
- `nlc fix --dry-run --json` exposes stable edit and safety metadata.
- Applied fixes preserve parser/formatter round-tripping.
- CLI JSON envelopes, schema versions, error shapes, and field names are documented and tested.
- `nlc tree` behavior, help, JSON/text output, and docs agree.
- Missing dependency-tree capabilities are named precisely instead of saying the whole feature is absent.
- Breaking JSON changes increment schema versions.

## Verification

- Run focused formatter, code fix, fix command, CLI JSON contract, and parity tests while developing.
- Run the chosen formatting gate.
- Run docs/website checks if docs change.
- Run `./scripts/test-all.sh` before committing.
