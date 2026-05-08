# Idiomatic N# Patterns for ASP.NET Core, EF Core, xUnit, and FluentValidation

Status: blessed implementation handoff
Scope: ASP.NET Core controllers/minimal APIs, EF Core queries, DI, validation, typed results, and tests

## Assumptions

- The SampleMigration converted sources are not present in this repo. This spec is based on the task handoff plus the current N# design/docs/examples in this repository.
- N# stays "Go for .NET": terse syntax, Go-style casing for default visibility, direct .NET interop, no wrapper framework unless interop forces it.
- These are source-style rules for implementers/converter authors. Do not invent new language features to satisfy this document unless called out in "compiler/converter follow-up".

## Core decision

Bless N# code that looks like N# first and ASP.NET/EF second:

- Use PascalCase for public surface consumed by ASP.NET, EF, xUnit, FluentValidation, and C# callers.
- Use camelCase for private injected fields, helper methods, local functions, and implementation state.
- Prefer records/DTOs and explicit result shapes over controller methods returning raw framework abstractions everywhere.
- Keep framework ceremony at the boundary. Business logic belongs in services with small method bodies and plain N# types.

## 1. Dependency injection and visibility

Canonical shape:

```nsharp
import Microsoft.Extensions.Logging
import FluentValidation

class IssuesController : ControllerBase {
    service: IssueService
    validator: IValidator<CreateIssueRequest>
    logger: ILogger<IssuesController>

    constructor(
        service: IssueService,
        validator: IValidator<CreateIssueRequest>,
        logger: ILogger<IssuesController>
    ) {
        this.service = service
        this.validator = validator
        this.logger = logger
    }
}
```

Rules:

- Public framework-discovered types are PascalCase: `IssuesController`, `IssueService`, `CreateIssueRequestValidator`, `AppDbContext`.
- Injected fields are camelCase and have no explicit modifier: `service`, `validator`, `db`, `logger`.
- Constructor parameters are camelCase and usually match the field name.
- Use `this.field = field` when the parameter and field have the same name. Do not use C#-style `_service` fields unless an existing C# interop contract requires it.
- Avoid explicit `private`/`public` when casing already expresses the intended visibility. Use explicit `internal`/`protected` only for real .NET interop needs.
- Register dependencies in `Program.nl`; keep registrations grouped by framework, application services, validation, and EF.

```nsharp
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Default")))

builder.Services.AddScoped<IssueService>()
builder.Services.AddValidatorsFromAssemblyContaining<CreateIssueRequestValidator>()
```

## 2. Controller shape

Canonical controller style:

```nsharp
import Microsoft.AspNetCore.Mvc
import FluentValidation

[ApiController]
[Route("api/issues")]
class IssuesController : ControllerBase {
    service: IssueService
    validator: IValidator<CreateIssueRequest>

    constructor(service: IssueService, validator: IValidator<CreateIssueRequest>) {
        this.service = service
        this.validator = validator
    }

    [HttpGet("{id}")]
    async func Get(id: Guid): ActionResult<IssueDto> {
        issue := await service.GetById(id)
        if issue == null {
            return NotFound()
        }

        return Ok(issue)
    }

    [HttpPost]
    async func Create(request: CreateIssueRequest): ActionResult<IssueDto> {
        validation := await validator.ValidateAsync(request)
        if !validation.IsValid {
            return BadRequest(validation.ToProblemDetails())
        }

        created := await service.Create(request)
        return Created($"/api/issues/{created.Id}", created)
    }
}
```

Rules:

- Use controllers when attribute routing, filters, model binding, `ProblemDetails`, or existing ASP.NET conventions matter.
- Return `ActionResult<T>` for controller endpoints that can fail. Avoid bare `IActionResult` unless the method genuinely returns unrelated result payload types.
- Keep controllers thin: validate, call a service, map result to HTTP.
- Use DTO records for request/response bodies. Do not return EF entities from controllers.
- Use expression-bodied helpers inside services/mappers, not in controller actions where branching and HTTP mapping should stay readable.

## 3. Minimal API / endpoint shape

Canonical minimal API style:

```nsharp
import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Http
import Microsoft.AspNetCore.Http.HttpResults

class IssueEndpoints {
    static func Map(app: WebApplication) {
        group := app.MapGroup("/api/issues")
        group.MapGet("/{id}", Get)
        group.MapPost("/", Create)
    }

    static async func Get(id: Guid, service: IssueService): Results<Ok<IssueDto>, NotFound> {
        issue := await service.GetById(id)
        if issue == null {
            return TypedResults.NotFound()
        }

        return TypedResults.Ok(issue)
    }

    static async func Create(
        request: CreateIssueRequest,
        service: IssueService,
        validator: IValidator<CreateIssueRequest>
    ): Results<Created<IssueDto>, ValidationProblem> {
        validation := await validator.ValidateAsync(request)
        if !validation.IsValid {
            return TypedResults.ValidationProblem(validation.ToDictionary())
        }

        created := await service.Create(request)
        return TypedResults.Created($"/api/issues/{created.Id}", created)
    }
}
```

