import YamlDotNet.Serialization.NamingConventions

class ExternalStaticRelativeDllMarker {
}

func HasRelativeCamelCaseNamingConvention(): bool {
    return CamelCaseNamingConvention.Instance != null
}

func Main() {
    print HasRelativeCamelCaseNamingConvention()
}
