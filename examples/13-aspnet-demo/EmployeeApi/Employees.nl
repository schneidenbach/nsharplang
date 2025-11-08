import System
import System.ComponentModel.DataAnnotations
import Microsoft.AspNetCore.Mvc
import Microsoft.EntityFrameworkCore
import System.Threading.Tasks
import System.Linq

package EmployeeApi

// ============================================================================
// DOMAIN: Status Constants
// ============================================================================

// Employment status constants
class EmploymentStatus {
    static Active: string = "active"
    static OnLeave: string = "on_leave"
    static Terminated: string = "terminated"
}

// Department constants
class Department {
    static Engineering: string = "engineering"
    static Sales: string = "sales"
    static Marketing: string = "marketing"
    static HR: string = "hr"
    static Finance: string = "finance"
}

// ============================================================================
// ENTITY: EmployeeEntity
// ============================================================================

// Main employee entity - represents an employee in our system
class EmployeeEntity {
    // Unique identifier
    Id: Guid

    // Employee first name (required, max 100 characters)
    [Required]
    [MaxLength(100)]
    FirstName: string

    // Employee last name (required, max 100 characters)
    [Required]
    [MaxLength(100)]
    LastName: string

    // Employee email (required, max 200 characters)
    [Required]
    [MaxLength(200)]
    Email: string

    // Department
    Department: string

    // Employment status
    Status: string

    // Hire date
    HireDate: DateTime

    // Optional salary information
    Salary: decimal?

    // Metadata
    CreatedAt: DateTime
    UpdatedAt: DateTime
}

// ============================================================================
// DTOs: Data Transfer Objects
// ============================================================================

// DTO for creating a new employee
class CreateEmployeeDto {
    [Required]
    [MaxLength(100)]
    FirstName: string

    [Required]
    [MaxLength(100)]
    LastName: string

    [Required]
    [MaxLength(200)]
    Email: string

    Department: string
    Status: string
    HireDate: DateTime
    Salary: decimal?
}

// DTO for updating an employee
class UpdateEmployeeDto {
    [MaxLength(100)]
    FirstName: string?

    [MaxLength(100)]
    LastName: string?

    [MaxLength(200)]
    Email: string?

    Department: string?
    Status: string?
    Salary: decimal?
}

// ============================================================================
// CONTROLLER: Employees API Endpoints
// ============================================================================

[ApiController]
[Route("api/employees")]
class EmployeesController : ControllerBase {
    db: AppDbContext

    // Constructor with dependency injection
    constructor(context: AppDbContext) {
        db = context
    }

    // GET /api/employees - Get all employees
    [HttpGet]
    func async GetAll(): IActionResult {
        employees := await db.Employees.ToArrayAsync()
        return Ok(employees)
    }

    // GET /api/employees/{id} - Get employee by ID
    [HttpGet("{id}")]
    func async GetById(id: Guid): IActionResult {
        employee := await db.Employees.FindAsync(id)

        return match employee {
            null => NotFound(),
            _ => Ok(employee)
        }
    }

    // POST /api/employees - Create a new employee
    [HttpPost]
    func async Create(dto: CreateEmployeeDto): IActionResult {
        // Validate
        errors := ValidateCreateEmployee(dto)
        if errors.Length > 0 {
            return BadRequest(new { errors = errors })
        }

        // Create entity
        employee := new EmployeeEntity {
            Id = Guid.NewGuid(),
            FirstName = dto.FirstName,
            LastName = dto.LastName,
            Email = dto.Email,
            Department = dto.Department,
            Status = dto.Status,
            HireDate = dto.HireDate,
            Salary = dto.Salary,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        }

        db.Employees.Add(employee)
        await db.SaveChangesAsync()

        return CreatedAtAction(nameof(GetById), new { id = employee.Id }, employee)
    }

