using System
using System.Linq
using WeatherDemo.Models
using WeatherDemo.Services

class Program {
    static func Main() {
        // Create service instance
        service := new WeatherService()

        // Header
        print "Weather API Demo"
        print "================"
        print ""

        // 7-day forecast
        print "7-Day Weather Forecast:"
        forecasts := service.GetForecasts(7)
        for forecast in forecasts {
            // String interpolation with computed property
            summary := forecast.Summary ?? "Unknown"
            print $"  {forecast.Date:yyyy-MM-dd}: {forecast.TemperatureC}°C ({forecast.TemperatureF}°F) - {summary}"
        }
        print ""

        // Single day forecast
        print "Forecast for day 3:"
        dayForecast := service.GetForecast(3)
        print $"  {dayForecast.Date:yyyy-MM-dd}: {dayForecast.TemperatureC}°C - {dayForecast.Summary}"
        print ""

        // Min/max temperature
        print "Temperature Range (7 days):"
        tempRange := service.GetMinMaxTemp(7)
        print $"  Minimum: {tempRange.Item1}°C"
        print $"  Maximum: {tempRange.Item2}°C"
        print ""

        // Hot days demonstration
        print "Hot days (>= 25°C):"
        hotDays := service.GetHotDaysSummary(7)
        if hotDays.Length > 0 {
            for day in hotDays {
                print $"  {day}"
            }
        } else {
            print "  No hot days this week!"
        }
    }
}
