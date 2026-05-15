import Microsoft.AspNetCore.Mvc

[ApiController]
[Route("api/weather")]
class WeatherController: ControllerBase {
    [HttpGet]
    func Get(): IActionResult {
        data := ["Sunny", "Cloudy", "Rainy"]
        return Ok(data)
    }

    [HttpGet("{id}")]
    func GetById([FromRoute] id: int): IActionResult {
        return Ok(id)
    }

    [HttpPost]
    func Create([FromBody] request: CreateWeatherRequest): IActionResult {
        return Ok(request)
    }
}

class CreateWeatherRequest {
    Summary: string
    TemperatureC: int
}
