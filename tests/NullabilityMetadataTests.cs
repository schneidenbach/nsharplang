using System.Collections.Generic;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

public class NullabilityMetadataTests
{
    [Fact]
    public void NullabilityTypeDisplay_FormatsNSharpOwnedTypeInfoCases()
    {
        var generic = new GenericTypeInfo("List", new List<TypeInfo> { BuiltInTypes.String });
        var nullableArray = new NullableTypeInfo(new ArrayTypeInfo(generic));
        var function = new FunctionTypeInfo
        {
            ParameterTypes = new List<TypeInfo> { BuiltInTypes.Int, nullableArray },
            ReturnType = BuiltInTypes.Bool
        };

        Assert.Equal("List<string>", NullabilityTypeDisplay.TryFormatTypeInfo(generic));
        Assert.Equal("List<string>[]?", NullabilityTypeDisplay.TryFormatTypeInfo(nullableArray));
        Assert.Equal("(int, List<string>[]?) -> bool", NullabilityTypeDisplay.TryFormatTypeInfo(function));
    }

    [Fact]
    public void NullabilityMetadata_PreservesFallbackFormatting()
    {
        var newtype = new NewtypeInfo("UserId", new SimpleTypeReference("int"));
        var reflection = new ReflectionTypeInfo(typeof(Dictionary<string, int>));

        Assert.Null(NullabilityTypeDisplay.TryFormatTypeInfo(newtype));
        Assert.Equal("UserId", NullabilityMetadata.FormatTypeInfo(newtype));
        Assert.Equal("Dictionary<string, int>", NullabilityMetadata.FormatTypeInfo(reflection));
    }

    [Fact]
    public void NullabilityMetadata_StripsObliviousMetadataThroughNSharp()
    {
        var inner = BuiltInTypes.String;
        var type = new ObliviousTypeInfo(new ObliviousTypeInfo(inner));

        Assert.Same(inner, NullabilityMetadata.StripMetadata(type));
    }
}
