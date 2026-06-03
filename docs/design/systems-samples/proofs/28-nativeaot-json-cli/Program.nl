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

    return Ok(new CliOptions { Input: args[0], Verbose: args.Length > 1 })
}

[boundary]
func Main(): int {
    rawArgs := Environment.GetCommandLineArgs()
    args := new string[rawArgs.Length - 1]
    for i := 1; i < rawArgs.Length; i++ {
        args[i - 1] = rawArgs[i]
    }

    options := ParseArgs(args)
    if options.IsOk == false {
        Console.Error.WriteLine(options.ErrValueUnchecked)
        return 1
    }

    json := JsonSerializer.Serialize(options.OkValueUnchecked, CliJsonContext.Default.CliOptions)
    Console.Out.WriteLine(json)
    return 0
}
