namespace AspNetCoreApi.Models

using System

// Record demonstrating:
// - Record syntax with value equality
// - Expression-bodied property (TemperatureF)
// - PascalCase = public visibility
// - Nullable string type
record WeatherForecast {
    Date: DateTime
    TemperatureC: int
    Summary: string?

    // Expression-bodied computed property
    TemperatureF: int => 32 + (TemperatureC * 9 / 5)
}
