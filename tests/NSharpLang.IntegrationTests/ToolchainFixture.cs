using System.Diagnostics;
using DotNet.Testcontainers.Builders;
using DotNet.Testcontainers.Containers;
using DotNet.Testcontainers.Images;
using Xunit;

namespace NSharpLang.IntegrationTests;

/// <summary>
/// Shared fixture that packs all NuGet packages, builds a Docker image
/// with those packages pre-staged, and starts a container that simulates
/// a brand-new machine with only the .NET SDK installed.
/// </summary>
public class ToolchainFixture : IAsyncLifetime
{
    private IFutureDockerImage? _image;
    private string? _buildContextDir;

    public IContainer Container { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        var repoRoot = FindRepoRoot();

        // Create a temporary Docker build context
        _buildContextDir = Path.Combine(
            Path.GetTempPath(),
            $"nsharp-integration-{Guid.NewGuid().ToString("N")[..12]}");
        Directory.CreateDirectory(_buildContextDir);

        var packagesDir = Path.Combine(_buildContextDir, "packages");
        Directory.CreateDirectory(packagesDir);

        // Build the tasks project first (SDK pack depends on its output binaries)
        await RunDotnetAsync(repoRoot,
            "build src/NSharpLang.Build.Tasks/NSharpLang.Build.Tasks.csproj -c Release --disable-build-servers -v q");

        // Pack all distributable NuGet packages
        await PackProject(repoRoot, "src/NSharpLang.Compiler/Compiler.csproj", packagesDir);
        await PackProject(repoRoot, "src/NSharpLang.Sdk/NSharpLang.Sdk.csproj", packagesDir);
        await PackProject(repoRoot, "templates/NSharpLang.Templates.csproj", packagesDir);
        await PackProject(repoRoot, "src/NSharpLang.Cli/Cli.csproj", packagesDir);
        await PackProject(repoRoot, "src/NSharpLang.LanguageServer/LanguageServer.csproj", packagesDir);

        // Copy Dockerfile into the build context
        var dockerfileSrc = Path.Combine(
            repoRoot, "tests", "NSharpLang.IntegrationTests", "Dockerfile.toolchain");
        File.Copy(dockerfileSrc, Path.Combine(_buildContextDir, "Dockerfile.toolchain"));

        // Build the Docker image
        var imageTag = Guid.NewGuid().ToString("N")[..12];
        _image = new ImageFromDockerfileBuilder()
            .WithDockerfileDirectory(_buildContextDir)
            .WithDockerfile("Dockerfile.toolchain")
            .WithName($"nsharp-integration-test:{imageTag}")
            .Build();

        await _image.CreateAsync();

        // Start the container
        Container = new ContainerBuilder()
            .WithImage(_image)
            .Build();

        await Container.StartAsync();
    }

    public async Task DisposeAsync()
    {
        if (Container != null)
            await Container.DisposeAsync();

        if (_image != null)
            await _image.DisposeAsync();

        if (_buildContextDir != null && Directory.Exists(_buildContextDir))
        {
            try { Directory.Delete(_buildContextDir, recursive: true); }
            catch { /* best-effort cleanup */ }
        }
    }

    private static Task PackProject(string repoRoot, string projectPath, string outputDir) =>
        RunDotnetAsync(repoRoot,
            $"pack {projectPath} -c Release -o \"{outputDir}\" --disable-build-servers -v q");

    private static async Task RunDotnetAsync(string workingDirectory, string arguments)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "dotnet",
            Arguments = arguments,
            WorkingDirectory = workingDirectory,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        using var process = Process.Start(psi)
            ?? throw new InvalidOperationException($"Failed to start: dotnet {arguments}");

        // Read both streams concurrently to avoid deadlock when a pipe buffer fills
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        await Task.WhenAll(stdoutTask, stderrTask);
        await process.WaitForExitAsync();

        var stdout = stdoutTask.Result;
        var stderr = stderrTask.Result;

        if (process.ExitCode != 0)
            throw new InvalidOperationException(
                $"dotnet {arguments} failed (exit code {process.ExitCode}):\n{stdout}\n{stderr}");
    }

    private static string FindRepoRoot()
    {
        var dir = AppContext.BaseDirectory;
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir, "NSharpLang.sln")))
                return dir;
            dir = Path.GetDirectoryName(dir);
        }

        throw new InvalidOperationException(
            "Could not find repository root (NSharpLang.sln). " +
            $"Searched upward from {AppContext.BaseDirectory}");
    }
}
