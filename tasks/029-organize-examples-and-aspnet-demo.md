# Task 029: Organize Examples + ASP.NET Core Demo App

**Status:** 🔲 TODO
**Priority:** High
**Dependencies:** Tasks 024, 025, 026, 028 (language features should be complete)
**Estimated Effort:** Large (15-20 hours)

## Goal

1. **Reorganize examples** into numbered directories (1-hello-world/, 2-types/, etc.)
2. **Build a real ASP.NET Core application** that showcases N# features in production-quality code
3. **Discover and fix any language/transpiler gaps** encountered during real-world usage

## Part 1: Organize Examples

### Current State
```
examples/
  hello.nl
  unions_and_match.nl
  pattern_guards.nl
  primary_constructors.nl
  ... 40+ files in flat structure
```

### Desired State
```
examples/
  1-hello-world/
    README.md
    Program.nl
  2-variables-and-types/
    README.md
    Variables.nl
    TypeInference.nl
    Nullables.nl
  3-functions/
    README.md
    BasicFunctions.nl
    ExpressionBodied.nl
    LocalFunctions.nl
  4-pattern-matching/
    README.md
    BasicMatch.nl
    Guards.nl
    ListPatterns.nl
  5-unions/
    README.md
    DefiningUnions.nl
    MatchingUnions.nl
    ResultType.nl
  6-classes-and-records/
    README.md
    Classes.nl
    Records.nl
    RecordStructs.nl
    PrimaryConstructors.nl
  7-interfaces/
    README.md
    StandardInterfaces.nl
    DuckInterfaces.nl
    ExtensionMethods.nl
  8-async/
    README.md
    AsyncAwait.nl
    AsyncStreams.nl
  9-linq-and-collections/
    README.md
    ArraysAndLists.nl
    LinqQueries.nl
    CollectionExpressions.nl
  10-interop/
    README.md
    CallingCSharp.nl
    Attributes.nl
    RefOut.nl
```

### Implementation

Each directory should have:
1. **README.md** - What this example demonstrates, how to run it
2. **One or more .nl files** - Clean, commented examples
3. **Expected output** in README

Example README.md:
```markdown
# 1. Hello World

Your first N# program!

## What it demonstrates

- Basic program structure
- Importing namespaces
- Top-level functions
- String interpolation
- Print output

## Files

- `Program.nl` - A simple "Hello, World!" program

## Running

```bash
cd examples/1-hello-world
nsharp run Program.nl
```

## Expected Output

```
Hello, World!
Hello, Alice!
```

## Code Walkthrough

...explanation of key concepts...
```

### Migration Script

Create a script to reorganize:

```bash
#!/bin/bash
# scripts/reorganize-examples.sh

# Create directories
mkdir -p examples/1-hello-world
mkdir -p examples/2-variables-and-types
# ... etc

# Move files
mv examples/hello.nl examples/1-hello-world/Program.nl
mv examples/unions_and_match.nl examples/5-unions/BasicUnions.nl
# ... etc

# Generate README.md for each directory
# (manual or templated)
```

## Part 2: ASP.NET Core Demo Application

### Application: Task Management API

Build a realistic task management API that shows N# in production.

**Features:**
- RESTful API with controllers
- Entity models with validation
- Database context (EF Core)
- Pattern matching for business logic
- Discriminated unions for domain modeling
- Async/await for database operations
- Error handling with Result types
- Unit tests in N# (if possible)

### Project Structure

```
examples/TaskManagementApi/
  README.md
  TaskManagementApi.csproj

  Program.nl                    # Entry point, app setup

  Models/
    Task.nl                     # Task entity
    User.nl                     # User entity
    Project.nl                  # Project entity
    TaskStatus.nl               # Enum for task status
    Priority.nl                 # Enum for priority

  Domain/
    TaskResult.nl               # Union for operation results
    ValidationError.nl          # Validation error types
    TaskFilters.nl              # Query filters

  Controllers/
    TasksController.nl          # CRUD for tasks
    ProjectsController.nl       # CRUD for projects
    UsersController.nl          # User management

  Services/
    TaskService.nl              # Business logic
    ProjectService.nl           # Project operations
    ValidationService.nl        # Validation logic

  Data/
    AppDbContext.nl             # EF Core context
    Migrations/                 # EF migrations

  Tests/
    TaskServiceTests.nl         # Unit tests
    ValidationTests.nl          # Validation tests

  appsettings.json
  appsettings.Development.json
```

