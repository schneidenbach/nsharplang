namespace NSharpLang.Compiler

import System
import System.IO

func SdkProjectReferenceTree(): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-sdk-project-reference-" + Guid.NewGuid().ToString("N"))
    app := Path.Combine(root, "App")
    shared := Path.Combine(root, "Shared")
    other := Path.Combine(root, "Other")
    Directory.CreateDirectory(app)
    Directory.CreateDirectory(shared)
    Directory.CreateDirectory(other)
    File.WriteAllText(Path.Combine(shared, "project.yml"), "name: Shared\noutputType: library\n")
    File.WriteAllText(Path.Combine(shared, "Shared.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
    File.WriteAllText(Path.Combine(other, "Other.csproj"), "<Project Sdk=\"Microsoft.NET.Sdk\" />\n")
    File.WriteAllText(Path.Combine(app, "Local.dll"), "")
    File.WriteAllText(
        Path.Combine(app, "project.yml"),
        "name: App\n" + "dependencies:\n" + "  - nuget: Serilog\n" + "    version: 3.1.1\n" + "  - project: ../Shared/project.yml\n" + "  - framework: Microsoft.AspNetCore.App\n" + "  - project: ../Shared/Shared.csproj\n" + "  - dll: Local.dll\n" + "  - project: ../Other/Other.csproj\n"
    )
    return root
}

test "SDK project references resolve relative YAML and csproj paths then deduplicate in source order" {
    root := SdkProjectReferenceTree()
    try {
        projectFile := Path.Combine(Path.Combine(root, "App"), "project.yml")
        config := ProjectFileParser.Parse(projectFile)
        projected := SdkProjectReferenceProjection.Resolve(projectFile, config.Dependencies, new string[](0))
        assert projected.Length == 2
        assert projected[0] == Path.Combine(Path.Combine(root, "Shared"), "Shared.csproj")
        assert projected[1] == Path.Combine(Path.Combine(root, "Other"), "Other.csproj")
    } finally {
        Directory.Delete(root, true)
    }
}

test "SDK project references do not add an existing generated-props row again" {
    root := SdkProjectReferenceTree()
    try {
        projectFile := Path.Combine(Path.Combine(root, "App"), "project.yml")
        config := ProjectFileParser.Parse(projectFile)
        shared := Path.Combine(Path.Combine(root, "Shared"), "Shared.csproj")
        other := Path.Combine(Path.Combine(root, "Other"), "Other.csproj")
        projected := SdkProjectReferenceProjection.Resolve(projectFile, config.Dependencies, [shared, shared])
        assert projected.Length == 1
        assert projected[0] == other
    } finally {
        Directory.Delete(root, true)
    }
}

test "SDK project references exclude package framework and DLL dependencies" {
    root := SdkProjectReferenceTree()
    try {
        projectFile := Path.Combine(Path.Combine(root, "App"), "project.yml")
        config := ProjectFileParser.Parse(projectFile)
        shared := Path.Combine(Path.Combine(root, "Shared"), "Shared.csproj")
        other := Path.Combine(Path.Combine(root, "Other"), "Other.csproj")
        projected := SdkProjectReferenceProjection.Resolve(projectFile, config.Dependencies, [shared, other])
        assert projected.Length == 0
    } finally {
        Directory.Delete(root, true)
    }
}
