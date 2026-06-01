namespace SystemsProofs.CliStartupHonesty

import System
import System.Text.Json
import System.Text.Json.Serialization

record StartupReport {
    Ready: bool
    Mode: string
}

[JsonSerializable(typeof(StartupReport))]
partial class StartupJsonContext : JsonSerializerContext {
}

[boundary]
func Warmup() {
    _ = JsonSerializer.Serialize(
        StartupReport { Ready: true, Mode: "warmup" },
        StartupJsonContext.Default.StartupReport)
}

[boundary]
func Main() {
    Warmup()
    report := StartupReport { Ready: true, Mode: "run" }
    print JsonSerializer.Serialize(report, StartupJsonContext.Default.StartupReport)
}
