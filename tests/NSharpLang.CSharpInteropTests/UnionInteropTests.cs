using NSharpInteropLib.Unions;
using NSharpLang.Runtime;
using Xunit;

namespace NSharpLang.CSharpInteropTests;

public class UnionInteropTests
{
    [Fact]
    public void CSharpCanCallOverloadShimsWithEitherArm()
    {
        Assert.Equal("hello", GreetingApi.Hi(new PrebakedGreeting("hello")));
        Assert.Equal("hi", GreetingApi.Hi("hi"));
    }

    [Fact]
    public void CSharpCanConsumeUnionReturnValues()
    {
        var prebaked = GreetingApi.Choose(prebaked: true);
        var text = GreetingApi.Choose(prebaked: false);

        Assert.True(prebaked.TryGet<PrebakedGreeting>(out var greeting));
        Assert.Equal("hello from N#", greeting.Text);

        Assert.True(text.TryGet<string>(out var message));
        Assert.Equal("hello from text", message);
    }

    [Fact]
    public void RuntimeUnionSupportsCoreCallerApi()
    {
        Union<int, string> number = 42;
        Union<int, string> text = "forty-two";
        Union<int, string> sameNumber = 42;

        Assert.Equal(0, number.Index);
        Assert.Equal(1, text.Index);
        Assert.True(number.Is<int>());
        Assert.False(number.Is<string>());
        Assert.True(text.TryGet<string>(out var value));
        Assert.Equal("forty-two", value);
        Assert.Equal("forty-two", text.As<string>());
        Assert.Equal("42", number.Match(i => i.ToString(), s => s));

        var switched = "";
        text.Switch(i => switched = i.ToString(), s => switched = s);
        Assert.Equal("forty-two", switched);

        Assert.Equal(number, sameNumber);
        Assert.NotEqual(number, text);
        Assert.Equal("42", number.ToString());
    }
}
