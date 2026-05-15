# AI Migration Recipe Library from COTM Clusters

Status: field recipe library from COTM migration artifacts
Audience: AI migration agents, reviewers, N# CLI/tooling implementers

This is not a one-shot converter playbook. The COTM evidence says the scalable path is a loop: capture diagnostics, cluster by root cause, apply one recipe family, rerun checks/tests, then advance. Prototype converter output may be useful scratch input, but it is not the contract and should not be exposed as a public `nlc convert` promise.

## Evidence base

The recipes below are grounded in these COTM artifacts and task handoffs:

| Artifact / task | Evidence used | Commands or files |
| --- | --- | --- |
| `t_d28776a7` baseline benchmark | 79 failure/debt clusters across Entities/API/Tests; owners, risk, recipe families, redaction audit | `docs/nsharp-conversion/baseline-benchmark-20260514T213001Z/failure-clusters.json`; `nlc check/lint/idiom/fix --dry-run/test` for Entities, API, Tests |
| `t_0bf73bad` Entities green slice | Entities had 0 `nlc check` errors, 0 diagnostic clusters, focused `dotnet build` passed; residual debt was idiom/lint quality, not compile blockers | `entities-check-20260514-green-slice.json`; `entities-diagnostic-clusters-20260514-green-slice.json`; `entities-idiom-20260514-green-slice.json`; `dotnet build cotm-backend-api/CongregationOfTheMission.Entities/...` |
| `t_9beefea6` API green slice | Representative typed ASP.NET controller routes, DTO records, thin service, route snapshot; named IL backend gap for method attributes | `api-green-slice-20260514/route-snapshot.json`; `green-slice-check.json`; `green-slice-build.log`; Codex review `CONCEPT_LOOKS_SOUND` |
| Sample diagnostic cluster | Missing import/qualification cluster shape for `UserManager`/`RoleManager` | `docs/examples/cotm-diagnostic-clusters.sample.json`, cluster `diag-598763f0`, recipe `converter:missing-import-qualification-or-rename` |
| Sample idiom v2 report | Idiom finding IDs and categories for null-forgiving and object initializer debt | `docs/examples/cotm-idiom-v2.sample.json`, findings `idiom-v2-artifact-nullforgiving-cotm-backend-api-models-loginrequest-nl-6-27` and `idiom-v2-initializer-objectcolon-cotm-backend-api-models-usersummary-nl-31-9` |

Assumptions:

- Recipes operate on an already-created N# migration workspace.
- Public .NET/framework-discovered names are preserved when ASP.NET Core, EF Core, xUnit, JSON serialization, or C# callers require them.
- Review gates are required for route contracts, persistence behavior, auth, validation, and nullability semantics.
- Secret-bearing logs are never copied into docs; COTM baseline artifacts must remain redacted.

## Standard recipe loop

Every recipe uses the same control loop:

1. Capture `git status --short`, the target project root, and the exact command that produced the evidence.
2. Run `nlc query diagnostics --project <project> --clusters --json` or `nlc check --project <project> --json`.
3. Run `nlc idiom --project <project>` when the issue is C# artifact debt or N# idiom drift.
4. Pick one recipe family and edit only the files in that cluster.
5. Run the narrowest proving command for the recipe.
6. Run a broader gate only when the targeted command is green.
7. Record remaining clusters, waivers, and test gaps.

Minimum validation command set:

```bash
nlc check --project <project> --json
nlc query diagnostics --project <project> --clusters --json
nlc idiom --project <project>
nlc fix --project <project> --dry-run --json
nlc format --check --project <project>
nlc test --project <project>
```

Use `dotnet build` or `dotnet test` when the recipe touches SDK/MSBuild/backend integration or framework interop.

## Recipe 1: diagnostic triage before editing

Use when:

- `nlc check` has many errors.
- The same error category appears across many files.
- Later errors look dependent on earlier parser, import, or type-resolution failures.

Signals:

