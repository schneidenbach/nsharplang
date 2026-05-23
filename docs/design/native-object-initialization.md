# Native N# Object and DTO Initialization Spec

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Define the canonical N# idiom for DTO/data object creation so converted C# object-initializer code becomes native, consistent N# instead of C# with lighter punctuation.

**Architecture:** N# keeps one named initializer expression for data construction: `new Type { Name: value }`. Records are the default data shape; classes remain for identity, lifecycle, framework integration, and behaviorful mutable state. Tooling owns migration pressure: formatter canonicalizes shape, analyzer/linter rejects C# leftovers, and AI/prototype migration drafts must pass the diagnostic/idiom/fix/format/test loop before review.

**Tech Stack:** N# parser/analyzer/transpiler/IL compiler, `nlc format`, `nlc lint`, ASP.NET Core model binding, System.Text.Json, Entity Framework Core, C# interop.

---

## Decision summary

Canonical answer:

```n#
record CreateIssueRequest {
    Title: string
    Description: string
    Priority: Priority
    Tags: string[] = []
}

request := new CreateIssueRequest {
    Title: "Crash on save",
    Description: "Editor crashes when saving a large file",
    Priority: Priority.High
}
```

Rules:

1. Use `record` for DTOs, request/response payloads, service return data, domain facts, immutable snapshots, and value-like aggregates.
2. Use `class` for services, controllers, framework extension points, EF entities, identity/lifecycle objects, mutable state, inheritance-heavy APIs, and types whose construction must run invariants.
3. Use `new Type { Name: value }` for named data construction. Do not write empty constructor parentheses before an initializer.
4. Use `with { Name: value }` for non-destructive updates to records and record structs.
5. Use constructors when construction has invariants, side effects, dependency injection, or required ordering. Do not hide invariants behind public settable data bags.
6. Do not add anonymous object literals, structural object literals, or a canonical builder pattern for DTO creation in this version.

Non-goals:

- No anonymous object syntax like `{ Title: "x" }`.
- No JavaScript-style object literal inference.
- No special DTO keyword.
- No canonical fluent builders for ordinary DTOs.
- No attempt to erase .NET realities like parameterless constructors, serializers, EF proxying, or public setters where frameworks require them.

## Syntax

### Initializer expression

Preferred:

```n#
value := new TypeName {
    FieldA: exprA,
    FieldB: exprB
}
```

Allowed where target type is explicit:

```n#
value: TypeName = new {
    FieldA: exprA,
    FieldB: exprB
}
```

Rejected or linted as C# leftovers:

```n#
value := new TypeName { FieldA: exprA }   // remove ()
value := new TypeName { FieldA = exprA }    // use : not =
value := new TypeName { FieldA: exprA; }    // use commas/newlines, not semicolons
```

Constructor plus initializer remains supported only when constructor arguments are meaningful:

```n#
options := new JsonSerializerOptions(existingOptions) {
    PropertyNameCaseInsensitive: true,
    PropertyNamingPolicy: JsonNamingPolicy.CamelCase
}
```

`new Type()` by itself remains the zero-argument constructor call:

```n#
items := new List<string>()
```

### Initializer entries

Entries are named assignments to public settable/init-settable properties or accessible fields:

```n#
new WeatherForecast {
    Date: DateOnly.FromDateTime(DateTime.Now),
    TemperatureC: 23,
    Summary: "Warm"
}
```

Accepted entry forms:

- `Name: expression` for fields/properties.
- `[indexExpr] = expression` only for existing CLR indexer initializer interop. This is not the DTO idiom and formatter must not use it in examples unless the example is specifically about indexers.
- Nested initializers as normal expressions.

Rejected by analyzer:

- Unknown member name.
- Duplicate member name.
- Assignment to read-only member outside constructor/init phase.
- Missing required member.
- Positional and named field collision when constructor arguments already bind a member whose initializer also sets it.

### With expression

Records use `with` for copy-and-change:

```n#
updated := issue with {
    Status: new IssueStatus.Closed {
        resolution: "fixed",
        closedAt: DateTime.Now
    }
}
```

Classes should not use `with` unless they explicitly participate in C# record-style clone semantics. Linter warning: "`with` is for record-like data; this type is mutable class state. Prefer a method that names the state transition."

## Type-shape guidance

### Records: default for DTO/data objects

Use records when the type is mostly data and equality/copy semantics are useful.

Good record candidates:

- ASP.NET request/response bodies.
- JSON payload DTOs.
- CLI command results and stats.
- Domain events and immutable snapshots.
- Query/projection results.
- Small value-like configuration snapshots.

Record semantics:

- Body records emit public init-only properties by default.
- Non-nullable fields without defaults are required for N# initialization.
- Fields with defaults are optional at call sites.
- `with` creates a modified copy.
- Generated CLR type must be friendly to System.Text.Json constructor/property binding.

Example:

```n#
record TaskStats {
    Total: int
    TodoCount: int
    InProgressCount: int
    DoneCount: int
}

stats := new TaskStats {
    Total: tasks.Count,
    TodoCount: todoCount,
    InProgressCount: inProgressCount,
    DoneCount: doneCount
}
```

### Positional records: rare and local

Use positional records only when all of these hold:

- The type has 2-3 fields.
- Field order is obvious and stable.
- The type is internal or local to a tight module.
- Call-site readability does not suffer.

Good:

```n#
record Point(x: double, y: double)
origin := new Point(0, 0)
```

Avoid for public DTOs:

```n#
record CreateUserRequest(name: string, email: string, role: string, source: string) // no
```

Prefer:

```n#
record CreateUserRequest {
    Name: string
    Email: string
    Role: string
    Source: string = "api"
}
```

### Classes: behavior, lifecycle, identity, frameworks

Use classes when the object is not just data:

- ASP.NET controllers, hosted services, filters, middleware.
- Dependency-injected services.
- Objects with identity and lifecycle.
- Mutable aggregates whose methods enforce transitions.
- EF Core entities and framework-proxied types.
- Types requiring inheritance or virtual members for framework reasons.

Prefer constructor injection and named transition methods:

```n#
class Routes {
    service: IssueService
    jsonOptions: JsonSerializerOptions

    constructor(svc: IssueService) {
        service = svc
        jsonOptions = new JsonSerializerOptions {
            PropertyNameCaseInsensitive: true,
            PropertyNamingPolicy: JsonNamingPolicy.CamelCase
        }
    }
}
```

Do not make invariant-heavy domain classes initializable data bags:

```n#
// Bad: bypasses validation rules.
account := new Account { Balance: -100, Status: AccountStatus.Active }

// Good: constructor/method names the invariant boundary.
account := Account.Open(initialDeposit)
account.Withdraw(amount)
```

### EF-compatible entities

EF entities are an explicit exception to the record-by-default DTO rule.

Recommended EF shape:

```n#
class IssueEntity {
    Id: int
    Title: string
    Description: string
    Priority: Priority
    CreatedAt: DateTime

    protected constructor() {
        // EF
    }

    constructor(title: string, description: string, priority: Priority) {
        if title.Length == 0 {
            throw new ArgumentException("Title is required")
        }

        Title = title
        Description = description
        Priority = priority
        CreatedAt = DateTime.UtcNow
    }
}
```

Guidance:

- EF entities may expose settable properties for materialization/change tracking.
- EF entities are not API DTOs. Map to records at the boundary.
- Linter should warn when a type annotated/configured as an EF entity is returned directly from a controller or used as a request body.
- Analyzer should not require `init` on EF entity properties when EF compatibility mode is active.

## Required and init-only semantics

### Records

For body records:

```n#
record CreateIssueRequest {
    Title: string
    Description: string
    Priority: Priority
    Tags: string[] = []
}
```

`Title`, `Description`, and `Priority` are required in N# initializers. `Tags` is optional because it has a default.

Compiler behavior:

- N# initializer must provide every required field exactly once.
- Deserialization can still use System.Text.Json-compatible construction. The emitted CLR shape may use required/init properties, a generated constructor, attributes, or a combination, but the N# source rule remains simple: non-defaulted non-nullable record fields are required.
- Nullable fields are optional unless explicitly marked `required`.
- Non-nullable fields with `= default` or another initializer are optional.

### Classes

Classes are mutable by default unless the member says otherwise:

```n#
class Configuration {
    required AppName: string { get; init }
    Version: string { get; init } = "1.0"
    ReloadCount: int = 0
}
```

Class guidance:

- Use `required` sparingly. If the class has invariants, use a constructor instead.
- Use `init` when a framework wants property initialization but the app should not mutate it later.
- Public settable properties are acceptable for EF/framework-bound classes, but should be a deliberate interop choice.

## Formatter and lint expectations

Formatter canonical output:

Short initializers stay inline:

```n#
point := new Point { X: 1, Y: 2 }
```

Multiple fields or long expressions wrap one entry per line:

```n#
options := new JsonSerializerOptions {
    PropertyNameCaseInsensitive: true,
    PropertyNamingPolicy: JsonNamingPolicy.CamelCase
}
```

Canonical choices:

- No empty `()` before initializer braces.
- `:` between member name and value.
- Commas between same-line entries.
- Multiline initializer entries are one per line; formatter may preserve or remove trailing commas, but canonical output should omit the final trailing comma unless the project later standardizes trailing commas globally.
- Opening brace stays on the same line as `new Type`.
- Nested initializers follow the same rules recursively.

Linter rules:

- `NSHxxx`: `new Type { ... }` can be `new Type { ... }`.
- `NSHxxx`: initializer entry uses `=`; use `:`.
- `NSHxxx`: DTO-like class should be a record.
- `NSHxxx`: record-like initializer is missing required fields.
- `NSHxxx`: unknown or duplicate initializer member.
- `NSHxxx`: object initializer bypasses a class constructor that appears to enforce invariants.
- `NSHxxx`: EF entity used directly as request/response DTO.
- `NSHxxx`: positional record is public and has more than three fields; prefer a body record.

## Before/after examples

### API request DTO

Before (copied C#-style migration input, not idiomatic N#):

```csharp
public class CreateIssueRequest {
    public string Title { get; set; }
    public string Description { get; set; }
    public Priority Priority { get; set; }
    public string[] Tags { get; set; }
}

request := new CreateIssueRequest {
    Title = title,
    Description = description,
    Priority = Priority.High,
    Tags = tags
}
```

After:

```n#
record CreateIssueRequest {
    Title: string
    Description: string
    Priority: Priority
    Tags: string[] = []
}

request := new CreateIssueRequest {
    Title: title,
    Description: description,
    Priority: Priority.High,
    Tags: tags
}
```

### Controller/service setup

Before:

```n#
jsonOptions = new JsonSerializerOptions {
    PropertyNameCaseInsensitive = true,
    PropertyNamingPolicy = JsonNamingPolicy.CamelCase
}
```

After:

```n#
jsonOptions = new JsonSerializerOptions {
    PropertyNameCaseInsensitive: true,
    PropertyNamingPolicy: JsonNamingPolicy.CamelCase
}
```

This remains a class because `JsonSerializerOptions` is framework mutable state, not an N# DTO.

### Command result stats

Before:

```n#
return new TaskStats {
    Total = tasks.Count,
    TodoCount = todoCount,
    InProgressCount = inProgressCount,
    DoneCount = doneCount
}
```

After:

```n#
return new TaskStats {
    Total: tasks.Count,
    TodoCount: todoCount,
    InProgressCount: inProgressCount,
    DoneCount: doneCount
}
```

`TaskStats` should be a record because it is immutable return data.

### Domain state transition

Before:

```n#
issue.Status = new IssueStatus.Done()
```

After:

```n#
updated := issue with {
    Status: new IssueStatus.Closed {
        resolution: "fixed",
        closedAt: DateTime.UtcNow
    }
}
```

Use union cases for state variants and `with` for immutable record updates.

### EF boundary mapping

Before:

```n#
app.MapGet("/api/issues/{id}", id => db.Issues.Find(id))
```

After:

```n#
record IssueResponse {
    Id: int
    Title: string
    Description: string
    Priority: Priority
    CreatedAt: DateTime
}

app.MapGet("/api/issues/{id}", id => {
    entity := db.Issues.Find(id)
    return new IssueResponse {
        Id: entity.Id,
        Title: entity.Title,
        Description: entity.Description,
        Priority: entity.Priority,
        CreatedAt: entity.CreatedAt
    }
})
```

The EF class stays EF-shaped; the API returns a record DTO.

## Implementation acceptance criteria

### Parser

- Parses `new Type { A: 1 }` without requiring `()`.
- Continues to parse `new Type()` for constructor calls.
- Parses `new Type(args) { A: 1 }` for CLR/framework interop.
- Parses target-typed `new { A: 1 }` only when semantic context provides the target type; if parser cannot defer this safely, explicitly reject it with a good diagnostic until analyzer support exists.
- Parses nested initializers and `with { A: 1 }` consistently.
- Rejects `A = 1` entries in object initializer position with a diagnostic that says "Use `A: 1` in N# initializers."

### Analyzer

- Resolves initializer member names semantically, not by string grep.
- Reports duplicate and unknown initializer members.
- Checks assignability of each initializer expression to the target member type.
- Checks required record/class members are initialized exactly once.
- Enforces init-only/read-only mutation rules after initialization.
- Allows EF/framework compatibility escape hatches without weakening the record DTO rule globally.
- Warns on object initializer use for classes with non-default constructors that appear to enforce invariants, except when constructor arguments are supplied intentionally.

### Transpiler / IL compiler

- Emits idiomatic C# that preserves .NET semantics: object initializers, init-only properties, required members or generated constructors/attributes as needed.
- Keeps System.Text.Json model binding working for record DTOs.
- Keeps ASP.NET controller/minimal API binding working for request records.
- Keeps EF entities settable/proxyable when declared as classes with EF-compatible constructors/properties.
- Maintains `with` lowering for records and record structs.
- Includes runtime tests for class, record, record struct, nested initializer, CLR type initializer, and `with` expression cases.

### Formatter

- Rewrites `new Type { ... }` to `new Type { ... }` when argument list is empty.
- Formats short initializer as one line when it fits the line width.
- Formats long/multifield initializer as multiline with one entry per line.
- Uses `:` entries in all docs/examples/tests.
- Is idempotent across nested initializers and `with` expressions.

### Linter / fixer

- Provides safe autofix for empty-paren initializer removal.
- Provides safe autofix for `Name = value` to `Name: value` only when parsed in initializer-entry context.
- Provides non-autofix guidance for DTO class-to-record conversion.
- Provides non-autofix warning when EF entity types leak through API boundaries.
- Provides migration-tooling diagnostics for C# leftovers; these feed the AI diagnostic migration loop instead of blessing one-shot syntax conversion.

### AI/prototype migration drafts

- Initial migration drafts should prefer N# records for C# DTO classes with only auto-properties.
- Preserve classes when the C# type has behavior, constructors with invariants, mutable lifecycle, EF attributes/configuration, inheritance/proxies, or framework base classes.
- Normalize object initializers to `new Type { Name: value }` and `with` expressions to `with { Name: value }` during the check/idiom/fix/format/test loop.
- Emit or retain migration notes when unsure whether a class is an EF entity or DTO; do not treat prototype output as review-ready without the diagnostic loop.

### Documentation and examples

- Update `website/docs/types.md` record/class sections to reflect this decision.
- Update `docs/guide/for-csharp-developers.md` with C# object initializer conversion examples.
- Update example projects to remove `new Type { ... }` and `Name = value` initializer leftovers.
- Add an explicit EF entity versus API DTO section.
- Add formatter/linter examples to CLI docs once rule IDs exist.

## Adversarial review note

Project guidance requires Codex review for language design decisions. I attempted a Codex review of this spec and the tentative direction, focusing on CLR/C# interop, System.Text.Json/ASP.NET model binding, EF compatibility, required/init semantics, and whether the syntax is too C#-adjacent. Codex CLI was installed, but the run failed with OpenAI API `401 Unauthorized: Missing bearer or basic authentication in header`. The review should be retried once Codex auth is restored; the highest-value questions to ask are:

- Will body records with required/init-like members bind reliably in ASP.NET Core and System.Text.Json, or does N# need generated constructors/attributes instead of plain init properties?
- Should target-typed `new { ... }` be postponed to avoid confusion with anonymous object literals?
- Is the EF entity escape hatch precise enough to avoid weakening the record-by-default DTO rule?
- Can the linter safely detect invariant-bypassing object initializers without noisy heuristics?

## Risks and mitigations

- Risk: records with init-only required members may not bind in every System.Text.Json/ASP.NET scenario. Mitigation: implementation must include model-binding integration tests before docs call this supported.
- Risk: `new Type { ... }` is still visibly C#-adjacent. Mitigation: keep it because it maps cleanly to CLR, is simple, and avoids inventing structural object literals that N# cannot type soundly yet.
- Risk: linter might over-warn on classes that are intentionally data bags for framework interop. Mitigation: provide attributes/config comments or project-level suppression for EF/framework DTO exceptions.
- Risk: target-typed `new { ... }` can be confused with anonymous object literals. Mitigation: either require target type in analyzer or postpone target-typed initializer support until diagnostics can make the distinction clear.

## Recommendation

Adopt this spec as the N# DTO/object initialization rule. It is conservative, CLR-friendly, easy to migrate from C#, and gives the formatter/linter a concrete cleanup target. The important line is not "records everywhere"; it is "records for data, classes for lifecycle, named initializers for explicit data construction, constructors for invariants."