### Example: Task.nl

```n#
import System
import System.ComponentModel.DataAnnotations

package TaskManagementApi.Models

// Task entity with validation
class Task {
    Id: Guid

    [Required]
    [MaxLength(200)]
    Title: string

    Description: string?

    Status: TaskStatus
    Priority: Priority

    DueDate: DateTime?
    CompletedAt: DateTime?

    ProjectId: Guid?
    AssignedToId: Guid?

    CreatedAt: DateTime
    UpdatedAt: DateTime

    // Navigation properties
    Project: Project?
    AssignedTo: User?
}
```

### Example: TaskStatus.nl

```n#
package TaskManagementApi.Models

enum TaskStatus: string {
    Todo = "todo"
    InProgress = "in_progress"
    Blocked = "blocked"
    Done = "done"
    Archived = "archived"
}
```

### Example: TaskResult.nl

```n#
package TaskManagementApi.Domain

// Discriminated union for operation results
union TaskResult<T> {
    Success { value: T }
    NotFound { id: Guid }
    ValidationError { errors: ValidationError[] }
    Unauthorized
}
```

### Example: TasksController.nl

```n#
import Microsoft.AspNetCore.Mvc
import System
import System.Threading.Tasks
import TaskManagementApi.Models
import TaskManagementApi.Services
import TaskManagementApi.Domain

package TaskManagementApi.Controllers

[ApiController]
[Route("api/tasks")]
class TasksController : ControllerBase {
    taskService: TaskService

    // Constructor injection
    func constructor(service: TaskService) {
        taskService = service
    }

    [HttpGet]
    async func GetAll(): Task<IActionResult> {
        tasks := await taskService.GetAllAsync()
        return Ok(tasks)
    }

    [HttpGet("{id}")]
    async func GetById(id: Guid): Task<IActionResult> {
        result := await taskService.GetByIdAsync(id)

        // Pattern match on discriminated union
        return match result {
            Success { value } => Ok(value),
            NotFound { id } => NotFound($"Task {id} not found"),
            _ => StatusCode(500, "Unexpected error")
        }
    }

    [HttpPost]
    async func Create(task: Task): Task<IActionResult> {
        result := await taskService.CreateAsync(task)

        return match result {
            Success { value } => CreatedAtAction(
                nameof(GetById),
                new { id = value.Id },
                value
            ),
            ValidationError { errors } => BadRequest(errors),
            _ => StatusCode(500, "Failed to create task")
        }
    }

    [HttpPut("{id}")]
    async func Update(id: Guid, task: Task): Task<IActionResult> {
        if id != task.Id {
            return BadRequest("ID mismatch")
        }

        result := await taskService.UpdateAsync(task)

        return match result {
            Success { value } => Ok(value),
            NotFound { id } => NotFound($"Task {id} not found"),
            ValidationError { errors } => BadRequest(errors),
            _ => StatusCode(500, "Failed to update task")
        }
    }

    [HttpDelete("{id}")]
    async func Delete(id: Guid): Task<IActionResult> {
        result := await taskService.DeleteAsync(id)

        return match result {
            Success { value } => NoContent(),
            NotFound { id } => NotFound($"Task {id} not found"),
            _ => StatusCode(500, "Failed to delete task")
        }
    }
}
```

### Example: TaskService.nl

