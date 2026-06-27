namespace NSharpLang.Compiler.CodeIntelligence

import System

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
}
