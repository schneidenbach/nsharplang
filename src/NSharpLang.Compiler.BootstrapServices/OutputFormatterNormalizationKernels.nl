namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler.Performance

public class OutputFormatterNormalizationKernels {
    public static func NormalizePath(path: string?): string? {
        if path == null {
            return null
        }

        value := path ?? ""
        return value.Replace('\\', '/')
    }

    public static func NormalizeSymbol(result: SymbolResult): SymbolResult {
        return result
    }

    public static func NormalizeOutline(result: OutlineResult): OutlineResult {
        return result
    }

    public static func NormalizeOutlineEntry(entry: OutlineEntry): OutlineEntry {
        return entry
    }

    public static func NormalizeDiagnostic(result: DiagnosticResult): DiagnosticResult {
        return result
    }

    public static func NormalizeType(result: TypeResult): TypeResult {
        return result
    }

    public static func NormalizeDefinition(result: DefinitionResult): DefinitionResult {
        return result
    }

    public static func NormalizeReference(result: ReferenceResult): ReferenceResult {
        return result
    }

    public static func NormalizeLocation(result: LocationResult): LocationResult {
        return result
    }

    public static func NormalizeInspectSymbol(result: InspectSymbolResult): InspectSymbolResult {
        return result
    }

    public static func NormalizeInspectReferences(result: InspectReferencesResult): InspectReferencesResult {
        return result
    }

    public static func NormalizeInspect(result: InspectResult): InspectResult {
        return result
    }

    public static func NormalizeInspectReferenceSummary(result: InspectReferenceSummaryResult): InspectReferenceSummaryResult {
        return result
    }

    public static func NormalizeInspectSummaryReferences(result: InspectSummaryReferencesResult): InspectSummaryReferencesResult {
        return result
    }

    public static func NormalizeInspectSummary(result: InspectSummaryResult): InspectSummaryResult {
        return result
    }

    public static func NormalizePerfReportSite(site: PerfReportSite): PerfReportSite {
        normalizedFile := NormalizePath(site.File)
        if normalizedFile == null {
            normalizedFile = site.File
        }

        return new PerfReportSite(
            site.Code,
            site.Effect,
            normalizedFile,
            site.Line,
            site.Column,
            site.Message,
            site.Function,
            site.Suggestion)
    }

    public static func NormalizePerfReportSiteJson(site: PerfReportSite): PerfReportSiteJson {
        normalizedFile := NormalizePath(site.File)
        if normalizedFile == null {
            normalizedFile = site.File
        }

        return new PerfReportSiteJson(
            site.Code,
            site.Effect,
            normalizedFile,
            site.Line,
            site.Column,
            site.Message,
            site.Function,
            site.Suggestion)
    }

    public static func NormalizePerfReportSites(sites: IReadOnlyList<PerfReportSite>): PerfReportSiteJson[] {
        result := new List<PerfReportSiteJson>()
        foreach site in sites {
            result.Add(NormalizePerfReportSiteJson(site))
        }

        return result.ToArray()
    }

    public static func NormalizePerfReportTrustedSite(site: PerfReportTrustedSite): PerfReportTrustedSite {
        normalizedFile := NormalizePath(site.File)
        if normalizedFile == null {
            normalizedFile = site.File
        }

        return new PerfReportTrustedSite(
            site.Function,
            normalizedFile,
            site.Line,
            site.Column,
            site.Owner,
            site.Review,
            site.Expires,
            site.HasUnsafe,
            site.BodyStatementCount)
    }

    public static func NormalizePerfReportTrustedSiteJson(site: PerfReportTrustedSite): PerfReportTrustedSiteJson {
        normalizedFile := NormalizePath(site.File)
        if normalizedFile == null {
            normalizedFile = site.File
        }

        return new PerfReportTrustedSiteJson(
            site.Function,
            normalizedFile,
            site.Line,
            site.Column,
            site.Owner,
            site.Review,
            site.Expires,
            site.HasUnsafe,
            site.BodyStatementCount)
    }

    public static func NormalizePerfReportTrustedSites(sites: IReadOnlyList<PerfReportTrustedSite>): PerfReportTrustedSiteJson[] {
        result := new List<PerfReportTrustedSiteJson>()
        foreach site in sites {
            result.Add(NormalizePerfReportTrustedSiteJson(site))
        }

        return result.ToArray()
    }

