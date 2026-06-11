using System;
using System.Globalization;

namespace NSharpLang.Compiler;

/// <summary>
/// Normalizes package-facing project versions into CLR assembly identity versions.
/// </summary>
public static class AssemblyVersionUtilities
{
    public static Version DefaultAssemblyVersion { get; } = new(1, 0, 0, 0);

    public static Version GetAssemblyVersionOrDefault(string? packageVersion)
        => TryGetAssemblyVersion(packageVersion, out var assemblyVersion)
            ? assemblyVersion
            : DefaultAssemblyVersion;

    public static bool TryGetAssemblyVersion(string? packageVersion, out Version assemblyVersion)
    {
        assemblyVersion = DefaultAssemblyVersion;

        if (string.IsNullOrWhiteSpace(packageVersion))
        {
            return false;
        }

        var numericCore = packageVersion.Trim();
        var metadataIndex = numericCore.IndexOfAny(['-', '+']);
        if (metadataIndex >= 0)
        {
            numericCore = numericCore[..metadataIndex];
        }

        var parts = numericCore.Split('.');
        if (parts.Length is < 2 or > 4)
        {
            return false;
        }

        Span<int> values = stackalloc int[] { 0, 0, 0, 0 };
        for (var i = 0; i < parts.Length; i++)
        {
            if (!int.TryParse(
                    parts[i],
                    NumberStyles.None,
                    CultureInfo.InvariantCulture,
                    out var value))
            {
                return false;
            }

            values[i] = value;
        }

        assemblyVersion = new Version(values[0], values[1], values[2], values[3]);
        return true;
    }
}
