using System.Collections.Generic;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

public class AnalyzerOverloadSignatureFactsTests
{
    [Fact]
    public void AnalyzerOverloadSignatureFacts_FormatsNestedTypeReferenceSignatures()
    {
        var nested = new GenericTypeReference("Dictionary", new List<TypeReference>
        {
            new SimpleTypeReference("string"),
            new ArrayTypeReference(new NullableTypeReference(new SimpleTypeReference("int")))
        });
        var tuple = new TupleTypeReference(new List<TupleTypeElement>
        {
            new(new SimpleTypeReference("string"), "name"),
            new(new ByRefTypeReference(new SimpleTypeReference("int")), null)
        });
        var function = new FunctionTypeReference(
            new List<TypeReference>
            {
                new SimpleTypeReference("int"),
                new UnionTypeReference(new List<TypeReference>
                {
                    new SimpleTypeReference("string"),
                    new SimpleTypeReference("null")
                })
            },
            new SimpleTypeReference("bool"));

        Assert.Equal("Dictionary<string,int?[]>", AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(nested));
        Assert.Equal("(string,&int)", AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(tuple));
        Assert.Equal("(int,string|null)->bool", AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(function));
    }

    [Fact]
    public void AnalyzerOverloadSignatureFacts_ComparesSourceParameterSignatures()
    {
        var first = FunctionWith(
            new SimpleTypeReference("int"),
            new GenericTypeReference("List", new List<TypeReference>
            {
                new ArrayTypeReference(new SimpleTypeReference("string"))
            }));
        var same = FunctionWith(
            new SimpleTypeReference("int"),
            new GenericTypeReference("List", new List<TypeReference>
            {
                new ArrayTypeReference(new SimpleTypeReference("string"))
            }));
        var different = FunctionWith(
            new SimpleTypeReference("int"),
            new GenericTypeReference("List", new List<TypeReference>
            {
                new ArrayTypeReference(new SimpleTypeReference("bool"))
            }));

        Assert.True(AnalyzerOverloadSignatureFacts.HasSourceParameterSignature(first));
        Assert.False(AnalyzerOverloadSignatureFacts.HasSourceParameterSignature(new FunctionTypeInfo()));
        Assert.True(AnalyzerOverloadSignatureFacts.ParameterSignaturesMatch(first, same));
        Assert.False(AnalyzerOverloadSignatureFacts.ParameterSignaturesMatch(first, different));
        Assert.False(AnalyzerOverloadSignatureFacts.HasDistinctParameterSignature(same, new[] { first }));
        Assert.True(AnalyzerOverloadSignatureFacts.HasDistinctParameterSignature(different, new[] { first }));
    }

    private static FunctionTypeInfo FunctionWith(params TypeReference[] parameters)
        => new()
        {
            SourceParameterTypes = new List<TypeReference>(parameters)
        };
}