    public static func NormalizeSystemsFunctionSummary(function: SystemsFunctionSummary): SystemsFunctionSummaryJson {
        normalizedFile := NormalizePath(function.File)
        if normalizedFile == null {
            normalizedFile = function.File
        }

        return new SystemsFunctionSummaryJson(
            function.Name,
            normalizedFile,
            function.Line,
            function.Column,
            function.IsHot,
            function.IsBoundary,
            function.AllocNone,
            function.SummarySource,
            NormalizeSystemsEffectFacts(function.Effects),
            function.Calls)
    }

    public static func NormalizeSystemsFunctionSummaries(functions: IReadOnlyList<SystemsFunctionSummary>): SystemsFunctionSummaryJson[] {
        result := new List<SystemsFunctionSummaryJson>()
        foreach function in functions {
            result.Add(NormalizeSystemsFunctionSummary(function))
        }

        return result.ToArray()
    }

    public static func NormalizeSystemsFinding(finding: SystemsFinding): SystemsFindingJson {
        normalizedFile := NormalizePath(finding.File)
        if normalizedFile == null {
            normalizedFile = finding.File
        }

        return new SystemsFindingJson(
            finding.Code,
            finding.Severity,
            finding.Effect,
            finding.Message,
            normalizedFile,
            finding.Line,
            finding.Column,
            finding.Length,
            finding.Function,
            finding.Policy,
            finding.SummarySource,
            finding.Suggestion,
            finding.CallPath)
    }

    public static func NormalizeSystemsFindings(findings: IReadOnlyList<SystemsFinding>): SystemsFindingJson[] {
        result := new List<SystemsFindingJson>()
        foreach finding in findings {
            result.Add(NormalizeSystemsFinding(finding))
        }

        return result.ToArray()
    }

    public static func NormalizeSystemsTrustedSite(site: SystemsTrustedSite): SystemsTrustedSiteJson {
        normalizedFile := NormalizePath(site.File)
        if normalizedFile == null {
            normalizedFile = site.File
        }

        return new SystemsTrustedSiteJson(
            site.Function,
            normalizedFile,
            site.Line,
            site.Column,
            site.Reason,
            site.Owner,
            site.Review,
            site.Expires,
            site.HasUnsafe,
            site.BodyStatementCount)
    }

    public static func NormalizeSystemsTrustedSites(sites: IReadOnlyList<SystemsTrustedSite>): SystemsTrustedSiteJson[] {
        result := new List<SystemsTrustedSiteJson>()
        foreach site in sites {
            result.Add(NormalizeSystemsTrustedSite(site))
        }

        return result.ToArray()
    }

    public static func NormalizeSystemsAotReport(aot: SystemsAotReport): SystemsAotReportJson {
        return new SystemsAotReportJson(
            aot.Target,
            aot.Analysis,
            aot.NativeImageEmitted,
            aot.TrimSafe)
    }

    public static func NormalizeSystemsEffectFacts(effects: SystemsEffectFacts): SystemsEffectFactsJson {
        return new SystemsEffectFactsJson(
            effects.Allocates,
            effects.Boxes,
            effects.ConstructsDelegate,
            effects.CapturesClosure,
            effects.UsesRuntimeDispatch,
            effects.UsesReflection,
            effects.UsesDynamicCode,
            effects.Throws,
            effects.HasImplicitTrapObligation,
            effects.UsesUnknownExternalCall,
            effects.UsesResource,
            effects.UsesPool,
            effects.UsesConcurrencyPrimitive,
            effects.RequiresWarmup,
            effects.AotSafe)
    }

    public static func NormalizeSystemsReportSummary(summary: SystemsReportSummary): SystemsReportSummaryJson {
        return new SystemsReportSummaryJson(
            summary.Functions,
            summary.HotFunctions,
            summary.BoundaryFunctions,
            summary.Findings,
            summary.Errors,
            summary.Warnings,
            summary.TrustedSites)
    }

    public static func NormalizeSystemsReport(report: SystemsReport): SystemsReportJsonPayload {
        return new SystemsReportJsonPayload(
            report.SchemaVersion,
            report.Profile,
            report.Mode,
            report.AotTarget,
            NormalizeSystemsAotReport(report.Aot),
            report.Warmup,
            NormalizeSystemsFunctionSummaries(report.Functions),
            NormalizeSystemsFindings(report.Findings),
            NormalizeSystemsTrustedSites(report.TrustedSites),
            NormalizeSystemsReportSummary(report.Summary))
    }
}
