namespace NSharpLang.Cli

public record CliCommandSpec(
    Name: string,
    Description: string,
    AliasOf: string? = null) {
    IsAlias: bool => AliasOf != null
}
