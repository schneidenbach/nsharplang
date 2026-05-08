# N# Migration Refactoring Loop

Status: prototype operations design
Scope: LLM-assisted migration cleanup after a C# to N# conversion snapshot, especially COTM-style ASP.NET Core / EF Core / xUnit / FluentValidation apps

## Why this exists

Large migrations should not be one giant "fix everything" prompt. Treat them as a controlled loop: snapshot the repository, run the compiler and checks, cluster failures, choose the safest recipe, make idiomatic N# edits, test the affected slice, and repeat until the project is green. Then do a final idiom audit so the output is not just compiling C# with fewer braces.

This document is an artifact for operators and future tooling. It assumes the converted N# snapshot already exists. If only C# input exists, stop and create a separate AI-assisted conversion/restoration plan before starting this loop.

## Non-goals

- Do not rewrite unrelated dirty files.
- Do not paper over unsupported compiler or language gaps with app-specific hacks.
- Do not mutate source automatically from a clustering/prototype tool unless the operator explicitly opts into that behavior.
- Do not claim COTM behavioral compatibility without the original COTM source, tests, route contract, database assumptions, and secrets/test infrastructure.

## Loop overview

1. Snapshot the repo and migration target.
2. Compile/check the converted N# project.
3. Cluster diagnostics by source, category, scope, risk, and likely recipe.
4. Select the safest next recipe.
5. Apply idiomatic N# edits in a narrow scope.
6. Run targeted checks/tests for that scope.
7. Run broader/full checks when the targeted slice is green.
8. Repeat until checks are green or progress stalls.
9. Perform a final idiom audit and operator handoff.

## Phase 0: snapshot and baseline

Before editing anything, capture enough state to make rollback and handoff boring.

Required inputs:

- Repository path and current branch/commit.
- `git status --short` before work starts.
- Target solution/project roots.
- Converted N# source roots.
- Available app tests and required infrastructure.
- Known unavailable prerequisites: private NuGet feeds, database, Testcontainers, secrets, external APIs.

Suggested commands:

```bash
git status --short
git rev-parse --short HEAD
dotnet --version
dotnet sln list
nlc check --project <project-dir> --json > artifacts/nlc-check-baseline.json
nlc lint --project <project-dir> --json > artifacts/nlc-lint-baseline.json
nlc idiom --project <project-dir> > artifacts/nlc-idiom-baseline.json
```

Use `--project <dir>` for project/root checks. `nlc check` also accepts a positional project directory, but `nlc lint` treats positional arguments as files, so migration automation should prefer the explicit project option. JSON is the default for `nlc check` and `nlc lint`; `--json` is shown here only to make the artifact contract obvious.

Snapshot artifacts may include:

- `migration-baseline.json`: commit, branch, target project roots, tool versions.
- `git-status-before.txt`: dirty tree state.
- `project-inventory.json`: solutions, projects, N# source roots.
- `test-inventory.txt`: discovered test commands and skipped prerequisites.
- `nlc-check-baseline.json`, `nlc-lint-baseline.json`, `nlc-idiom-baseline.json`: initial machine-readable compiler/lint/idiom state.

Stop here if the target root is ambiguous, the tree is dirty in files the loop would need to own, or required credentials/test infrastructure are missing.

## Phase 1: compile/check

Start with the cheapest deterministic checks. A migration iteration is not allowed to move to runtime testing until parsing and semantic checks are stable enough to make test failures meaningful.

Preferred order:

1. `nlc check` for parser and semantic diagnostics.
2. `nlc lint` for C# leftovers and N# idiom drift.
3. `nlc idiom` for migration-quality scoring and C# artifact inventory.
4. `dotnet build` for SDK/MSBuild/backend integration.
5. `dotnet test --filter ...` for the affected slice.
6. Full `dotnet test` or repo-level test script once targeted tests pass.

Record the command, exit code, and diagnostic JSON/text path for every iteration. Do not summarize failures only from terminal scrollback.

## Phase 2: diagnostic clustering

Cluster diagnostics before editing. The point is to avoid whack-a-mole fixes and identify recipe families that remove whole classes of errors safely.

Cluster dimensions:

- Source: parser/compiler, semantic analyzer, linter/style, backend/build, runtime/test, final idiom audit.
- Code/category: delimiter or terminator, identifier resolution, type resolution, type mismatch, nullable flow, missing import, unused import, casing/visibility, C#-ism, framework interop.
- Recipe family: syntax normalization, import/type qualification, symbol rename/casing, API shape rewrite, nullability rewrite, DTO/record conversion, LINQ method-chain rewrite, ASP.NET result typing, EF service extraction, validation extraction, test fixture simplification.
- Risk: mechanical, review-needed, human-decision-required.
- Scope: single file, symbol graph, project-wide, public API, data/model/schema, tests only.
- Dependency order: parse before semantic, imports before type mismatches, signatures before call sites, runtime/test after compile, idiom audit last.

A useful cluster record should answer:

