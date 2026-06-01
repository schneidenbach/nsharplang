namespace SystemsProofs.MonoWasmPlugin

import System

public struct PluginInput {
    A: int
    B: int
}

public struct PluginOutput {
    Sum: int
    Product: int
}

public class Plugin {
    [hot]
    [aotSafe(mono-wasm)]
    public static func Run(input: PluginInput): PluginOutput {
        return PluginOutput {
            Sum: input.A + input.B,
            Product: input.A * input.B
        }
    }
}
