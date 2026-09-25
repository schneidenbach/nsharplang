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
        "name: App\n" + "dependencies:\n" + "  - nuget: Serilog\n" + "    version: 3.1.1\n" + "  - project: ../Shared/project.yml\n" + "  - framework: Microsoft.AspNetCore.App\n" + "  - nuget: Humanizer\n" + "  - project: ../Shared/Shared.csproj\n" + "  - dll: Local.dll\n" + "  - project: ../Other/Other.csproj\n"
    )
    return root
}

test "SDK references map package metadata frameworks and projects in source order while excluding DLLs" {
    root := SdkProjectReferenceTree()
    try {
        projectFile := Path.Combine(Path.Combine(root, "App"), "project.yml")
        projected := SdkProjectReferenceProjection.Resolve(projectFile, new string[](0))
        assert projected.PackageReferences.Length == 2
        assert projected.PackageReferences[0].Identity == "Serilog"
        assert projected.PackageReferences[0].Metadata.Count == 1
        assert projected.PackageReferences[0].Metadata["Version"] == "3.1.1"
        assert projected.PackageReferences[1].Identity == "Humanizer"
        assert projected.PackageReferences[1].Metadata.Count == 0
        assert projected.FrameworkReferences.Length == 1
        assert projected.FrameworkReferences[0] == "Microsoft.AspNetCore.App"
        assert projected.ProjectReferences.Length == 2
        assert projected.ProjectReferences[0] == Path.Combine(Path.Combine(root, "Shared"), "Shared.csproj")
        assert projected.ProjectReferences[1] == Path.Combine(Path.Combine(root, "Other"), "Other.csproj")
    } finally {
        Directory.Delete(root, true)
    }
}

test "SDK references do not add an existing generated-props project row again" {
    root := SdkProjectReferenceTree()
    try {
        projectFile := Path.Combine(Path.Combine(root, "App"), "project.yml")
        shared := Path.Combine(Path.Combine(root, "Shared"), "Shared.csproj")
        other := Path.Combine(Path.Combine(root, "Other"), "Other.csproj")
        projected := SdkProjectReferenceProjection.Resolve(projectFile, [shared, shared])
        assert projected.ProjectReferences.Length == 1
        assert projected.ProjectReferences[0] == other
    } finally {
        Directory.Delete(root, true)
    }
}

test "SDK references retain package and framework rows when every project row already exists" {
    root := SdkProjectReferenceTree()
    try {
        projectFile := Path.Combine(Path.Combine(root, "App"), "project.yml")
        shared := Path.Combine(Path.Combine(root, "Shared"), "Shared.csproj")
        other := Path.Combine(Path.Combine(root, "Other"), "Other.csproj")
        projected := SdkProjectReferenceProjection.Resolve(projectFile, [shared, other])
        assert projected.PackageReferences.Length == 2
        assert projected.FrameworkReferences.Length == 1
        assert projected.ProjectReferences.Length == 0
    } finally {
        Directory.Delete(root, true)
    }
}
