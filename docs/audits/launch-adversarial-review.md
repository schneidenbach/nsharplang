# N# launch adversarial Codex review

Date: 2026-05-14
Repo: `/Users/spencer/code/nsharplang`
SHA reviewed: `6f8cf1d5b842ba172a7d5381b1d255bce40ce833`
Mode: auto/deep hybrid. Initial Codex xhigh read-only critique covered the broad launch concept; I then debated the six critical findings in one focused Codex xhigh read-only challenge pass. Critical findings were defended or revised; none were retracted.

## Verification

Codex CLI was available and ran successfully in read-only sandbox mode with xhigh reasoning.

Commands:

```bash
codex exec -c model_reasoning_effort='"xhigh"' --sandbox read-only --skip-git-repo-check -C /Users/spencer/code/nsharplang - < /Users/spencer/code/nsharplang/.hermes/launch-adversarial-codex-prompt.md > /Users/spencer/code/nsharplang/.hermes/launch-adversarial-codex-output.txt 2>&1

codex exec -c model_reasoning_effort='"xhigh"' --sandbox read-only --skip-git-repo-check -C /Users/spencer/code/nsharplang - < /Users/spencer/code/nsharplang/.hermes/launch-adversarial-codex-debate-prompt.md > /Users/spencer/code/nsharplang/.hermes/launch-adversarial-codex-debate-output.txt 2>&1
```

Artifacts:

- Initial prompt: `/Users/spencer/code/nsharplang/.hermes/launch-adversarial-codex-prompt.md`
- Initial raw Codex transcript/output: `/Users/spencer/code/nsharplang/.hermes/launch-adversarial-codex-output.txt`
- Debate prompt: `/Users/spencer/code/nsharplang/.hermes/launch-adversarial-codex-debate-prompt.md`
- Debate raw Codex transcript/output: `/Users/spencer/code/nsharplang/.hermes/launch-adversarial-codex-debate-output.txt`

## Executive recommendation

Do not present N# as launch-green or production-ready.

Proceed with a constrained pre-talk story only:

- Safe: N# is a Go-for-.NET language/toolchain experiment becoming real.
- Safe: main Build is green at this SHA.
- Safe: core unit suite is green: 2265 passed, 3 skipped.
- Safe: curated `nlc check` on `templates/nsharp-console`.
- Safe: curated `nlc query symbols` JSON on `examples/17-issue-tracker/backend`.
- Safe with caveat: VS Code diagnostics/hover/completions are smoke-tested; capture a real screenshot/clip before using visual claims.
- Internal-only validation corpora are not public proof or demo material.

Do not claim:

- full product/release launch readiness;
- full `./scripts/test-all.sh` green;
- full VS Code integration/zero-config debug/task polish;
- safe semantic rename/references/definition on unsaved buffers;
- CodeLens/reference-count correctness;
- public migration success for private application corpora;
- public installability/package publishing;
- docs/site launch polish;
- “perfect” or “seamless” C# interop.

Confidence: high. Evidence comes from current repo files, parent evidence matrix, and two successful Codex xhigh read-only passes.

## Accepted / rejected / deferred decisions

### Language

ACCEPT:

- Go-style casing-first visibility with explicit .NET interop escape hatches.
- Null-aware, .NET-honest direction instead of null-free/Option-everywhere purity.
- DTO/data records, lifecycle/framework classes, and canonical `new Type { Name: value }` as the object initialization direction.
- No universal `Option<T>` framing; unions are for domain outcomes, not every simple absence.

REJECT:

- “Perfect C# interop” wording. Use “first-class, pragmatic C# interop with explicit limitations.”
- Public claims that `must`, flow null-state, and `nlc query type nullState` are shipped behavior; those are design/plan until implementation lands.
- Universal Option/Maybe messaging in migration/docs.

DEFER:

- Any talk/demo claim about object initialization framework binding until ASP.NET/System.Text.Json/EF integration tests exist.
- Public non-Pascal API escape-hatch examples unless analyzer/docs label them explicit interop waivers.

