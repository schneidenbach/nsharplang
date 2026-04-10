// Generated from MathUtils.nl — this is the exact C# that N# emits.
// If the compiler output changes, update this file to match.
#nullable enable annotations

using System;
namespace NSharpInteropLib;

public class MathUtils
{
    public static int Add(int a, int b)
    {
        return (a + b);
    }

    public static double Multiply(double a, double b)
    {
        return (a * b);
    }

    public static bool IsEven(int n)
    {
        return ((n % 2) == 0);
    }

    public static int Clamp(int value, int min, int max)
    {
        if ((value < min))
        {
            return min;
        }
        if ((value > max))
        {
            return max;
        }
        return value;
    }

    public static long Factorial(int n)
    {
        if ((n <= 1))
        {
            return 1;
        }
        return (n * Factorial((n - 1)));
    }
}
