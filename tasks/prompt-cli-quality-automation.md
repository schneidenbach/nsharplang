# Prompt: CLI Quality And Machine-Readable Automation

Last updated: 2026-05-25

Copy this into a fresh agent/dev session.

```text
You are working in the N# repository. Your goal is to improve CLI reliability, automation behavior, and JSON/docs parity.

Read `tasks/CURRENT.md` first. Focus on these current issues:
- 24. Add formatter repo/example audit and CI gate
- 25. Grow `nlc fix` into a broader machine-drivable tool
- 30. Add native test coverage reporting or document its absence clearly
- 33. Audit dependency tree command and docs parity
- 35. Keep CLI JSON contracts authoritative

Expected approach:
1. Audit current CLI command implementations, help text, JSON envelopes, docs, tests, and completion metadata.
2. Add a formatting audit/gate for examples/templates/representative fixtures if the repo is expected to stay formatted.
3. Expand `nlc fix` only where fixes are high-confidence and can expose clear safety metadata.
4. Either implement coverage behavior or make the unsupported state explicit and consistent in help/docs/JSON.
5. Audit `nlc tree` behavior and docs so docs do not call implemented behavior future work.
6. Keep `memory/components/cli-toolchain.md`, `docs/guide/cli-reference.md`, website docs, help text, completions, and tests synchronized.

Acceptance:
- CLI help, docs, completion scripts, and JSON schema tests agree.
- `nlc format --check` can be used as a trustworthy repo/example gate.
- `nlc fix --dry-run --json` remains stable and machine-usable.
- Coverage requests have clear exit codes and JSON/human output.
- Any JSON contract change is versioned or explicitly proven non-breaking.

Verification:
- Add focused CLI parity and JSON contract tests.
- Run relevant focused `dotnet test` filters.
- Run `./scripts/test-all.sh` before committing.
```
