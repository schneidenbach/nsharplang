namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler.Performance

// Public formatting entry points. Versioned JSON and human-readable text are owned by Core.
static class OutputFormatter {
    static func SummarizeDiagnostics(results: IReadOnlyList<DiagnosticResult>): DiagnosticSummary {
        return OutputFormatterDiagnosticKernels.SummarizeDiagnosticSeverities(results)
    }

    static func FilterDiagnosticsBySeverity(diagnostics: IReadOnlyList<DiagnosticResult>, severity: string): List<DiagnosticResult> {
        return OutputFormatterDiagnosticKernels.FilterDiagnosticSeverityResults(diagnostics, severity)
    }

    static func DeduplicateAndSortDiagnostics(diagnostics: IReadOnlyList<DiagnosticResult>): List<DiagnosticResult> {
        return CodeIntelligenceResultKernels.DeduplicateDiagnosticResults(diagnostics)
    }

    static func SymbolsToJson(results: List<SymbolResult>, projectRoot: string? = null): string {
        if projectRoot == null {
            return OutputFormatterJsonKernels.SymbolsToJson(results, null)
        }
        return OutputFormatterJsonKernels.SymbolsToJson(results, projectRoot)
    }

    static func OutlineToJson(result: OutlineResult): string {
        return OutputFormatterJsonKernels.OutlineToJson(result)
    }

    static func DiagnosticsToJson(results: List<DiagnosticResult>, projectRoot: string? = null): string {
        if projectRoot == null {
            return OutputFormatterJsonKernels.DiagnosticsToJson(results, null)
        }
        return OutputFormatterJsonKernels.DiagnosticsToJson(results, projectRoot)
    }

    static func DiagnosticClustersToJson(results: List<DiagnosticResult>, projectRoot: string? = null): string {
        if projectRoot == null {
            return OutputFormatterJsonKernels.DiagnosticClustersToJson(results, null)
        }
        return OutputFormatterJsonKernels.DiagnosticClustersToJson(results, projectRoot)
    }

    static func CheckToJson(results: List<DiagnosticResult>, projectRoot: string?, checkedFiles: int): string {
        if projectRoot == null {
            return OutputFormatterJsonKernels.CheckToJson(results, null, checkedFiles)
        }
        return OutputFormatterJsonKernels.CheckToJson(results, projectRoot, checkedFiles)
    }

    static func LintToJson(results: List<DiagnosticResult>, projectRoot: string?, lintedFiles: int): string {
        if projectRoot == null {
            return OutputFormatterJsonKernels.LintToJson(results, null, lintedFiles)
        }
        return OutputFormatterJsonKernels.LintToJson(results, projectRoot, lintedFiles)
    }

    static func TypeToJson(result: TypeResult, fileName: string, line: int, col: int): string {
        return OutputFormatterJsonKernels.TypeToJson(result, fileName, line, col)
    }

    static func BuildPerfReportToJson(
        projectRoot: string?,
        ok: bool = true,
        allocationSites: IReadOnlyList<PerfReportSite>? = null,
        delegateSites: IReadOnlyList<PerfReportSite>? = null,
        boxingSites: IReadOnlyList<PerfReportSite>? = null,
        dispatchSites: IReadOnlyList<PerfReportSite>? = null,
        closureCaptures: IReadOnlyList<PerfReportSite>? = null,
        poolSites: IReadOnlyList<PerfReportSite>? = null,
        resourceSites: IReadOnlyList<PerfReportSite>? = null,
        boundaryLeakSites: IReadOnlyList<PerfReportSite>? = null,
        hotReadinessSites: IReadOnlyList<PerfReportSite>? = null,
        implicitTrapSites: IReadOnlyList<PerfReportSite>? = null,
        trustedSites: IReadOnlyList<PerfReportTrustedSite>? = null
    ): string {
        return BuildPerfReportWithDispatchFirst(
            dispatchSites,
            projectRoot,
            ok,
            allocationSites,
            delegateSites,
            boxingSites,
            closureCaptures,
            poolSites,
            resourceSites,
            boundaryLeakSites,
            hotReadinessSites,
            implicitTrapSites,
            trustedSites
        )
    }

