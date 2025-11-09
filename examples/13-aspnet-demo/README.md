# Employee API - N# Demo

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

## Project Structure (Vertical Slices)

This project uses a **flat, vertical slice architecture** - each feature lives in one file:

```
EmployeeApi/
  Program.nl              # Entry point, app configuration
  Database.nl             # EF Core DbContext
  Employees.nl            # Everything for Employees feature:
                          #   - Enums (EmploymentStatus, Department)
                          #   - Entity (EmployeeEntity)
                          #   - DTOs (CreateEmployeeDto, UpdateEmployeeDto)
                          #   - Controller (EmployeesController)
                          #   - Validation functions
  appsettings.json        # Configuration
  EmployeeApi.csproj      # .NET project file
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
cd examples/13-aspnet-demo/EmployeeApi
nsharp run Program.nl
```

That's it! The N# compiler automatically:
- Discovers and transpiles all `.nl` files
- Compiles to .NET
- Runs the application
- Cleans up temporary files

### Option 2: Build then Run Separately
```bash
cd examples/13-aspnet-demo/EmployeeApi

# Build all .nl files (auto-discovers Program.nl, Database.nl, Employees.nl)
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

All endpoints are under `/api/employees`:

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /api/employees | Get all employees |
| GET | /api/employees/{id} | Get employee by ID |
| GET | /api/employees/status/{status} | Get employees by status |
| GET | /api/employees/department/{department} | Get employees by department |
| POST | /api/employees | Create new employee |
| PUT | /api/employees/{id} | Update employee |
| DELETE | /api/employees/{id} | Delete employee |

## Usage Examples

### Create an Employee (POST /api/employees)

```bash
curl -X POST https://localhost:5001/api/employees \
  -H "Content-Type: application/json" \
  -d '{
    "firstName": "Alice",
    "lastName": "Johnson",
    "email": "alice.johnson@company.com",
    "department": "engineering",
    "status": "active",
    "hireDate": "2024-01-15T00:00:00Z",
    "salary": 95000
  }'
```

Response (201 Created):
```json
{
  "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "firstName": "Alice",
  "lastName": "Johnson",
  "email": "alice.johnson@company.com",
  "department": "engineering",
  "status": "active",
  "hireDate": "2024-01-15T00:00:00Z",
  "salary": 95000,
  "createdAt": "2024-11-08T12:00:00Z",
  "updatedAt": "2024-11-08T12:00:00Z"
}
```

### Get All Employees (GET /api/employees)

```bash
curl https://localhost:5001/api/employees
```

### Get Employee by ID (GET /api/employees/{id})

```bash
curl https://localhost:5001/api/employees/3fa85f64-5717-4562-b3fc-2c963f66afa6
```

### Get Employees by Department (GET /api/employees/department/{department})

```bash
curl https://localhost:5001/api/employees/department/engineering
```

### Get Employees by Status (GET /api/employees/status/{status})

```bash
curl https://localhost:5001/api/employees/status/active
```

### Update Employee (PUT /api/employees/{id})

```bash
curl -X PUT https://localhost:5001/api/employees/3fa85f64-5717-4562-b3fc-2c963f66afa6 \
  -H "Content-Type: application/json" \
  -d '{
    "salary": 105000,
    "department": "engineering"
  }'
```

### Delete Employee (DELETE /api/employees/{id})

```bash
curl -X DELETE https://localhost:5001/api/employees/3fa85f64-5717-4562-b3fc-2c963f66afa6
```

## Domain Model

### EmploymentStatus Constants

```n#
class EmploymentStatus {
    static Active: string = "active"
    static OnLeave: string = "on_leave"
    static Terminated: string = "terminated"
}
```

### Department Constants

```n#
class Department {
    static Engineering: string = "engineering"
    static Sales: string = "sales"
    static Marketing: string = "marketing"
    static HR: string = "hr"
    static Finance: string = "finance"
}
```

### Employee Entity

```n#
class EmployeeEntity {
    Id: Guid
    FirstName: string
    LastName: string
    Email: string
    Department: string
    Status: string
    HireDate: DateTime
    Salary: decimal?
    CreatedAt: DateTime
    UpdatedAt: DateTime
}
```

## N# Language Features Demonstrated

1. **Package System**: `package EmployeeApi`
2. **Imports**: Clean C# interop with `import System`, `import Microsoft.AspNetCore.Mvc`
3. **Type Inference**: `employees := await db.Employees.ToArrayAsync()`
4. **Pattern Matching**:
   ```n#
   return match employee {
       null => NotFound(),
       _ => Ok(employee)
   }
   ```
5. **Async/Await**: `func async GetAll(): IActionResult`
6. **Lambda Expressions**: `.Where(e => e.Status == status)`
7. **Object Initializers**:
   ```n#
   employee := new EmployeeEntity {
       Id = Guid.NewGuid(),
       FirstName = dto.FirstName,
       ...
   }
   ```
8. **Attributes**: `[HttpGet]`, `[Route("api/employees")]`, `[Required]`
9. **Constructor Calls to Base**: `constructor(options: DbContextOptions<AppDbContext>): base(options)`

## Validation

The API includes comprehensive validation:
- Required fields (FirstName, LastName, Email, Department, Status)
- Max length validation (FirstName/LastName: 100 chars, Email: 200 chars)
- Email format validation
- Salary range validation (cannot be negative)
- Business rule validation (hire date, etc.)

## Database

The application uses SQLite for simplicity:
- Database file: `employees.db`
- Auto-created on first run
- In-memory option available for testing

## Testing the API

1. **Start the application**
   ```bash
   nsharp run Program.nl
   ```

2. **Navigate to Swagger**
   Open https://localhost:5001/swagger

3. **Create some employees** using the POST endpoint

4. **Query employees** by department or status

5. **Update employee information**

6. **Delete employees**

## Why Employee API (not Task API)?

The term "Task" is heavily overloaded in .NET:
- `System.Threading.Tasks.Task` - The async type
- `System.Threading.Tasks.Task<T>` - Generic async type
- "Tasks" as in work items/todos

This caused confusion in code like:
```n#
func GetTasks(): Task<List<TaskEntity>> async  // Which Task?!
```

With EmployeeApi, it's crystal clear:
```n#
func GetEmployees(): Task<List<EmployeeEntity>> async
```

Now `Task` obviously refers to the async type, not a domain entity.
