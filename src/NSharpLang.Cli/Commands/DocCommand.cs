using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Commands;

public static class DocCommand
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    public static int Execute(string[] args)
    {
        var options = GetOptionSummary(args);
        if (options.ShowHelp)
            return ShowHelp();

        var useJson = options.Json;
        var openAfterGenerate = options.Open;
        var projectRoot = options.ProjectOption ?? Directory.GetCurrentDirectory();
        var outputDir = options.OutputOption ?? Path.Combine(projectRoot, "nsharp", "docs");
        projectRoot = Path.GetFullPath(projectRoot);
        outputDir = Path.GetFullPath(outputDir);

        if (!Directory.Exists(projectRoot))
            return EmitError(useJson, projectRoot, $"Project directory not found: {projectRoot}");

        try
        {
            var service = new CodeIntelligenceService();
            var snapshot = service.LoadProject(projectRoot);
            var symbols = service.GetSymbols(snapshot);

            var manifest = ProjectDocGenerator.Generate(projectRoot, outputDir, symbols);

            if (openAfterGenerate && !TryOpen(manifest.IndexPath, out var openError))
                return EmitError(useJson, projectRoot, openError!);

            if (useJson)
            {
                Console.Write(JsonSerializer.Serialize(new
                {
                    schemaVersion = 1,
                    command = "doc",
                    ok = true,
                    projectRoot = NormalizePath(projectRoot),
                    outputDir = NormalizePath(outputDir),
                    result = manifest
                }, JsonOptions));
            }
            else
            {
                Console.WriteLine($"Generated API docs for {manifest.PageCount} symbols.");
                Console.WriteLine($"Output: {outputDir}");
                Console.WriteLine($"Index: {manifest.IndexPath}");
                if (openAfterGenerate)
                    Console.WriteLine("Opened generated documentation in the default browser.");
            }

            return 0;
        }
        catch (Exception ex)
        {
            return EmitError(useJson, projectRoot, $"Doc generation failed: {ex.Message}");
        }
    }

    private static int ShowHelp()
    {
        Console.WriteLine(@"N# API Documentation

Usage: nlc doc [options]

Generate HTML API documentation for the current project. Similar to `cargo doc`.

Options:
  --project <dir>   Project root directory (default: current directory)
  --output <dir>    Output directory (default: ./nsharp/docs)
  --json            Emit a structured JSON result envelope
  --open            Open the generated index in the default browser
  --help, -h        Show this help text

Examples:
  nlc doc
  nlc doc --open
  nlc doc --json
  nlc doc --project examples/16-task-cli --output /tmp/nsharp-docs

Exit codes:
  0  Documentation generated successfully
  1  Documentation generation failed");

        return 0;
    }

    private static int EmitError(bool useJson, string projectRoot, string message)
    {
        if (useJson)
        {
            Console.Write(JsonSerializer.Serialize(new
            {
                schemaVersion = 1,
                command = "doc",
                ok = false,
                projectRoot = NormalizePath(projectRoot),
                error = new
                {
                    message
                }
            }, JsonOptions));
        }
        else
        {
            Console.Error.WriteLine(message);
        }

        return 1;
    }

    internal static DocOptionSummary GetOptionSummary(string[] args)
        => DocCommandKernels.TryGetOptionSummary(args, out var summary)
            ? summary
            : GetOptionSummaryWithCSharp(args);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product doc option parsing routes through DocCommandKernels.
    private static DocOptionSummary GetOptionSummaryWithCSharp(string[] args)
        => new(
            GetOptionValueWithCSharp(args, "--project"),
            GetOptionValueWithCSharp(args, "--output"),
            ContainsArgWithCSharp(args, "--json"),
            ContainsArgWithCSharp(args, "--open"),
            ContainsArgWithCSharp(args, "--help") || ContainsArgWithCSharp(args, "-h") || (args.Length > 0 && args[0] == "help"));

    private static string? GetOptionValueWithCSharp(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == flag)
                return args[i + 1];
        }

        return null;
    }

    private static bool ContainsArgWithCSharp(string[] args, string value)
    {
        for (var i = 0; i < args.Length; i++)
            if (args[i] == value)
                return true;
        return false;
    }

    private static bool TryOpen(string path, out string? error)
    {
        error = null;

        string fileName;
        string arguments;

        if (OperatingSystem.IsMacOS())
        {
            fileName = "open";
            arguments = Quote(path);
        }
        else if (OperatingSystem.IsWindows())
        {
            fileName = "cmd";
            arguments = $"/c start \"\" {Quote(path)}";
        }
        else
        {
            fileName = "xdg-open";
            arguments = Quote(path);
        }

        try
        {
            var result = DotnetRunner.RunProcess(fileName, arguments);
            if (result.ExitCode == 0)
                return true;

            error = $"Generated docs, but failed to open {path}.";
            return false;
        }
        catch (Exception ex)
        {
            error = $"Generated docs, but failed to open {path}: {ex.Message}";
            return false;
        }
    }

    private static string Quote(string value) => $"\"{value}\"";

    private static string NormalizePath(string path) => path.Replace('\\', '/');
}

