using System.Collections.Generic;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

public class TypeReferenceFactsTests
{
    [Fact]
    public void TypeReferenceFacts_UsesExplicitSpanBeforeFallback()
    {
        var typeRef = new SimpleTypeReference("Ignored", 2, 3)
        {
            Span = new SourceSpan(9, 4, 9, 12)
        };

        Assert.Equal(new SourceSpan(9, 4, 9, 12), TypeReferenceFacts.GetStartSpan(typeRef));
    }

    [Fact]
    public void TypeReferenceFacts_ReturnsNameSpanForNamedTypeReferences()
    {
        Assert.Equal(
            new SourceSpan(3, 7, 3, 13),
            TypeReferenceFacts.GetStartSpan(new SimpleTypeReference("Person", 3, 7)));

        Assert.Equal(
            new SourceSpan(4, 5, 4, 8),
            TypeReferenceFacts.GetStartSpan(new GenericTypeReference("Box", new List<TypeReference>(), 4, 5)));
    }

    [Fact]
    public void TypeReferenceFacts_UnwrapsCompositeTypeReferencesWithoutExplicitSpan()
    {
        Assert.Equal(
            new SourceSpan(6, 9, 6, 12),
            TypeReferenceFacts.GetStartSpan(new ArrayTypeReference(new SimpleTypeReference("int", 6, 9))));

        Assert.Equal(
            new SourceSpan(7, 10, 7, 16),
            TypeReferenceFacts.GetStartSpan(new NullableTypeReference(new SimpleTypeReference("string", 7, 10))));

        Assert.Equal(
            new SourceSpan(8, 3, 8, 7),
            TypeReferenceFacts.GetStartSpan(new ByRefTypeReference(new SimpleTypeReference("bool", 8, 3))));

        Assert.Equal(
            new SourceSpan(9, 11, 9, 16),
            TypeReferenceFacts.GetStartSpan(new UnionTypeReference(new List<TypeReference>
            {
                new SimpleTypeReference("First", 9, 11),
                new SimpleTypeReference("Second", 9, 19)
            })));

        Assert.Equal(
            new SourceSpan(10, 4, 10, 10),
            TypeReferenceFacts.GetStartSpan(new TupleTypeReference(new List<TupleTypeElement>
            {
                new(new SimpleTypeReference("double", 10, 4), null),
                new(new SimpleTypeReference("string", 10, 12), null)
            })));

        Assert.Equal(
            new SourceSpan(11, 14, 11, 18),
            TypeReferenceFacts.GetStartSpan(new FunctionTypeReference(
                new List<TypeReference> { new SimpleTypeReference("int", 11, 5) },
                new SimpleTypeReference("Guid", 11, 14))));
    }

    [Fact]
    public void TypeReferenceFacts_ReturnsNoneForEmptyCompositeTypeReferences()
    {
        Assert.Equal(
            SourceSpan.None,
            TypeReferenceFacts.GetStartSpan(new UnionTypeReference(new List<TypeReference>())));

        Assert.Equal(
            SourceSpan.None,
            TypeReferenceFacts.GetStartSpan(new TupleTypeReference(new List<TupleTypeElement>())));
    }
}
