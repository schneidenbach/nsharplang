namespace SystemsProofs.MonoWasmPlugin

public struct PluginInput {
    A: int
    B: int

    constructor(a: int, b: int) {
        A = a
        B = b
    }
}

public struct PluginOutput {
    Sum: int
    Product: int

    constructor(sum: int, product: int) {
        Sum = sum
        Product = product
    }
}

public class Plugin {
    [hot]
    [aotSafe(mono-wasm)]
    public static func Run(input: PluginInput): PluginOutput {
        output := new PluginOutput(input.A + input.B, input.A * input.B)
        return output
    }
}