    static func CheckSystemsReportToJson(diagnostics: List<DiagnosticResult>, projectRoot: string?, checkedFiles: int, report: SystemsReport): string {
        if projectRoot == null {
            return OutputFormatterJsonKernels.CheckSystemsReportToJson(diagnostics, null, checkedFiles, report)
        }
        return OutputFormatterJsonKernels.CheckSystemsReportToJson(diagnostics, projectRoot, checkedFiles, report)
    }

    static func TrustedToJson(report: SystemsReport, projectRoot: string?): string {
        return OutputFormatterJsonKernels.TrustedToJson(report, projectRoot)
    }

    static func PerfToJson(fileName: string, line: int, col: int, projectRoot: string?, facts: IReadOnlyList<object>? = null): string {
        return PerfToJsonWithFactsFirst(facts, fileName, line, col, projectRoot)
    }

    static func DefinitionToJson(result: DefinitionResult): string {
        return OutputFormatterJsonKernels.DefinitionToJson(result)
    }

    static func DefinitionSearchToJson(query: string, results: IReadOnlyList<DefinitionResult>): string {
        return OutputFormatterJsonKernels.DefinitionSearchToJson(query, results)
    }

    static func ReferencesToJson(symbolName: string, symbolKind: string, definedAt: LocationResult?, results: List<ReferenceResult>): string {
        if definedAt == null {
            return OutputFormatterJsonKernels.ReferencesToJson(symbolName, symbolKind, null, results)
        }
        return OutputFormatterJsonKernels.ReferencesToJson(symbolName, symbolKind, definedAt, results)
    }

    static func CompletionsToJson(result: CompletionResult, fileName: string, line: int, col: int): string {
        return OutputFormatterJsonKernels.CompletionsToJson(result, fileName, line, col)
    }

    static func InspectToJson(result: InspectResult, fileName: string, line: int, col: int): string {
        return OutputFormatterJsonKernels.InspectToJson(result, fileName, line, col)
    }

    static func InspectSummaryToJson(result: InspectResult, fileName: string, line: int, col: int): string {
        return OutputFormatterJsonKernels.InspectSummaryToJson(result, fileName, line, col)
    }

    static func CompletionsToText(result: CompletionResult, fileName: string, line: int, col: int): string {
        return OutputFormatterTextBuilders.CompletionsToText(result, fileName, line, col)
    }

    static func InspectToText(result: InspectResult, fileName: string, line: int, col: int): string {
        return OutputFormatterTextBuilders.InspectToText(result, fileName, line, col)
    }

    static func DocToJson(result: DocResult, query: string): string {
        return OutputFormatterJsonKernels.DocToJson(result, query)
    }

    static func HoverToJson(result: HoverResult, fileName: string, line: int, col: int): string {
        return OutputFormatterJsonKernels.HoverToJson(result, fileName, line, col)
    }

    static func HoverToText(result: HoverResult, fileName: string, line: int, col: int): string {
        return OutputFormatterTextBuilders.HoverToText(result, fileName, line, col)
    }

    static func CallGraphToJson(result: CallGraphResult): string {
        return OutputFormatterJsonKernels.CallGraphToJson(result)
    }

    static func CallGraphToText(result: CallGraphResult): string {
        return OutputFormatterTextBuilders.CallGraphToText(result)
    }

    static func ImplementorsToJson(result: ImplementorsResult): string {
        return OutputFormatterJsonKernels.ImplementorsToJson(result)
    }

    static func ImplementorsToText(result: ImplementorsResult): string {
        return OutputFormatterTextBuilders.ImplementorsToText(result)
    }

    static func ErrorToJson(command: string, error: string, projectRoot: string? = null, errorCode: string? = null, details: object? = null): string {
        return OutputFormatterJsonKernels.ErrorToJson(command, error, projectRoot, errorCode, details)
    }

