namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Text.Json

public class CompilationArtifacts {
    public static func WriteRuntimeConfig(config: ProjectConfig, assemblyPath: string) {
        ArgumentNullException.ThrowIfNull(config)
        ArgumentException.ThrowIfNullOrWhiteSpace(assemblyPath)

        runtimeConfigPath := Path.ChangeExtension(assemblyPath, ".runtimeconfig.json")
        frameworkVersion := GetRuntimeFrameworkVersion(config.TargetFramework)
        frameworks := GetRuntimeFrameworks(config, frameworkVersion)

        runtimeOptions := new Dictionary<string, object>()
        runtimeOptions["tfm"] = config.TargetFramework
        if frameworks.Count == 1 {
            runtimeOptions["framework"] = frameworks[0]
        } else {
            runtimeOptions["frameworks"] = frameworks
        }

        payload := new Dictionary<string, object>()
        payload["runtimeOptions"] = runtimeOptions

        json := JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented: true })
        File.WriteAllText(runtimeConfigPath, json + Environment.NewLine)
    }

    public static func GetRuntimeFrameworkVersion(targetFramework: string): string {
        if string.IsNullOrWhiteSpace(targetFramework) || !targetFramework.StartsWith("net", StringComparison.OrdinalIgnoreCase) {
            return "9.0.0"
        }

        version := targetFramework.Substring(3)
        if string.IsNullOrWhiteSpace(version) {
            return "9.0.0"
        }

        dotCount := 0
        i := 0
        while i < version.Length {
            if version[i] == '.' {
                dotCount = dotCount + 1
            }

            i = i + 1
        }

        if dotCount == 0 {
            return version + ".0.0"
        }

        if dotCount == 1 {
            return version + ".0"
        }

        return version
    }

    static func GetRuntimeFrameworks(config: ProjectConfig, frameworkVersion: string): List<Dictionary<string, string>> {
        frameworks := new List<Dictionary<string, string>>()
        netCoreFramework := new Dictionary<string, string>()
        netCoreFramework["name"] = "Microsoft.NETCore.App"
        netCoreFramework["version"] = frameworkVersion
        frameworks.Add(netCoreFramework)

        requiresAspNetCore := config.Sdk.IndexOf("Web", StringComparison.OrdinalIgnoreCase) >= 0
        i := 0
        while !requiresAspNetCore && i < config.Dependencies.Count {
            dependency := config.Dependencies[i]
            if dependency.Type == ReferenceType.Framework
                && String.Compare(dependency.Framework ?? "", "Microsoft.AspNetCore.App", StringComparison.OrdinalIgnoreCase) == 0 {
                requiresAspNetCore = true
            }

            i = i + 1
        }

        if requiresAspNetCore {
            aspNetFramework := new Dictionary<string, string>()
            aspNetFramework["name"] = "Microsoft.AspNetCore.App"
            aspNetFramework["version"] = frameworkVersion
            frameworks.Add(aspNetFramework)
        }

        return frameworks
    }
}