```json
{
  "cluster_id": "imports-missing-fluentvalidation",
  "source": "semantic",
  "category": "missing import/type resolution",
  "sample_diagnostics": ["NLxxxx: type IValidator not found"],
  "files": ["src/Api/IssuesController.nl"],
  "recipe": "import/type qualification",
  "risk": "mechanical",
  "expected_check": "nlc check --project <project-dir> --json > artifacts/check-imports-missing-fluentvalidation.json"
}
```

If the same cluster reappears after two iterations with no diagnostic count reduction, stop and ask for a human decision or compiler/tooling fix.

## Phase 3: recipe selection

Choose one recipe per iteration unless two recipes are obviously coupled. Prefer low-risk recipes that unblock later semantic checks.

Recipe priority:

1. Parse-blocking syntax normalization.
2. Imports and type qualification.
3. Symbol casing/visibility fixes that match N# conventions.
4. Signature shape fixes before call-site rewrites.
5. Nullability and DTO/record cleanup.
6. ASP.NET result typing and validation mapping.
7. EF query/service extraction.
8. Test fixture simplification.
9. Final idiom audit.

Recipe safety rules:

- Mechanical recipes may be batched when they are syntax-local and covered by `nlc check`.
- Review-needed recipes require a scoped diff inspection before tests.
- Human-decision-required recipes must block when they affect public routes, auth, persistence semantics, validation behavior, or data contracts.

## Phase 4: idiomatic edits

Every edit should make the code more N#, not merely less broken.

General idiom rules:

- Preserve public .NET surface names needed by ASP.NET Core, EF Core, xUnit, FluentValidation, JSON serializers, and C# callers.
- Use camelCase for private fields, helpers, locals, and implementation details.
- Prefer DTO records for request/response payloads and service return data.
- Keep controllers and minimal endpoints thin: bind, validate, call a service, map to HTTP result.
- Keep framework ceremony at the boundary; business logic belongs in services or domain helpers.
- Do not return EF entities from HTTP endpoints.
- Prefer method-chain LINQ over query comprehension syntax.
- Use `AsNoTracking()` for read-only EF queries.
- Prefer projection before materialization.
- Keep ordinary unit tests in idiomatic N# test blocks; keep xUnit class fixtures only where framework interop requires them.

## Phase 5: targeted validation

After each recipe, run the narrowest check that proves the recipe worked.

Examples:

- Syntax normalization: `nlc check --project <project-dir> --json`.
- Imports/type names: `nlc check --project <project-dir> --json` plus focused build if generated C# changed.
- ASP.NET result typing: affected controller/minimal API tests.
- EF query rewrite: affected service tests, integration tests if database infrastructure exists.
- Validation rewrite: validator tests plus endpoint validation tests.
- Test fixture simplification: the affected test class or namespace.

Record skipped tests with the reason. "Not run" without a reason is not a valid handoff.

## Phase 6: full validation and repeat-until-green

When targeted validation passes, broaden the check radius:

```bash
nlc check --project <project-dir> --json > artifacts/nlc-check-final.json
nlc lint --project <project-dir> --json > artifacts/nlc-lint-final.json
nlc idiom --project <project-dir> > artifacts/nlc-idiom-final.json
dotnet build <solution-or-project>
dotnet test <solution-or-test-project>
```

For this repo, the full local gate is usually:

```bash
./scripts/test-all.sh
```

Use it before committing code changes. For documentation-only migration-loop edits, a targeted docs/content inspection plus `git diff --check` may be enough if the full script would spend time validating unrelated existing dirty work; record that decision explicitly.

Repeat the loop while each iteration improves one of these metrics:

- Fewer parse/compiler/lint diagnostics.
- A previously failing targeted test passes.
- A broader command becomes runnable.
- The remaining failures move to a later phase.

Stop and block when diagnostics flap, counts do not improve for two consecutive iterations, or the next recipe requires a domain/API/auth/persistence decision.

## Final idiom audit

Compilation is not the finish line. The final pass checks whether the migrated app reads like native N#.

Run and archive the idiom report after the final compiler/lint pass:

```bash
nlc idiom --project <project-dir> > artifacts/nlc-idiom-final.json
```

The report is a gate, not an optional narrative review. Treat these fields as machine-checkable pass/fail inputs:

- `ok` is `true` and `schemaVersion` is understood by the migration runner.
- `thresholds.checkErrors` is `0`; `nlc check` must already have passed with zero errors.
- `thresholds.blockingCsharpArtifacts` is `0`, or every remaining artifact has an explicit waiver in the handoff with file, line, owner, interop reason, and review status.
- `thresholds.safeFixesRemaining` is `0`; run `nlc fix --project <project-dir> --dry-run --json` when safe-fix availability matters for the current build.
- `grade` is `idiomatic` or `mostly-idiomatic`. A lower grade is a failed final audit unless the run is explicitly scoped as a partial migration and the non-migrated areas are listed as out of scope.
- `signals.manualReviewIslands.count` is `0`, or every island is represented in the handoff as `blocked`/`waived` with a reason and next owner.