- Cluster categories: `identifier-resolution`, `type-resolution`, parser/syntax, duplicate generated `<error>` types, missing package declarations, wrong package declarations.
- Repeated diagnostic codes, e.g. `NL301` undefined identifiers in the sample cluster.
- `failure-clusters.json` groups with shared `recipe`, `risk`, or owner.
- COTM baseline evidence: `t_d28776a7` found 79 failure/debt groups, so raw terminal errors were not actionable enough.

Edits:

- Do not edit first. Sort clusters in this order: parse blockers, package/import/type resolution, symbol casing/signatures, DTO/object initialization/nullability, ASP.NET/EF boundaries, tests, idiom audit.
- Collapse dependent errors under the root cause. If one missing import produces many member/type errors, fix the import first.
- Add owner/risk/recipe fields to the local artifact if the cluster file lacks them.

COTM before:

```json
{
  "id": "diag-598763f0",
  "category": "identifier-resolution",
  "recipe": "converter:missing-import-qualification-or-rename",
  "relatedDiagnostics": [
    { "code": "NL301", "message": "Undefined variable 'UserManager'" },
    { "code": "NL301", "message": "Undefined variable 'RoleManager'" }
  ],
  "nextCommand": "nlc query inspect --file cotm-backend-api/AuthController.nl --pos 42:17"
}
```

COTM after:

```json
{
  "cluster_id": "imports-authcontroller-identity-managers",
  "root_cause": "missing Identity imports or qualification for manager types",
  "recipe": "imports-and-type-qualification",
  "risk": "mechanical-until-auth-behavior-changes",
  "expected_validation": [
    "nlc check --project cotm-backend-api/CongregationOfTheMission.Api --json",
    "nlc query diagnostics --project cotm-backend-api/CongregationOfTheMission.Api --clusters --json"
  ]
}
```

Tests/gates:

- `nlc query diagnostics --project <project> --clusters --json` must show reduced cluster count or a different root blocker.
- If cluster count does not drop after two focused iterations, block for a compiler/tooling or domain decision.

## Recipe 2: imports, packages, and type qualification

Use when:

- Diagnostics report undefined identifiers, missing types, or wrong package shape.
- Idiom report flags `usingDirectives`, `namespaceDeclarations`, `missingPackageDeclarations`, or `wrongPackageDeclarations`.
- Framework symbols are present in C# source but missing in N# output.

Signals:

- `NL301 Undefined variable '<TypeName>'`.
- Cluster recipe similar to `missing-import-qualification-or-rename`.
- `nextCommand` points to `nlc query inspect --file ... --pos ...`.
- Baseline COTM API/Tests check failures in `t_d28776a7` before Entities were cleaned.

Edits:

- Add or correct the N# `package` declaration first.
- Replace C# `using` leftovers with N# `import` lines.
- Prefer explicit import/qualification over renaming a framework type.
- Keep public framework-discovered names stable; only rename private helpers when casing/visibility requires it.

COTM before:

```n#
package CongregationOfTheMission.Api

func buildManagers() {
    userManager := UserManager.Create()
    roleManager := RoleManager.Create()
}
```

COTM after:

```n#
import Microsoft.AspNetCore.Identity

package CongregationOfTheMission.Api

func buildManagers() {
    userManager := UserManager.Create()
    roleManager := RoleManager.Create()
}
```

Tests/gates:

- `nlc check --project <project> --json` for semantic resolution.
- `nlc query inspect --file <file> --pos <line>:<column>` on the previously missing type.
- Focused `dotnet build` when imports affect SDK/framework integration.

## Recipe 3: DTO classes to records

Use when:

- C# request/response/view model classes only carry data.
- Idiom report flags `dto.record` or `dto.anonymousApi`.
- ASP.NET endpoints return anonymous shapes or EF entities directly.

Signals:

- `signals.dtoClasses.count > 0` or `findings.category == "dto.record"`.
- API green-slice evidence from `t_9beefea6`: route snapshot used `PersonSummaryDto`, `LocationSummaryDto[]`, and `CarePlanSummaryDto` rather than anonymous payloads.
- COTM contract requires DTO records for API boundaries unless mutation/identity is required.

