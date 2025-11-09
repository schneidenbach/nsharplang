import Microsoft.EntityFrameworkCore

package EmployeeApi.Database

// Entity Framework Core database context
class AppDbContext : DbContext {
    // Constructor accepting options and passing to base
    constructor(options: DbContextOptions<AppDbContext>): base(options) {}

    // DbSet for EmployeeEntity - EF Core will auto-implement this
    Employees: DbSet<EmployeeEntity>?
}
