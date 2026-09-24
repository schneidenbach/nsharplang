namespace NSharpLang.Cli.Commands

import System
import System.IO
import System.Text
import NSharpLang.Compiler

class EnvProjectInfo {
    Name: string?
    TargetFramework: string?
    OutputType: string?
    Sdk: string?

    constructor(name: string?, targetFramework: string?, outputType: string?, sdk: string?) {
        Name = name
        TargetFramework = targetFramework
        OutputType = outputType
        Sdk = sdk
    }
}

class EnvCommand {
    static func Execute(args: string[]): int {
        options := EnvCommandKernels.GetOptionSummary(args)
        if options.ShowHelp {
            print EnvCommandKernels.GetHelpText()
            return 0
        }

        outputMode := CommandOutputKernels.GetOutputMode(options.Json)

        nlcVersion := GetNlcVersion()
        dotnetVersion := RunCapture("--version") ?? "unknown"
        dotnetInfo := RunCapture("--info") ?? ""
        runtime := "dotnet " + dotnetVersion
        hostVersion := ReadDotnetInfoValueAfter(dotnetInfo, "Host:", "Version:")
        if hostVersion != null {
            runtime = ".NET " + (hostVersion ?? "")
        }

        os := ReadDotnetInfoValue(dotnetInfo, "OS Name:") ?? "unknown"
        osVersion := ReadDotnetInfoValue(dotnetInfo, "OS Version:")
        if osVersion != null {
            os = os + " " + (osVersion ?? "")
        }

        arch := ReadDotnetInfoValueAfter(dotnetInfo, "Host:", "Architecture:") ?? "unknown"
        userProfile := Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
        nugetCachePath := Environment.GetEnvironmentVariable("NUGET_PACKAGES")
        if nugetCachePath == null {
            nugetCachePath = Path.Combine(Path.Combine(userProfile, ".nuget"), "packages")
        }

        nsharpHome := Path.Combine(userProfile, ".nsharp")
        nsharpBinPath := Path.Combine(nsharpHome, "bin")
        nsharpPackageCachePath := Path.Combine(nsharpHome, "packages")
        projectInfo := GetProjectInfo(Environment.CurrentDirectory)

        if outputMode == 1 {
            print BuildJson(nlcVersion, dotnetVersion, runtime, os, arch, nugetCachePath ?? "", nsharpBinPath, nsharpPackageCachePath, projectInfo)
        } else {
            PrintText(nlcVersion, dotnetVersion, runtime, os, arch, nugetCachePath ?? "", nsharpBinPath, nsharpPackageCachePath, projectInfo)
        }

        return 0
    }

    static func RunCapture(arguments: string): string? {
        try {
            result := DotnetRunner.Run(arguments, null, true, null)
            if result.ExitCode == 0 {
                return result.Stdout.Trim()
            }
        } catch {
        }

        return null
    }

    static func GetNlcVersion(): string {
        return "0.1.0"
    }

    static func ReadDotnetInfoValue(info: string, key: string): string? {
        index := info.IndexOf(key, StringComparison.Ordinal)
        if index < 0 {
            return null
        }

        valueStart := index + key.Length
        valueEnd := valueStart
        while valueEnd < info.Length {
            if info[valueEnd] == '\n' {
                break
            }

            valueEnd = valueEnd + 1
        }

        return info.Substring(valueStart, valueEnd - valueStart).Trim()
    }

    static func ReadDotnetInfoValueAfter(info: string, marker: string, key: string): string? {
        markerIndex := info.IndexOf(marker, StringComparison.Ordinal)
        if markerIndex < 0 {
            return ReadDotnetInfoValue(info, key)
        }

        index := info.IndexOf(key, markerIndex, StringComparison.Ordinal)
        if index < 0 {
            return null
        }

        valueStart := index + key.Length
        valueEnd := valueStart
        while valueEnd < info.Length {
            if info[valueEnd] == '\n' {
                break
            }

            valueEnd = valueEnd + 1
        }

        return info.Substring(valueStart, valueEnd - valueStart).Trim()
    }

