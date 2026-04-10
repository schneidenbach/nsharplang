using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace NSharpLang.Compiler;

public static class CompilationArtifacts
{
    public static void WriteRuntimeConfig(ProjectConfig config, string assemblyPath)
    {
        ArgumentNullException.ThrowIfNull(config);
        ArgumentException.ThrowIfNullOrWhiteSpace(assemblyPath);

        var runtimeConfigPath = Path.ChangeExtension(assemblyPath, ".runtimeconfig.json");
        var frameworkVersion = GetRuntimeFrameworkVersion(config.TargetFramework);
        var frameworks = GetRuntimeFrameworks(config, frameworkVersion);

        var runtimeOptions = frameworks.Count == 1
            ? new Dictionary<string, object?>
            {
                ["tfm"] = config.TargetFramework,
                ["framework"] = frameworks[0]
            }
            : new Dictionary<string, object?>
            {
                ["tfm"] = config.TargetFramework,
                ["frameworks"] = frameworks
            };

        var payload = new Dictionary<string, object?>
        {
            ["runtimeOptions"] = runtimeOptions
        };

        var json = JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(runtimeConfigPath, json + Environment.NewLine);
    }

    public static string GetRuntimeFrameworkVersion(string targetFramework)
    {
        if (string.IsNullOrWhiteSpace(targetFramework) || !targetFramework.StartsWith("net", StringComparison.OrdinalIgnoreCase))
        {
            return "9.0.0";
        }

        var version = targetFramework[3..];
        if (string.IsNullOrWhiteSpace(version))
        {
            return "9.0.0";
        }

        var dotCount = version.Count(c => c == '.');
        return dotCount switch
        {
            0 => $"{version}.0.0",
            1 => $"{version}.0",
            _ => version
        };
    }

    private static List<Dictionary<string, string>> GetRuntimeFrameworks(ProjectConfig config, string frameworkVersion)
    {
        var frameworks = new List<Dictionary<string, string>>
        {
            new()
            {
                ["name"] = "Microsoft.NETCore.App",
                ["version"] = frameworkVersion
            }
        };

        var requiresAspNetCore = config.Sdk.Contains("Web", StringComparison.OrdinalIgnoreCase)
            || config.Dependencies.Any(dependency =>
                dependency.Type == ReferenceType.Framework
                && string.Equals(dependency.Framework, "Microsoft.AspNetCore.App", StringComparison.OrdinalIgnoreCase));

        if (requiresAspNetCore)
        {
            frameworks.Add(new Dictionary<string, string>
            {
                ["name"] = "Microsoft.AspNetCore.App",
                ["version"] = frameworkVersion
            });
        }

        return frameworks;
    }
}