    static func DiagnosticsToText(results: List<DiagnosticResult>): string {
        return OutputFormatterTextBuilders.DiagnosticsToText(results)
    }

    static func SymbolsToText(results: List<SymbolResult>): string {
        return OutputFormatterTextBuilders.SymbolsToText(results)
    }

    static func OutlineToText(result: OutlineResult): string {
        return OutputFormatterTextBuilders.OutlineToText(result)
    }

    static func TypeToText(result: TypeResult, fileName: string, line: int, col: int): string {
        return OutputFormatterTextBuilders.TypeToText(result, fileName, line, col)
    }

    static func DefinitionToText(result: DefinitionResult): string {
        return OutputFormatterTextBuilders.DefinitionToText(result)
    }

    static func DefinitionSearchToText(query: string, results: IReadOnlyList<DefinitionResult>): string {
        return OutputFormatterTextBuilders.DefinitionSearchToText(query, results)
    }

    static func ReferencesToText(symbolName: string, results: List<ReferenceResult>): string {
        return OutputFormatterTextBuilders.ReferencesToText(symbolName, results)
    }

    static func DocToText(result: DocResult): string {
        return OutputFormatterTextBuilders.DocToText(result)
    }

    private static func PerfToJsonWithFactsFirst(facts: IReadOnlyList<object>?, fileName: string, line: int, col: int, projectRoot: string?): string {
        if facts == null {
            return OutputFormatterJsonKernels.PerfToJson(fileName, line, col, projectRoot, new List<object>())
        }

        return OutputFormatterJsonKernels.PerfToJson(fileName, line, col, projectRoot, facts)
    }

    private static func BuildPerfReportWithDispatchFirst(
        dispatchSites: IReadOnlyList<PerfReportSite>?,
        projectRoot: string?,
        ok: bool,
        allocationSites: IReadOnlyList<PerfReportSite>?,
        delegateSites: IReadOnlyList<PerfReportSite>?,
        boxingSites: IReadOnlyList<PerfReportSite>?,
        closureCaptures: IReadOnlyList<PerfReportSite>?,
        poolSites: IReadOnlyList<PerfReportSite>?,
        resourceSites: IReadOnlyList<PerfReportSite>?,
        boundaryLeakSites: IReadOnlyList<PerfReportSite>?,
        hotReadinessSites: IReadOnlyList<PerfReportSite>?,
        implicitTrapSites: IReadOnlyList<PerfReportSite>?,
        trustedSites: IReadOnlyList<PerfReportTrustedSite>?
    ): string {
        allocation := NormalizePerfReportSites(allocationSites)
        delegates := NormalizePerfReportSites(delegateSites)
        boxing := NormalizePerfReportSites(boxingSites)
        dispatch := NormalizePerfReportSites(dispatchSites)
        closures := NormalizePerfReportSites(closureCaptures)
        pool := NormalizePerfReportSites(poolSites)
        resources := NormalizePerfReportSites(resourceSites)
        boundaryLeaks := NormalizePerfReportSites(boundaryLeakSites)
        hotReadiness := NormalizePerfReportSites(hotReadinessSites)
        implicitTraps := NormalizePerfReportSites(implicitTrapSites)
        trusted := NormalizePerfReportTrustedSites(trustedSites)
        return OutputFormatterJsonKernels.BuildPerfReportToJson(
            projectRoot,
            ok,
            allocation,
            delegates,
            boxing,
            dispatch,
            closures,
            pool,
            resources,
            boundaryLeaks,
            hotReadiness,
            implicitTraps,
            trusted
        )
    }

    private static func NormalizePerfReportSites(sites: IReadOnlyList<PerfReportSite>?): IReadOnlyList<PerfReportSite> {
        if sites == null {
            return new List<PerfReportSite>()
        }

        return sites
    }

    private static func NormalizePerfReportTrustedSites(sites: IReadOnlyList<PerfReportTrustedSite>?): IReadOnlyList<PerfReportTrustedSite> {
        if sites == null {
            return new List<PerfReportTrustedSite>()
        }

        return sites
    }
}
