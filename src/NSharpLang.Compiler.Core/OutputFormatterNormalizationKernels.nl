namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler.Performance

class OutputFormatterNormalizationKernels {
    static func NormalizePath(path: string?): string? {
        if path == null {
            return null
        }

        value := path ?? ""
        return value.Replace('\\', '/')
    }

    static func NormalizeSymbol(result: SymbolResult): SymbolResult {
        return result
    }

    static func NormalizeOutline(result: OutlineResult): OutlineResult {
        return result
    }

    static func NormalizeOutlineEntry(entry: OutlineEntry): OutlineEntry {
        return entry
    }

    static func NormalizeDiagnostic(result: DiagnosticResult): DiagnosticResult {
        return result
    }

    static func NormalizeType(result: TypeResult): TypeResult {
        return result
    }

    static func NormalizeDefinition(result: DefinitionResult): DefinitionResult {
        return result
    }

    static func NormalizeReference(result: ReferenceResult): ReferenceResult {
        return result
    }

    static func NormalizeLocation(result: LocationResult): LocationResult {
        return result
    }

    static func NormalizeInspectSymbol(result: InspectSymbolResult): InspectSymbolResult {
        return result
    }

    static func NormalizeInspectReferences(result: InspectReferencesResult): InspectReferencesResult {
        return result
    }

    static func NormalizeInspect(result: InspectResult): InspectResult {
        return result
    }

    static func NormalizeInspectReferenceSummary(result: InspectReferenceSummaryResult): InspectReferenceSummaryResult {
        return result
    }

    static func NormalizeInspectSummaryReferences(result: InspectSummaryReferencesResult): InspectSummaryReferencesResult {
        return result
    }

    static func NormalizeInspectSummary(result: InspectSummaryResult): InspectSummaryResult {
        return result
    }

    static func NormalizePerfReportSite(site: PerfReportSite): PerfReportSite {
        normalizedFile := NormalizePath(site.File)
        if normalizedFile == null {
            normalizedFile = site.File
        }

        return new PerfReportSite(site.Code, site.Effect, normalizedFile, site.Line, site.Column, site.Message, site.Function, site.Suggestion)
    }

    static func NormalizePerfReportSiteJson(site: PerfReportSite): PerfReportSiteJson {
        normalizedFile := NormalizePath(site.File)
        if normalizedFile == null {
            normalizedFile = site.File
        }

        return new PerfReportSiteJson(site.Code, site.Effect, normalizedFile, site.Line, site.Column, site.Message, site.Function, site.Suggestion)
    }

    static func NormalizePerfReportSites(sites: IReadOnlyList<PerfReportSite>): PerfReportSiteJson[] {
        result := new List<PerfReportSiteJson>()
        for site in sites {
            result.Add(NormalizePerfReportSiteJson(site))
        }

        return result.ToArray()
    }

    static func NormalizePerfReportTrustedSite(site: PerfReportTrustedSite): PerfReportTrustedSite {
        normalizedFile := NormalizePath(site.File)
        if normalizedFile == null {
            normalizedFile = site.File
        }

        return new PerfReportTrustedSite(site.Function, normalizedFile, site.Line, site.Column, site.Owner, site.Review, site.Expires, site.HasUnsafe, site.BodyStatementCount)
    }

    static func NormalizePerfReportTrustedSiteJson(site: PerfReportTrustedSite): PerfReportTrustedSiteJson {
        normalizedFile := NormalizePath(site.File)
        if normalizedFile == null {
            normalizedFile = site.File
        }

        return new PerfReportTrustedSiteJson(site.Function, normalizedFile, site.Line, site.Column, site.Owner, site.Review, site.Expires, site.HasUnsafe, site.BodyStatementCount)
    }

    static func NormalizePerfReportTrustedSites(sites: IReadOnlyList<PerfReportTrustedSite>): PerfReportTrustedSiteJson[] {
        result := new List<PerfReportTrustedSiteJson>()
        for site in sites {
            result.Add(NormalizePerfReportTrustedSiteJson(site))
        }

        return result.ToArray()
    }

