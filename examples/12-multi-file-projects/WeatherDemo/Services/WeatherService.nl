namespace WeatherDemo.Services

import System
import System.Linq
import WeatherDemo.Models

// Business logic service demonstrating N# features
class WeatherService {
    // Private field (camelCase = private)
    summaries: string[] = [
        "Freezing", "Bracing", "Chilly", "Cool", "Mild",
        "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
    ]

    // Default parameter values
    func GetForecasts(days: int = 5): WeatherForecast[] {
        // LINQ with lambdas and collection expressions
        return Enumerable
            .Range(0, days)
            .Select(index => new WeatherForecast {
                Date: DateTime.Now.AddDays(index),
                TemperatureC: Random.Shared.Next(-20, 55),
                Summary: summaries[Random.Shared.Next(summaries.Length)]
            })
            .ToArray()
    }

    // Pattern matching with guards for classification
    func GetForecast(day: int): WeatherForecast {
        temp := Random.Shared.Next(-20, 55)

        // Pattern matching with guards - elegant!
        summary := match temp {
            t when t < 0 => "Freezing",
            t when t < 10 => "Cold",
            t when t < 20 => "Mild",
            t when t >= 30 => "Hot",
            _ => "Warm"
        }

        return new WeatherForecast {
            Date: DateTime.Now.AddDays(day),
            TemperatureC: temp,
            Summary: summary
        }
    }

    // Method with multiple return values
    func GetMinMaxTemp(days: int = 7): (int, int) {
        forecasts := GetForecasts(days)
        temps := forecasts.Select(f => f.TemperatureC).ToArray()

        minTemp := temps.Min()
        maxTemp := temps.Max()

        return (minTemp, maxTemp)
    }

    // Returns array with hot days
    func GetHotDaysSummary(days: int = 7): string[] {
        forecasts := GetForecasts(days)

        // LINQ filtering and transformation
        hotDays := forecasts
            .Where(f => f.TemperatureC >= 25)
            .Select(f => $"{f.Date:yyyy-MM-dd}: {f.TemperatureC}°C")
            .ToArray()

        return hotDays
    }
}
