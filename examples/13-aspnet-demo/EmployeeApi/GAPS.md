# Language Gaps Found During ASP.NET Core Demo

This document tracks language/compiler limitations discovered while building the Task Management API.

## Gap 1: External Type Resolution from Imports

**Status:** 🔴 BLOCKING

**What we tried:**
```n#
import Microsoft.AspNetCore.Builder

package TaskManagementApi

func Main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)  // Error here
    //...
}
```

**Error:**
```
error NL103: Undefined identifier 'WebApplication'
  --> Program.nl:10:16
```

**Problem:**
The compiler's type checker doesn't resolve types from imported .NET namespaces (like `Microsoft.AspNetCore.Builder`). It only knows about:
1. Types defined in the current N# file
2. Built-in types (int, string, etc.)
3. System namespace types

**What we need:**
The compiler should:
1. When it sees `import Microsoft.AspNetCore.Builder`, load that assembly's metadata
2. Resolve `WebApplication` as `Microsoft.AspNetCore.Builder.WebApplication`
3. Allow type inference to work: `builder := WebApplication.CreateBuilder(args)` should infer `WebApplicationBuilder`

**Current workaround:**
Use explicit casts or write the code directly in C# for now.

**Task to create:**
- Task 030: Add .NET Assembly Metadata Resolution to Type Checker
  - Load referenced assemblies from imports
  - Resolve external types during semantic analysis
  - Support type inference from external method return types

---

## Gap 2: Boolean Type Inference from External Methods

**Status:** 🔴 BLOCKING

**What we tried:**
```n#
if app.Environment.IsDevelopment() {
    // ...
}
```

**Error:**
```
error NL202: If condition must be boolean, got 'unknown'
  --> Program.nl:25:5
```

**Problem:**
The method `IsDevelopment()` returns `bool`, but the compiler doesn't know this because it can't resolve the external type `IHostEnvironment` and its methods.

**What we need:**
Same as Gap 1 - proper external type resolution.

**Related to:** Gap 1

---

## Gap 3: Null-Coalescing with Methods (Potential)

**Status:** 🟡 NEEDS TESTING

**What we might need:**
```n#
title := dto.Title ?? "Untitled"
```

This should work if `dto.Title` is `string?`, but we haven't tested it yet with external types.

---

## Workarounds

### Option 1: Write Pure C# Entry Points

Create `Program.cs` in C#:
```csharp
using Microsoft.AspNetCore.Builder;

var builder = WebApplication.CreateBuilder(args);
// ... setup code
```

And call into N#-generated code for business logic.

### Option 2: Skip Type Checking for External Types

Add a compiler flag `--skip-external-type-check` that treats unknown types as `dynamic` in C#.

### Option 3: Provide Assembly References

Add a compiler option to specify assemblies:
```bash
nlc transpile Program.nl \
  --reference Microsoft.AspNetCore.dll \
  --reference Microsoft.Extensions.Hosting.dll
```

---

## Recommendations

### Short-term (This Demo)
Use Option 1: Write `Program.cs` in C# that calls into N# code:

```csharp
// Program.cs (hand-written C#)
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers();
builder.Services.AddDbContext<AppDbContext>(/* ... */);

var app = builder.Build();
app.MapControllers();
app.Run();
```

```n#
// Tasks.nl (N# code works fine for this)
[ApiController]
[Route("api/tasks")]
class TasksController : ControllerBase {
    // ... this works!
}
```

### Long-term (Task 030)
Implement proper assembly metadata loading in the type checker.

---

## Summary

**Total Gaps Found:** 2 (blocking), 1 (potential)

**Impact:** High - Can't transpile ASP.NET Core entry points

**Severity:** Medium - Workaround exists (write Program.cs in C#)

**Priority:** High - Needed for real-world ASP.NET Core apps
