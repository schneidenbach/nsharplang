using System.Reflection;
using System.Runtime.InteropServices.JavaScript;
using System.Runtime.Versioning;
using System.Text.Json;

namespace NSharpLang.Playground.Wasm;

[SupportedOSPlatform("browser")]
public static partial class PlaygroundExports
{
    private static readonly PlaygroundCompiler Compiler = new();
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [JSExport]
    public static string GetCatalog()
        => Serialize(Compiler.GetCatalog());

    [JSExport]
    public static string Check(string source)
        => Serialize(Compiler.Check(source));

    [JSExport]
    public static string CheckProject(string filesJson, string activeFile)
        => Serialize(Compiler.CheckProject(ParseFiles(filesJson), activeFile));

    [JSExport]
    public static string Format(string source, string fileName)
        => Serialize(Compiler.Format(source, fileName));

    [JSExport]
    public static string RunProject(string filesJson, string activeFile)
        => Serialize(Compiler.RunProject(ParseFiles(filesJson), activeFile));

    [JSExport]
    public static string Complete(string filesJson, string fileName, int line, int column)
        => Serialize(Compiler.Complete(ParseFiles(filesJson), fileName, line, column));

    [JSExport]
    public static string Hover(string filesJson, string fileName, int line, int column)
        => Serialize(Compiler.Hover(ParseFiles(filesJson), fileName, line, column));

    [JSExport]
    public static string Version()
        => Serialize(
            new PlaygroundVersionResponse(
                PlaygroundCompiler.SchemaVersion,
                typeof(PlaygroundCompiler).Assembly.GetName().Version?.ToString() ?? "0.0.0",
                Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "0.0.0"));

    private static PlaygroundFile[] ParseFiles(string filesJson)
    {
        if (string.IsNullOrWhiteSpace(filesJson))
        {
            return [];
        }

        return JsonSerializer.Deserialize<PlaygroundFile[]>(filesJson, JsonOptions) ?? [];
    }

    private static string Serialize<T>(T value)
        => JsonSerializer.Serialize(value, JsonOptions);
}

public sealed record PlaygroundVersionResponse(int SchemaVersion, string Compiler, string WasmHost);
