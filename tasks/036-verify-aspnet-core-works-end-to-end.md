# Task 036: Verify ASP.NET Core Demo Works End-to-End

**Priority:** Critical (Production readiness verification)
**Dependencies:** Task 030 (Assembly Resolution) - Completed
**Estimated Effort:** Medium (3-5 hours)
**Status:** Not started

## Goal

Verify that the TaskManagementApi ASP.NET Core demo actually works end-to-end. This is not just about transpilation - the entire application must build, run, and handle real HTTP requests successfully.

## Success Criteria - MANDATORY

This task is **NOT COMPLETE** until ALL of the following work:

- [ ] All .nl files transpile to valid C# without errors
- [ ] `dotnet build` succeeds with zero errors
- [ ] `dotnet run` starts the web server successfully
- [ ] Swagger UI loads at https://localhost:5001/swagger
- [ ] GET /api/tasks returns 200 OK (empty array initially)
- [ ] POST /api/tasks creates a new task
- [ ] GET /api/tasks/{id} retrieves the created task
- [ ] PUT /api/tasks/{id} updates the task
- [ ] DELETE /api/tasks/{id} deletes the task
- [ ] GET /api/tasks/status/{status} filters by status
- [ ] GET /api/tasks/priority/{priority} filters by priority
- [ ] Database (tasks.db) is created and persists data
- [ ] All validation works (required fields, max lengths, etc.)

## Current State

The TaskManagementApi has three .nl files:

1. **Program.nl** - ASP.NET Core entry point with WebApplication setup
2. **Database.nl** - EF Core DbContext
3. **Tasks.nl** - Entity, DTOs, Controller, and validation logic

**Key features being tested:**
- External type resolution (WebApplication, DbContext, etc.)
- Constructor chaining with base()
- Attributes ([HttpGet], [Route], etc.)
- Async functions returning IActionResult
- Pattern matching (null checking)
- LINQ queries (.Where(), .ToArrayAsync())
- Lambda expressions
- Object initializers

## Implementation Steps

### 1. Navigate to Project Directory

```bash
cd examples/13-aspnet-demo/TaskManagementApi
```

### 2. Transpile All .nl Files

```bash
# Using the CLI
dotnet run --project ../../../src/Cli/Cli.csproj -- transpile Program.nl > Program.g.cs
dotnet run --project ../../../src/Cli/Cli.csproj -- transpile Database.nl > Database.g.cs
dotnet run --project ../../../src/Cli/Cli.csproj -- transpile Tasks.nl > Tasks.g.cs
```

**Expected Result:**
- Three .g.cs files generated
- No transpilation errors
- Generated C# should be valid and idiomatic

**If this fails:**
- Check error messages
- Verify Task 030 (Assembly Resolution) is working
- Fix any parser/analyzer issues
- DO NOT PROCEED until transpilation works

### 3. Update .csproj to Include Generated Files

**File:** `TaskManagementApi.csproj`

Uncomment the Compile ItemGroup:

```xml
<ItemGroup>
  <Compile Include="Program.g.cs" />
  <Compile Include="Database.g.cs" />
  <Compile Include="Tasks.g.cs" />
</ItemGroup>
```

**Or better:** Add a wildcard pattern:
```xml
<ItemGroup>
  <Compile Include="*.g.cs" />
</ItemGroup>
```

### 4. Build the Project

```bash
dotnet build
```

**Expected Result:**
- Build succeeds with 0 errors, 0 warnings (ideally)
- Produces `bin/Debug/net9.0/TaskManagementApi.dll`

**If this fails:**
- Examine build errors
- Check that generated C# is syntactically correct
- Verify all NuGet packages are restored
- Fix transpiler bugs that produce invalid C#
- DO NOT PROCEED until build succeeds

### 5. Create Database (First Run)

```bash
# If using migrations
dotnet ef migrations add InitialCreate
dotnet ef database update

# Or let EF create it automatically on first run
```

### 6. Run the Application

```bash
dotnet run
```

