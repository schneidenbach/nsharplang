namespace WeatherDemo.Models


// Record with computed properties - demonstrates immutable data types
record WeatherForecast {
    Date: DateTime
    TemperatureC: int
    Summary: string?

    // Expression-bodied computed property (C# 6+)
    TemperatureF: int => 32 + (TemperatureC * 9 / 5)
}
