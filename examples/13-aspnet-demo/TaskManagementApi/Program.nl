import Microsoft.AspNetCore.Builder
import Microsoft.Extensions.DependencyInjection
import Microsoft.EntityFrameworkCore
import Microsoft.Extensions.Hosting

package TaskManagementApi

// Entry point for the ASP.NET Core application
func Main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)

    // Add services to the container
    builder.Services.AddControllers()
    builder.Services.AddEndpointsApiExplorer()
    builder.Services.AddSwaggerGen()

    // Add database context with SQLite
    builder.Services.AddDbContext<AppDbContext>((options) => {
        options.UseSqlite("Data Source=tasks.db")
    })

    app := builder.Build()

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
