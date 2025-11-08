namespace AspNetCoreApi.Services

using System
using System.Linq
using AspNetCoreApi.Models

import "../Models/WeatherForecast"

// Service class demonstrating:
// - Class with private field (camelCase = private)
// - Default parameter values
// - LINQ operations (Range, Select, ToArray)
// - Pattern matching with guards
// - Null safety with nullable return type
// - Object initialization syntax
class WeatherService {
    summaries: string[] = immutable [
        "Freezing", "Bracing", "Chilly", "Cool", "Mild",
        "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
    ]

    // Generate multiple forecasts using LINQ
    func GetForecasts(days: int = 5): WeatherForecast[] {
        return Enumerable
            .Range(0, days)
            .Select(index => new WeatherForecast {
                Date: DateTime.Now.AddDays(index),
                TemperatureC: Random.Shared.Next(-20, 55),
                Summary: summaries[Random.Shared.Next(summaries.Length)]
            })
            .ToArray()
    }

    // Get single forecast with pattern matching
    func GetForecast(day: int): WeatherForecast {
        temp := Random.Shared.Next(-20, 55)

        // Pattern matching with guards to determine summary
        summary := match temp {
            t when t < 0 => "Freezing",
            t when t < 10 => "Cold",
            t when t < 20 => "Mild",
            t when t >= 30 => "Hot",
            _ => "Warm"
        }

        return new WeatherForecast {
            Date: DateTime.Now.AddDays(day + 1),
            TemperatureC: temp,
            Summary: summary
        }
    }

    // Get forecast summary statistics
    func GetStatistics(days: int = 7): (avgTemp: int, minTemp: int, maxTemp: int) {
        forecasts := GetForecasts(days)

        temps := forecasts.Select(f => f.TemperatureC).ToArray()

        avgTemp := (int)temps.Average()
        minTemp := temps.Min()
        maxTemp := temps.Max()

        return (avgTemp, minTemp, maxTemp)
    }
}
