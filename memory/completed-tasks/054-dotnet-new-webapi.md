# Task 054: dotnet new Web API Template

**Effort:** Small (5-6 hours)
**Depends:** Task 043
**Ships:** `dotnet new nsharp-webapi` works

## Goal

Create ASP.NET Core Web API template.

## Deliverable

Template that creates working Web API project.

## Template Files

**Program.nl:**
```n#
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
```

**Controllers/WeatherController.nl:**
```n#
import Microsoft.AspNetCore.Mvc

[ApiController]
[Route("api/weather")]
class WeatherController : ControllerBase {
    [HttpGet]
    func Get(): IActionResult {
        data := ["Sunny", "Cloudy", "Rainy"]
        return Ok(data)
    }
}
```

**project.yml:**
```yaml
name: WebApi
version: 1.0.0
outputType: exe
targetFramework: net9.0
sdk: Microsoft.NET.Sdk.Web

dependencies:
  - framework: Microsoft.AspNetCore.App
```

## Testing

```bash
dotnet new nsharp-webapi -o MyApi
cd MyApi
dotnet run
curl http://localhost:5000/api/weather
```

## Done When

- [ ] Template creates valid API
- [ ] Swagger UI works
- [ ] Controller returns data
- [ ] Hot reload works
