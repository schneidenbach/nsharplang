# AI C# to N# Migration Contract

Status: implementation-facing contract
Audience: AI agents, converter authors, CLI/analyzer implementers, reviewers

AI-assisted C# to N# migration is not a one-shot syntax conversion. The contract is an iterative refactoring loop:

1. Inventory the C# project and choose the migration slice.
2. Convert or sketch the initial N# files with `package` declarations and the target folder shape.
3. Run `nlc check --project <out> --json` and cluster diagnostics by code/category before editing.
4. Run `nlc idiom --project <out>` and treat high-severity C# artifacts as blockers even when code compiles.
5. Run `nlc fix --project <out> --dry-run --json`; apply safe fixes, inspect review-needed fixes, and never auto-apply architecture/domain suggestions.
6. Refactor one cluster at a time, then rerun `nlc check`, `nlc idiom`, `nlc fix --dry-run`, formatting, and tests.
7. Stop only when the gates below pass or every remaining review-needed item has an explicit diagnostic-backed waiver.

## Required idiomatic N# output

Migrated output must look like N#, not C# with fewer semicolons:

- Use `package` declarations that match the destination folder/package shape. Group framework boundaries, domain models, services, endpoints/controllers, and tests deliberately.
- Use Go-style visibility and casing: PascalCase for public .NET/framework-discovered surface, camelCase for private helpers, fields, locals, and implementation details. Avoid explicit `public`/`private` when casing already communicates visibility.
- Convert DTO-shaped request/response/view-model classes to `record` unless mutation or identity is required.
- Model domain results and expected failures with `union` plus exhaustive `match`; map those results once at the ASP.NET/framework boundary.
- Use canonical N# object initialization: `new Type { Name: value }`, never C# assignment initializers inside migrated N#.
- Preserve direct ASP.NET Core and EF Core interop at boundaries, but make the N# side idiomatic: typed results/records for APIs, thin controllers/endpoints, services owning EF queries, LINQ method chains rather than C# query syntax.
- Clean up nullability instead of suppressing it. Prefer precise nullable types, guards, unions/options/results, and `match` over `null!`, `default!`, or unsafe `.Value` access.

## Rejected hybrid output

The migration is incomplete if any of these appear without an explicit diagnostic-backed waiver:

- Copied C# modifiers where N# casing should carry visibility: `public`, `private`, `protected`, `internal`, `sealed`, `abstract`, `readonly`, `virtual`, `override`.
- Statement semicolons in migrated N# files, except syntax positions where N# explicitly requires separators.
- C# property blocks: `{ get; set; }`, `{ get; init; }`, or translated backing-property boilerplate that should be a field/record property.
- `_field` private style when a camelCase field is sufficient.
- `IActionResult`, `IResult`, or anonymous DTO defaults when `ActionResult<T>`, `Results<...>`, typed results, or named records fit the endpoint.
- C# query comprehension syntax (`from ... in ... select ...`) in EF/LINQ code.
- `null!`, `default!`, or arbitrary null-forgiving operators used to silence the compiler.
- Unsafe `.Value` on option/result-like values instead of `match`/checked handling.
- Leftover TODO/manual-review islands that are not represented in `nlc check`/`nlc idiom` diagnostics with owner, reason, and fix safety.

## CLI quality gates

An AI agent should run this loop from the destination N# project root:

```bash
# Optional when the converter is available in the current build.
nlc convert --dir <csharp-src> --output <nsharp-out>

cd <nsharp-out>
nlc check --project . --json
nlc idiom --project .
nlc fix --project . --dry-run --json
nlc format --check --project .
nlc test --project .
```

Completion gates:

- `nlc check` reports zero errors.
- `nlc idiom` reports zero blocking C# artifacts and no unowned manual-review islands.
- `nlc fix --dry-run --json` has no remaining safe fixes.
- Review-needed fixes are either applied or explicitly waived with rationale.
- Suggestion-only domain/architecture recommendations are accepted or waived; they are never silently ignored.
- Project tests pass after migrated source changes.

If the local build does not register `nlc convert`, do not invent a successful conversion. Produce the initial `.nl` files by the available converter/manual migration path, record that `nlc convert` was unavailable, and still enforce the `check`/`idiom`/`fix`/format/test gates.

## `nlc idiom` report contract

The report must remain machine-readable and stable. Compatible fields should be added without breaking existing consumers; incompatible shape changes require a schema version bump.

Top-level fields:

- `schemaVersion`
- `command`
- `ok`
- `projectRoot`
- `scannedFiles`
- `score`
- `grade`
- `summary`
- `signals`
- `files`
- `recommendations`
- `thresholds`

Debt/signal categories should cover:

- `layout.package`
- `visibility.casing`
- `artifact.modifier`
- `artifact.semicolon`
- `artifact.propertyBlock`
- `artifact.underscoreField`
- `artifact.nullForgiving`
- `artifact.defaultForgiving`
- `dto.record`
- `dto.anonymousApi`
- `initializer.objectColon`
- `result.unionMatch`
- `aspnet.typedResults`
- `aspnet.controllerThinness`
- `ef.serviceBoundary`
- `ef.querySyntax`
- `nullability.flowMustMatch`
- `manualReview.todo`

Each individual signal should be representable with: `id`, `category`, `severity`, `message`, `file`, `line`, `column`, `snippet`, `suggestion`, `preferredFix`, `fixSafety` (`safe`, `reviewNeeded`, `suggestionOnly`, `none`), `docsUrl`, `relatedCheckDiagnostic`, `clusterKey`, and `confidence`.

## Refactoring order for agents

1. Package declarations, imports, and folder/package shape.
2. Parse/semantic diagnostics from `nlc check`, clustered by root cause.
3. Visibility/casing and copied C# modifiers.
4. DTO classes, records, and object initializer syntax.
5. ASP.NET and EF boundary idioms.
6. Domain results as unions plus exhaustive `match`.
7. Nullability cleanup and removal of suppressions.
8. Manual-review/TODO islands.
9. Format, tests, and final report review.
