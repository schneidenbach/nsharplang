# Weather Demo - Multi-File N# Project

This example demonstrates a complete multi-file N# application showcasing advanced language features and multi-file compilation.

## Project Structure

```
WeatherDemo/
├── project.yml                    # Project configuration
├── Program.nl                     # Main entry point
├── Models/
│   └── WeatherForecast.nl        # Data model (record)
└── Services/
    └── WeatherService.nl         # Business logic service
```

## Features Demonstrated

### Language Features
- ✅ **Records** - Immutable data types with value equality (WeatherForecast)
- ✅ **Expression-bodied properties** - Computed properties (TemperatureF)
- ✅ **Pattern matching with guards** - Temperature classification
- ✅ **LINQ operations** - Data filtering and transformation
- ✅ **Null-safe operators** - `??` for null coalescing
- ✅ **String interpolation** - Formatted output with `$"..."`
- ✅ **Named tuples** - Return multiple values with names
- ✅ **Immutable arrays** - `immutable [...]` syntax
- ✅ **Default parameter values** - Optional function parameters
- ✅ **PascalCase/camelCase visibility** - Convention-based access modifiers
- ✅ **Multi-file compilation** - Types defined across multiple files
- ✅ **Import system** - Cross-file type references
- ✅ **Namespaces** - Organized code structure

### Project Features
- ✅ **project.yml configuration** - Version, dependencies, language settings
- ✅ **Multi-file compilation** - Three .nl files compiled together
- ✅ **Cross-file imports** - Services using Models types

## How to Run

```bash
# From the WeatherDemo directory
dotnet build
dotnet run
```

## Code Highlights

### Record with Computed Property
```nl
record WeatherForecast {
    Date: DateTime
    TemperatureC: int
    Summary: string?

    // Expression-bodied computed property
    TemperatureF: int => 32 + (TemperatureC * 9 / 5)
}
```

### Pattern Matching with Guards
```nl
summary := match temp {
    t when t < 0 => "Freezing",
    t when t < 10 => "Cold",
    t when t < 20 => "Mild",
    t when t >= 30 => "Hot",
    _ => "Warm"
}
```

### LINQ with Lambdas
```nl
forecasts := Enumerable
    .Range(0, days)
    .Select(index => new WeatherForecast {
        Date: DateTime.Now.AddDays(index),
        TemperatureC: Random.Shared.Next(-20, 55),
        Summary: summaries[Random.Shared.Next(summaries.Length)]
    })
    .ToArray()
```

### Named Tuple Return
```nl
func GetStatistics(days: int = 7): (avgTemp: int, minTemp: int, maxTemp: int) {
    forecasts := GetForecasts(days)
    temps := forecasts.Select(f => f.TemperatureC).ToArray()

    avgTemp := (int)temps.Average()
    minTemp := temps.Min()
    maxTemp := temps.Max()

    return (avgTemp, minTemp, maxTemp)
}
```

## Sample Output

```
Weather API Demo
================

7-Day Weather Forecast:
  2025-11-08: -10°C (14°F) - Sweltering
  2025-11-09: -17°C (2°F) - Scorching
  2025-11-10: 21°C (69°F) - Scorching
  2025-11-11: 20°C (68°F) - Cool
  2025-11-12: 25°C (77°F) - Cool
  2025-11-13: 38°C (100°F) - Hot
  2025-11-14: 33°C (91°F) - Scorching

Forecast for day 3:
  2025-11-12: -2°C - Freezing

Weather Statistics (7 days):
  Average: 14°C
  Minimum: -15°C
  Maximum: 42°C

Hot days (>= 25°C):
  2025-11-12: 25°C
  2025-11-13: 38°C
  2025-11-14: 33°C
```

## Why This Example Matters

This example proves that N# is ready for **real-world multi-file projects**:

1. **Clean separation of concerns** - Models, services, and entry point in separate files
2. **Type-safe cross-file references** - Import system ensures type safety
3. **Modern language features** - Records, pattern matching, LINQ, expression-bodied members
4. **Pragmatic design** - Familiar .NET types and patterns
5. **Production-ready** - Proper project structure with configuration

## Next Steps

- Add more complex business logic
- Implement error handling with automatic exception capture
- Add discriminated unions for API responses
- Create `.tests.nl` files and run them with `dotnet test`