    static func GetProjectInfo(projectRoot: string): EnvProjectInfo? {
        projectYml := Path.Combine(projectRoot, "project.yml")
        if !File.Exists(projectYml) {
            return null
        }

        try {
            config := ProjectFileParser.Parse(projectYml)
            return new EnvProjectInfo(config.Name, config.TargetFramework, config.OutputType, config.Sdk)
        } catch {
        }

        return null
    }

    static func PrintText(nlcVersion: string, dotnetVersion: string, runtime: string, os: string, arch: string, nugetCachePath: string, nsharpBinPath: string, nsharpPackageCachePath: string, projectInfo: EnvProjectInfo?) {
        print EnvCommandKernels.GetTextLine(1, nlcVersion)
        print EnvCommandKernels.GetTextLine(2, dotnetVersion)
        print EnvCommandKernels.GetTextLine(3, runtime)
        print EnvCommandKernels.GetTextLine(4, os)
        print EnvCommandKernels.GetTextLine(5, arch)
        print EnvCommandKernels.GetTextLine(6, nugetCachePath)
        print EnvCommandKernels.GetTextLine(7, nsharpBinPath)
        print EnvCommandKernels.GetTextLine(8, nsharpPackageCachePath)

        if projectInfo != null {
            info := projectInfo ?? new EnvProjectInfo(null, null, null, null)
            print ""
            print EnvCommandKernels.GetTextLine(9, info.Name ?? "")
            print EnvCommandKernels.GetTextLine(10, info.TargetFramework ?? "")
            print EnvCommandKernels.GetTextLine(11, info.OutputType ?? "")
            print EnvCommandKernels.GetTextLine(12, info.Sdk ?? "")
        }
    }

    static func BuildJson(nlcVersion: string, dotnetVersion: string, runtime: string, os: string, arch: string, nugetCachePath: string, nsharpBinPath: string, nsharpPackageCachePath: string, projectInfo: EnvProjectInfo?): string {
        builder := new StringBuilder()
        builder.Append("{\"schemaVersion\":2,\"command\":\"env\",\"ok\":true")
        builder.Append(",\"nlcVersion\":")
        CommandOutputKernels.AppendJsonString(builder, nlcVersion)
        builder.Append(",\"dotnetVersion\":")
        CommandOutputKernels.AppendJsonString(builder, dotnetVersion)
        builder.Append(",\"runtime\":")
        CommandOutputKernels.AppendJsonString(builder, runtime)
        builder.Append(",\"os\":")
        CommandOutputKernels.AppendJsonString(builder, os)
        builder.Append(",\"arch\":")
        CommandOutputKernels.AppendJsonString(builder, arch)
        builder.Append(",\"nugetCachePath\":")
        CommandOutputKernels.AppendJsonString(builder, nugetCachePath)
        builder.Append(",\"nsharpBinPath\":")
        CommandOutputKernels.AppendJsonString(builder, nsharpBinPath)
        builder.Append(",\"nsharpPackageCachePath\":")
        CommandOutputKernels.AppendJsonString(builder, nsharpPackageCachePath)

        if projectInfo != null {
            info := projectInfo ?? new EnvProjectInfo(null, null, null, null)
            builder.Append(",\"project\":{")
            builder.Append("\"name\":")
            CommandOutputKernels.AppendJsonNullableString(builder, info.Name)
            builder.Append(",\"targetFramework\":")
            CommandOutputKernels.AppendJsonNullableString(builder, info.TargetFramework)
            builder.Append(",\"outputType\":")
            CommandOutputKernels.AppendJsonNullableString(builder, info.OutputType)
            builder.Append(",\"sdk\":")
            CommandOutputKernels.AppendJsonNullableString(builder, info.Sdk)
            builder.Append("}")
        }

        builder.Append("}")
        return builder.ToString()
    }
}
