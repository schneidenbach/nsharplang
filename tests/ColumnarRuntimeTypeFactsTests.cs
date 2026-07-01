using System;
using System.Diagnostics;
using System.IO;
using NSharpLang.Compiler.Columnar;
using Xunit;

namespace NSharpLang.Tests;

public class ColumnarRuntimeTypeFactsTests
{
    [Theory]
    [InlineData(typeof(Process), true)]
    [InlineData(typeof(ProcessStartInfo), true)]
    [InlineData(typeof(StreamReader), true)]
    [InlineData(typeof(string), false)]
    public void IsSupportedProcessInteropType_ClassifiesProcessInteropTypes(Type type, bool expected)
    {
        Assert.Equal(expected, ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType(type));
    }
}
