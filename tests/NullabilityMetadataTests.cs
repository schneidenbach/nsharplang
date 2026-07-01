using System;
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

    [Fact]
    public void NullabilityMetadataCore_MapsClrBuiltInsThroughNSharp()
    {
        Assert.Equal(BuiltInTypes.Int, NullabilityMetadataCore.ConvertBuiltInType(typeof(int).FullName));
        Assert.Equal(BuiltInTypes.String, NullabilityMetadataCore.ConvertBuiltInType(typeof(string).FullName));
        Assert.Equal("int", NullabilityMetadataCore.FormatSimpleClrTypeName(nameof(Int32)));
        Assert.Null(NullabilityMetadataCore.ConvertBuiltInType(typeof(Dictionary<string, int>).FullName));
    }

    [Fact]
    public void NullabilityMetadataCore_OwnsNullabilityWrappingPolicy()
    {
        var stringType = BuiltInTypes.String;
        var nullable = new NullableTypeInfo(stringType);
        var oblivious = new ObliviousTypeInfo(stringType);

        Assert.Same(nullable, NullabilityMetadataCore.EnsureNullable(nullable));
        Assert.Same(stringType, Assert.IsType<NullableTypeInfo>(NullabilityMetadataCore.EnsureNullable(oblivious)).InnerType);
        Assert.Same(nullable, NullabilityMetadataCore.EnsureOblivious(nullable));
        Assert.Same(stringType, NullabilityMetadataCore.EnsureNotNull(nullable));
        Assert.Same(stringType, NullabilityMetadataCore.EnsureNotNull(oblivious));
    }

    [Fact]
    public void NullabilityMetadataCore_OwnsTypeInfoReferenceNullabilityEligibility()
    {
        Assert.False(NullabilityMetadataCore.CanCarryReferenceNullability(BuiltInTypes.Int));
        Assert.True(NullabilityMetadataCore.CanCarryReferenceNullability(BuiltInTypes.String));
        Assert.False(NullabilityMetadataCore.CanCarryReferenceNullability(new NullableTypeInfo(BuiltInTypes.String)));
        Assert.True(NullabilityMetadataCore.CanCarryReferenceNullability(new ObliviousTypeInfo(BuiltInTypes.String)));
        Assert.False(NullabilityMetadataCore.CanCarryReferenceNullability(BuiltInTypes.Unknown));
    }
}
