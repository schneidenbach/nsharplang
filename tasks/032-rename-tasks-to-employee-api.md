# Task 032: Rename TaskManagementApi to EmployeeApi

**Priority:** Low (Example project improvement)
**Dependencies:** None
**Estimated Effort:** Small (1-2 hours)
**Status:** Not started

## Goal

Rename the ASP.NET Core demo from "TaskManagementApi" to "EmployeeApi" because "Tasks" is an overloaded term in the .NET ecosystem (Task, Task<T>, async tasks, etc.).

## Rationale

The word "Task" is heavily overloaded in .NET:
- `System.Threading.Tasks.Task` - The async type
- `System.Threading.Tasks.Task<T>` - Generic async type
- "Tasks" as in work items/todos

This causes confusion when reading the code:
```n#
func GetTasks(): Task<List<TaskEntity>> async  // Which Task?!
```

An Employee API is clearer and demonstrates the same features without the naming confusion.

## Proposed Changes

### Directory Structure
```
examples/13-aspnet-demo/
  EmployeeApi/              # Renamed from TaskManagementApi
    Program.nl
    Database.nl
    Employees.nl            # Renamed from Tasks.nl
    EmployeeApi.csproj      # Renamed from TaskManagementApi.csproj
    appsettings.json
    README.md
```

### Domain Model

**Old (Tasks):**
```n#
enum TaskStatus: string {
    Todo = "todo"
    InProgress = "in_progress"
    Done = "done"
}

enum Priority: string {
    Low = "low"
    Medium = "medium"
    High = "high"
}

class TaskEntity {
    Id: Guid
    Title: string
    Description: string?
    Status: string
    Priority: string
    DueDate: DateTime?
}
```

**New (Employees):**
```n#
enum EmploymentStatus: string {
    Active = "active"
    OnLeave = "on_leave"
    Terminated = "terminated"
}

enum Department: string {
    Engineering = "engineering"
    Sales = "sales"
    Marketing = "marketing"
    HR = "hr"
    Finance = "finance"
}

class EmployeeEntity {
    Id: Guid
    FirstName: string
    LastName: string
    Email: string
    Department: string
    Status: string
    HireDate: DateTime
    Salary: decimal?
}
```

### API Endpoints

**Old:**
- GET /api/tasks
- GET /api/tasks/{id}
- GET /api/tasks/status/{status}
- POST /api/tasks
- PUT /api/tasks/{id}
- DELETE /api/tasks/{id}

**New:**
- GET /api/employees
- GET /api/employees/{id}
- GET /api/employees/department/{department}
- GET /api/employees/status/{status}
- POST /api/employees
- PUT /api/employees/{id}
- DELETE /api/employees/{id}

### DTOs

```n#
record CreateEmployeeDto {
    FirstName: string
    LastName: string
    Email: string
    Department: string
    Status: string
    HireDate: DateTime
    Salary: decimal?
}

record UpdateEmployeeDto {
    FirstName: string?
    LastName: string?
    Email: string?
    Department: string?
    Status: string?
    Salary: decimal?
}
```

### Controller

```n#
[ApiController]
[Route("api/employees")]
class EmployeesController : ControllerBase {
    db: AppDbContext

    constructor(context: AppDbContext) {
        db = context
    }

    [HttpGet]
    func GetAll(): Task<IActionResult> async {
        employees := await db.Employees.ToArrayAsync()
        return Ok(employees)
    }

    [HttpGet("{id}")]
    func GetById(id: Guid): Task<IActionResult> async {
        employee := await db.Employees.FindAsync(id)
        return match employee {
            null => NotFound(),
            _ => Ok(employee)
        }
    }

    [HttpGet("department/{department}")]
    func GetByDepartment(department: string): Task<IActionResult> async {
        employees := await db.Employees
            .Where((e) => e.Department == department)
            .ToArrayAsync()
        return Ok(employees)
    }

    // ... etc
}
```

## Implementation Steps

1. **Copy directory**
   ```bash
   cp -r examples/13-aspnet-demo/TaskManagementApi examples/13-aspnet-demo/EmployeeApi
   ```

2. **Rename files**
   - TaskManagementApi.csproj → EmployeeApi.csproj
   - Tasks.nl → Employees.nl

3. **Update all type names**
   - TaskEntity → EmployeeEntity
   - TaskStatus → EmploymentStatus
   - Priority → Department
   - TasksController → EmployeesController
   - CreateTaskDto → CreateEmployeeDto
   - UpdateTaskDto → UpdateEmployeeDto

4. **Update namespaces**
   - `package TaskManagementApi` → `package EmployeeApi`

5. **Update Database.nl**
   - `DbSet<TaskEntity> Tasks` → `DbSet<EmployeeEntity> Employees`

6. **Update README.md**
   - Replace all Task references with Employee
   - Update example JSON payloads
   - Update endpoint documentation
   - Update curl examples

7. **Update example data**
   ```json
   {
     "firstName": "Alice",
     "lastName": "Johnson",
     "email": "alice.johnson@company.com",
     "department": "engineering",
     "status": "active",
     "hireDate": "2024-01-15T00:00:00Z",
     "salary": 95000
   }
   ```

8. **Test thoroughly**
   ```bash
   cd examples/13-aspnet-demo/EmployeeApi
   nsharp build  # (once Task 031 is done)
   dotnet run
   # Test all endpoints with curl or Swagger
   ```

9. **Keep or remove old example?**
   - Option A: Delete TaskManagementApi entirely
   - Option B: Keep both (shows different domain examples)
   - **Recommendation:** Delete TaskManagementApi to avoid confusion

10. **Update parent README**
    - Update examples/13-aspnet-demo/README.md
    - Update main README.md if it references TaskManagementApi

## Success Criteria

- [ ] EmployeeApi directory created with all files renamed
- [ ] All types renamed (Employee, EmploymentStatus, Department, etc.)
- [ ] All endpoints work (GET, POST, PUT, DELETE)
- [ ] README.md updated with correct examples
- [ ] Database creates employees.db successfully
- [ ] Swagger UI shows employee endpoints
- [ ] No references to "Task" except `System.Threading.Tasks.Task`
- [ ] Example requests in README work with curl

## Testing

### Manual Verification
1. Delete TaskManagementApi (or rename to TaskManagementApi.old)
2. Build and run EmployeeApi
3. Navigate to Swagger UI
4. Create an employee via POST
5. Retrieve via GET
6. Filter by department
7. Update employee info
8. Delete employee
9. Verify all operations work

### Code Review
- Search codebase for remaining "Task" references (excluding System.Threading.Tasks)
- Verify no broken links in documentation
- Verify all JSON examples are valid

## Notes

This is a nice-to-have improvement that makes the example clearer. "Employee" is a universally understood domain concept without naming conflicts in .NET. After this change, code like:

```n#
func GetEmployees(): Task<List<EmployeeEntity>> async
```

is much clearer - it's obvious that `Task` refers to the async type, not the domain entity.

## Example Swagger Output

After this change, the Swagger UI will show:

**EmployeesController**
- GET /api/employees - Get all employees
- GET /api/employees/{id} - Get employee by ID
- GET /api/employees/department/engineering - Get engineers
- GET /api/employees/status/active - Get active employees
- POST /api/employees - Create new employee
- PUT /api/employees/{id} - Update employee
- DELETE /api/employees/{id} - Delete employee

Much cleaner!
