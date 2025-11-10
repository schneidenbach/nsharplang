import Microsoft.AspNetCore.Builder
import Microsoft.Extensions.DependencyInjection

func main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)

    builder.Services.AddControllers()
    builder.Services.AddEndpointsApiExplorer()
    builder.Services.AddSwaggerGen()

    app := builder.Build()

    app.UseSwagger()
    app.UseSwaggerUI()
    app.UseHttpsRedirection()
    app.UseAuthorization()
    app.MapControllers()

    app.Run()
}
