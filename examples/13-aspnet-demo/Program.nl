import Microsoft.AspNetCore.Builder
import Microsoft.Extensions.DependencyInjection
import Microsoft.EntityFrameworkCore
import Microsoft.Extensions.Hosting
import System

package EmployeeApi

// Entry point for the ASP.NET Core application
func main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)

    // Add services to the container
    builder.Services.AddControllers()
    builder.Services.AddEndpointsApiExplorer()
    builder.Services.AddSwaggerGen()

    // Add database context with SQLite (skip for test environment)
    if builder.Environment.EnvironmentName != "Testing" {
        builder.Services.AddDbContext<AppDbContext>(options => {
            options.UseSqlite("Data Source=employees.db")
        })
    }

    app := builder.Build()

    // Ensure database is created (skip for in-memory databases used in tests)
    if !app.Environment.EnvironmentName.Contains("Test") {
        scope := app.Services.CreateScope()
        db := scope.ServiceProvider.GetRequiredService<AppDbContext>()

        // Only call EnsureCreated for non-in-memory databases
        if db.Database.ProviderName != "Microsoft.EntityFrameworkCore.InMemory" {
            db.Database.EnsureCreated()
        }

        scope.Dispose()
    }

    // Configure the HTTP request pipeline
    if app.Environment.IsDevelopment() {
        app.UseSwagger()
        app.UseSwaggerUI()
    }

    app.UseHttpsRedirection()
    app.UseAuthorization()
    app.MapControllers()

    app.Run()
}