Edits:

- Convert immutable DTO classes to `record`.
- Keep serialized member names stable when route contracts require them.
- Project EF entities into DTO records before returning from controllers/endpoints.
- Do not convert domain entities or EF tracked types to records just because they look property-heavy.

COTM before:

```n#
class PersonSummaryDto {
    Id: Guid
    FullName: string
    LocationName: string?
}
```

COTM after:

```n#
record PersonSummaryDto(id: Guid, fullName: string, locationName: string?)
```

Tests/gates:

- `nlc check --project <project> --json`.
- Route snapshot or serialization approval test for API payload names.
- Affected endpoint tests if DTO shape changes externally visible JSON.

## Recipe 4: object initialization syntax

Use when:

- Migrated code still uses C# assignment initializers inside object literals.
- Idiom report finding category is `initializer.objectColon`.

Signals:

- `docs/examples/cotm-idiom-v2.sample.json` finding `idiom-v2-initializer-objectcolon-cotm-backend-api-models-usersummary-nl-31-9`.
- Snippet shape: `Name = user.Name` inside `new Type { ... }`.
- `fixSafety: "safe"` for pure syntax replacement.

Edits:

- Replace `Property = value` with `Property: value` inside object initializers.
- Do not change assignment statements outside initializer context.
- Preserve PascalCase member names when initializing public .NET members.

COTM before:

```n#
return new UserSummary {
    Id = user.Id,
    Name = user.Name
}
```

COTM after:

```n#
return new UserSummary {
    Id: user.Id,
    Name: user.Name
}
```

Tests/gates:

- `nlc idiom --project <project>` should remove `initializer.objectColon` findings.
- `nlc check --project <project> --json` should stay green or reduce syntax/semantic debt.
- `nlc fix --project <project> --dry-run --json` should report no remaining safe initializer fixes in the touched files.

## Recipe 5: nullability and suppression cleanup

Use when:

- Migrated code contains `null!`, `default!`, unsafe `.Value`, or nullable flow hacks.
- Compiler warnings are suppressed instead of modeled.
- COTM idiom report flags high-severity nullability findings.

Signals:

- `findings.category == "artifact.nullForgiving"` or `artifact.defaultForgiving`.
- Sample finding `idiom-v2-artifact-nullforgiving-cotm-backend-api-models-loginrequest-nl-6-27` with snippet `email: string = default!`.
- `nullability.flowMustMatch`, unsafe `.Value`, or repeated nullable warnings in generated/build output.

Edits:

- Choose the actual model: required, nullable, union/result/option, or guarded value.
- Use guards at framework boundaries for request payloads.
- Use `match` for result/option/domain failures.
- Do not globally silence nullable warnings.

COTM before:

```n#
record LoginRequest {
    email: string = default!
    password: string = default!
}
```

COTM after, required request shape:

```n#
record LoginRequest(email: string, password: string)
```

COTM after, optional/partial request shape:

```n#
record LoginRequest(email: string?, password: string?)

func validateLogin(request: LoginRequest): LoginValidation {
    if request.email == null || request.password == null {
        return LoginValidation.MissingCredentials
    }

    return LoginValidation.Valid(request.email, request.password)
}
```

Tests/gates:

- `nlc idiom --project <project>` must remove null-forgiving/default-forgiving findings or record explicit waivers.
- Add or run validation tests for missing/empty request fields.
- Run affected auth/controller tests because nullability edits can change behavior.

## Recipe 6: EF Core service-boundary cleanup

Use when:

- Controllers contain EF query logic directly.
- API endpoints return EF entities.
- C# query comprehension or late materialization hides projection behavior.
- Idiom categories include `ef.serviceBoundary` or `ef.querySyntax`.

Signals:

- `from ... in ... select ...` query syntax.
- `DbContext` injected directly into broad controllers instead of a thin boundary.
- `ToListAsync()` before DTO projection.
- COTM recipe scope from `t_d28776a7`: API/Entities separated; Entities green slice reached compile/build stability without DB schema changes.

