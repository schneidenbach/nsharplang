# Task 034: Test and Document Remaining ASP.NET Core Gaps

**Priority:** Medium (Completeness - close out GAPS.md)
**Dependencies:** Task 030 (Assembly Resolution) - Completed
**Estimated Effort:** Small (2-3 hours)
**Status:** Not started

## Goal

Verify that all gaps identified in `examples/13-aspnet-demo/TaskManagementApi/GAPS.md` are either resolved or documented as known limitations.

## Background

Task 030 (Compiler Enhancements) implemented:
- ✅ Gap 1: External Type Resolution from Imports
- ✅ Gap 2: Boolean Type Inference from External Methods

This task verifies those fixes work end-to-end and addresses any remaining issues.

## Gaps from GAPS.md

### Gap 1: External Type Resolution ✅ (Should be fixed)

**Test:**
```n#
import Microsoft.AspNetCore.Builder

package TaskManagementApi

func Main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)  // Should work now
    app := builder.Build()
    app.Run()
}
```

**Verification:**
- [ ] Create test file with above code
- [ ] Run `nsharp transpile Program.nl`
- [ ] Verify no error NL103 (Undefined identifier 'WebApplication')
- [ ] Verify transpiled C# is correct
- [ ] Add integration test to test suite

### Gap 2: Boolean Type Inference ✅ (Should be fixed)

**Test:**
```n#
import Microsoft.AspNetCore.Builder

func Main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)
    app := builder.Build()

    if app.Environment.IsDevelopment() {  // Should work now
        print "Development mode"
    }
}
```

**Verification:**
- [ ] Create test file with above code
- [ ] Run `nsharp transpile Program.nl`
- [ ] Verify no error NL202 (If condition must be boolean)
- [ ] Verify type inference correctly identifies `IsDevelopment()` returns bool
- [ ] Add integration test to test suite

### Gap 3: Null-Coalescing with Methods 🟡 (Needs testing)

**Test:**
```n#
record TaskDto {
    Title: string?
    Description: string?
}

func ProcessTask(dto: TaskDto) {
    title := dto.Title ?? "Untitled"
    description := dto.Description ?? "No description"

    print title
    print description
}
```

**Verification:**
- [ ] Create test file with above code
- [ ] Verify null-coalescing operator works with nullable properties
- [ ] Verify type inference: `title` should be `string` (non-nullable)
- [ ] Add test to test suite
- [ ] Document behavior in DESIGN.md

## Additional Gaps to Test

### Gap 4: Attributes with Parameters

**Test:**
```n#
import Microsoft.AspNetCore.Mvc

[ApiController]
[Route("api/tasks")]
class TasksController : ControllerBase {

    [HttpGet]
    func GetAll(): IActionResult {
        // ...
    }

    [HttpGet("{id}")]
    func GetById(id: Guid): IActionResult {
        // ...
    }

    [HttpPost]
    func Create([FromBody] dto: CreateTaskDto): IActionResult {
        // ...
    }
}
```

**Verification:**
- [ ] Verify `[Route("api/tasks")]` parses correctly
- [ ] Verify `[HttpGet("{id}")]` parses correctly
- [ ] Verify `[FromBody]` parameter attribute works
- [ ] If not working, document as known limitation

### Gap 5: Property Accessors

**Test:**
```n#
class TaskEntity {
    Id: Guid { get; set; }
    Title: string { get; set; }
    CreatedAt: DateTime { get; init; }
}
```

**Verification:**
- [ ] Check if explicit `{ get; set; }` syntax works
- [ ] Current N# uses implicit properties - verify this works
- [ ] Document the N# approach vs C# approach

### Gap 6: Null-Forgiving Operator

**Test:**
```n#
func Test() {
    name: string? = GetName()
    length := name!.Length  // Null-forgiving operator
}
```

**Verification:**
- [ ] Check if `null!` operator is supported
- [ ] If not, document workaround (explicit null check or cast)
- [ ] Low priority - easy workaround exists

## Implementation Steps

### 1. Create Integration Tests

**File:** `tests/Compiler.Tests/Integration/AspNetCoreTests.cs`

```csharp
public class AspNetCoreIntegrationTests
{
    [Fact]
    public void ExternalTypeResolution_WebApplication_Resolves()
    {
        var source = @"
import Microsoft.AspNetCore.Builder

package TestApp

func Main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)
}";

        var analyzer = CreateAnalyzerWithAspNetCore();
        var result = analyzer.Analyze(Parse(source));

        Assert.True(result.Success);

        var builderVar = result.Scope.GetVariable("builder");
        Assert.NotNull(builderVar);
        Assert.Equal("WebApplicationBuilder", builderVar.Type.Name);
    }

    [Fact]
    public void BooleanInference_IsDevelopment_InfersBoolean()
    {
        var source = @"
import Microsoft.AspNetCore.Builder

func Main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)
    app := builder.Build()

    if app.Environment.IsDevelopment() {
        print ""Dev mode""
    }
}";

        var result = AnalyzeAndTranspile(source);

        Assert.True(result.Success);
        Assert.Contains("if", result.GeneratedCode);
    }

    [Fact]
    public void NullCoalescing_WithNullableProperties_Works()
    {
        var source = @"
record TaskDto {
    Title: string?
    Description: string?
}

func ProcessTask(dto: TaskDto): string {
    title := dto.Title ?? ""Untitled""
    return title
}";

        var result = AnalyzeAndTranspile(source);

        Assert.True(result.Success);
        Assert.Contains("??", result.GeneratedCode);
    }
}
```