    static func NormalizeSystemsFunctionSummary(function: SystemsFunctionSummary): SystemsFunctionSummaryJson {
        normalizedFile := NormalizePath(function.File)
        if normalizedFile == null {
            normalizedFile = function.File
        }

        return new SystemsFunctionSummaryJson(function.Name, normalizedFile, function.Line, function.Column, function.IsHot, function.IsBoundary, function.AllocNone, function.SummarySource, NormalizeSystemsEffectFacts(function.Effects), function.Calls)
    }

    static func NormalizeSystemsFunctionSummaries(functions: IReadOnlyList<SystemsFunctionSummary>): SystemsFunctionSummaryJson[] {
        result := new List<SystemsFunctionSummaryJson>()
        for function in functions {
            result.Add(NormalizeSystemsFunctionSummary(function))
        }

        return result.ToArray()
    }

    static func NormalizeSystemsFinding(finding: SystemsFinding): SystemsFindingJson {
        normalizedFile := NormalizePath(finding.File)
        if normalizedFile == null {
            normalizedFile = finding.File
        }

        return new SystemsFindingJson(finding.Code, finding.Severity, finding.Effect, finding.Message, normalizedFile, finding.Line, finding.Column, finding.Length, finding.Function, finding.Policy, finding.SummarySource, finding.Suggestion, finding.CallPath)
    }

    static func NormalizeSystemsFindings(findings: IReadOnlyList<SystemsFinding>): SystemsFindingJson[] {
        result := new List<SystemsFindingJson>()
        for finding in findings {
            result.Add(NormalizeSystemsFinding(finding))
        }

        return result.ToArray()
    }

    static func NormalizeSystemsTrustedSite(site: SystemsTrustedSite): SystemsTrustedSiteJson {
        normalizedFile := NormalizePath(site.File)
        if normalizedFile == null {
            normalizedFile = site.File
        }

        return new SystemsTrustedSiteJson(site.Function, normalizedFile, site.Line, site.Column, site.Reason, site.Owner, site.Review, site.Expires, site.HasUnsafe, site.BodyStatementCount)
    }

    static func NormalizeSystemsTrustedSites(sites: IReadOnlyList<SystemsTrustedSite>): SystemsTrustedSiteJson[] {
        result := new List<SystemsTrustedSiteJson>()
        for site in sites {
            result.Add(NormalizeSystemsTrustedSite(site))
        }

        return result.ToArray()
    }

    static func NormalizeSystemsAotReport(aot: SystemsAotReport): SystemsAotReportJson {
        return new SystemsAotReportJson(aot.Target, aot.Analysis, aot.NativeImageEmitted, aot.TrimSafe)
    }

    static func NormalizeSystemsEffectFacts(effects: SystemsEffectFacts): SystemsEffectFactsJson {
        return new SystemsEffectFactsJson(effects.Allocates, effects.Boxes, effects.ConstructsDelegate, effects.CapturesClosure, effects.UsesRuntimeDispatch, effects.UsesReflection, effects.UsesDynamicCode, effects.Throws, effects.HasImplicitTrapObligation, effects.UsesUnknownExternalCall, effects.UsesResource, effects.UsesPool, effects.UsesConcurrencyPrimitive, effects.RequiresWarmup, effects.AotSafe)
    }

    static func NormalizeSystemsReportSummary(summary: SystemsReportSummary): SystemsReportSummaryJson {
        return new SystemsReportSummaryJson(summary.Functions, summary.HotFunctions, summary.BoundaryFunctions, summary.Findings, summary.Errors, summary.Warnings, summary.TrustedSites)
    }

    static func NormalizeSystemsReport(report: SystemsReport): SystemsReportJsonPayload {
        return new SystemsReportJsonPayload(report.SchemaVersion, report.Profile, report.Mode, report.AotTarget, NormalizeSystemsAotReport(report.Aot), report.Warmup, NormalizeSystemsFunctionSummaries(report.Functions), NormalizeSystemsFindings(report.Findings), NormalizeSystemsTrustedSites(report.TrustedSites), NormalizeSystemsReportSummary(report.Summary))
    }
}