```n#
import System
import System.Linq
import System.Threading.Tasks
import Microsoft.EntityFrameworkCore
import TaskManagementApi.Models
import TaskManagementApi.Data
import TaskManagementApi.Domain

package TaskManagementApi.Services

class TaskService {
    db: AppDbContext

    func constructor(context: AppDbContext) {
        db = context
    }

    async func GetAllAsync(): Task<Task[]> {
        return await db.Tasks
            .Include(t => t.Project)
            .Include(t => t.AssignedTo)
            .ToArrayAsync()
    }

    async func GetByIdAsync(id: Guid): Task<TaskResult<Task>> {
        task := await db.Tasks
            .Include(t => t.Project)
            .Include(t => t.AssignedTo)
            .FirstOrDefaultAsync(t => t.Id == id)

        // Use pattern matching with null check
        return match task {
            null => TaskResult<Task>.NotFound(new { id }),
            _ => TaskResult<Task>.Success(new { value = task })
        }
    }

    async func CreateAsync(task: Task): Task<TaskResult<Task>> {
        // Validate
        errors := ValidateTask(task)
        if errors.Length > 0 {
            return TaskResult<Task>.ValidationError(new { errors })
        }

        // Set timestamps
        now := DateTime.UtcNow
        task.CreatedAt = now
        task.UpdatedAt = now
        task.Id = Guid.NewGuid()

        db.Tasks.Add(task)
        await db.SaveChangesAsync()

        return TaskResult<Task>.Success(new { value = task })
    }

    async func UpdateAsync(task: Task): Task<TaskResult<Task>> {
        existing := await db.Tasks.FindAsync(task.Id)

        if existing == null {
            return TaskResult<Task>.NotFound(new { id = task.Id })
        }

        // Validate
        errors := ValidateTask(task)
        if errors.Length > 0 {
            return TaskResult<Task>.ValidationError(new { errors })
        }

        // Update properties
        existing.Title = task.Title
        existing.Description = task.Description
        existing.Status = task.Status
        existing.Priority = task.Priority
        existing.DueDate = task.DueDate
        existing.ProjectId = task.ProjectId
        existing.AssignedToId = task.AssignedToId
        existing.UpdatedAt = DateTime.UtcNow

        // Handle status transitions
        if task.Status == TaskStatus.Done && existing.CompletedAt == null {
            existing.CompletedAt = DateTime.UtcNow
        }

        await db.SaveChangesAsync()

        return TaskResult<Task>.Success(new { value = existing })
    }

    async func DeleteAsync(id: Guid): Task<TaskResult<bool>> {
        task := await db.Tasks.FindAsync(id)

        if task == null {
            return TaskResult<bool>.NotFound(new { id })
        }

        db.Tasks.Remove(task)
        await db.SaveChangesAsync()

        return TaskResult<bool>.Success(new { value = true })
    }

    func ValidateTask(task: Task): ValidationError[] {
        errors := []

        if task.Title == null || task.Title.Length == 0 {
            errors = [...errors, ValidationError("Title is required", "Title")]
        }

        if task.Title?.Length > 200 {
            errors = [...errors, ValidationError("Title too long", "Title")]
        }

        if task.DueDate != null && task.DueDate < DateTime.UtcNow {
            errors = [...errors, ValidationError("Due date cannot be in the past", "DueDate")]
        }

        return errors
    }
}
```

### Example: AppDbContext.nl

```n#
import Microsoft.EntityFrameworkCore
import TaskManagementApi.Models

package TaskManagementApi.Data

class AppDbContext : DbContext {
    func constructor(options: DbContextOptions<AppDbContext>) : base(options) {
    }

    Tasks: DbSet<Task>
    Projects: DbSet<Project>
    Users: DbSet<User>

    protected override func OnModelCreating(modelBuilder: ModelBuilder) {
        // Configure Task entity
        modelBuilder.Entity<Task>()
            .HasIndex(t => t.Status)

        modelBuilder.Entity<Task>()
            .HasIndex(t => t.DueDate)

        // Configure relationships
        modelBuilder.Entity<Task>()
            .HasOne(t => t.Project)
            .WithMany(p => p.Tasks)
            .HasForeignKey(t => t.ProjectId)
            .OnDelete(DeleteBehavior.SetNull)

        modelBuilder.Entity<Task>()
            .HasOne(t => t.AssignedTo)
            .WithMany(u => u.AssignedTasks)
            .HasForeignKey(t => t.AssignedToId)
            .OnDelete(DeleteBehavior.SetNull)

        base.OnModelCreating(modelBuilder)
    }
}
```

