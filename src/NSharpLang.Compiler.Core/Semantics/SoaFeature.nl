namespace NSharpLang.Compiler

import System

// THE ENVIRONMENT'S ANSWER TO "IS THE EXPERIMENTAL `soa record` LOWERING ON?", read at the two entry
// points that own a compilation - `Analyzer` and `MultiFileCompiler`, each when it is built - and
// carried from there as that compilation's `SoaEnabled`. Nothing downstream reads the variable again,
// so a caller that wants the other answer sets the property instead of rewriting the environment.
class SoaFeature {
    static EnvironmentVariable: string => "NSHARP_EXPERIMENTAL_SOA"

    static IsEnabled: bool => IsEnabledValue()

    static func IsEnabledValue(): bool {
        value := Environment.GetEnvironmentVariable(SoaFeature.EnvironmentVariable)
        return value != null && !string.Equals(value, "0", StringComparison.OrdinalIgnoreCase) && !string.Equals(value, "false", StringComparison.OrdinalIgnoreCase)
    }
}
