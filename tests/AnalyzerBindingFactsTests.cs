using System;
using System.Collections.Generic;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

public class AnalyzerBindingFactsTests
{
    [Fact]
    public void AnalyzerBindingFacts_ResolvesParameterDeclarationPosition()
    {
        var explicitPosition = AnalyzerBindingFacts.GetParameterDeclarationPosition(7, 11, 2, 3);
        var fallbackPosition = AnalyzerBindingFacts.GetParameterDeclarationPosition(0, 0, 2, 3);

        Assert.Equal((7, 11), explicitPosition);
        Assert.Equal((2, 3), fallbackPosition);
    }

    [Fact]
    public void AnalyzerBindingFacts_ClassifiesValueBindingsForShadowing()
    {
        Assert.True(AnalyzerBindingFacts.IsValueBinding("count", BuiltInTypes.Int, hasTypeBinding: false));
        Assert.False(AnalyzerBindingFacts.IsValueBinding("this", BuiltInTypes.Int, hasTypeBinding: false));
        Assert.False(AnalyzerBindingFacts.IsValueBinding("value", BuiltInTypes.Int, hasTypeBinding: false));
        Assert.False(AnalyzerBindingFacts.IsValueBinding("T", BuiltInTypes.Int, hasTypeBinding: true));
        Assert.False(AnalyzerBindingFacts.IsValueBinding("Run", new FunctionTypeInfo(), hasTypeBinding: false));
        Assert.False(AnalyzerBindingFacts.IsValueBinding(
            "Run",
            new NSharpMethodGroupInfo(new List<FunctionTypeInfo> { new() }),
            hasTypeBinding: false));
    }

    [Fact]
    public void AnalyzerBindingFacts_MapsTypeInfoToBindingDeclarationKind()
    {
        Assert.Equal("class", AnalyzerBindingFacts.TypeInfoToDeclarationKind(ClassType()));
        Assert.Equal("struct", AnalyzerBindingFacts.TypeInfoToDeclarationKind(StructType()));
        Assert.Equal("record", AnalyzerBindingFacts.TypeInfoToDeclarationKind(RecordType()));
        Assert.Equal("soaRecord", AnalyzerBindingFacts.TypeInfoToDeclarationKind(
            new SoaRecordTypeInfo(new SoaRecordDeclarationInfo("Rows", new List<SoaColumnInfo>()))));
        Assert.Equal("interface", AnalyzerBindingFacts.TypeInfoToDeclarationKind(InterfaceType()));
        Assert.Equal("enum", AnalyzerBindingFacts.TypeInfoToDeclarationKind(
            new EnumTypeInfo(new EnumDeclarationInfo("Color", new List<EnumMemberInfo>(), EnumType.Int))));
        Assert.Equal("union", AnalyzerBindingFacts.TypeInfoToDeclarationKind(
            new AnonymousUnionTypeInfo(new List<TypeInfo> { BuiltInTypes.Int, BuiltInTypes.String })));
        Assert.Equal("union", AnalyzerBindingFacts.TypeInfoToDeclarationKind(
            new UnionTypeInfo(new UnionDeclarationInfo("Result", null, new List<UnionCase>()))));
        Assert.Equal("function", AnalyzerBindingFacts.TypeInfoToDeclarationKind(new FunctionTypeInfo()));
        Assert.Equal("function", AnalyzerBindingFacts.TypeInfoToDeclarationKind(
            new NSharpMethodGroupInfo(new List<FunctionTypeInfo> { new() })));
        Assert.Equal("variable", AnalyzerBindingFacts.TypeInfoToDeclarationKind(BuiltInTypes.Int));
        Assert.Equal("variable", AnalyzerBindingFacts.TypeInfoToDeclarationKind(
            new AliasTypeInfo(new SimpleTypeReference("int"))));
        Assert.Equal("variable", AnalyzerBindingFacts.TypeInfoToDeclarationKind(
            new NewtypeInfo("UserId", new SimpleTypeReference("int"))));
    }

    [Fact]
    public void AnalyzerBindingFacts_ClassifiesTypeDeclarationKindStrings()
    {
        Assert.True(AnalyzerBindingFacts.IsTypeDeclarationKind("class"));
        Assert.True(AnalyzerBindingFacts.IsTypeDeclarationKind("struct"));
        Assert.True(AnalyzerBindingFacts.IsTypeDeclarationKind("record"));
        Assert.True(AnalyzerBindingFacts.IsTypeDeclarationKind("soaRecord"));
        Assert.True(AnalyzerBindingFacts.IsTypeDeclarationKind("interface"));
        Assert.True(AnalyzerBindingFacts.IsTypeDeclarationKind("enum"));
        Assert.True(AnalyzerBindingFacts.IsTypeDeclarationKind("union"));
        Assert.True(AnalyzerBindingFacts.IsTypeDeclarationKind("typeAlias"));
        Assert.True(AnalyzerBindingFacts.IsTypeDeclarationKind("newtype"));
        Assert.False(AnalyzerBindingFacts.IsTypeDeclarationKind("function"));
        Assert.False(AnalyzerBindingFacts.IsTypeDeclarationKind("variable"));
    }

    private static ClassTypeInfo ClassType()
        => new(
            "Customer",
            0,
            0,
            false,
            null,
            Array.Empty<TypeReference>(),
            Array.Empty<TypeParameter>(),
            Array.Empty<ParameterDeclarationInfo>(),
            Array.Empty<DeclaredMemberInfo>(),
            Array.Empty<NestedTypeInfo>(),
            hasParameterlessConstructor: false);

    private static StructTypeInfo StructType()
        => new(
            "Point",
            0,
            0,
            Array.Empty<TypeReference>(),
            Array.Empty<TypeParameter>(),
            Array.Empty<ParameterDeclarationInfo>(),
            Array.Empty<DeclaredMemberInfo>(),
            Array.Empty<NestedTypeInfo>());

    private static RecordTypeInfo RecordType()
        => new(
            "Order",
            0,
            0,
            isStruct: false,
            Array.Empty<TypeReference>(),
            Array.Empty<TypeParameter>(),
            Array.Empty<ParameterDeclarationInfo>(),
            Array.Empty<DeclaredMemberInfo>(),
            Array.Empty<NestedTypeInfo>());

    private static InterfaceTypeInfo InterfaceType()
        => new(
            "IWorker",
            0,
            0,
            isDuckInterface: false,
            Array.Empty<TypeReference>(),
            Array.Empty<TypeParameter>(),
            Array.Empty<DeclaredMemberInfo>(),
            Array.Empty<NestedTypeInfo>());
}