### Example: Program.nl

```n#
import Microsoft.AspNetCore.Builder
import Microsoft.Extensions.DependencyInjection
import Microsoft.Extensions.Hosting
import Microsoft.EntityFrameworkCore
import TaskManagementApi.Data
import TaskManagementApi.Services

package TaskManagementApi

func Main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)

    // Add services
    builder.Services.AddControllers()
    builder.Services.AddEndpointsApiExplorer()
    builder.Services.AddSwaggerGen()

    // Add database
    builder.Services.AddDbContext<AppDbContext>(options =>
        options.UseSqlite("Data Source=tasks.db")
    )

    // Add custom services
    builder.Services.AddScoped<TaskService>()
    builder.Services.AddScoped<ProjectService>()

    app := builder.Build()

    // Configure pipeline
    if app.Environment.IsDevelopment() {
        app.UseSwagger()
        app.UseSwaggerUI()
    }

    app.UseHttpsRedirection()
    app.UseAuthorization()
    app.MapControllers()

    app.Run()
}
```

### README.md for Demo App

```markdown
# Task Management API - N# Demo

A production-quality ASP.NET Core Web API built with N# to showcase the language's features.

## Features Demonstrated

- **Controllers**: RESTful API endpoints
- **Discriminated Unions**: `TaskResult<T>` for operation results
- **Pattern Matching**: Exhaustive matching on results
- **Async/Await**: Database operations
- **Entity Models**: EF Core entities
- **Enums**: String enums for status values
- **Validation**: Business rule validation
- **Dependency Injection**: Services injected into controllers
- **LINQ**: Database queries

## Running

```bash
cd examples/TaskManagementApi

# Restore packages
dotnet restore

# Build N# code
nsharp build

# Run migrations
dotnet ef database update

# Run the API
dotnet run
```

## API Endpoints

- `GET /api/tasks` - Get all tasks
- `GET /api/tasks/{id}` - Get task by ID
- `POST /api/tasks` - Create task
- `PUT /api/tasks/{id}` - Update task
- `DELETE /api/tasks/{id}` - Delete task

## Swagger UI

Open https://localhost:5001/swagger to explore the API.

## Project Structure

[Explain the structure...]

## Key N# Features

### Discriminated Unions for Results

Instead of throwing exceptions, we use `TaskResult<T>`:

```n#
union TaskResult<T> {
    Success { value: T }
    NotFound { id: Guid }
    ValidationError { errors: ValidationError[] }
    Unauthorized
}
```

### Pattern Matching in Controllers

```n#
return match result {
    Success { value } => Ok(value),
    NotFound { id } => NotFound($"Task {id} not found"),
    ValidationError { errors } => BadRequest(errors),
    _ => StatusCode(500, "Unexpected error")
}
```

This is exhaustive - compiler ensures all cases are handled!

### String Enums

```n#
enum TaskStatus: string {
    Todo = "todo"
    InProgress = "in_progress"
    Done = "done"
}
```

These transpile to static classes with const string fields.

## What We Learned

[Document any language gaps found and tasks created to fix them]
```

## Part 3: Discover and Fix Gaps

### Process

While building the ASP.NET Core app:

1. **Try to write idiomatic N# code**
2. **Hit a limitation?** Document it
3. **Create a task to fix it**
4. **Workaround for now** (if possible)
5. **Track all gaps** in this task

### Likely Gaps to Find

Based on the ASP.NET Core app, we'll likely need:

