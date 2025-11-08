namespace AspNetCoreApi

using System
using System.Linq
using System.Collections.Generic
using AspNetCoreApi.Models
using AspNetCoreApi.Services

import "Models/WeatherForecast"
import "Services/WeatherService"

// Console demo demonstrating:
// - Service instantiation
// - LINQ operations
// - Pattern matching
// - Tuple deconstruction
// - Null safety
// - String interpolation

func Main() {
    print "Weather API Demo"
    print "================"
    print ""

    // Create service
    service := new WeatherService()

    // Get 7-day forecast
    print "7-Day Weather Forecast:"
    forecasts := service.GetForecasts(7)

    for forecast in forecasts {
        summary := forecast.Summary ?? "Unknown"
        print $"  {forecast.Date:yyyy-MM-dd}: {forecast.TemperatureC}°C ({forecast.TemperatureF}°F) - {summary}"
    }

    print ""

    // Get single day forecast
    print "Forecast for day 3:"
    dayForecast := service.GetForecast(3)
    print $"  {dayForecast.Date:yyyy-MM-dd}: {dayForecast.TemperatureC}°C - {dayForecast.Summary}"

    print ""

    // Get statistics using tuple deconstruction
    print "Weather Statistics (7 days):"
    stats := service.GetStatistics(7)
    print $"  Average: {stats.avgTemp}°C"
    print $"  Minimum: {stats.minTemp}°C"
    print $"  Maximum: {stats.maxTemp}°C"

    print ""

    // Filter using LINQ
    print "Hot days (>= 25°C):"
    hotDays := forecasts.Where(f => f.TemperatureC >= 25).ToArray()

    if hotDays.Length > 0 {
        for day in hotDays {
            print $"  {day.Date:yyyy-MM-dd}: {day.TemperatureC}°C"
        }
    } else {
        print "  None"
    }
}
