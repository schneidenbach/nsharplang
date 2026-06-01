namespace SystemsProofs.NativeAotJsonCli

import System
import System.Text.Json
import System.Text.Json.Serialization

record CliOptions {
    Input: string
    Verbose: bool
}

[JsonSerializable(typeof(CliOptions))]
partial class CliJsonContext : JsonSerializerContext {
}

[boundary]
func ParseArgs(args: string[]): Result<CliOptions, string> {
    if args.Length < 1 {
        return Err("missing input")
    }

    return Ok(CliOptions { Input: args[0], Verbose: args.Length > 1 })
}

[boundary]
func Main(): int {
    options := ParseArgs(Environment.GetCommandLineArgs())
    json := JsonSerializer.Serialize(options, CliJsonContext.Default.CliOptions)
    Console.Out.WriteLine(json)
    return 0
}