1. **Base class constructor calls** - `: base(options)`
2. **Method overrides** - `override func OnModelCreating`
3. **Lambda expressions** - `options => options.UseSqlite(...)`
4. **Object initializers** - `new { id = value.Id }`
5. **Generic method calls** - `AddDbContext<AppDbContext>`
6. **Spread in arrays** - `[...errors, newError]`
7. **Null-coalescing** - `task?.Title ?? "Untitled"`
8. **LINQ query syntax** (if we want it)

### Gap Tracking Template

For each gap found:

```markdown
## Gap: [Feature Name]

**What we tried:**
```n#
[code that didn't work]
```

**Error:**
```
[error message]
```

**What we need:**
[Description of missing feature]

**Workaround:**
[If any]

**Task created:**
Task XXX: [Task name]
```

## Testing the Demo App

### Manual Testing Checklist

- [ ] API builds successfully from N# source
- [ ] Swagger UI loads
- [ ] GET /api/tasks returns empty array
- [ ] POST /api/tasks creates a task
- [ ] GET /api/tasks/{id} returns the task
- [ ] PUT /api/tasks/{id} updates the task
- [ ] DELETE /api/tasks/{id} deletes the task
- [ ] Validation errors return 400
- [ ] Not found returns 404
- [ ] Pattern matching handles all union cases

### Automated Testing

If possible, write tests in N#:

```n#
import Xunit
import TaskManagementApi.Services
import TaskManagementApi.Domain

package TaskManagementApi.Tests

class TaskServiceTests {
    [Fact]
    async func CreateTask_ValidTask_ReturnsSuccess() {
        // Arrange
        service := CreateTestService()
        task := new Task {
            Title = "Test Task",
            Status = TaskStatus.Todo,
            Priority = Priority.Medium
        }

        // Act
        result := await service.CreateAsync(task)

        // Assert
        match result {
            Success { value } => {
                Assert.NotEqual(Guid.Empty, value.Id)
                Assert.Equal("Test Task", value.Title)
            },
            _ => Assert.Fail("Expected Success result")
        }
    }

    [Fact]
    async func CreateTask_EmptyTitle_ReturnsValidationError() {
        // Arrange
        service := CreateTestService()
        task := new Task { Title = "" }

        // Act
        result := await service.CreateAsync(task)

        // Assert
        match result {
            ValidationError { errors } => {
                Assert.True(errors.Length > 0)
                Assert.Contains(errors, e => e.Field == "Title")
            },
            _ => Assert.Fail("Expected ValidationError result")
        }
    }

    func CreateTestService(): TaskService {
        // Setup in-memory database for testing
        options := new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options

        context := new AppDbContext(options)
        return new TaskService(context)
    }
}
```

## Success Criteria

- [ ] Examples reorganized into numbered directories
- [ ] Each directory has README.md with explanations
- [ ] ASP.NET Core demo app builds successfully
- [ ] Demo app runs and all endpoints work
- [ ] All CRUD operations functional
- [ ] Pattern matching used throughout
- [ ] Discriminated unions for results
- [ ] Code is production-quality (commented, clean)
- [ ] All language gaps documented
- [ ] Tasks created for each gap found
- [ ] README explains N# features showcased
- [ ] Tests written (if N# supports xUnit)

## Documentation Updates

**Files to create:**
- `examples/README.md` - Index of all examples
- Each example directory's README.md
- `examples/TaskManagementApi/README.md` - Full walkthrough
- `examples/TaskManagementApi/GAPS.md` - Document all gaps found

**Files to update:**
- Main `README.md` - Link to examples and demo app
- `DESIGN.md` - Add any new features discovered as needed

## Deliverables

1. **Reorganized examples/** directory with numbered folders
2. **Working ASP.NET Core application** in N#
3. **Comprehensive README** for demo app
4. **Gap documentation** listing all limitations found
5. **New tasks** for fixing discovered gaps
6. **Tests** (if possible in current N# state)

## Notes

This task is deliberately exploratory. The goal is to:
1. Make examples more approachable
2. Prove N# works for real applications
3. **Find and fix rough edges**

Expect to create 5-10 new tasks for gaps discovered. That's good! It means we're pushing the language to production-ready state.