**Expected Result:**
- Application starts without exceptions
- Listens on https://localhost:5001 (or similar)
- Console shows "Now listening on: https://localhost:5001"
- No startup errors

**If this fails:**
- Check runtime exceptions
- Verify DbContext configuration
- Check appsettings.json
- Fix any runtime issues
- DO NOT PROCEED until app starts

### 7. Test Swagger UI

Open browser:
```
https://localhost:5001/swagger
```

**Expected Result:**
- Swagger UI loads
- Shows TasksController with all endpoints:
  - GET /api/tasks
  - GET /api/tasks/{id}
  - POST /api/tasks
  - PUT /api/tasks/{id}
  - DELETE /api/tasks/{id}
  - GET /api/tasks/status/{status}
  - GET /api/tasks/priority/{priority}

**If this fails:**
- Check if Swagger is configured in Program.nl
- Verify controllers are discovered
- Check routing configuration

### 8. Test GET /api/tasks (Empty)

```bash
curl -k https://localhost:5001/api/tasks
```

**Expected Result:**
```json
[]
```

**If this fails:**
- Check controller is registered
- Check routing works
- Verify database connection

### 9. Test POST /api/tasks (Create)

```bash
curl -k -X POST https://localhost:5001/api/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test N# ASP.NET Core",
    "description": "Verify the entire stack works",
    "status": "todo",
    "priority": "high",
    "dueDate": "2025-12-31T23:59:59Z"
  }'
```

**Expected Result:**
```json
{
  "id": "a1b2c3d4-...",
  "title": "Test N# ASP.NET Core",
  "description": "Verify the entire stack works",
  "status": "todo",
  "priority": "high",
  "dueDate": "2025-12-31T23:59:59Z",
  "completedAt": null,
  "createdAt": "2025-11-08T...",
  "updatedAt": "2025-11-08T..."
}
```

**Save the returned ID for next steps.**

**If this fails:**
- Check request body binding
- Check validation logic
- Check database write operations
- Verify EF Core is configured correctly

### 10. Test GET /api/tasks/{id}

```bash
# Use the ID from step 9
curl -k https://localhost:5001/api/tasks/{id}
```

**Expected Result:** Same JSON as create response

**If this fails:**
- Check routing with parameters
- Check database read operations

### 11. Test PUT /api/tasks/{id} (Update)

```bash
curl -k -X PUT https://localhost:5001/api/tasks/{id} \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test N# ASP.NET Core - UPDATED",
    "description": "It works!",
    "status": "done",
    "priority": "high",
    "dueDate": "2025-12-31T23:59:59Z"
  }'
```

**Expected Result:** Updated task with status="done" and completedAt set

**If this fails:**
- Check update logic
- Check if condition for setting completedAt works

### 12. Test GET /api/tasks/status/done

```bash
curl -k https://localhost:5001/api/tasks/status/done
```

**Expected Result:** Array with one task (status="done")

**If this fails:**
- Check LINQ .Where() works
- Check lambda expressions transpile correctly

### 13. Test DELETE /api/tasks/{id}

```bash
curl -k -X DELETE https://localhost:5001/api/tasks/{id}
```

**Expected Result:** 204 No Content

Then verify it's gone:
```bash
curl -k https://localhost:5001/api/tasks/{id}
```

**Expected Result:** 404 Not Found

**If this fails:**
- Check delete logic
- Check pattern matching for null

### 14. Test Validation

Create task with missing title:
```bash
curl -k -X POST https://localhost:5001/api/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "description": "No title",
    "status": "todo",
    "priority": "low"
  }'
```

**Expected Result:** 400 Bad Request with error message about title

**If this fails:**
- Check validation functions
- Check error response format

### 15. Verify Database Persistence

Stop the app (Ctrl+C), then:

```bash
# Check database file exists
ls -la tasks.db

# Restart app
dotnet run

# Create a task
curl -k -X POST https://localhost:5001/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Persistence Test", "status": "todo", "priority": "low"}'

# Stop app again (Ctrl+C)

# Restart app again
dotnet run

# Retrieve tasks
curl -k https://localhost:5001/api/tasks
```