Rules:

- Prefer `Results<Ok<T>, NotFound, ValidationProblem>` plus `TypedResults.*` for minimal APIs.
- Keep route mapping in a public `Map` method and endpoint handlers as static methods on a feature endpoint class.
- Use ASP.NET parameter injection in endpoint method parameters for services/validators; do not manually resolve from `IServiceProvider`.
- Use lambdas only for trivial endpoints such as health checks. Non-trivial route handlers get named methods.

## 4. EF Core query style

Canonical query style:

```nsharp
import Microsoft.EntityFrameworkCore

class IssueService {
    db: AppDbContext

    constructor(db: AppDbContext) {
        this.db = db
    }

    async func ListOpen(projectId: Guid): List<IssueSummaryDto> {
        return await db.Issues
            .AsNoTracking()
            .Where(issue => issue.ProjectId == projectId && issue.Status == IssueStatus.Open)
            .OrderBy(issue => issue.CreatedAt)
            .Select(issue => new IssueSummaryDto {
                Id: issue.Id,
                Title: issue.Title,
                AssigneeName: issue.Assignee == null ? null : issue.Assignee.DisplayName,
                CreatedAt: issue.CreatedAt
            })
            .ToListAsync()
    }

    async func GetDetails(id: Guid): IssueDetailsDto? {
        return await db.Issues
            .AsNoTracking()
            .Include(issue => issue.Assignee)
            .Include(issue => issue.Comments)
            .Where(issue => issue.Id == id)
            .Select(issue => new IssueDetailsDto {
                Id: issue.Id,
                Title: issue.Title,
                AssigneeName: issue.Assignee == null ? null : issue.Assignee.DisplayName,
                CommentCount: issue.Comments.Count
            })
            .SingleOrDefaultAsync()
    }
}
```

Rules:

- Use LINQ method syntax, not C# query comprehension syntax. Method chains fit N# and convert cleanly.
- Put `.AsNoTracking()` first for read-only queries.
- Use `.Include(...)` only when returning entities or when a later projection actually needs navigation data. Prefer projection over entity graph materialization.
- Put filters before projections; project to DTOs before materializing with `ToListAsync`, `SingleOrDefaultAsync`, etc.
- Keep predicates direct. If a predicate becomes complex, extract a private camelCase helper or a named query method.
- Do not hide EF queries inside controllers. Controllers call services; services own EF.
- Do not use `Result`/`.Wait()` in ASP.NET code. Use `async func` and `await` all the way.

## 5. DTOs, records, and validators

Canonical DTO style:

```nsharp
record CreateIssueRequest {
    Title: string
    Description: string?
    Priority: Priority
    AssigneeId: Guid?
}

record IssueDto {
    Id: Guid
    Title: string
    Description: string?
    Priority: Priority
    AssigneeName: string?
}
```

Canonical FluentValidation style:

```nsharp
import FluentValidation

class CreateIssueRequestValidator : AbstractValidator<CreateIssueRequest> {
    constructor() {
        RuleFor(x => x.Title)
            .NotEmpty()
            .MaximumLength(200)

        RuleFor(x => x.Description)
            .MaximumLength(4000)

        RuleFor(x => x.Priority)
            .IsInEnum()
    }
}
```

Rules:

- Request and response bodies are records unless mutation is required.
- Validators are PascalCase public classes so assembly scanning can discover them.
- Keep validation rules in FluentValidation validators; keep cross-aggregate/business invariants in services.
- Endpoint/controller validation should convert validation failures into `ValidationProblem`/`BadRequest`, not throw.
- Prefer small extension helpers for framework adaptation, for example `ToProblemDetails()` or `ToDictionary()`, but keep them in one shared validation file.

## 6. Typed API results

Controller decision table:

| Situation | Blessed return type |
| --- | --- |
| Always succeeds with a body | `T` or `ActionResult<T>` |
| Can return not found/bad request/etc. | `ActionResult<T>` |
| Multiple unrelated payload shapes | `IActionResult` only as escape hatch |
| No body | `IActionResult` or framework result type |

Minimal API decision table:

| Situation | Blessed return type |
| --- | --- |
| One success shape | `Ok<T>` or `Created<T>` if feasible |
| Success plus expected failures | `Results<Ok<T>, NotFound, ValidationProblem>` |
| Many result cases | Consider a controller or a service result union before falling back to `IResult` |

Rules:

- Minimal APIs should use `TypedResults.*`; controllers should use `Ok(...)`, `NotFound()`, `CreatedAtAction(...)`, etc.
- Avoid returning anonymous objects from public APIs except throwaway examples. Use named DTO records for real endpoints.
- If service logic has domain failures, model them as an N# union or a result record in the service layer, then map once at the HTTP boundary.

