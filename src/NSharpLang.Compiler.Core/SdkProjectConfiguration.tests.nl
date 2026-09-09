namespace NSharpLang.Compiler

import System
import System.IO

func SdkConfigDirectory(yaml: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-sdk-config-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    File.WriteAllText(Path.Combine(directory, "project.yml"), yaml)
    return directory
}

func SdkConfigFailure(directory: string): string {
    try {
        SdkProjectConfiguration.Load(directory)
        return "<accepted>"
    } catch ex: Exception {
        if ex is InvalidOperationException {
            return "InvalidOperationException|" + ex.Message
        }
        if ex is FileNotFoundException {
            return "FileNotFoundException|" + ex.Message
        }
        return "<unexpected>|" + ex.Message
    }
}

test "SDK configuration defaults come from project.yml and the project directory" {
    directory := SdkConfigDirectory("backend: il\n")
    try {
        config := SdkProjectConfiguration.Load(directory)
        assert config.TargetFramework == "net10.0"
        assert config.OutputType == "Exe"
        assert config.AssemblyName == Path.GetFileName(directory)
        assert config.Version == ""
        assert config.AssemblyVersion == ""
        assert config.FileVersion == ""
        assert config.Sdk == "Microsoft.NET.Sdk"
        assert config.TestFramework == "xunit"
        assert SdkProjectConfiguration.DefaultTestFramework == "xunit"
        assert SdkProjectConfiguration.LoadingMessage(SdkProjectConfiguration.ProjectFilePath(directory)) == "Loading project configuration from " + Path.Combine(directory, "project.yml")
    } finally {
        Directory.Delete(directory, true)
    }
}

test "SDK configuration preserves explicit properties and projects SemVer into CLR versions" {
    directory := SdkConfigDirectory("name: Widget\nversion: 1.2.0-beta.1+build.5\noutputType: library\ntargetFramework: net9.0\nsdk: Microsoft.NET.Sdk.Web\ntestFramework: nunit\n")
    try {
        config := SdkProjectConfiguration.Load(directory)
        assert config.AssemblyName == "Widget"
        assert config.OutputType == "Library"
        assert config.TargetFramework == "net9.0"
        assert config.Sdk == "Microsoft.NET.Sdk.Web"
        assert config.TestFramework == "nunit"
        assert config.Version == "1.2.0-beta.1+build.5"
        assert config.AssemblyVersion == "1.2.0.0"
        assert config.FileVersion == "1.2.0.0"
    } finally {
        Directory.Delete(directory, true)
    }
}

test "SDK configuration keeps empty names and blank package versions without synthesizing CLR versions" {
    directory := SdkConfigDirectory("name: ''\nversion: '   '\n")
    try {
        config := SdkProjectConfiguration.Load(directory)
        assert config.AssemblyName == ""
        assert config.Version == "   "
        assert config.AssemblyVersion == ""
        assert config.FileVersion == ""
        File.WriteAllText(Path.Combine(directory, "project.yml"), "version: invalid\n")
        fallback := SdkProjectConfiguration.Load(directory)
        assert fallback.Version == "invalid"
        assert fallback.AssemblyVersion == "1.0.0.0"
        assert fallback.FileVersion == "1.0.0.0"
    } finally {
        Directory.Delete(directory, true)
    }
}

test "SDK configuration rejects invalid output types through the canonical parser diagnostic" {
    directory := SdkConfigDirectory("outputType: Exe\n")
    try {
        assert SdkConfigFailure(directory) == "InvalidOperationException|Invalid outputType: 'Exe'. Must be 'exe' or 'library'."
        File.WriteAllText(Path.Combine(directory, "project.yml"), "backend: csharp\n")
        assert SdkConfigFailure(directory) == "InvalidOperationException|Invalid backend: 'csharp'. Must be 'il'."
        File.WriteAllText(Path.Combine(directory, "project.yml"), "testFramework: mstest\n")
        assert SdkConfigFailure(directory) == "InvalidOperationException|Invalid testFramework: 'mstest'. Must be 'xunit' or 'nunit'."
    } finally {
        Directory.Delete(directory, true)
    }
}

test "SDK configuration requires project.yml and validates entry paths before projecting outputs" {
    directory := SdkConfigDirectory("entry: Missing.nl\n")
    try {
        assert SdkConfigFailure(directory) == "FileNotFoundException|Entry file not found: Missing.nl (resolved to " + Path.Combine(directory, "Missing.nl") + ")"
        File.Delete(Path.Combine(directory, "project.yml"))
        assert SdkConfigFailure(directory) == "FileNotFoundException|Project file not found: " + Path.Combine(directory, "project.yml")
    } finally {
        Directory.Delete(directory, true)
    }
}
