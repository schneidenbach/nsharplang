# Task Management API - N# Demo

A production-quality ASP.NET Core Web API built entirely in N# to showcase real-world language features.

## Features Demonstrated

- **RESTful API**: Full CRUD operations with proper HTTP verbs
- **Entity Framework Core**: SQLite database with Code-First approach
- **Pattern Matching**: Type checking and null handling
- **Async/Await**: Asynchronous database operations
- **Dependency Injection**: Services injected into controllers
- **Data Validation**: Custom validation logic
- **DTOs**: Data Transfer Objects for clean API contracts
- **LINQ**: Database queries with Where clauses
- **String Enums**: Type-safe status and priority values

## Project Structure (Vertical Slices)

This project uses a **flat, vertical slice architecture** - each feature lives in one file:

```
TaskManagementApi/
  Program.nl              # Entry point, app configuration
  Database.nl             # EF Core DbContext
  Tasks.nl                # Everything for Tasks feature:
                          #   - Enums (TaskStatus, Priority)
                          #   - Entity (TaskEntity)
                          #   - DTOs (CreateTaskDto, UpdateTaskDto)
                          #   - Controller (TasksController)
                          #   - Validation functions
  appsettings.json        # Configuration
  TaskManagementApi.csproj # .NET project file
```

**Benefits of this structure:**
- Each file is self-contained
- Easy to find all code for a feature
- Deleting a file removes the entire feature
- No deep folder nesting

## Prerequisites

- .NET 9.0 SDK
- N# compiler (`nsharp`)

Install N# globally:
```bash
dotnet tool install -g nsharp
```

## Building and Running

### Option 1: Using N# Run Command (Simplest)
```bash
cd examples/13-aspnet-demo/TaskManagementApi
nsharp run Program.nl
```

That's it! The N# compiler automatically:
- Discovers and transpiles all `.nl` files
- Compiles to .NET
- Runs the application
- Cleans up temporary files

### Option 2: Build then Run Separately
```bash
cd examples/13-aspnet-demo/TaskManagementApi

# Build all .nl files (auto-discovers Program.nl, Database.nl, Tasks.nl)
nsharp build

# Run with dotnet
dotnet run
```

The API will start on `https://localhost:5001` (or similar).

### Explore with Swagger
Open your browser to:
```
https://localhost:5001/swagger
```

You'll see an interactive API documentation page where you can test all endpoints!

## API Endpoints

### Tasks

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET    | `/api/tasks` | Get all tasks |
| GET    | `/api/tasks/{id}` | Get task by ID |
| GET    | `/api/tasks/status/{status}` | Get tasks by status |
| GET    | `/api/tasks/priority/{priority}` | Get tasks by priority |
| POST   | `/api/tasks` | Create a new task |
| PUT    | `/api/tasks/{id}` | Update a task |
| DELETE | `/api/tasks/{id}` | Delete a task |

### Status Values
- `todo`
- `in_progress`
- `done`

### Priority Values
- `low`
- `medium`
- `high`

## Example Requests

### Create a Task
```bash
curl -X POST https://localhost:5001/api/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Learn N# pattern matching",
    "description": "Study the pattern matching examples",
    "status": "todo",
    "priority": "high",
    "dueDate": "2025-12-31T23:59:59Z"
  }'
```

### Get All Tasks
```bash
curl https://localhost:5001/api/tasks
```

### Update a Task
```bash
curl -X PUT https://localhost:5001/api/tasks/{id} \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Learn N# pattern matching",
    "description": "Completed the examples!",
    "status": "done",
    "priority": "high"
  }'
```

## Key N# Features Showcased

### 1. Pattern Matching for Null Checks

Instead of verbose null checking:
```csharp
// C#
var task = await db.Tasks.FindAsync(id);
if (task == null) {
    return NotFound();
}
return Ok(task);
```

N# uses concise pattern matching:
```n#
task := await db.Tasks.FindAsync(id)
return match task {
    null => NotFound(),
    _ => Ok(task)
}
```

### 2. String Enums

```n#
enum TaskStatus: string {
    Todo = "todo"
    InProgress = "in_progress"
    Done = "done"
}
```

These transpile to static classes with string constants, making them serialization-friendly.

### 3. Lambda Expressions

```n#
tasks := await db.Tasks
    .Where((t) => t.Status == status)
    .ToArrayAsync()
```

### 4. Type Inference with `:=`

```n#
// Compiler infers the type
task := new TaskEntity { ... }
errors := new System.Collections.Generic.List<string>()
```

### 5. Base Constructor Calls

```n#
func constructor(options: DbContextOptions<AppDbContext>) : base(options) {
}
```

### 6. Override Methods

```n#
func OnModelCreating(modelBuilder: ModelBuilder): void override {
    base.OnModelCreating(modelBuilder)
    // ...
}
```

### 7. Properties with Get/Set

```n#
class TaskEntity {
    Id: Guid { get; set; }
    Title: string { get; set; }
    Description: string? { get; set; }
}
```

## Database

The API uses SQLite with Entity Framework Core. The database file (`tasks.db`) is created automatically on first run.

### Migrations

To create a migration:
```bash
dotnet ef migrations add InitialCreate
```

To apply migrations:
```bash
dotnet ef database update
```

## What We Learned

While building this demo, we validated that N# supports:

✅ ASP.NET Core controllers with attributes
✅ Entity Framework Core DbContext
✅ Async/await patterns
✅ LINQ queries
✅ Dependency injection
✅ DTOs and model binding
✅ Pattern matching for control flow
✅ Lambda expressions
✅ Base class constructors
✅ Method overrides
✅ Nullable reference types

## Production Readiness

This demo shows that N# is ready for real-world ASP.NET Core applications. The generated C# code is:
- **Idiomatic**: Looks like hand-written C#
- **Performant**: No overhead compared to C#
- **Interoperable**: Works seamlessly with existing .NET libraries
- **Debuggable**: Standard .NET debugging tools work

## Next Steps

Want to extend this demo?

1. **Add authentication**: JWT tokens, ASP.NET Core Identity
2. **Add more entities**: Projects, Users, Tags
3. **Add relationships**: Tasks belong to Projects
4. **Add filtering**: Search, pagination, sorting
5. **Add tests**: XUnit tests in N#
6. **Add frontend**: Blazor WebAssembly UI

## Troubleshooting

### Database doesn't exist
Run `dotnet ef database update` to create the database.

### Port already in use
Change the port in `Properties/launchSettings.json` or set the `ASPNETCORE_URLS` environment variable.

### Swagger not loading
Make sure you're running in Development mode:
```bash
export ASPNETCORE_ENVIRONMENT=Development
dotnet run
```

## Learn More

- [N# Documentation](../../README.md)
- [Pattern Matching Examples](../04-pattern-matching/)
- [Multi-File Projects](../12-multi-file-projects/)