Store the report next to `nlc-check-final.json`, `nlc-lint-final.json`, build logs, and test logs so a reviewer can compare the final gate with the baseline report without rerunning tools.

Audit checklist:

- Public ASP.NET/EF/xUnit/FluentValidation surface remains discoverable and PascalCase where frameworks expect it.
- Private implementation uses N# casing and avoids C# `_field` cargo cult unless interop requires it.
- DTOs are records unless mutation/framework construction requires classes.
- Controllers/minimal endpoints return `ActionResult<T>` or `Results<...>`/`TypedResults.*` where appropriate.
- HTTP endpoints preserve routes, status codes, and validation behavior.
- EF reads use `AsNoTracking`, method-chain LINQ, projection before materialization, and no entity leakage through controllers.
- Validators are discoverable PascalCase classes and validation failures map to `BadRequest`/`ValidationProblem`.
- Tests are idiomatic N# except for documented xUnit interop fixtures.
- Remaining C#-isms are documented framework interop exceptions, not leftovers.

## COTM-style acceptance criteria

A COTM-style migration is acceptable when all applicable items are true:

- `nlc check --project <project-dir> --json`, `nlc lint --project <project-dir> --json`, `nlc idiom --project <project-dir>`, `dotnet build`, and app-level `dotnet test` pass for migrated projects, with command output archived and exit codes recorded.
- Controllers or minimal endpoints retain routes, status codes, request/response shapes, and validation behavior, verified by at least one concrete artifact per migrated API slice: original source/test reference, endpoint/integration test log, OpenAPI or route snapshot diff, golden request/response fixture comparison, or an explicit blocked note naming the missing prerequisite.
- Endpoint methods use `ActionResult<T>` or `Results<...>`/`TypedResults.*` instead of vague result types where typed results fit.
- EF read queries use method-chain LINQ, `AsNoTracking()` for read-only paths, projection before materialization, and no EF entities returned from controllers.
- FluentValidation validators are discoverable PascalCase classes and validation failures map to `BadRequest` or `ValidationProblem`.
- Request/response DTOs are named records unless mutation or framework construction requires classes.
- Ordinary unit tests use idiomatic N# test blocks; xUnit fixtures remain only for required interop.
- Final idiom audit is mostly-idiomatic or better, with any remaining C#-isms documented as framework interop exceptions and backed by `nlc-idiom-final.json` signal paths.
- The handoff lists skipped tests, missing infrastructure, and behavior that could not be verified from available source. Each item must be marked `pass`, `fail`, `not_applicable`, or `blocked`; prose-only assurances are not sufficient.

For real app compatibility, include an evidence matrix in the handoff. A minimal matrix looks like:

| Compatibility item | Expected source | Verification artifact | Status |
|---|---|---|---|
| Routes and HTTP methods | Original C# endpoints, controller attributes, or route snapshot | OpenAPI/route snapshot diff or endpoint test log | `pass`/`fail`/`blocked` |
| Status codes | Original tests/controllers/minimal APIs | Endpoint test assertions or golden HTTP transcript | `pass`/`fail`/`blocked` |
| Request/response JSON shape | DTO definitions, serializers, OpenAPI, or golden fixtures | Snapshot diff, contract test, or serialized fixture comparison | `pass`/`fail`/`blocked` |
| Validation behavior | FluentValidation rules and original validation tests | Validator tests plus invalid-request endpoint tests | `pass`/`fail`/`blocked` |
| Persistence behavior | EF model/query source and database prerequisites | Service/integration test log, DB fixture note, or blocked infrastructure note | `pass`/`fail`/`blocked` |

## Operator handoff checklist

Include this in the final migration run handoff:

- Repository, branch, starting commit, ending commit, and whether unrelated dirty files existed before the run.
- Target solution/project roots and converted N# source roots.
- Commands run, exit codes, and log/artifact paths.
- Diagnostic clusters fixed, clusters remaining, and known unsupported compiler/language gaps.
- Recipes applied and files touched by each recipe.
- Targeted tests run and why they were selected.
- Full checks run, or explicit reasons they were not run.
- COTM acceptance criteria status: pass/fail/not applicable/blocked for each item.
- Public API/route/data/validation changes requiring human review.
- Remaining C#-ism exceptions and why they are acceptable interop.
- Rollback point or patch bundle location.

## Safe-by-default prototype shape

A future clustering helper should default to read-only analysis. Its default output should be a plan, not edits.

Suggested CLI shape:

```bash
nlc migrate plan --project <project-dir> \
  --diagnostics artifacts/nlc-check.json \
  --out artifacts/migration-plan.json
```

Default behavior:

- Reads existing diagnostics and source files.
- Emits diagnostic clusters, recipe candidates, risk levels, and suggested validation commands.
- Does not modify files.
- Exits non-zero only for malformed inputs or unreadable project roots, not because diagnostics exist.

Any mutating mode must require an explicit flag such as `--apply mechanical-only` and should still refuse review-needed or human-decision-required recipes unless a later design defines safe guardrails.
