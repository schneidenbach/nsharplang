import System
import System.Reflection.Emit
import YamlDotNet.Serialization.NamingConventions

class ExternalStaticPackageMarker {
}

func HasCamelCaseNamingConvention(): bool {
    return CamelCaseNamingConvention.Instance != null
}

func ReadEnvironmentNewLine(): string {
    return Environment.NewLine
}

func ReadUtcNow(): DateTime {
    return DateTime.UtcNow
}

func ReadFullyQualifiedOpcode(): OpCode {
    return System.Reflection.Emit.OpCodes.Ldsfld
}

func Main() {
    print HasCamelCaseNamingConvention()
}