```nsharp
union CreateIssueResult {
    Created(IssueDto issue)
    DuplicateTitle(string title)
    InvalidProject(Guid projectId)
}
```

## 7. xUnit and N# tests

Preferred simple N# test style:

```nsharp
import Microsoft.EntityFrameworkCore
import FluentAssertions

setup {
    fixture := new IssueServiceFixture()
}

test "CreateService builds an isolated service" {
    service := fixture.CreateService()

    service.Should().NotBeNull()
}

test "CreateDb uses an isolated in-memory database" {
    first := fixture.CreateDb()
    second := fixture.CreateDb()

    first.Should().NotBeSameAs(second)
}
```

Canonical fixture shape:

```nsharp
class IssueServiceFixture {
    func CreateDb(): AppDbContext {
        options := new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options

        return new AppDbContext(options)
    }

    func CreateService(): IssueService {
        db := CreateDb()
        return new IssueService(db)
    }
}
```

Class-based xUnit interop, when a framework fixture is required:

```nsharp
import Xunit

class IssueApiTests : IClassFixture<WebApplicationFactory<Program>> {
    factory: WebApplicationFactory<Program>

    constructor(factory: WebApplicationFactory<Program>) {
        this.factory = factory
    }

    [Fact]
    async func GetMissingIssueReturns404(): Task {
        client := factory.CreateClient()
        response := await client.GetAsync("/api/issues/00000000-0000-0000-0000-000000000000")
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode)
    }
}
```

Ordinary async N# methods should usually keep the implicit return form (`async func Load(): IssueDto` lowers to the configured async wrapper). Framework interop surfaces are different: if xUnit, ASP.NET, or another .NET framework expects a C# `Task` signature, emit it explicitly:

```nsharp
async func Name(...): Task {
    await WorkAsync()
}

async func LoadIssue(...): Task<IssueDto> {
    return await GetIssueAsync()
}
```

For `Task<T>`, declare `: Task<T>` and return a bare `T` value from the async body; do not return `Task.FromResult(...)` just to satisfy the signature.

Rules:

- Use `test "behavior" { ... }` for ordinary N# unit/integration tests.
- Use class-based xUnit only for interop surfaces that require xUnit fixtures, attributes, or ASP.NET test host types.
- Fixtures are PascalCase public types when xUnit must construct them. Internal test helpers can be camelCase members or local functions.
- Use real components and real in-memory/testcontainer-backed infrastructure; avoid mocks unless an external side effect is impossible to run deterministically.
- Test names describe behavior, not implementation.

## 8. AI-assisted migration cleanup rules for C#-shaped N#

When AI-assisted migration produces C#-shaped N#, implementers should normalize in this order:

1. Rename private fields from `_thing` to `thing`; update constructor assignment to `this.thing = thing`.
2. Convert controller returns from `IActionResult` to `ActionResult<T>` when the success body has a stable DTO type.
3. Convert minimal APIs from `IResult`/anonymous lambdas to named static handlers with `Results<...>` and `TypedResults.*`.
4. Move EF queries out of controllers into services.
5. Replace anonymous response objects with DTO records.
6. Replace hand-written validation branches with FluentValidation validators where rules are input-shape validation.
7. Convert C# query syntax or over-parenthesized LINQ into N# method chains.
8. Convert xUnit fixture-heavy tests into simple `test "..."` blocks unless xUnit fixture interop is required; when keeping class-based xUnit/framework interop, preserve required C# async signatures with explicit `: Task` or `: Task<T>`.

## 9. Compiler migration follow-up checklist

Implementers should verify or add tests for these interop expectations:

- Generic ASP.NET result types parse and emit correctly: `ActionResult<T>`, `Results<Ok<T>, NotFound>`, `Created<T>`, `ValidationProblem`.
- Static imports or fully-qualified references to `TypedResults` and `HttpResults` resolve through ASP.NET shared framework assemblies.
- FluentValidation chained method calls preserve indentation and lambda syntax.
- EF extension methods resolve when `Microsoft.EntityFrameworkCore` is imported and the project references EF packages.
- xUnit fixture interfaces (`IClassFixture<T>`, `IAsyncLifetime`, `IDisposable`) emit the required public members even when N# source uses idiomatic casing.
- xUnit/framework async methods that must be discovered or invoked through C# signatures emit explicit `Task`/`Task<T>` returns rather than implicit async wrappers.
- Migration cleanup rewrites `_field` private backing fields to camelCase fields when safe, but does not rename serialized/public contract members.

## Non-goals

- Do not create an N# web framework abstraction over ASP.NET Core.
- Do not ban ASP.NET conventions that are necessary for model binding, DI, filters, or xUnit discovery.
- Do not force every endpoint into unions. Use unions for domain/service results; use ASP.NET typed results at the HTTP boundary.
- Do not optimize for the converter's easiest output. Optimize for the code humans should maintain after conversion.
