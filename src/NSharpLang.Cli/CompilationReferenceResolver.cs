using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using NSharpLang.Compiler;

namespace NSharpLang.Cli;

internal static class CompilationReferenceResolver
{
    internal static void AddResolvedDllReferences(string projectDir, ProjectConfig config)
    {
        var requiresReferenceResolution = config.Dependencies.Any(dependency =>
            dependency.Type is ReferenceType.Framework or ReferenceType.NuGet or ReferenceType.Project);
        if (!requiresReferenceResolution)
        {
            return;
        }

        var restoreResult = Commands.RestoreCommand.Restore(projectDir, quiet: true);
        if (restoreResult != 0)
        {
            throw new InvalidOperationException("Failed to restore project configuration for reference resolution.");
        }

        var projectFile = Program.EnsureProjectFiles(projectDir, config);
        var restoreReferencesResult = DotnetRunner.Run(
            $"restore \"{projectFile}\" -v q --disable-build-servers {Program.GetBackendMsBuildProperty(CompilationBackend.Il)}",
            workingDirectory: projectDir,
            timeout: TimeSpan.FromMinutes(2));
        if (restoreReferencesResult.ExitCode != 0)
        {
            var detail = (restoreReferencesResult.Stderr + restoreReferencesResult.Stdout).Trim();
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(detail)
                ? "Failed to restore project references for compilation."
                : $"Failed to restore project references for compilation:{Environment.NewLine}{detail}");
        }

        var resolveResult = DotnetRunner.Run(
            $"msbuild \"{projectFile}\" -t:ResolveReferences -getItem:ReferencePath -nologo -v:q {Program.GetBackendMsBuildProperty(CompilationBackend.Il)}",
            workingDirectory: projectDir,
            timeout: TimeSpan.FromMinutes(2));

        if (resolveResult.ExitCode != 0)
        {
            var detail = (resolveResult.Stderr + resolveResult.Stdout).Trim();
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(detail)
                ? "Failed to resolve project references for compilation."
                : $"Failed to resolve project references for compilation:{Environment.NewLine}{detail}");
        }

        using var document = JsonDocument.Parse(resolveResult.Stdout);
        if (!document.RootElement.TryGetProperty("Items", out var items)
            || !items.TryGetProperty("ReferencePath", out var referencePaths)
            || referencePaths.ValueKind != JsonValueKind.Array)
        {
            return;
        }

        foreach (var reference in referencePaths.EnumerateArray())
        {
            if (!reference.TryGetProperty("Identity", out var identityProperty))
            {
                continue;
            }

            var identity = identityProperty.GetString();
            if (string.IsNullOrWhiteSpace(identity) || !File.Exists(identity))
            {
                continue;
            }

            var fullPath = Path.GetFullPath(identity);
            var alreadyPresent = config.Dependencies.Any(dependency =>
                dependency.Type == ReferenceType.Dll
                && string.Equals(Path.GetFullPath(dependency.Dll!), fullPath, StringComparison.OrdinalIgnoreCase));

            if (!alreadyPresent)
            {
                config.Dependencies.Add(new Reference { Dll = fullPath });
            }
        }
    }
}
