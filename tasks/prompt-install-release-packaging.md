# Prompt: Install, Release, Packaging, Publish

Last updated: 2026-05-25

Copy this into a fresh agent/dev session.

```text
You are working in the N# repository. Your goal is to make install, CI setup, packaging, and publishing feel like one coherent supported toolchain.

Read `tasks/CURRENT.md` first. Focus on these current issues:
- 23. Create a current `setup-nsharp` GitHub Action
- 26. Unify install, release, and local toolset ergonomics
- 29. Polish NuGet library publishing
- 31. Decide cross-compilation and publish-target scope

Expected approach:
1. Audit `scripts/install.sh`, local setup/deploy scripts, `doctor`, package artifact generation, VSIX install, templates, `nlc pack`, `nlc publish`, docs, and GitHub workflows.
2. Create or update `actions/setup-nsharp/action.yml` around current installer semantics. Do not reintroduce stale `--version` behavior if the installer rejects it; use explicit source/toolset inputs instead.
3. Dogfood the setup action in an appropriate workflow without depending on stale csproj assumptions.
4. Tighten the library publishing story: template sample tests if appropriate, dedicated docs, and an end-to-end packed-NuGet C# consumer test if feasible.
5. Clarify what `nlc build --release`, `nlc publish`, cross-target, and unsupported target-platform workflows actually support today.

Acceptance:
- Setup action installs .NET, installs N#, adds `~/.nsharp/bin` to PATH, and verifies `nlc`.
- Public install docs, local setup docs, `doctor`, CI setup, release artifacts, and VSIX install describe the same model.
- Library publishing docs and tests prove the promised C# consumption path.
- Unsupported publish/cross-target scenarios fail with useful guidance.

Verification:
- Add focused tests for setup docs/parity where practical, `nlc pack`, template shape, and C# consumption.
- Validate workflow/action YAML.
- Run focused tests during development.
- Run `./scripts/test-all.sh` before committing.
```
