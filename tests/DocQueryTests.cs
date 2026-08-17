using System;
using System.IO;
using System.Text.Json;
using NSharpLang.Cli;
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

    // The product CLI runs on Microsoft.NETCore.App only, so the reference packs offer assembly
    // names its runtime cannot load — the environment that used to crash `nlc query doc` outright.
    // Running the built Cli.dll under its own runtimeconfig reproduces that environment exactly,
    // which the ASP.NET-enabled test host cannot.
    [Fact]
    public void QueryDoc_InTheCliRuntime_SkipsUnloadablePackAssemblies_AndExplainsTheMiss()
    {
        var cli = FindCliDll();

        var hit = DotnetRunner.Run($"\"{cli}\" query doc Console", workingDirectory: Path.GetTempPath());
        Assert.Equal(0, hit.ExitCode);
        Assert.Contains("\"ok\": true", hit.Stdout);

        var miss = DotnetRunner.Run($"\"{cli}\" query doc HttpLoggingOptions", workingDirectory: Path.GetTempPath());
        Assert.Equal(1, miss.ExitCode);
        using var envelope = JsonDocument.Parse(miss.Stdout);
        var message = envelope.RootElement.GetProperty("error").GetProperty("message").GetString();
        Assert.Contains("No documentation found for 'HttpLoggingOptions'.", message);
        Assert.Contains("(assembly 'Microsoft.AspNetCore.HttpLogging'), but that assembly is not part of this runtime", message);
    }

    private static string FindCliDll()
    {
        var testBin = new DirectoryInfo(AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar));
        var configuration = testBin.Parent!.Name;
        for (var current = testBin; current != null; current = current.Parent)
        {
            var candidate = Path.Combine(current.FullName, "src", "NSharpLang.Cli", "bin", configuration, "net10.0", "Cli.dll");
            if (File.Exists(candidate)) return candidate;
        }

        throw new InvalidOperationException("Could not locate the built N# CLI above this test tree.");
    }
}
