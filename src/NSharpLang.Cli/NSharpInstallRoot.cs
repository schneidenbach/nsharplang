using System;
using System.IO;

namespace NSharpLang.Cli;

/// <summary>
/// Resolves the N# install root for the running CLI so that scaffolding and
/// diagnostics point at the feed that was actually installed, never a baked-in
/// default path. Resolution order: the NSHARP_INSTALL_DIR override, then the
/// installed toolset layout (Cli.dll lives in &lt;root&gt;/lib/nlc with
/// &lt;root&gt;/bin and &lt;root&gt;/packages siblings), then the default ~/.nsharp.
/// </summary>
internal static class NSharpInstallRoot
{
    /// <summary>
    /// Feed value written into generated projects when the CLI cannot prove it
    /// is running from an installed toolset. NuGet expands %HOME% at restore
    /// time, which keeps development-scaffolded projects portable.
    /// </summary>
    internal const string DefaultFeedValue = "%HOME%/.nsharp/packages";

    internal const string InstallRootFeedValue = "%NSHARP_INSTALL_DIR%/packages";

    internal const string InstallDirEnvironmentVariable = "NSHARP_INSTALL_DIR";

    internal static string Resolve()
        => Resolve(
            AppContext.BaseDirectory,
            Environment.GetEnvironmentVariable(InstallDirEnvironmentVariable),
            DefaultInstallRoot());

    internal static string Resolve(string baseDirectory, string? installDirOverride, string defaultInstallRoot)
    {
        if (!string.IsNullOrWhiteSpace(installDirOverride))
            return NormalizeDirectory(installDirOverride);

        var hostDirectory = NormalizeDirectory(baseDirectory);
        var libDirectory = Path.GetDirectoryName(hostDirectory);
        var root = libDirectory is null ? null : Path.GetDirectoryName(libDirectory);
        if (root is not null &&
            string.Equals(Path.GetFileName(libDirectory), "lib", StringComparison.OrdinalIgnoreCase) &&
            Directory.Exists(Path.Combine(root, "bin")) &&
            Directory.Exists(Path.Combine(root, "packages")))
        {
            return root;
        }

        return NormalizeDirectory(defaultInstallRoot);
    }

    internal static string PackagesDirectory()
        => PackagesDirectory(Resolve());

    internal static string PackagesDirectory(string installRoot)
        => Path.Combine(installRoot, "packages");

    /// <summary>
    /// The nsharp-local feed value for generated project NuGet.config files:
    /// the installer env variable when available, the portable %HOME% literal
    /// for development/default fallback, or the absolute packages path when a
    /// custom launcher layout is detected without an exported install root.
    /// </summary>
    internal static string ProjectFeedValue()
        => ProjectFeedValue(
            AppContext.BaseDirectory,
            Environment.GetEnvironmentVariable(InstallDirEnvironmentVariable),
            DefaultInstallRoot());

    internal static string ProjectFeedValue(string baseDirectory, string? installDirOverride, string defaultInstallRoot)
    {
        if (!string.IsNullOrWhiteSpace(installDirOverride))
            return InstallRootFeedValue;

        return ProjectFeedValue(Resolve(baseDirectory, installDirOverride, defaultInstallRoot), defaultInstallRoot);
    }

    internal static string ProjectFeedValue(string installRoot, string defaultInstallRoot)
        => PathsEqual(installRoot, defaultInstallRoot)
            ? DefaultFeedValue
            : PackagesDirectory(NormalizeDirectory(installRoot));

    internal static string DefaultInstallRoot()
        => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nsharp");

    private static string NormalizeDirectory(string path)
        => Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));

    private static bool PathsEqual(string left, string right)
        => string.Equals(
            NormalizeDirectory(left),
            NormalizeDirectory(right),
            OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);
}
