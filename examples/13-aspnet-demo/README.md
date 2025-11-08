# ASP.NET Core Demo Application

This directory was intended to showcase N# in a production ASP.NET Core application. During implementation, we discovered several language gaps that need to be addressed.

## Current Status

⚠️ **PARTIALLY IMPLEMENTED** - Blocked by compiler limitations

## What We Built

1. **Reorganized Examples** - All examples now in numbered, organized directories (01-hello-world/, 02-variables-and-types/, etc.)
2. **Task Management API Structure** - Complete API design in N# syntax
3. **Gap Documentation** - Comprehensive list of compiler limitations discovered

## Key Findings

### What Works ✅

- **Basic classes and records**
- **Constructor chaining** with `base()` and `this()`
- **Pattern matching** for control flow
- **Async/await** syntax
- **Properties** (simple auto-properties)
- **Attributes** on classes and members
- **Type inference** with `:=`

### What Needs Work ❌

1. **External Type Resolution** - Compiler doesn't resolve types from imported .NET assemblies
   - `import Microsoft.AspNetCore.Builder` doesn't make `WebApplication` available
   - Type checker needs assembly metadata loading

2. **String Enums** - `enum Status: string { ... }` syntax not supported
   - Workaround: Use classes with static string constants

3. **Override Methods** - `override func` syntax not working
   - Blocks EF Core `OnModelCreating` override

4. **Property Accessors** - `{ get; set; }` syntax not recognized
   - N# uses simpler property syntax

5. **Null-Forgiving Operator** - `null!` not supported
   - Minor issue, easy workaround

## Workaround

For now, ASP.NET Core apps should:
1. Write `Program.cs` in C# (entry point, app configuration)
2. Write business logic, controllers, services in N#
3. Transpile N# to C# and include in project

## Example

```csharp
// Program.cs (C#)
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers();
builder.Services.AddDbContext<AppDbContext>(/*...*/);
var app = builder.Build();
app.MapControllers();
app.Run();
```

```n#
// TasksController.nl (N#)
[ApiController]
[Route("api/tasks")]
class TasksController : ControllerBase {
    db: AppDbContext

    constructor(context: AppDbContext) {
        db = context
    }

    [HttpGet]
    func GetAll(): Task<IActionResult> async {
        tasks := await db.Tasks.ToArrayAsync()
        return Ok(tasks)
    }
}
```

This hybrid approach works today and showcases N#'s strengths while avoiding compiler limitations.

## Next Steps

See `TaskManagementApi/GAPS.md` for detailed gap analysis and recommended fixes.

**Priority Task:** Implement assembly metadata resolution in the type checker (Task 030).
