using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices.JavaScript;
using System.Runtime.Versioning;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NSharpLang.Playground.Wasm;

[JsonSourceGenerationOptions(JsonSerializerDefaults.Web, IncludeFields = true)]
[JsonSerializable(typeof(PlaygroundCatalogResponse)), JsonSerializable(typeof(PlaygroundCheckResponse)), JsonSerializable(typeof(PlaygroundFormatResponse)), JsonSerializable(typeof(PlaygroundCompletionResponse)), JsonSerializable(typeof(PlaygroundHoverResponse)), JsonSerializable(typeof(PlaygroundRunResponse)), JsonSerializable(typeof(PlaygroundVersionResponse)), JsonSerializable(typeof(PlaygroundFileInput[]))]
internal partial class PlaygroundJsonContext : JsonSerializerContext { }

internal sealed record PlaygroundFileInput(string Name, string Code);

[SupportedOSPlatform("browser")]
public static partial class PlaygroundExports
{
    private static readonly PlaygroundCompiler Compiler = new();

    [JSExport] public static string GetCatalog() => Serialize(Compiler.GetCatalog());
    [JSExport] public static string Check(string source) => Serialize(Compiler.Check(source));
    [JSExport] public static string CheckProject(string filesJson, string activeFile) => Serialize(Compiler.CheckProject(ParseFiles(filesJson), activeFile));
    [JSExport] public static string Format(string source, string fileName) => Serialize(Compiler.Format(source, fileName));
    [JSExport]
    public static async System.Threading.Tasks.Task<string> RunProject(string filesJson, string activeFile)
        => Serialize(await Compiler.RunProject(ParseFiles(filesJson), activeFile));
    [JSExport] public static string Complete(string filesJson, string fileName, int line, int column) => Serialize(Compiler.Complete(ParseFiles(filesJson), fileName, line, column));
    [JSExport] public static string Hover(string filesJson, string fileName, int line, int column) => Serialize(Compiler.Hover(ParseFiles(filesJson), fileName, line, column));
    [JSExport] public static string Version() => Serialize(new PlaygroundVersionResponse(PlaygroundCompiler.SchemaVersion, typeof(PlaygroundCompiler).Assembly.GetName().Version?.ToString() ?? "0.0.0", Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "0.0.0"));

    [JSExport]
    public static void RegisterMetadataReferences(string archiveBase64)
    {
        using var archive = new ZipArchive(new MemoryStream(Convert.FromBase64String(archiveBase64)));
        foreach (var entry in archive.Entries)
        {
            if (entry.FullName != entry.Name || !entry.Name.EndsWith(".dll", StringComparison.OrdinalIgnoreCase)) continue;
            using var input = entry.Open();
            using var output = File.Create(Path.Combine(AppContext.BaseDirectory, entry.Name));
            input.CopyTo(output);
        }
    }

    private static PlaygroundFile[] ParseFiles(string filesJson)
    {
        if (string.IsNullOrWhiteSpace(filesJson)) return [];
        var inputType = PlaygroundJsonContext.Default.GetTypeInfo(typeof(PlaygroundFileInput[]))!;
        var inputs = (PlaygroundFileInput[]?)JsonSerializer.Deserialize(filesJson, inputType) ?? [];
        return System.Array.ConvertAll(inputs, static file => new PlaygroundFile(file.Name, file.Code));
    }

    private static string Serialize<T>(T value) => JsonSerializer.Serialize(value, PlaygroundJsonContext.Default.GetTypeInfo(typeof(T))!);
}
