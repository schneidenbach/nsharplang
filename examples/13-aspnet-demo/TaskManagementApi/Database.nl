import Microsoft.EntityFrameworkCore

package TaskManagementApi

// Entity Framework Core database context
class AppDbContext : DbContext {
    // Constructor accepting options and passing to base
    constructor(options: DbContextOptions<AppDbContext>):
        base(options) {
    }

    // DbSet for TaskEntity - EF Core will auto-implement this
    Tasks: DbSet<TaskEntity>?
}
