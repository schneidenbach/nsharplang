namespace NSharpLang.Compiler

import System

class SoaFeature {
    static EnvironmentVariable: string => "NSHARP_EXPERIMENTAL_SOA"

    static IsEnabled: bool => IsEnabledValue()

    static func IsEnabledValue(): bool {
        value := Environment.GetEnvironmentVariable(SoaFeature.EnvironmentVariable)
        return value != null && !string.Equals(value, "0", StringComparison.OrdinalIgnoreCase) && !string.Equals(value, "false", StringComparison.OrdinalIgnoreCase)
    }
}
