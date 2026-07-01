using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

public class LoopSequenceTypeFactsTests
{
    [Theory]
    [InlineData("IEnumerable")]
    [InlineData("System.Collections.Generic.IEnumerable`1")]
    [InlineData("List")]
    [InlineData("HashSet")]
    [InlineData("IList")]
    [InlineData("ICollection")]
    [InlineData("IQueryable")]
    [InlineData("ISet")]
    [InlineData("Queue")]
    [InlineData("Stack")]
    [InlineData("LinkedList")]
    [InlineData("Collection")]
    [InlineData("ObservableCollection")]
    [InlineData("SortedSet")]
    [InlineData("IReadOnlyList")]
    [InlineData("IReadOnlyCollection")]
    [InlineData("Span")]
    [InlineData("System.ReadOnlySpan`1")]
    public void LoopSequenceTypeFacts_ReturnsElementTypeForSyncSequences(string name)
    {
        var sequence = new GenericTypeInfo(name, new List<TypeInfo> { BuiltInTypes.Int });

        Assert.Equal("int", LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(sequence, requireAsync: false)?.ToString());
    }

    [Theory]
    [InlineData("IAsyncEnumerable")]
    [InlineData("System.Collections.Generic.IAsyncEnumerable`1")]
    public void LoopSequenceTypeFacts_ReturnsElementTypeForAsyncSequences(string name)
    {
        var sequence = new GenericTypeInfo(name, new List<TypeInfo> { BuiltInTypes.String });

        Assert.Equal("string", LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(sequence, requireAsync: true)?.ToString());
    }

    [Theory]
    [InlineData("Dictionary")]
    [InlineData("IDictionary")]
    [InlineData("IReadOnlyDictionary")]
    [InlineData("SortedDictionary")]
    [InlineData("SortedList")]
    public void LoopSequenceTypeFacts_DictionariesEnumerateKeyValuePairs(string name)
    {
        var sequence = new GenericTypeInfo(name, new List<TypeInfo> { BuiltInTypes.String, BuiltInTypes.Int });

        var elementType = Assert.IsType<GenericTypeInfo>(
            LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(sequence, requireAsync: false));
        Assert.Equal("KeyValuePair", elementType.Name);
        Assert.Equal(new[] { "string", "int" }, elementType.TypeArguments.Select(argument => argument.ToString()));
    }

    [Fact]
    public void LoopSequenceTypeFacts_RejectsWrongModeAndArity()
    {
        Assert.Null(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(
            new GenericTypeInfo("IAsyncEnumerable", new List<TypeInfo> { BuiltInTypes.Int }),
            requireAsync: false));
        Assert.Null(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(
            new GenericTypeInfo("IEnumerable", new List<TypeInfo> { BuiltInTypes.Int }),
            requireAsync: true));
        Assert.Null(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(
            new GenericTypeInfo("IEnumerable", new List<TypeInfo>()),
            requireAsync: false));
        Assert.Null(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(
            new GenericTypeInfo("IAsyncEnumerable", new List<TypeInfo> { BuiltInTypes.Int, BuiltInTypes.String }),
            requireAsync: true));
        Assert.Null(LoopSequenceTypeFacts.GetGenericLoopSequenceElementType(
            new GenericTypeInfo("Task", new List<TypeInfo> { BuiltInTypes.Int }),
            requireAsync: false));
    }
}
