using NSharpLang.Runtime;

namespace NSharpInteropLib.Unions;

public sealed class PrebakedGreeting
{
    public PrebakedGreeting(string text)
    {
        Text = text;
    }

    public string Text { get; }
}

public static class GreetingApi
{
    public static string Hi(Union<PrebakedGreeting, string> greeting)
    {
        return greeting.Match(
            prebaked => prebaked.Text,
            text => text);
    }

    public static string Hi(PrebakedGreeting greeting) => Hi((Union<PrebakedGreeting, string>)greeting);

    public static string Hi(string greeting) => Hi((Union<PrebakedGreeting, string>)greeting);

    public static Union<PrebakedGreeting, string> Choose(bool prebaked)
    {
        return prebaked ? new PrebakedGreeting("hello from N#") : "hello from text";
    }
}
