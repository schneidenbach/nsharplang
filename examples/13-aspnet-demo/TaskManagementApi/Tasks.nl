import System
import System.ComponentModel.DataAnnotations
import Microsoft.AspNetCore.Mvc
import Microsoft.EntityFrameworkCore
import System.Threading.Tasks
import System.Linq

package TaskManagementApi

// ============================================================================
// DOMAIN: Status Constants
// ============================================================================

// Task status constants
class TaskStatus {
    static Todo: string = "todo"
    static InProgress: string = "in_progress"
    static Done: string = "done"
}

// Priority level constants
class Priority {
    static Low: string = "low"
    static Medium: string = "medium"
    static High: string = "high"
}

// ============================================================================
// ENTITY: TaskEntity
// ============================================================================

// Main task entity - represents a task in our system
class TaskEntity {
    // Unique identifier
    Id: Guid

    // Task title (required, max 200 characters)
    [Required]
    [MaxLength(200)]
    Title: string

    // Optional description
    Description: string?

    // Current status of the task
    Status: string

    // Priority level
    Priority: string

    // Optional due date
    DueDate: DateTime?

    // When the task was completed
    CompletedAt: DateTime?

    // Metadata
    CreatedAt: DateTime
    UpdatedAt: DateTime
}

// ============================================================================
// DTOs: Data Transfer Objects
// ============================================================================

// DTO for creating a new task
class CreateTaskDto {
    [Required]
    [MaxLength(200)]
    Title: string

    Description: string?
    Status: string
    Priority: string
    DueDate: DateTime?
}

// DTO for updating a task
class UpdateTaskDto {
    [Required]
    [MaxLength(200)]
    Title: string

    Description: string?
    Status: string
    Priority: string
    DueDate: DateTime?
}

// ============================================================================
// CONTROLLER: Tasks API Endpoints
// ============================================================================

[ApiController]
[Route("api/tasks")]
class TasksController : ControllerBase {
    db: AppDbContext

    // Constructor with dependency injection
    constructor(context: AppDbContext) {
        db = context
    }

    // GET /api/tasks - Get all tasks
    [HttpGet]
    func GetAll(): Task<IActionResult> async {
        tasks := await db.Tasks.ToArrayAsync()
        return Ok(tasks)
    }

    // GET /api/tasks/{id} - Get task by ID
    [HttpGet("{id}")]
    func GetById(id: Guid): Task<IActionResult> async {
        task := await db.Tasks.FindAsync(id)

        return match task {
            null => NotFound(),
            _ => Ok(task)
        }
    }

    // POST /api/tasks - Create a new task
    [HttpPost]
    func Create([FromBody] dto: CreateTaskDto): Task<IActionResult> async {
        // Validate
        errors := ValidateCreateTask(dto)
        if errors.Length > 0 {
            return BadRequest(new { errors = errors })
        }

        // Create entity
        task := new TaskEntity {
            Id = Guid.NewGuid(),
            Title = dto.Title,
            Description = dto.Description,
            Status = dto.Status,
            Priority = dto.Priority,
            DueDate = dto.DueDate,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        }

        db.Tasks.Add(task)
        await db.SaveChangesAsync()

        return CreatedAtAction(nameof(GetById), new { id = task.Id }, task)
    }

    // PUT /api/tasks/{id} - Update a task
    [HttpPut("{id}")]
    func Update(id: Guid, [FromBody] dto: UpdateTaskDto): Task<IActionResult> async {
        existing := await db.Tasks.FindAsync(id)
        if existing == null {
            return NotFound()
        }

        // Validate
        errors := ValidateUpdateTask(dto)
        if errors.Length > 0 {
            return BadRequest(new { errors = errors })
        }

        // Update properties
        existing.Title = dto.Title
        existing.Description = dto.Description
        existing.Status = dto.Status
        existing.Priority = dto.Priority
        existing.DueDate = dto.DueDate
        existing.UpdatedAt = DateTime.UtcNow

        // Set completion time if status changed to done
        if dto.Status == TaskStatus.Done && existing.CompletedAt == null {
            existing.CompletedAt = DateTime.UtcNow
        }

        await db.SaveChangesAsync()

        return Ok(existing)
    }

    // DELETE /api/tasks/{id} - Delete a task
    [HttpDelete("{id}")]
    func Delete(id: Guid): Task<IActionResult> async {
        task := await db.Tasks.FindAsync(id)

        if task == null {
            return NotFound()
        }

        db.Tasks.Remove(task)
        await db.SaveChangesAsync()

        return NoContent()
    }

    // GET /api/tasks/status/{status} - Get tasks by status
    [HttpGet("status/{status}")]
    func GetByStatus(status: string): Task<IActionResult> async {
        tasks := await db.Tasks
            .Where((t) => t.Status == status)
            .ToArrayAsync()

        return Ok(tasks)
    }

    // GET /api/tasks/priority/{priority} - Get tasks by priority
    [HttpGet("priority/{priority}")]
    func GetByPriority(priority: string): Task<IActionResult> async {
        tasks := await db.Tasks
            .Where((t) => t.Priority == priority)
            .ToArrayAsync()

        return Ok(tasks)
    }
}

// ============================================================================
// VALIDATION
// ============================================================================

func ValidateCreateTask(dto: CreateTaskDto): string[] {
    errors := new System.Collections.Generic.List<string>()

    if dto.Title == null || dto.Title.Length == 0 {
        errors.Add("Title is required")
    }

    if dto.Title != null && dto.Title.Length > 200 {
        errors.Add("Title must be 200 characters or less")
    }

    if dto.Status == null {
        errors.Add("Status is required")
    }

    if dto.Priority == null {
        errors.Add("Priority is required")
    }

    if dto.DueDate != null && dto.DueDate < DateTime.UtcNow {
        errors.Add("Due date cannot be in the past")
    }

    return errors.ToArray()
}

func ValidateUpdateTask(dto: UpdateTaskDto): string[] {
    errors := new System.Collections.Generic.List<string>()

    if dto.Title == null || dto.Title.Length == 0 {
        errors.Add("Title is required")
    }

    if dto.Title != null && dto.Title.Length > 200 {
        errors.Add("Title must be 200 characters or less")
    }

    if dto.Status == null {
        errors.Add("Status is required")
    }

    if dto.Priority == null {
        errors.Add("Priority is required")
    }

    return errors.ToArray()
}
