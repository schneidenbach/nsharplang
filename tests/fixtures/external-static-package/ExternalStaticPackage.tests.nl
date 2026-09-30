import System.IO

test "package route executes YamlDotNet static field and external static property" {
    outputDirectory := Path.GetDirectoryName(
        typeof(ExternalStaticPackageMarker).get_Assembly().get_Location())
    assert outputDirectory != null
    assert File.Exists(Path.Combine(outputDirectory, "YamlDotNet.dll"))
    assert File.Exists(Path.Combine(
        outputDirectory, "Microsoft.Build.Framework.dll"))
    assert HasCamelCaseNamingConvention()
    assert ReadEnvironmentNewLine().Length > 0
    assert ReadUtcNow().Year >= 2026
    opcode: object = ReadFullyQualifiedOpcode()
    assert opcode.ToString() == "ldsfld"
    folder: object = System.Environment.SpecialFolder.UserProfile
    assert folder.ToString() == "UserProfile"
}
