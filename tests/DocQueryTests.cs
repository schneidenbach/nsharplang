using System;
using System.Linq;
using System.Reflection;
using NSharpLang.Compiler.CodeIntelligence;
using Xunit;

namespace NSharpLang.Tests;

public class DocQueryTests
{
    private static readonly Lazy<DocQuery> Query = new(() =>
    {
        var query = new DocQuery();
        query.LoadSystemAssemblies();
        return query;
    });

    [Fact]
    public void Lookup_Console_LoadsXmlDocsFromReferencePacks()
    {
        var result = Query.Value.Lookup("Console");

        Assert.NotNull(result);
        Assert.Equal("System.Console", result!.FullName);
        Assert.False(string.IsNullOrWhiteSpace(result.Summary));
    }

    [Fact]
    public void Lookup_ListAdd_UsesGenericDocIdsForParameters()
    {
        var result = Query.Value.Lookup("List.Add");

        Assert.NotNull(result);
        Assert.StartsWith("method", result!.Kind, StringComparison.Ordinal);
        Assert.False(string.IsNullOrWhiteSpace(result.Summary));

        var item = Assert.Single(result.Parameters!, p => p.Name == "item");
        Assert.Equal("T", item.Type);
        Assert.False(string.IsNullOrWhiteSpace(item.Summary));
        Assert.DoesNotContain(" end of the .", result.Summary!, StringComparison.Ordinal);
        Assert.DoesNotContain(" can be  ", item.Summary!, StringComparison.Ordinal);
    }

    [Fact]
    public void Lookup_EnvironmentSpecialFolder_ResolvesNestedType()
    {
        var result = Query.Value.Lookup("Environment.SpecialFolder");

        Assert.NotNull(result);
        Assert.Equal("enum", result!.Kind);
        Assert.Equal("System.Environment.SpecialFolder", result.FullName);
        Assert.False(string.IsNullOrWhiteSpace(result.Summary));
    }

    [Fact]
    public void Lookup_Regex_FindsAssembliesOutsideHardcodedSeedList()
    {
        var result = Query.Value.Lookup("Regex");

        Assert.NotNull(result);
        Assert.Equal("System.Text.RegularExpressions.Regex", result!.FullName);
        Assert.False(string.IsNullOrWhiteSpace(result.Summary));
    }

    [Fact]
    public void Lookup_List_And_Process_ExposeConstructorsAndEvents()
    {
        var list = Query.Value.Lookup("List");
        var process = Query.Value.Lookup("Process");

        Assert.NotNull(list);
        Assert.Contains(list!.Members!, m => m.Kind == "constructor");
        Assert.Contains(list.Members!, m => m.Kind == "method" && m.Name == "Add");

        Assert.NotNull(process);
        Assert.Contains(process!.Members!, m => m.Kind == "event" && m.Name == "Exited");
    }

    [Fact]
    public void Lookup_Environment_ListsNestedTypes()
    {
        var result = Query.Value.Lookup("Environment");

        Assert.NotNull(result);
        Assert.Contains(result!.Members!, m => m.Kind == "nested type" && m.Name == "SpecialFolder");
    }

    [Fact]
    public void DeduplicateReferencePackAssemblyNames_PreservesFirstSourceOrder()
    {
        var method = typeof(DocQuery).GetMethod(
                "DeduplicateReferencePackAssemblyNames",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("DocQuery did not emit DeduplicateReferencePackAssemblyNames.");

        var names = new[]
        {
            "System.Console",
            "system.console",
            "System.Text.Json",
            "System.Runtime",
            "SYSTEM.TEXT.JSON",
            "system.runtime"
        };

        var actual = Assert.IsType<string[]>(method.Invoke(null, new object[] { names }));

        Assert.Equal(new[]
        {
            "System.Console",
            "System.Text.Json",
            "System.Runtime"
        }, actual);
    }

    [Fact]
    public void DeduplicateTypeCandidates_PreservesFirstSourceOrder()
    {
        var method = typeof(DocQuery).GetMethod(
                "DeduplicateTypeCandidates",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("DocQuery did not emit DeduplicateTypeCandidates.");

        var candidates = new[]
        {
            typeof(string),
            typeof(int),
            typeof(string),
            typeof(Console),
            typeof(int)
        };

        var actual = Assert.IsType<Type[]>(method.Invoke(null, new object[] { candidates }));

        Assert.Equal(new[]
        {
            typeof(string),
            typeof(int),
            typeof(Console)
        }, actual);
    }
}
