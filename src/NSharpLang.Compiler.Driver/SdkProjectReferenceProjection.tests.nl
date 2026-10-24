namespace NSharpLang.Compiler

import System
import System.IO
import NSharpLang.Cli

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

test "SDK references map package metadata frameworks projects and DLLs in source order" {
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
        // A `dll:` row becomes an MSBuild `Reference`, resolved against the project directory, so
        // `dotnet build` copies it beside the output exactly as `nlc build` does.
        assert projected.DllReferences.Length == 1
        assert projected.DllReferences[0] == Path.Combine(Path.Combine(root, "App"), "Local.dll")
    } finally {
        Directory.Delete(root, true)
    }
}

test "SDK DLL references keep an absolute path and drop a second spelling of the same file" {
    root := SdkProjectReferenceTree()
    try {
        app := Path.Combine(root, "App")
        vendor := Path.Combine(root, "Vendor")
        Directory.CreateDirectory(vendor)
        File.WriteAllText(Path.Combine(vendor, "Vendor.dll"), "")
        local := Path.Combine(app, "Local.dll")
        File.WriteAllText(
            Path.Combine(app, "project.yml"),
            "name: App\n" + "dependencies:\n" + "  - dll: ../Vendor/Vendor.dll\n" + "  - dll: " + local + "\n" + "  - dll: ./Local.dll\n"
        )
        projected := SdkProjectReferenceProjection.Resolve(Path.Combine(app, "project.yml"), new string[](0))
        assert projected.DllReferences.Length == 2
        assert projected.DllReferences[0] == Path.Combine(vendor, "Vendor.dll")
        assert projected.DllReferences[1] == local
        assert projected.PackageReferences.Length == 0
        assert projected.ProjectReferences.Length == 0
    } finally {
        Directory.Delete(root, true)
    }
}

test "SDK references leave out Microsoft.NETCore.App, which MSBuild already references implicitly" {
    root := SdkProjectReferenceTree()
    try {
        app := Path.Combine(root, "App")
        File.WriteAllText(
            Path.Combine(app, "project.yml"),
            "name: App\n" + "dependencies:\n" + "  - framework: Microsoft.NETCore.App\n" + "  - framework: Microsoft.AspNetCore.App\n" + "  - framework: microsoft.netcore.app\n"
        )
        projected := SdkProjectReferenceProjection.Resolve(Path.Combine(app, "project.yml"), new string[](0))
        assert projected.FrameworkReferences.Length == 1
        assert projected.FrameworkReferences[0] == "Microsoft.AspNetCore.App"
    } finally {
        Directory.Delete(root, true)
    }
}

test "under the Web SDK Microsoft.AspNetCore.App is implicit too, and under BlazorWebAssembly it is not" {
    root := SdkProjectReferenceTree()
    try {
        app := Path.Combine(root, "App")
        dependencies := "dependencies:\n" + "  - framework: Microsoft.AspNetCore.App\n" + "  - framework: Microsoft.NETCore.App\n" + "  - framework: Microsoft.WindowsDesktop.App\n"
        File.WriteAllText(Path.Combine(app, "project.yml"), "name: App\nsdk: Microsoft.NET.Sdk.Web\n" + dependencies)
        web := SdkProjectReferenceProjection.Resolve(Path.Combine(app, "project.yml"), new string[](0))
        assert string.Join("|", web.FrameworkReferences) == "Microsoft.WindowsDesktop.App"

        File.WriteAllText(Path.Combine(app, "project.yml"), "name: App\nsdk: Microsoft.NET.Sdk.BlazorWebAssembly\n" + dependencies)
        blazor := SdkProjectReferenceProjection.Resolve(Path.Combine(app, "project.yml"), new string[](0))
        assert string.Join("|", blazor.FrameworkReferences) == "Microsoft.AspNetCore.App|Microsoft.WindowsDesktop.App"
    } finally {
        Directory.Delete(root, true)
    }
}

test "the MSBuild-implicit framework rule is an exact SDK id match" {
    assert CompilationReferenceResolverKernels.IsMsBuildImplicitFramework("Microsoft.NET.Sdk", "Microsoft.NETCore.App")
    assert CompilationReferenceResolverKernels.IsMsBuildImplicitFramework("Microsoft.NET.Sdk", "microsoft.netcore.app")
    assert !CompilationReferenceResolverKernels.IsMsBuildImplicitFramework("Microsoft.NET.Sdk", "Microsoft.AspNetCore.App")
    assert CompilationReferenceResolverKernels.IsMsBuildImplicitFramework("Microsoft.NET.Sdk.Web", "Microsoft.AspNetCore.App")
    assert CompilationReferenceResolverKernels.IsMsBuildImplicitFramework("microsoft.net.sdk.web", "Microsoft.AspNetCore.App")
    assert !CompilationReferenceResolverKernels.IsMsBuildImplicitFramework("Microsoft.NET.Sdk.BlazorWebAssembly", "Microsoft.AspNetCore.App")
    assert !CompilationReferenceResolverKernels.IsMsBuildImplicitFramework("Microsoft.NET.Sdk.WebAssembly", "Microsoft.AspNetCore.App")
    assert !CompilationReferenceResolverKernels.IsMsBuildImplicitFramework("Microsoft.NET.Sdk.Web", "Microsoft.WindowsDesktop.App")
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
