// Generated from GenericUnions.nl — this is the exact C# shape that N# emits.
// If the compiler output changes, update this file to match.
#nullable enable annotations

namespace NSharpInteropLib.Unions;

public abstract class Fetched<T>
{
    protected Fetched() { }

    public sealed class Hit : Fetched<T>
    {
        public Hit() { }

        public Hit(T Value)
        {
            this.Value = Value;
        }

        public T Value;
    }

    public sealed class Miss : Fetched<T>
    {
        public Miss() { }

        public Miss(string Reason)
        {
            this.Reason = Reason;
        }

        public string Reason;
    }
}

public class FetchApi
{
    public static Fetched<int> FetchNumber(bool hit)
    {
        if (hit)
        {
            return new Fetched<int>.Hit { Value = 42 };
        }
        return new Fetched<int>.Miss { Reason = "no luck" };
    }
}
