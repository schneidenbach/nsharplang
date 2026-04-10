using System;
using System.Diagnostics;
using System.IO;
using NSharpLang.Cli;

namespace NSharpLang.Tests;

internal static class TestSdkFeed
{
    private static readonly Lazy<PackedSdkInfo> PackedSdk = new(BuildSdkFeed);

    public static string Version => PackedSdk.Value.Version;
    public static string FeedPath => PackedSdk.Value.FeedPath;

    public static void WriteSdkResolutionFiles(string projectDir)
    {
        File.WriteAllText(Path.Combine(projectDir, "global.json"), $$"""
{
  "sdk": {
    "version": "9.0.100"
  },
  "msbuild-sdks": {
    "NSharpLang.Sdk": "{{Version}}"
  }
}
""");

        File.WriteAllText(Path.Combine(projectDir, "NuGet.config"), $$"""
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="local" value="{{FeedPath}}" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
""");
    }

    public static void WriteVersionedSdkProject(string projectDir, string projectName)
    {
        File.WriteAllText(Path.Combine(projectDir, $"{projectName}.csproj"), $"<Project Sdk=\"NSharpLang.Sdk/{Version}\" />\n");
        WriteSdkResolutionFiles(projectDir);
    }

    private static PackedSdkInfo BuildSdkFeed()
    {
        var repoRoot = FindRepoRoot();
        var feedDir = Path.Combine(Path.GetTempPath(), $"nsharp-sdk-feed-{Guid.NewGuid():N}");
        var version = $"0.1.0-il{Guid.NewGuid():N}";
        Directory.CreateDirectory(feedDir);

        var buildTasksExitCode = RunDotnetNoCapture(
            repoRoot,
            $"build \"{Path.Combine(repoRoot, "src", "NSharpLang.Build.Tasks", "NSharpLang.Build.Tasks.csproj")}\" -c Release -v q --disable-build-servers",
            timeout: TimeSpan.FromMinutes(5));
        if (buildTasksExitCode != 0)
        {
            throw new InvalidOperationException("Failed to build NSharp build tasks.");
        }

        var packExitCode = RunDotnetNoCapture(
            repoRoot,
            $"pack \"{Path.Combine(repoRoot, "src", "NSharpLang.Sdk", "NSharpLang.Sdk.csproj")}\" -c Release -o \"{feedDir}\" -p:Version={version} -v q --disable-build-servers",
            timeout: TimeSpan.FromMinutes(5));
        if (packExitCode != 0)
        {
            throw new InvalidOperationException("Failed to pack NSharp SDK.");
        }

        return new PackedSdkInfo(feedDir, version);
    }

    private static string FindRepoRoot()
    {
        var dir = AppContext.BaseDirectory;
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir, "NSharpLang.sln")))
            {
                return dir;
            }

            dir = Path.GetDirectoryName(dir);
        }

        throw new InvalidOperationException("Could not find the repository root.");
    }

    internal static int RunDotnetNoCapture(string workingDirectory, string arguments, TimeSpan timeout)
    {
        var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = arguments,
                WorkingDirectory = workingDirectory,
                RedirectStandardOutput = false,
                RedirectStandardError = false,
                UseShellExecute = false
            }
        };

        process.Start();

        if (!process.WaitForExit((int)timeout.TotalMilliseconds))
        {
            try { process.Kill(entireProcessTree: true); } catch { }
            throw new TimeoutException($"Process 'dotnet {arguments}' did not complete within {timeout}.");
        }

        return process.ExitCode;
    }

    internal sealed record PackedSdkInfo(string FeedPath, string Version);
}
