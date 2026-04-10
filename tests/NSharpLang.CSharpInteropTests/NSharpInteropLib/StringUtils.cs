// Generated from StringUtils.nl — this is the exact C# that N# emits.
// If the compiler output changes, update this file to match.
#nullable enable annotations

using System;

namespace NSharpInteropLib;

public class StringUtils
{
    public static bool TryParseInt(string input, out int result)
    {
        return Int32.TryParse(input, out result);
    }

    public static void Swap(ref string a, ref string b)
    {
        var temp = a;
        a = b;
        b = temp;
    }

    public static string Reverse(string input)
    {
        var chars = input.ToCharArray();
        Array.Reverse(chars);
        return new string(chars);
    }

    public static string Truncate(string input, int maxLength)
    {
        if ((input.Length <= maxLength))
        {
            return input;
        }
        return (input.Substring(0, maxLength) + "...");
    }
}