### 2. Update GAPS.md

After testing, update the GAPS file with results:

```markdown
# Language Gaps - Resolution Status

## ✅ Gap 1: External Type Resolution (RESOLVED - v1.71)

**Fixed by:** Task 030 Phase 1

**Status:** Works perfectly. The compiler now loads assembly metadata and resolves external types.

**Example:**
```n#
import Microsoft.AspNetCore.Builder

builder := WebApplication.CreateBuilder(args)  // ✅ Works!
```

## ✅ Gap 2: Boolean Type Inference (RESOLVED - v1.71)

**Fixed by:** Task 030 Phase 1

**Status:** Works perfectly. Type inference from external methods fully functional.

## ✅ Gap 3: Null-Coalescing (VERIFIED - v1.71)

**Status:** Already worked, now tested and verified.

**Example:**
```n#
title := dto.Title ?? "Untitled"  // ✅ Works!
```

## Remaining Limitations

### Parameter Attributes

**Status:** 🔴 Not yet supported

**Example:**
```n#
func Create([FromBody] dto: CreateTaskDto)  // ❌ Doesn't work yet
```

**Workaround:** Use implicit binding (ASP.NET Core infers [FromBody] for complex types)

**Tracking:** Task 035 (if needed)

### Null-Forgiving Operator

**Status:** 🟡 Not critical

**Example:**
```n#
length := name!.Length  // May not work
```

**Workaround:** Use explicit null check or cast

**Priority:** Low - workaround is simple
```

### 3. Update Documentation

**File:** `memory/limitations.md`

Remove resolved limitations:
- ~~External type resolution~~
- ~~Boolean type inference from external methods~~

Add any newly discovered limitations.

**File:** `DESIGN.md`

Add section on null-coalescing:

```markdown
### Null-Coalescing Operator

The null-coalescing operator `??` provides a default value when the left side is null:

```n#
title: string? = GetTitle()
displayTitle := title ?? "Untitled"  // displayTitle is string (non-nullable)
```

Type inference:
- If left is `T?` and right is `T`, result is `T` (non-nullable)
- If both are nullable, result is nullable
```

### 4. Create End-to-End Example

**File:** `examples/13-aspnet-demo/MinimalApi/Program.nl`

Create a working minimal ASP.NET Core app entirely in N#:

```n#
import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Http

package MinimalApi

func Main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)
    app := builder.Build()

    app.MapGet("/", () => "Hello from N#!")
    app.MapGet("/time", () => DateTime.Now.ToString())

    if app.Environment.IsDevelopment() {
        print "Running in development mode"
    }

    app.Run()
}
```

**Verification:**
- [ ] Transpile with `nsharp transpile Program.nl`
- [ ] Build with `dotnet build`
- [ ] Run with `dotnet run`
- [ ] Test endpoints with curl
- [ ] Verify no errors

## Success Criteria

- [ ] Gap 1 (External Types) verified as fixed
- [ ] Gap 2 (Boolean Inference) verified as fixed
- [ ] Gap 3 (Null-Coalescing) tested and documented
- [ ] Gap 4 (Attributes) tested - document if not working
- [ ] Gap 5 (Property Accessors) clarified in docs
- [ ] Gap 6 (Null-Forgiving) documented with workaround
- [ ] At least 5 new integration tests
- [ ] GAPS.md updated with resolution status
- [ ] Working minimal ASP.NET Core example
- [ ] All tests pass

## Deliverables

1. **Integration test suite** - AspNetCoreIntegrationTests.cs with 5+ tests
2. **Updated GAPS.md** - Mark resolved gaps, document remaining limitations
3. **Minimal API example** - Working ASP.NET Core app in pure N#
4. **Documentation updates** - DESIGN.md, memory/limitations.md

## Notes

This task is about **verification and documentation**, not new implementation. Task 030 should have resolved the critical gaps. We're just:

1. Making sure it actually works end-to-end
2. Documenting what works and what doesn't
3. Creating examples that prove it works
4. Updating GAPS.md so it's current

If we discover new gaps, we can create separate tasks for them.

## Timeline

- **Testing existing gaps:** 2 hours
- **Integration tests:** 1 hour
- **Documentation updates:** 1 hour
- **Minimal API example:** 30 minutes

**Total:** ~4.5 hours (round to 2-3 hours for the estimate since some may already be done)
