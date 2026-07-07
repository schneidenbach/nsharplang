using System;
using System.Collections.Generic;
using System.IO;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Commands;

public static class DocCommand
{
    public static int Execute(string[] args)
    {
        var options = DocCommandKernels.GetOptionSummary(args);
        if (options.ShowHelp)
        {
            Console.WriteLine(DocCommandKernels.GetHelpText());
            return 0;
        }

        var outputMode = DocCommandKernels.GetOutputMode(options.Json);
        var openAfterGenerate = options.Open;
        var projectRoot = options.ProjectOption ?? Directory.GetCurrentDirectory();
        var outputDir = options.OutputOption ?? Path.Combine(projectRoot, "nsharp", "docs");
        projectRoot = Path.GetFullPath(projectRoot);
        outputDir = Path.GetFullPath(outputDir);

        if (!Directory.Exists(projectRoot))
            return EmitError(outputMode, projectRoot, DocCommandKernels.GetProjectDirectoryNotFoundMessage(projectRoot));

        try
        {
            var service = new CodeIntelligenceService();
            var snapshot = service.LoadProject(projectRoot);
            var symbols = service.GetSymbols(snapshot);

            var manifest = ProjectDocGenerator.Generate(projectRoot, outputDir, symbols);

            if (openAfterGenerate && !TryOpen(manifest.IndexPath, out var openError))
                return EmitError(outputMode, projectRoot, openError!);

            if (outputMode == 1)
            {
                Console.Write(DocCommandKernels.ResultJson(projectRoot, outputDir, manifest));
            }
            else
            {
                Console.WriteLine(DocCommandKernels.GetGeneratedSummaryMessage(manifest.PageCount));
                Console.WriteLine(DocCommandKernels.GetOutputPathMessage(outputDir));
                Console.WriteLine(DocCommandKernels.GetIndexPathMessage(manifest.IndexPath));
                if (openAfterGenerate)
                    Console.WriteLine(DocCommandKernels.GetOpenedMessage());
            }

            return 0;
        }
        catch (Exception ex)
        {
            return EmitError(outputMode, projectRoot, DocCommandKernels.GetGenerationFailedMessage(ex.Message));
        }
    }

    private static int EmitError(int outputMode, string projectRoot, string message)
    {
        if (outputMode == 1)
        {
            Console.Write(DocCommandKernels.ErrorJson(projectRoot, message));
        }
        else
        {
            Console.Error.WriteLine(message);
        }

        return 1;
    }

    private static bool TryOpen(string path, out string? error)
    {
        error = null;
        var command = DocCommandKernels.GetOpenCommand(path, OperatingSystem.IsMacOS(), OperatingSystem.IsWindows());

        try
        {
            var result = DotnetRunner.RunProcess(command.FileName, command.Arguments);
            if (result.ExitCode == 0)
                return true;

            error = DocCommandKernels.GetOpenFailedMessage(path);
            return false;
        }
        catch (Exception ex)
        {
            error = DocCommandKernels.GetOpenFailedWithDetailMessage(path, ex.Message);
            return false;
        }
    }

}

internal static class ProjectDocGenerator
{
    public static DocManifest Generate(string projectRoot, string outputDir, IReadOnlyList<SymbolResult> symbols)
    {
        var orderedSymbols = DocCommandKernels.OrderSymbolsForGeneration(symbols);

        if (Directory.Exists(outputDir))
            Directory.Delete(outputDir, recursive: true);

        Directory.CreateDirectory(outputDir);
        var symbolDir = Path.Combine(outputDir, "symbols");
        Directory.CreateDirectory(symbolDir);

        var pages = new List<DocPage>();
        var rawSlugs = new string[orderedSymbols.Count];
        for (var i = 0; i < orderedSymbols.Count; i++)
        {
            var symbol = orderedSymbols[i];
            rawSlugs[i] = $"{symbol.Kind}-{symbol.Name}-{Path.GetFileNameWithoutExtension(symbol.File)}";
        }

        var slugs = DocCommandKernels.CreateSlugs(rawSlugs);

        for (var i = 0; i < orderedSymbols.Count; i++)
        {
            var symbol = orderedSymbols[i];
            var slug = slugs[i];
            var relativePath = NormalizePath(Path.Combine("symbols", $"{slug}.html"));
            var absolutePath = Path.Combine(outputDir, relativePath.Replace('/', Path.DirectorySeparatorChar));
            File.WriteAllText(absolutePath, DocCommandKernels.RenderSymbolPage(symbol, projectRoot));
            pages.Add(new DocPage(symbol.Name, DocCommandKernels.GetPageKindText(symbol.Kind), relativePath));
        }

        var indexPath = Path.Combine(outputDir, "index.html");
        File.WriteAllText(indexPath, DocCommandKernels.RenderIndexPage(orderedSymbols, pages, projectRoot));

        return new DocManifest(
            NormalizePath(indexPath),
            pages.Count,
            pages);
    }

    private static string NormalizePath(string path)
        => OutputFormatterNormalizationKernels.NormalizePath(path) ?? path;
}
