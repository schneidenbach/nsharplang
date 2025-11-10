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
