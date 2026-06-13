using System;

namespace NSharpLang.Compiler;

internal static class SoaFeature
{
    public const string EnvironmentVariable = "NSHARP_EXPERIMENTAL_SOA";

    public static bool IsEnabled
    {
        get
        {
            var value = Environment.GetEnvironmentVariable(EnvironmentVariable);
            return value != null
                   && !string.Equals(value, "0", StringComparison.OrdinalIgnoreCase)
                   && !string.Equals(value, "false", StringComparison.OrdinalIgnoreCase);
        }
    }
}