internal static class ProjectDocGenerator
{
    public static DocManifest Generate(string projectRoot, string outputDir, IReadOnlyList<SymbolResult> symbols)
    {
        var orderedSymbols = OrderSymbolsForGeneration(symbols);

        if (Directory.Exists(outputDir))
            Directory.Delete(outputDir, recursive: true);

        Directory.CreateDirectory(outputDir);
        var symbolDir = Path.Combine(outputDir, "symbols");
        Directory.CreateDirectory(symbolDir);

        var pages = new List<DocPage>();
        var slugs = CreateSlugs(orderedSymbols);

        for (var i = 0; i < orderedSymbols.Count; i++)
        {
            var symbol = orderedSymbols[i];
            var slug = slugs[i];
            var relativePath = NormalizePath(Path.Combine("symbols", $"{slug}.html"));
            var absolutePath = Path.Combine(outputDir, relativePath.Replace('/', Path.DirectorySeparatorChar));
            File.WriteAllText(absolutePath, RenderSymbolPage(symbol, projectRoot));
            pages.Add(new DocPage(symbol.Name, symbol.Kind.ToString().ToLowerInvariant(), relativePath));
        }

        var indexPath = Path.Combine(outputDir, "index.html");
        File.WriteAllText(indexPath, RenderIndexPage(orderedSymbols, pages, projectRoot));

        return new DocManifest(
            NormalizePath(indexPath),
            pages.Count,
            pages);
    }

    internal static List<SymbolResult> OrderSymbolsForGeneration(IReadOnlyList<SymbolResult> symbols)
    {
        if (DocCommandKernels.TryOrderSymbolsForGeneration(symbols, out var orderedSymbols))
            return orderedSymbols;

        return symbols
            .Where(symbol => symbol.Kind is not SymbolKind.Variable and not SymbolKind.Parameter)
            .OrderBy(symbol => symbol.Kind.ToString(), StringComparer.Ordinal)
            .ThenBy(symbol => symbol.Name, StringComparer.Ordinal)
            .ToList();
    }

    private static string RenderIndexPage(IReadOnlyList<SymbolResult> symbols, IReadOnlyList<DocPage> pages, string projectRoot)
    {
        var grouped = new List<string>();
        var index = 0;
        while (index < symbols.Count)
        {
            var kind = symbols[index].Kind;
            var items = new List<string>();
            while (index < symbols.Count && symbols[index].Kind == kind)
            {
                var symbol = symbols[index];
                var page = pages.First(p => p.Name == symbol.Name && p.Kind == symbol.Kind.ToString().ToLowerInvariant());
                items.Add($"<li><a href=\"{WebUtility.HtmlEncode(page.Path)}\">{WebUtility.HtmlEncode(symbol.Name)}</a><span>{WebUtility.HtmlEncode(DescribeLocation(projectRoot, symbol))}</span></li>");
                index++;
            }

            grouped.Add($"""
<section>
  <h2>{WebUtility.HtmlEncode(kind.ToString())}</h2>
  <ul class="symbol-list">
    {string.Join(Environment.NewLine + "    ", items)}
  </ul>
</section>
""");
        }

        return WrapHtml(
            title: "N# API Docs",
            body: $"""
<header>
  <p class="eyebrow">N# API Reference</p>
  <h1>{WebUtility.HtmlEncode(Path.GetFileName(projectRoot))}</h1>
  <p>{symbols.Count} documented symbols</p>
</header>
{string.Join(Environment.NewLine, grouped)}
""");
    }

    private static string RenderSymbolPage(SymbolResult symbol, string projectRoot)
    {
        var members = OrderMembersForGeneration(symbol.Members)
            .Select(member => $"<li><code>{WebUtility.HtmlEncode(FormatSignature(member))}</code></li>")
            .ToArray();

        var parameters = symbol.Parameters?.Length > 0
            ? $"<p><strong>Parameters:</strong> {WebUtility.HtmlEncode(string.Join(", ", symbol.Parameters.Select(FormatParameter)))}</p>"
            : string.Empty;

        var membersSection = members.Length > 0
            ? $"""
<section>
  <h2>Members</h2>
  <ul class="member-list">
    {string.Join(Environment.NewLine + "    ", members)}
  </ul>
</section>
"""
            : string.Empty;

        return WrapHtml(
            title: $"N# API Docs - {symbol.Name}",
            body: $"""
<nav><a href="../index.html">Back to index</a></nav>
<header>
  <p class="eyebrow">{WebUtility.HtmlEncode(symbol.Kind.ToString())}</p>
  <h1>{WebUtility.HtmlEncode(symbol.Name)}</h1>
  <p><code>{WebUtility.HtmlEncode(FormatSignature(symbol))}</code></p>
  <p>{WebUtility.HtmlEncode(DescribeLocation(projectRoot, symbol))}</p>
  {parameters}
</header>
{membersSection}
""");
    }