### CLI / semantic tooling

ACCEPT:

- `nlc query symbols` as the curated semantic CLI demo, because the evidence matrix has a concrete successful JSON run.
- Broad CLI surface exists as help output, but only as surface, not per-command reliability.

REJECT:

- Broad “all query commands are semantic/stable/proven” claims.
- Any “grep-free everywhere” claim while LSP fallbacks and CodeLens text counts remain.

DEFER:

- Query `hover`, `call-graph`, `implementors`, `references`, `definition`, and completion/docs parity claims until each has dry-run output and parity tests.
- Completion/docs/help consistency until `CompletionCommand` and docs stop omitting implemented query commands.

### VS Code / LSP

ACCEPT:

- Diagnostics, hover, and completions as smoke-tested basics.

REJECT:

- Zero-config debugging/task polish as a launch claim.
- CodeLens/reference-count correctness as shipped.
- Unsaved-buffer rename/references/definition safety as shipped.

DEFER:

- Full VS Code integration claims until full `npm test`/`./scripts/test-all.sh` completes reliably and a real VS Code visual pass is captured.
- Semantic refactor claims until open-buffer project snapshots exist or risky operations are disabled when snapshots are stale.

### Migration

ACCEPT:

- No public `nlc convert` command. The contract is AI-authored `.nl` plus `nlc check`, `nlc idiom`, `nlc fix --dry-run`, format, and tests.
- Private application corpora as internal validation targets only.

REJECT:

- Raw private application screenshots/files/configs/logs in public material.
- “Real app migrated” as a public proof point based on inventory alone.

DEFER:

- Public migration proof for private application corpora until there is a redacted subset, security approval, and fresh `nlc check`/build/test/idiom evidence.

### Docs / site

ACCEPT:

- Existing docs can be used as internal context with caveats.

REJECT:

- Docs/site launch-polished claims unless the current docs build and claim audit have just passed.
- Marketplace, `dotnet tool install -g nlc`, zero-config debug, production-ready, feature-complete, or stale test-count claims unless verified and updated.

DEFER:

- Linking docs/site in the talk unless the linked pages are patched first.
- Docs parity confidence until command tables are generated or tested against `nlc help`, `nlc query help`, and completion output.

### Release packaging

ACCEPT:

- Packaging infrastructure exists.

REJECT:

- Public installability/publish claims without clean-machine proof.

DEFER:

- CLI/SDK/templates/language-server/VSIX release claims until clean-machine install tests cover package artifacts or published feeds, `dotnet new`, build, run, and VS Code installation path.

## Confirmed / revised concerns

### [CRITICAL] Launch-green narrative outruns evidence

Aspect: operations

Codex initial position: full `test-all` timed out, full VS Code integration is not green, screenshots are absent, private application corpus evidence is inventory-only, package publishing is unverified.

Debate result: DEFENDED as critical.

Decision: do not say launch-ready/full-suite-green. Use only unit/main-build/VS Code-smoke/curated CLI demo language.

### [CRITICAL] Raw private app material is not public-demo safe

Aspect: security

Codex initial position: private app material has sensitive-name/content signals and explicit “do not show raw private app material” guidance.

Debate result: DEFENDED as critical.

Decision: keep private app material internal until redacted, approved, and validated.

### [WARNING] Private app inventory is not migration proof

Aspect: correctness

Decision: defer public private-app migration success claims until check/build/test/idiom evidence exists.

### [CRITICAL] Project model story is internally inconsistent

Aspect: operations

Codex initial position: repo has a one-line `.csproj` philosophy, csproj-free docs/tests/templates, `nlc new` help saying no `.csproj`, and implementation creating one.

Debate result: DEFENDED as critical.

Decision: pick one public contract before strong project-creation/zero-config claims: either one-line `.csproj` everywhere or csproj-free templates with `nlc`-first build/run/test.

### [CRITICAL] VS Code zero-config claims are not launch-safe

Aspect: operations

