using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Threading;
using NSharpLang.Cli;

namespace NSharpLang.Tests;

internal static class TestSdkFeed
{
    // The feed build shells out to the repo's own project graph, and the Build.Tasks step pulls
    // in the full compiler including the BootstrapServices N# self-emit: ~6m20s serially on a
    // quiet machine (measured 2026-08-02), longer under concurrent gate load. Each step gets the
    // same generous ceiling; hitting it means a hang, not a slow build.
    private static readonly TimeSpan SdkFeedCommandTimeout = TimeSpan.FromMinutes(20);

    // A waiter must outlast a peer process holding the lock through the whole feed build
    // (all SdkFeedCommandTimeout steps), not just one step.
    private static readonly TimeSpan CacheLockTimeout = TimeSpan.FromMinutes(45);

    private static readonly Lazy<PackedSdkInfo> PackedSdk = new(BuildSdkFeed);

    public static string Version => PackedSdk.Value.Version;
    public static string FeedPath => PackedSdk.Value.FeedPath;

    // Serializes the COLD-START package extraction. The toolchain test classes run concurrently, and
    // their first dotnet restores would otherwise race to extract the same NSharpLang.Sdk/Runtime
    // nupkgs into a cold NUGET_PACKAGES (the gate's isolated run starts empty) — MSBuild's SDK
    // resolver intermittently fails on that race. One warm-up restore runs before any concurrent
    // spawn; every later restore hits the extracted cache.
    private static readonly Lazy<bool> ColdStartWarmup = new(() =>
    {
        var warmupDir = Path.Combine(Path.GetTempPath(), $"nsharp-sdk-feed-warmup-{Guid.NewGuid():N}");
        Directory.CreateDirectory(warmupDir);
        try
        {
            File.WriteAllText(Path.Combine(warmupDir, "Warmup.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n");
            File.WriteAllText(Path.Combine(warmupDir, "project.yml"), """
name: Warmup
outputType: library
targetFramework: net10.0
""");
            WriteResolutionFilesCore(warmupDir);
            var exitCode = RunDotnetNoCapture(
                warmupDir,
                $"restore \"{Path.Combine(warmupDir, "Warmup.csproj")}\" -v q --disable-build-servers",
                timeout: SdkFeedCommandTimeout);
            if (exitCode != 0)
            {
                throw new InvalidOperationException("SDK feed warm-up restore failed.");
            }
            return true;
        }
        finally
        {
            Directory.Delete(warmupDir, recursive: true);
        }
    });

    public static void WriteSdkResolutionFiles(string projectDir)
    {
        _ = ColdStartWarmup.Value;
        WriteResolutionFilesCore(projectDir);
    }

    private static void WriteResolutionFilesCore(string projectDir)
    {
        File.WriteAllText(Path.Combine(projectDir, "global.json"), $$"""
{
  "sdk": {
    "version": "10.0.100",
    "rollForward": "latestFeature"
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

        File.WriteAllText(Path.Combine(projectDir, "Directory.Build.props"), $$"""
<Project>
  <PropertyGroup>
    <NSharpLangRuntimeVersion>{{PackedSdk.Value.RuntimeVersion}}</NSharpLangRuntimeVersion>
  </PropertyGroup>
</Project>
""");
    }

    public static void WriteVersionedSdkProject(string projectDir, string projectName)
    {
        File.WriteAllText(Path.Combine(projectDir, $"{projectName}.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n");
        WriteSdkResolutionFiles(projectDir);
    }

    private static PackedSdkInfo BuildSdkFeed()
    {
        var repoRoot = FindRepoRoot();
        var cacheKey = ComputeSdkFeedCacheKey(repoRoot);
        var cacheRoot = Path.Combine(Path.GetTempPath(), "nsharp-sdk-feed-cache");
        var feedDir = Path.Combine(cacheRoot, cacheKey);
        Directory.CreateDirectory(cacheRoot);

        using var cacheLock = AcquireCacheLock(Path.Combine(cacheRoot, $"{cacheKey}.lock"));
        if (TryReadCachedSdkFeed(feedDir, out var cached))
        {
            return cached;
        }

        var keySuffix = cacheKey[..Math.Min(16, cacheKey.Length)];
        var version = $"0.1.0-il{keySuffix}";
        var runtimeVersion = $"0.1.0-runtime{keySuffix}";
        var tempFeedDir = Path.Combine(cacheRoot, $"{cacheKey}.tmp-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempFeedDir);

        try
        {
            var buildTasksExitCode = RunDotnetNoCapture(
                repoRoot,
                $"build \"{Path.Combine(repoRoot, "src", "NSharpLang.Build.Tasks", "NSharpLang.Build.Tasks.csproj")}\" -c Release -v q --disable-build-servers",
                timeout: SdkFeedCommandTimeout);
            if (buildTasksExitCode != 0)
            {
                throw new InvalidOperationException("Failed to build NSharp build tasks.");
            }

            var runtimePackExitCode = RunDotnetNoCapture(
                repoRoot,
                $"pack \"{Path.Combine(repoRoot, "src", "NSharpLang.Runtime", "NSharpLang.Runtime.csproj")}\" -c Release -o \"{tempFeedDir}\" -p:Version={runtimeVersion} -v q --disable-build-servers",
                timeout: SdkFeedCommandTimeout);
            if (runtimePackExitCode != 0)
            {
                throw new InvalidOperationException("Failed to pack NSharp runtime.");
            }

            var packExitCode = RunDotnetNoCapture(
                repoRoot,
                $"pack \"{Path.Combine(repoRoot, "src", "NSharpLang.Sdk", "NSharpLang.Sdk.csproj")}\" -c Release -o \"{tempFeedDir}\" -p:Version={version} -v q --disable-build-servers",
                timeout: SdkFeedCommandTimeout);
            if (packExitCode != 0)
            {
                throw new InvalidOperationException("Failed to pack NSharp SDK.");
            }

            WriteSdkFeedManifest(tempFeedDir, version, runtimeVersion);
            if (Directory.Exists(feedDir))
            {
                Directory.Delete(feedDir, recursive: true);
            }

            Directory.Move(tempFeedDir, feedDir);
            return new PackedSdkInfo(feedDir, version, runtimeVersion);
        }
        finally
        {
            if (Directory.Exists(tempFeedDir))
            {
                Directory.Delete(tempFeedDir, recursive: true);
            }
        }
    }

    private static FileStream AcquireCacheLock(string lockPath)
    {
        var stopwatch = Stopwatch.StartNew();
        while (true)
        {
            try
            {
                return new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            }
            catch (IOException) when (stopwatch.Elapsed < CacheLockTimeout)
            {
                Thread.Sleep(100);
            }
        }
    }

    private static bool TryReadCachedSdkFeed(string feedDir, out PackedSdkInfo info)
    {
        info = default!;
        var manifestPath = Path.Combine(feedDir, "nsharp-test-sdk-feed.txt");
        if (!File.Exists(manifestPath))
        {
            return false;
        }

        var values = File.ReadAllLines(manifestPath)
            .Select(line => line.Split('=', 2))
            .Where(parts => parts.Length == 2)
            .ToDictionary(parts => parts[0], parts => parts[1], StringComparer.Ordinal);

        if (!values.TryGetValue("version", out var version) ||
            !values.TryGetValue("runtimeVersion", out var runtimeVersion))
        {
            return false;
        }

        if (!File.Exists(Path.Combine(feedDir, $"NSharpLang.Sdk.{version}.nupkg")) ||
            !File.Exists(Path.Combine(feedDir, $"NSharpLang.Runtime.{runtimeVersion}.nupkg")))
        {
            return false;
        }

        info = new PackedSdkInfo(feedDir, version, runtimeVersion);
        return true;
    }

    private static void WriteSdkFeedManifest(string feedDir, string version, string runtimeVersion)
    {
        File.WriteAllLines(Path.Combine(feedDir, "nsharp-test-sdk-feed.txt"), new[]
        {
            $"version={version}",
            $"runtimeVersion={runtimeVersion}"
        });
    }

    private static string ComputeSdkFeedCacheKey(string repoRoot)
    {
        using var sha = SHA256.Create();
        foreach (var path in EnumerateSdkFeedInputs(repoRoot).OrderBy(path => path, StringComparer.Ordinal))
        {
            var relative = Path.GetRelativePath(repoRoot, path).Replace('\\', '/');
            UpdateHash(sha, relative);
            using var stream = File.OpenRead(path);
            var buffer = new byte[64 * 1024];
            int read;
            while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
            {
                sha.TransformBlock(buffer, 0, read, null, 0);
            }

            sha.TransformBlock(new byte[] { 0 }, 0, 1, null, 0);
        }

        UpdateHash(sha, Environment.Version.ToString());
        sha.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
        return Convert.ToHexString(sha.Hash!).ToLowerInvariant();
    }

    private static void UpdateHash(HashAlgorithm hash, string value)
    {
        var bytes = System.Text.Encoding.UTF8.GetBytes(value);
        hash.TransformBlock(bytes, 0, bytes.Length, null, 0);
        hash.TransformBlock(new byte[] { 0 }, 0, 1, null, 0);
    }

    private static string[] EnumerateSdkFeedInputs(string repoRoot)
    {
        var roots = new[]
        {
            Path.Combine(repoRoot, "src", "NSharpLang.Compiler.BootstrapServices"),
            Path.Combine(repoRoot, "src", "NSharpLang.Compiler"),
            Path.Combine(repoRoot, "src", "NSharpLang.Build.Tasks"),
            Path.Combine(repoRoot, "src", "NSharpLang.Runtime"),
            Path.Combine(repoRoot, "src", "NSharpLang.Sdk")
        };
        var rootFiles = new[]
        {
            Path.Combine(repoRoot, "global.json"),
            Path.Combine(repoRoot, "Directory.Build.props"),
            Path.Combine(repoRoot, "Directory.Build.targets"),
            Path.Combine(repoRoot, "NuGet.config")
        };

        return roots
            .Where(Directory.Exists)
            .SelectMany(root => Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
            .Where(path => !IsUnderBuildOutputDirectory(path))
            .Concat(rootFiles.Where(File.Exists))
            .ToArray();
    }

    private static bool IsUnderBuildOutputDirectory(string path)
    {
        var parts = path.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return parts.Contains("bin", StringComparer.OrdinalIgnoreCase) ||
               parts.Contains("obj", StringComparer.OrdinalIgnoreCase);
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

    internal sealed record PackedSdkInfo(string FeedPath, string Version, string RuntimeVersion);
}
