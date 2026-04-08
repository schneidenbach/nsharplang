using System.Linq;

namespace NSharpLang.Tests;

public enum ILCompilerCallMode
{
    Slow = 1,
    Fast = 7
}

public static class ILCompilerCallHelpers
{
    public static int Pick(object value)
    {
        return 1;
    }

    public static int Pick(string value)
    {
        return 2;
    }

    public static int Format(int a, int b = 2, int c = 3)
    {
        return a * 100 + b * 10 + c;
    }

    public static long AddLong(long value, long delta = 5L)
    {
        return value + delta;
    }

    public static int ModeValue(ILCompilerCallMode mode = ILCompilerCallMode.Fast)
    {
        return (int)mode;
    }

    public static int Sum(params int[] values)
    {
        return values.Sum();
    }

    public static T Identity<T>(T value)
    {
        return value;
    }
}