Codex initial position: smoke basics are safe, but zero-config build/debug/test is contradicted by direct `dotnet` tasks and debug-test behavior.

Debate result: DEFENDED as critical.

Decision: demo diagnostics/hover/completions only; no F5/tasks/debug polish claims until fixed and visually verified.

### [WARNING, revised from critical] Unsaved-buffer semantic tooling can degrade to text edits

Aspect: correctness

Codex initial position: critical for semantic refactor claims.

Debate result: REVISED to warning for the constrained talk, because it is not a blocker if only `nlc query symbols` is demoed and rename/references/definition safety are not claimed.

Decision: exclude IDE semantic refactor claims; fix/disable unsafe fallbacks before claiming them.

### [WARNING] CodeLens reference counts are not product-ready

Aspect: correctness

Decision: defer CodeLens/reference-count claims until PR #106 is reviewed/merged and real VS Code verification proves registered, clickable, semantic behavior.

### [WARNING] CLI query semantic story needs per-command proof

Aspect: correctness

Decision: accept only `query symbols` demo now. Defer broad query claims until per-command proof and docs/completion/help parity exist.

### [WARNING] Nullability policy is mostly design, not shipped behavior

Aspect: feasibility

Decision: accept the direction; defer claims that `must`, null-state flow analysis, metadata import, and `query type nullState` are shipped.

### [WARNING] Option messaging conflicts with nullability stance

Aspect: complexity

Decision: reject universal Option framing. Patch public docs to distinguish simple absence (`T?`) from domain outcomes (unions/results).

### [WARNING] Object initialization spec has unproven framework-binding risk

Aspect: correctness

Decision: accept the design direction; defer target-typed/record-binding claims until ASP.NET/System.Text.Json/EF integration tests pass.

### [WARNING] Go-style casing visibility can surprise CLR users

Aspect: assumptions

Decision: accept casing-first visibility, but require analyzer/docs pressure on public non-Pascal APIs unless explicitly waived for interop.

### [WARNING] “Perfect/seamless interop” is an overclaim

Aspect: assumptions

Decision: reject “perfect” wording; use pragmatic/first-class interop with explicit limitations.

### [WARNING, revised from critical] Docs/site are not launch-polished

Aspect: operations

Debate result: REVISED to warning for a talk that does not link docs/site, but still a blocker for public launch.

Decision: public docs/site wording has been tightened, but avoid treating the site as final launch copy until the docs build, package/feed checks, and full claim audit pass.

### [WARNING] Release packaging/installability is unproven

Aspect: operations

Decision: defer install/publish claims until clean-machine install evidence exists.

## Minimal defensible talk script

1. “N# is a Go-for-.NET language/toolchain experiment becoming real: small syntax, .NET interop, project.yml-first direction, and an LLM-friendly CLI.”
2. Show exact SHA and green main Build.
3. Show `dotnet test tests/Tests.csproj -v q`: 2265 passed, 3 skipped.
4. Show `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- check --project templates/nsharp-console --text`.
5. Show `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query symbols --project examples/17-issue-tracker/backend --json`.
6. If a real VS Code clip/screenshot is captured, show diagnostics/hover/completions only; otherwise show smoke test output.
7. Say explicitly: “The full end-to-end suite is a pre-talk gate, not a proof point today.”

## Immediate next gates before stronger claims

1. Make `./scripts/test-all.sh` complete green in a clean checkout.
2. Resolve project model contract: one-line `.csproj` everywhere vs csproj-free + `nlc` build/run/test.
3. Fix VS Code tasks/debug/test workflow and visually verify in real VS Code.
4. Merge/review/verify PR #106 or remove CodeLens/reference-count claims.
5. Disable or replace unsafe LSP text fallbacks for rename/references when snapshots are stale.
6. Produce an approved redacted private-app subset plus fresh validation logs before making any private-app migration proof claim.
7. Keep docs/site stale-count, install/marketplace/debug, and production-ready wording under the claim audit; rerun docs build before launch.
8. Run clean-machine package/template/CLI/VSIX install tests.
