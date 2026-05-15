---
sidebar_label: AI C# Migration Contract
title: AI C# to N# Migration Contract
---

# AI C# to N# Migration Contract

AI-assisted C# to N# migration is not a one-shot syntax conversion. It is an iterative refactoring loop with analyzer gates.

## Required loop

```bash
# Produce <nsharp-out> with an AI migration pass that writes idiomatic N# directly.
# Do not rely on syntax-conversion as the migration contract.

cd <nsharp-out>
nlc check --project . --json
nlc idiom --project .
nlc fix --project . --dry-run --json
nlc format --check --project .
nlc test --project .
```

There is intentionally no public `nlc convert` shortcut in the migration contract. Produce the initial `.nl` files with an AI migration pass, record any migration prototype output as scratch evidence only, and still enforce the `check`/`idiom`/`fix`/format/test gates.

## What review-ready N# means

Migrated output must look like N#, not C# with fewer semicolons:

- Use `package` declarations that match the destination folder/package shape.
- Use Go-style visibility and casing: PascalCase for public .NET/framework-discovered surface; camelCase for private helpers, fields, locals, and implementation details.
- Avoid explicit `public`/`private` when casing already communicates visibility.
- Convert DTO-shaped request/response/view-model classes to `record` unless mutation or identity is required.
- Model domain results and expected failures with `union` plus exhaustive `match`; map those results once at the ASP.NET/framework boundary.
- Use canonical N# object initialization: `new Type { Name: value }`.
- Preserve direct ASP.NET Core, EF Core, xUnit, and framework interop at boundaries, but make the N# side idiomatic: typed results/records for APIs, thin controllers/endpoints, services owning EF queries, LINQ method chains rather than C# query syntax.
- Keep ordinary async methods idiomatic with implicit return types, but emit explicit `async func Name(...): Task` or `: Task<T>` when a framework-discovered surface must have a C# `Task` signature; `Task<T>` bodies return bare `T` values.
- Clean up nullability instead of suppressing it.

## Rejected hybrid output

The migration is incomplete if any of these appear without an explicit waiver:

- Copied C# modifiers where N# casing should carry visibility.
- Statement semicolons in migrated N# files, except syntax positions where N# explicitly requires separators.
- C# property blocks: `{ get; set; }`, `{ get; init; }`, or translated backing-property boilerplate that should be a field/record property.
- `_field` private style when a camelCase field is sufficient.
- `IActionResult`, `IResult`, or anonymous DTO defaults when typed results or named records fit the endpoint.
- C# query comprehension syntax in EF/LINQ code.
- `null!`, `default!`, or arbitrary null-forgiving operators used to silence the compiler.
- Unsafe `.Value` on option/result-like values instead of `match`/checked handling.
- Leftover TODO/manual-review islands that are not represented in diagnostics with owner, reason, and fix safety.

## Completion gates

- `nlc check` reports zero errors.
- `nlc idiom` reports zero blocking C# artifacts and no unowned manual-review islands.
- `nlc fix --dry-run --json` has no remaining safe fixes.
- Review-needed fixes are either applied or explicitly waived with rationale.
- Suggestion-only domain/architecture recommendations are accepted or waived; they are never silently ignored.
- Project tests pass after migrated source changes.

## `nlc idiom` report contract

`nlc idiom` exists so humans and agents can evaluate migration quality without scraping prose. Its current contract is `schemaVersion: 2`; stable top-level fields are:

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
- `findings`
- `recommendations`
- `thresholds`

`findings[]` is the agent-actionable v2 surface. Each entry includes `id`, `category`, `severity`, `file`, `line`, `column`, `snippet`, `suggestion`, `fixSafety`, `docsUrl`, `clusterKey`, and `confidence`.

Debt/signal categories should include layout/package issues, visibility/casing issues, C# artifacts (`modifier`, `semicolon`, `propertyBlock`, `underscoreField`, null/default-forgiving), DTO-to-record opportunities, object-initializer cleanup, union/match adoption, ASP.NET typed result adoption, EF service-boundary cleanup, query-syntax cleanup, nullability flow, and manual-review TODOs.
