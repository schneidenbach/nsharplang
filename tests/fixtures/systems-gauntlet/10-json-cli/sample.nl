import System.Text.Json
import System.Text.Json.Serialization

enum CliError {
    Failed
}

record CliPayload {
    Code: int
}

[JsonSerializable(typeof(CliPayload))]
partial class CliJsonContext : JsonSerializerContext {
}

[boundary]
func EmitJson(payload: CliPayload): Result<string, CliError> {
    return Ok(JsonSerializer.Serialize(payload, CliJsonContext.Default.CliPayload))
}

[hot]
func Score(value: int): Result<int, CliError> {
    return Ok(value)
}
