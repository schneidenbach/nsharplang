// PARITY CORPUS (Arc M1): checksum oracles extracted from
// src/NSharpLang.Compiler.Dogfood/CompilerServices/CompletionReceivers.nl. These functions exist solely as
// parity-test surfaces (tests + benchmarks bind them by NAME and compile them TOGETHER with
// their product file — most delegate to sibling kernels that stay in the product). They are
// NOT part of the shipped dogfood assembly.

func CodeIntelligenceCompletionReceiverChecksumInto(
    prefixes: string[],
    resultContexts: int[],
    resultReceivers: string[]): int {
    count := CodeIntelligenceCompletionReceiversInto(prefixes, resultContexts, resultReceivers)
    checksum := count
    i := 0

    while i < count {
        checksum = checksum + resultContexts[i] * 31 + resultReceivers[i].Length * 17
        i = i + 1
    }

    return checksum
}