    // PUT /api/employees/{id} - Update an employee
    [HttpPut("{id}")]
    func async Update(id: Guid, dto: UpdateEmployeeDto): IActionResult {
        existing := await db.Employees.FindAsync(id)
        if existing == null {
            return NotFound()
        }

        // Validate
        errors := ValidateUpdateEmployee(dto)
        if errors.Length > 0 {
            return BadRequest(new { errors = errors })
        }

        // Update properties (only if provided)
        if dto.FirstName != null {
            existing.FirstName = dto.FirstName
        }
        if dto.LastName != null {
            existing.LastName = dto.LastName
        }
        if dto.Email != null {
            existing.Email = dto.Email
        }
        if dto.Department != null {
            existing.Department = dto.Department
        }
        if dto.Status != null {
            existing.Status = dto.Status
        }
        if dto.Salary != null {
            existing.Salary = dto.Salary
        }
        existing.UpdatedAt = DateTime.UtcNow

        await db.SaveChangesAsync()

        return Ok(existing)
    }

    // DELETE /api/employees/{id} - Delete an employee
    [HttpDelete("{id}")]
    func async Delete(id: Guid): IActionResult {
        employee := await db.Employees.FindAsync(id)

        if employee == null {
            return NotFound()
        }

        db.Employees.Remove(employee)
        await db.SaveChangesAsync()

        return NoContent()
    }

    // GET /api/employees/status/{status} - Get employees by status
    [HttpGet("status/{status}")]
    func async GetByStatus(status: string): IActionResult {
        employees := await db.Employees
            .Where(e => e.Status == status)
            .ToArrayAsync()

        return Ok(employees)
    }

    // GET /api/employees/department/{department} - Get employees by department
    [HttpGet("department/{department}")]
    func async GetByDepartment(department: string): IActionResult {
        employees := await db.Employees
            .Where(e => e.Department == department)
            .ToArrayAsync()

        return Ok(employees)
    }
}

// ============================================================================
// VALIDATION
// ============================================================================

func ValidateCreateEmployee(dto: CreateEmployeeDto): string[] {
    errors := new System.Collections.Generic.List<string>()

    if dto.FirstName == null || dto.FirstName.Length == 0 {
        errors.Add("First name is required")
    }

    if dto.FirstName != null && dto.FirstName.Length > 100 {
        errors.Add("First name must be 100 characters or less")
    }

    if dto.LastName == null || dto.LastName.Length == 0 {
        errors.Add("Last name is required")
    }

    if dto.LastName != null && dto.LastName.Length > 100 {
        errors.Add("Last name must be 100 characters or less")
    }

    if dto.Email == null || dto.Email.Length == 0 {
        errors.Add("Email is required")
    }

    if dto.Email != null && dto.Email.Length > 200 {
        errors.Add("Email must be 200 characters or less")
    }

    if dto.Department == null {
        errors.Add("Department is required")
    }

    if dto.Status == null {
        errors.Add("Status is required")
    }

    if dto.Salary != null && dto.Salary < 0 {
        errors.Add("Salary cannot be negative")
    }

    return errors.ToArray()
}

func ValidateUpdateEmployee(dto: UpdateEmployeeDto): string[] {
    errors := new System.Collections.Generic.List<string>()

    if dto.FirstName != null && dto.FirstName.Length == 0 {
        errors.Add("First name cannot be empty")
    }

    if dto.FirstName != null && dto.FirstName.Length > 100 {
        errors.Add("First name must be 100 characters or less")
    }

    if dto.LastName != null && dto.LastName.Length == 0 {
        errors.Add("Last name cannot be empty")
    }

    if dto.LastName != null && dto.LastName.Length > 100 {
        errors.Add("Last name must be 100 characters or less")
    }

    if dto.Email != null && dto.Email.Length == 0 {
        errors.Add("Email cannot be empty")
    }

    if dto.Email != null && dto.Email.Length > 200 {
        errors.Add("Email must be 200 characters or less")
    }

    if dto.Salary != null && dto.Salary < 0 {
        errors.Add("Salary cannot be negative")
    }

    return errors.ToArray()
}
