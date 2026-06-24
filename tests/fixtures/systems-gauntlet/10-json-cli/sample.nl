import System.Text.Json

enum CliError {
    Failed
}

record CliPayload {
    Code: int
}

[boundary]
func EmitJson(payload: CliPayload): Result<string, CliError> {
    return Ok(JsonSerializer.Serialize(payload))
}

[hot]
func Score(value: int): Result<int, CliError> {
    return Ok(value)
}
