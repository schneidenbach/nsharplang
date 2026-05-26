using System.Reflection;
using System.Runtime.InteropServices.JavaScript;
using System.Runtime.Versioning;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;

namespace NSharpLang.Playground.Wasm;

[SupportedOSPlatform("browser")]
public static partial class PlaygroundExports
{
    private static readonly PlaygroundCompiler Compiler = new();

    [JSExport]
    public static string GetCatalog()
        => Serialize(Compiler.GetCatalog(), PlaygroundJsonContext.Default.PlaygroundCatalogResponse);

    [JSExport]
    public static string Check(string source)
        => Serialize(Compiler.Check(source), PlaygroundJsonContext.Default.PlaygroundCheckResponse);

    [JSExport]
    public static string CheckProject(string filesJson, string activeFile)
        => Serialize(
            Compiler.CheckProject(ParseFiles(filesJson), activeFile),
            PlaygroundJsonContext.Default.PlaygroundCheckResponse);

    [JSExport]
    public static string Format(string source, string fileName)
        => Serialize(
            Compiler.Format(source, fileName),
            PlaygroundJsonContext.Default.PlaygroundFormatResponse);

    [JSExport]
    public static string Complete(string filesJson, string fileName, int line, int column)
        => Serialize(
            Compiler.Complete(ParseFiles(filesJson), fileName, line, column),
            PlaygroundJsonContext.Default.PlaygroundCompletionResponse);

    [JSExport]
    public static string Hover(string filesJson, string fileName, int line, int column)
        => Serialize(
            Compiler.Hover(ParseFiles(filesJson), fileName, line, column),
            PlaygroundJsonContext.Default.PlaygroundHoverResponse);

    [JSExport]
    public static string Version()
        => Serialize(
            new PlaygroundVersionResponse(
                PlaygroundCompiler.SchemaVersion,
                typeof(PlaygroundCompiler).Assembly.GetName().Version?.ToString() ?? "0.0.0",
                Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "0.0.0"),
            PlaygroundJsonContext.Default.PlaygroundVersionResponse);

    private static PlaygroundFile[] ParseFiles(string filesJson)
    {
        if (string.IsNullOrWhiteSpace(filesJson))
        {
            return [];
        }

        return JsonSerializer.Deserialize(filesJson, PlaygroundJsonContext.Default.PlaygroundFileArray) ?? [];
    }

    private static string Serialize<T>(T value, JsonTypeInfo<T> jsonTypeInfo)
        => JsonSerializer.Serialize(value, jsonTypeInfo);
}

public sealed record PlaygroundVersionResponse(int SchemaVersion, string Compiler, string WasmHost);

[JsonSerializable(typeof(PlaygroundCatalogResponse))]
[JsonSerializable(typeof(PlaygroundCheckResponse))]
[JsonSerializable(typeof(PlaygroundFormatResponse))]
[JsonSerializable(typeof(PlaygroundCompletionResponse))]
[JsonSerializable(typeof(PlaygroundHoverResponse))]
[JsonSerializable(typeof(PlaygroundVersionResponse))]
[JsonSerializable(typeof(PlaygroundFile[]))]
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class PlaygroundJsonContext : JsonSerializerContext
{
}