    private static List<SymbolResult> OrderMembersForGeneration(SymbolResult[]? members)
    {
        if (members == null || members.Length == 0)
            return new List<SymbolResult>();

        if (DocCommandKernels.TryOrderMembersForGeneration(members, out var orderedMembers))
            return orderedMembers;

        return members
            .OrderBy(member => member.Kind.ToString(), StringComparer.Ordinal)
            .ThenBy(member => member.Name, StringComparer.Ordinal)
            .ToList();
    }

    private static string WrapHtml(string title, string body) => $$$"""
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{{{WebUtility.HtmlEncode(title)}}}</title>
  <style>
    :root {{
      color-scheme: light;
      --bg: #f6f3ee;
      --card: #fffdf8;
      --ink: #1f1b18;
      --muted: #5d534b;
      --line: #d9cfc5;
      --accent: #a6401b;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: Georgia, "Iowan Old Style", "Palatino Linotype", serif;
      background:
        radial-gradient(circle at top left, rgba(166, 64, 27, 0.08), transparent 35%),
        linear-gradient(180deg, #fbf9f4 0%, var(--bg) 100%);
      color: var(--ink);
    }}
    main {{
      max-width: 960px;
      margin: 0 auto;
      padding: 48px 24px 80px;
    }}
    header, nav, section {{
      background: var(--card);
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 24px;
      margin-bottom: 20px;
      box-shadow: 0 10px 40px rgba(39, 28, 20, 0.05);
    }}
    h1, h2 {{ margin: 0 0 12px; }}
    .eyebrow {{
      text-transform: uppercase;
      letter-spacing: 0.12em;
      font-size: 0.78rem;
      color: var(--accent);
      margin: 0 0 8px;
    }}
    code {{
      font-family: "SF Mono", "JetBrains Mono", Consolas, monospace;
      font-size: 0.95rem;
    }}
    ul {{
      margin: 0;
      padding-left: 20px;
    }}
    li {{
      margin: 8px 0;
    }}
    li span {{
      color: var(--muted);
      margin-left: 12px;
    }}
    a {{
      color: var(--accent);
      text-decoration: none;
    }}
    a:hover {{
      text-decoration: underline;
    }}
  </style>
</head>
<body>
  <main>
    {{{body}}}
  </main>
</body>
</html>
""";

    private static string DescribeLocation(string projectRoot, SymbolResult symbol)
        => $"{NormalizePath(Path.GetRelativePath(projectRoot, symbol.File))}:{symbol.Line}:{symbol.Column}";

    private static string FormatSignature(SymbolResult symbol)
    {
        var prefix = symbol.Kind switch
        {
            SymbolKind.Function => "func ",
            SymbolKind.Method => "func ",
            SymbolKind.Constructor => "ctor ",
            SymbolKind.Class => "class ",
            SymbolKind.Struct => "struct ",
            SymbolKind.Record => "record ",
            SymbolKind.Interface => "interface ",
            SymbolKind.Enum => "enum ",
            SymbolKind.Union => "union ",
            SymbolKind.Property => "prop ",
            SymbolKind.Field => "field ",
            SymbolKind.TypeAlias => "type ",
            SymbolKind.Test => "test ",
            _ => string.Empty
        };

        var parameters = symbol.Parameters == null
            ? string.Empty
            : $"({string.Join(", ", symbol.Parameters.Select(FormatParameter))})";

        var suffix = string.IsNullOrWhiteSpace(symbol.TypeName) ? string.Empty : $": {symbol.TypeName}";
        return $"{prefix}{symbol.Name}{parameters}{suffix}";
    }

    private static string FormatParameter(ParameterResult parameter)
        => parameter.HasDefault
            ? $"{parameter.Name}: {parameter.Type} = {parameter.DefaultValue}"
            : $"{parameter.Name}: {parameter.Type}";

    private static string[] CreateSlugs(IReadOnlyList<SymbolResult> symbols)
    {
        var rawSlugs = new string[symbols.Count];
        for (var i = 0; i < symbols.Count; i++)
            rawSlugs[i] = CreateRawSlug(symbols[i]);

        if (DocCommandKernels.TryCreateSlugs(rawSlugs, out var dogfoodSlugs))
            return dogfoodSlugs;

        var slugs = new string[rawSlugs.Length];
        for (var i = 0; i < rawSlugs.Length; i++)
            slugs[i] = ToSlugWithLinq(rawSlugs[i]);

        return slugs;
    }

    private static string CreateRawSlug(SymbolResult symbol)
        => $"{symbol.Kind}-{symbol.Name}-{Path.GetFileNameWithoutExtension(symbol.File)}";

    private static string ToSlugWithLinq(string raw)
    {
        var chars = raw
            .ToLowerInvariant()
            .Select(ch => char.IsLetterOrDigit(ch) ? ch : '-')
            .ToArray();
        return string.Join(string.Empty, new string(chars).Split('-', StringSplitOptions.RemoveEmptyEntries));
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');
}

internal record DocManifest(
    string IndexPath,
    int PageCount,
    IReadOnlyList<DocPage> Pages);

internal record DocPage(
    string Name,
    string Kind,
    string Path);