Edits:

- Keep EF entities and schema untouched unless the task explicitly owns persistence changes.
- Move query logic to a service/repository boundary.
- Use method-chain LINQ, `AsNoTracking()` for read paths, projection before materialization, and DTO records at API boundaries.
- Preserve tracking where updates are intentional.

COTM before:

```n#
async func GetPerson(id: Guid): Task<ActionResult<Person>> {
    person := await db.People.FirstOrDefaultAsync(p => p.Id == id)
    if person == null {
        return NotFound()
    }

    return person
}
```

COTM after:

```n#
async func GetPerson(id: Guid): Task<ActionResult<PersonSummaryDto>> {
    result := await peopleService.findSummary(id)

    return match result {
        PersonLookup.Found(summary) => Ok(summary)
        PersonLookup.NotFound => NotFound()
    }
}

async func findSummary(id: Guid): Task<PersonLookup> {
    summary := await db.People
        .AsNoTracking()
        .Where(p => p.Id == id)
        .Select(p => new PersonSummaryDto(p.Id, p.FullName, p.Location.Name))
        .FirstOrDefaultAsync()

    if summary == null {
        return PersonLookup.NotFound
    }

    return PersonLookup.Found(summary)
}
```

Tests/gates:

- Focused service tests with representative present/not-found rows.
- `dotnet test --filter <affected EF/API tests>` when test infrastructure exists.
- If database fixtures/secrets are unavailable, record a waiver and require route/service-level compile checks; do not claim behavioral parity.

## Recipe 7: ASP.NET boundary typing and thin controllers

Use when:

- Endpoints return `IActionResult`, anonymous objects, raw EF entities, or broad controller methods with business logic.
- Framework attributes and route declarations must be preserved.
- Route behavior is the public contract.

Signals:

- Idiom categories: `aspnet.typedResults`, `aspnet.controllerThinness`, `dto.anonymousApi`.
- API green-slice route snapshot from `t_9beefea6`: `GET /api/green-slice/people/{id}` returns `PersonSummaryDto`; `GET /api/green-slice/locations` returns `LocationSummaryDto[]`; `POST /api/green-slice/care-plans` returns `CarePlanSummaryDto`.
- Known backend blocker from `t_9beefea6`: `NL103` for ASP.NET `HttpGet`/`HttpPost` method attribute emission.

Edits:

- Preserve route templates, verbs, auth attributes, and binding attributes.
- Make controllers/endpoints thin: bind, validate, call service, map result.
- Return named DTO records and typed `ActionResult<T>`/typed results.
- If the compiler/backend cannot emit an attribute yet, record it as a tooling blocker instead of rewriting routes to hide the gap.

COTM before:

```n#
[HttpGet("people/{id}")]
async func GetPerson(id: Guid): Task<IActionResult> {
    person := await db.People.FindAsync(id)
    if person == null {
        return NotFound()
    }

    return Ok(new { person.Id, person.FullName })
}
```

COTM after:

```n#
[HttpGet("people/{id}")]
async func GetPerson(id: Guid): Task<ActionResult<PersonSummaryDto>> {
    lookup := await peopleService.findSummary(id)

    return match lookup {
        PersonLookup.Found(person) => Ok(person)
        PersonLookup.NotFound => NotFound()
    }
}
```

Tests/gates:

- Route snapshot comparison for method/path/handler/return type.
- Focused API tests for 200/404/400 branches if infrastructure exists.
- `nlc check` and `dotnet build`; if `NL103` remains, mark the recipe applied but backend-blocked.

## Recipe 8: xUnit and test migration

Use when:

- Test projects fail after source migration.
- Test files retain C# ceremony or framework fixture patterns that do not match N# idioms.
- `nlc test` passes but is known weak/no-op evidence.

Signals:

