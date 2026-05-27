# AI C# to N# Migration Contract

Status: implementation-facing contract
Audience: AI agents, converter authors, CLI/analyzer implementers, reviewers

AI-assisted C# to N# migration is not a one-shot syntax conversion. The contract is an iterative refactoring loop:

1. Inventory the C# project and choose the migration slice.
2. Convert or sketch the initial N# files with `package` declarations and the target folder shape.
3. Run `nlc check --project <out> --json` and cluster diagnostics by code/category before editing.
4. Run `nlc fix --project <out> --dry-run --json`; apply safe fixes, inspect review-needed fixes, and never auto-apply architecture/domain suggestions.
5. Refactor one cluster at a time, then rerun `nlc check`, `nlc fix --dry-run`, formatting, and tests.
6. Stop only when the gates below pass or every remaining review-needed item has an explicit diagnostic-backed waiver.

## Required idiomatic N# output

Migrated output must look like N#, not C# with fewer semicolons:

- Use `package` declarations that match the destination folder/package shape. Group framework boundaries, domain models, services, endpoints/controllers, and tests deliberately.
- Use Go-style visibility and casing: PascalCase for public .NET/framework-discovered surface, camelCase for private helpers, fields, locals, and implementation details. Avoid explicit `public`/`private` when casing already communicates visibility.
- Convert DTO-shaped request/response/view-model classes to `record` unless mutation or identity is required.
- Model domain results and expected failures with `union` plus exhaustive `match`; map those results once at the ASP.NET/framework boundary.
- Use canonical N# object initialization: `new Type { Name: value }`, never C# assignment initializers inside migrated N#.
- Preserve direct ASP.NET Core, EF Core, xUnit, and framework interop at boundaries, but make the N# side idiomatic: typed results/records for APIs, thin controllers/endpoints, services owning EF queries, LINQ method chains rather than C# query syntax.
- Keep ordinary async methods idiomatic with implicit return types, but emit explicit `async func Name(...): Task` or `: Task<T>` when a framework-discovered surface must have a C# `Task` signature; `Task<T>` bodies return bare `T` values.
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
- Leftover TODO/manual-review islands that are not represented in `nlc check`, `nlc lint`, or `nlc fix --dry-run` output with owner, reason, and fix safety.

## CLI quality gates

An AI agent should run this loop from the destination N# project root:

```bash
# Produce <nsharp-out> with an AI migration pass that writes idiomatic N# directly.
# Do not rely on syntax-conversion as the migration contract.

cd <nsharp-out>
nlc check --project . --json
nlc fix --project . --dry-run --json
nlc format --check --project .
nlc test --project .
```

Completion gates:

- `nlc check` reports zero errors.
- `nlc fix --dry-run --json` has no remaining safe fixes.
- Review-needed fixes are either applied or explicitly waived with rationale.
- Suggestion-only domain/architecture recommendations are accepted or waived; they are never silently ignored.
- Project tests pass after migrated source changes.

There is intentionally no public `nlc convert` shortcut in the migration contract. Produce the initial `.nl` files with an AI migration pass and still enforce the `check`/`fix`/format/test gates.

## Refactoring order for agents

1. Package declarations, imports, and folder/package shape.
2. Parse/semantic diagnostics from `nlc check`, clustered by root cause.
3. Visibility/casing and copied C# modifiers.
4. DTO classes, records, and object initializer syntax.
5. ASP.NET and EF boundary idioms.
6. Domain results as unions plus exhaustive `match`.
7. Nullability cleanup and removal of suppressions.
8. Manual-review/TODO islands.
9. Format, tests, and final review.
