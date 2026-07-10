import System.IO

test "project-relative DLL static field resolves outside the project working directory" {
    outputDirectory := Path.GetDirectoryName(typeof(ExternalStaticRelativeDllMarker).get_Assembly().get_Location())

    assert outputDirectory != null
    assert File.Exists(Path.Combine(outputDirectory, "YamlDotNet.dll"))
    assert File.Exists(Path.Combine(outputDirectory, "NSharpLang.Compiler.BootstrapServices.dll"))

    assert HasRelativeCamelCaseNamingConvention()
}
