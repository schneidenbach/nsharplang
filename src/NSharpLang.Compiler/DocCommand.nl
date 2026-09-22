namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence

// The doc command owns the complete load -> symbols -> render -> write route. Every page's TEXT is
// rendered by DocCommandKernels, so the generator below only decides where bytes land: the command
// never composes markup of its own, and the JSON manifest and the human summary read the same
// DocManifest the write produced.
class DocCommand {
    static func Execute(args: string[]): int {
        options := DocCommandKernels.GetOptionSummary(args)
        if options.ShowHelp {
            Console.WriteLine(DocCommandKernels.GetHelpText())
            return 0
        }

        outputMode := CommandOutputKernels.GetOutputMode(options.Json)
        openAfterGenerate := options.Open
        projectRoot := CommandOutputKernels.GetProjectRoot(options.ProjectOption, Directory.GetCurrentDirectory())
        outputDir := DocCommandKernels.GetOutputDirectory(projectRoot, options.OutputOption)

        if !Directory.Exists(projectRoot) {
            return EmitError(outputMode, projectRoot, CommandOutputKernels.GetProjectDirectoryNotFoundMessage(projectRoot))
        }

        try {
            service := new CodeIntelligenceService()
            snapshot := service.LoadProject(projectRoot)
            symbols := service.GetSymbols(snapshot, null, null)

            manifest := Generate(projectRoot, outputDir, symbols)

            openError: string? = null
            if openAfterGenerate && !TryOpen(manifest.IndexPath, out openError) {
                return EmitError(outputMode, projectRoot, openError ?? DocCommandKernels.GetOpenFailedMessage(manifest.IndexPath))
            }

            if outputMode == 1 {
                Console.Write(DocCommandKernels.ResultJson(projectRoot, outputDir, manifest))
            } else {
                Console.WriteLine(DocCommandKernels.GetGeneratedSummaryMessage(manifest.PageCount))
                Console.WriteLine(DocCommandKernels.GetOutputPathMessage(outputDir))
                Console.WriteLine(DocCommandKernels.GetIndexPathMessage(manifest.IndexPath))
                if openAfterGenerate {
                    Console.WriteLine(DocCommandKernels.GetOpenedMessage())
                }
            }

            return 0
        } catch ex: Exception {
            return EmitError(outputMode, projectRoot, DocCommandKernels.GetGenerationFailedMessage(ex.Message))
        }
    }

    // The whole write: one page per symbol under the symbol directory, then the index that links
    // them. Slugs are assigned for the WHOLE ordered set at once, because two symbols whose names
    // slug identically have to be disambiguated against each other rather than one at a time.
    private static func Generate(projectRoot: string, outputDir: string, symbols: IReadOnlyList<SymbolResult>): DocManifest {
        orderedSymbols := DocCommandKernels.OrderSymbolsForGeneration(symbols)

        if Directory.Exists(outputDir) {
            Directory.Delete(outputDir, true)
        }

        Directory.CreateDirectory(outputDir)
        Directory.CreateDirectory(DocCommandKernels.GetSymbolDirectory(outputDir))

        rawSlugs := new string[](orderedSymbols.Count)
        for i := 0; i < orderedSymbols.Count; i++ {
            rawSlugs[i] = DocCommandKernels.GetRawSlug(orderedSymbols[i])
        }

        slugs := DocCommandKernels.CreateSlugs(rawSlugs)
        pages := new List<DocPage>()
        for i := 0; i < orderedSymbols.Count; i++ {
            symbol := orderedSymbols[i]
            relativePath := DocCommandKernels.GetSymbolRelativePath(slugs[i])
            File.WriteAllText(
                DocCommandKernels.GetSymbolAbsolutePath(outputDir, relativePath),
                DocCommandKernels.RenderSymbolPage(symbol, projectRoot)
            )
            pages.Add(new DocPage(symbol.Name, DocCommandKernels.GetPageKindText(symbol.Kind), relativePath))
        }

        indexPath := DocCommandKernels.GetIndexPath(outputDir)
        File.WriteAllText(indexPath, DocCommandKernels.RenderIndexPage(orderedSymbols, pages, projectRoot))

        return new DocManifest(DocCommandKernels.GetManifestIndexPath(indexPath), pages.Count, pages)
    }

    private static func EmitError(outputMode: int, projectRoot: string, message: string): int {
        if outputMode == 1 {
            Console.Write(DocCommandKernels.ErrorJson(projectRoot, message))
        } else {
            Console.Error.WriteLine(message)
        }

        return 1
    }

    private static func TryOpen(path: string, out error: string?): bool {
        error = null
        command := DocCommandKernels.GetOpenCommand(path, OperatingSystem.IsMacOS(), OperatingSystem.IsWindows())

        try {
            result := DotnetRunner.RunProcess(command.FileName, command.Arguments)
            if result.ExitCode == 0 {
                return true
            }

            error = DocCommandKernels.GetOpenFailedMessage(path)
            return false
        } catch ex: Exception {
            error = DocCommandKernels.GetOpenFailedWithDetailMessage(path, ex.Message)
            return false
        }
    }
}