**Expected Result:** The task persists across restarts

**If this fails:**
- Check SQLite connection string
- Check database file location
- Verify EF Core configuration

## Documentation

After everything works, update:

### Update README.md

**File:** `examples/13-aspnet-demo/TaskManagementApi/README.md`

Change the build instructions from:

```markdown
### Step 2: Compile N# to C#
```bash
nsharp build Program.nl
nsharp build Database.nl
nsharp build Tasks.nl
```
```

To (once Task 031 is done):

```markdown
### Step 2: Build and Run
```bash
nsharp build  # Transpiles all .nl files automatically
dotnet run
```
```

Or for now, provide the working transpile commands.

### Update GAPS.md

**File:** `examples/13-aspnet-demo/TaskManagementApi/GAPS.md`

Mark resolved gaps:

```markdown
## ✅ Gap 1: External Type Resolution (RESOLVED - v1.71)

**Status:** Fixed by Task 030 Phase 1

**Verification:** TaskManagementApi builds and runs successfully with all external types resolved.
```

## Troubleshooting Guide

Document common issues and solutions:

### Issue: "Undefined identifier 'WebApplication'"

**Solution:** Verify Task 030 assembly resolution is working. Check that analyzer loads Microsoft.AspNetCore assemblies.

### Issue: "Cannot resolve method 'CreateBuilder'"

**Solution:** Ensure external method resolution is working. Check reflection-based method lookup in Analyzer.

### Issue: "Property 'Tasks' on 'AppDbContext' has no setter"

**Solution:** DbSet properties need to be mutable. Generated C# should have `{ get; set; }`.

### Issue: Runtime error on startup

**Solution:** Check that generated C# matches .NET conventions. Review transpiled code.

### Issue: Swagger doesn't show endpoints

**Solution:** Verify controllers are registered with `AddControllers()`. Check routing attributes.

## Known Limitations

Document any discovered limitations:

### Works ✅
- External type resolution
- Constructor chaining with base()
- Async functions
- Pattern matching
- LINQ queries
- Lambda expressions
- Attributes on classes and methods
- Object initializers
- If conditions with external method calls

### Doesn't Work Yet ❌
(Document any issues found)

### Workarounds Required 🔧
(Document any workarounds needed)

## Acceptance Criteria

This task is **ONLY COMPLETE** when:

1. ✅ All transpilation succeeds
2. ✅ Build succeeds
3. ✅ App runs without errors
4. ✅ Swagger UI loads
5. ✅ All 7 CRUD operations tested and work
6. ✅ Validation tested and works
7. ✅ Database persistence tested and works
8. ✅ Documentation updated
9. ✅ Known issues documented
10. ✅ Can demo to stakeholders with confidence

## Definition of Done

**DO NOT mark this task as complete until you can:**

1. Start the app from scratch
2. Create 3 tasks via API
3. Update one to "done"
4. Delete one
5. Filter by status
6. Show it works in Swagger UI
7. Restart the app and see data persisted

**If ANY of the above fails, the task is NOT DONE.**

## Time Estimate Breakdown

- Transpilation testing: 30 minutes
- Build fixes: 1-2 hours (if issues found)
- Runtime testing: 1 hour
- Full API testing: 1 hour
- Documentation: 30 minutes
- Edge case testing: 30 minutes

**Total:** 3-5 hours (could be more if major issues found)

## Success Metrics

- **Binary:** Works or doesn't work - no partial credit
- **Proof:** Screenshot of Swagger UI and curl commands working
- **Verification:** Can hand to another developer and they can run it

## Notes

This is a **CRITICAL** task. The ASP.NET Core demo is our proof that N# is production-ready for real-world applications. If this doesn't work perfectly, the language is not ready.

**Do not cut corners. Do not mark as complete until everything works flawlessly.**

This task validates:
- Task 030 (Assembly Resolution)
- Parser correctness
- Analyzer correctness
- Transpiler correctness
- Runtime behavior
- .NET interop
- Real-world usability

It's the ultimate integration test.
