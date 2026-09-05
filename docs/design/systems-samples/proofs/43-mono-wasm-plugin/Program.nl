namespace SystemsProofs.MonoWasmPlugin

struct PluginInput {
    A: int
    B: int

    constructor(a: int, b: int) {
        A = a
        B = b
    }
}

struct PluginOutput {
    Sum: int
    Product: int

    constructor(sum: int, product: int) {
        Sum = sum
        Product = product
    }
}

class Plugin {
    [hot]
    [aotSafe(mono-wasm)]
    static func Run(input: PluginInput): PluginOutput {
        output := new PluginOutput(input.A + input.B, input.A * input.B)
        return output
    }
}