- COTM baseline `t_d28776a7`: Tests project `check`, `lint`, and `fix_dry_run` failed; `test` passed but was labeled weak/no-op baseline evidence.
- Attributes like `[Fact]`, `[Theory]`, `[InlineData]` are required framework surface, but the body can still be idiomatic N#.
- Excessive class fixture state, `_field` style, semicolons, and C# property boilerplate.

Edits:

- Preserve xUnit attributes and externally discovered test method names.
- Convert private test helpers/fields to camelCase N# style where safe.
- Prefer small arrange/act/assert tests with explicit DTO/service inputs.
- Avoid relying on `nlc test` alone until it proves real test discovery and execution for the project.

COTM before:

```n#
public class PeopleControllerTests {
    private readonly TestDb _db;

    [Fact]
    public async Task GetPerson_ReturnsNotFound() {
        var controller = new PeopleController(_db);
        var result = await controller.GetPerson(Guid.NewGuid());
        Assert.IsType<NotFoundResult>(result);
    }
}
```

COTM after:

```n#
class PeopleControllerTests {
    db: TestDb

    [Fact]
    async func GetPerson_ReturnsNotFound(): Task {
        controller := new PeopleController(db)
        result := await controller.GetPerson(Guid.NewGuid())
        Assert.IsType<NotFoundResult>(result.Result)
    }
}
```

Tests/gates:

- `nlc check --project <tests-project> --json`.
- `nlc lint --project <tests-project> --json` or `nlc idiom --project <tests-project>` for C#-ism cleanup.
- `dotnet test <tests-project>` or a focused `--filter` command. If unavailable, explicitly label the gap.

## Recipe selection matrix

| First failing signal | Prefer recipe | Risk | Proving command |
| --- | --- | --- | --- |
| Parser/syntax clusters dominate | Diagnostic triage, then syntax-local fix | Mechanical | `nlc check --project <project> --json` |
| `NL301 Undefined variable` or missing types | Imports/packages/type qualification | Mechanical unless public API changes | `nlc query inspect`, `nlc check` |
| `dto.record`, anonymous API DTOs | DTO records | Review-needed for serialized contracts | Route/serialization tests, `nlc check` |
| `initializer.objectColon` | Object initialization syntax | Safe/mechanical | `nlc idiom`, `nlc fix --dry-run` |
| `artifact.nullForgiving`, `default!`, unsafe `.Value` | Nullability cleanup | Review-needed | Validation tests, `nlc idiom`, `nlc check` |
| EF in controllers, query syntax, entity returns | EF service boundary cleanup | Review-needed/human for persistence semantics | Service/API tests, `dotnet test` |
| `IActionResult`, anonymous endpoints, route contract drift | ASP.NET boundary typing | Human-decision for route/auth changes | Route snapshot, API tests, `dotnet build` |
| Test project `check`/`lint` fails or no-op `nlc test` | xUnit/test migration | Review-needed | `dotnet test`, `nlc check` |

## Reviewer gate

Use a reviewer gate when a recipe affects:

- Public routes, status codes, auth, validation, or serialized DTO contracts.
- EF tracking, schema, transaction boundaries, or query semantics.
- Nullability choices that can reject or accept different user input.
- Any compiler/tooling workaround that might hide an N# backend gap.

The COTM API green slice used Codex review and got `CONCEPT_LOOKS_SOUND`; keep that pattern for future migration slices. A reviewer should receive the artifact IDs, exact commands, route/test evidence, and a list of known gaps such as the `NL103` method attribute emission blocker.

## Done criteria for a migrated slice

A slice is done only when all of these are true or explicitly waived with evidence:

- `nlc check` is zero-error for the target slice.
- `nlc query diagnostics --clusters` has no unowned compiler diagnostic clusters.
- `nlc idiom` has no blocking C# artifact findings in the touched files.
- `nlc fix --dry-run` has no remaining safe fixes for the slice.
- Route snapshots, focused service tests, or `dotnet test` cover behavior changed by the recipe.
- Build/tooling blockers are named directly, not hidden behind converter framing.
- The handoff records artifact paths, commands, remaining risks, and reviewer result.
