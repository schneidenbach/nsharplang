namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import System.Text.Json

class OutputFormatterJsonKernels {
    static func CreateWriteIndentedOptions(): JsonSerializerOptions {
        return new JsonSerializerOptions { WriteIndented: true }
    }

    static func TrustedToJson(report: SystemsReport, projectRoot: string?): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "trusted"
        envelope["ok"] = true

        normalizedProjectRoot := OutputFormatterNormalizationKernels.NormalizePath(projectRoot)
        if normalizedProjectRoot != null {
            envelope["projectRoot"] = normalizedProjectRoot ?? ""
        }

        trustedSites := OutputFormatterNormalizationKernels.NormalizeSystemsTrustedSites(report.TrustedSites)
        envelope["results"] = BuildTrustedResults(trustedSites)

        summary := new Dictionary<string, object>()
        summary["trustedSites"] = report.TrustedSites.Count
        envelope["summary"] = summary

        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func DefinitionToJson(result: DefinitionResult): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "definition"
        envelope["ok"] = true
        envelope["result"] = BuildDefinitionResult(result)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func DefinitionSearchToJson(query: string, results: IReadOnlyList<DefinitionResult>): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "definition"
        envelope["ok"] = results.Count > 0
        envelope["query"] = query
        envelope["results"] = BuildDefinitionResults(results)
        envelope["note"] = DefinitionSearchKernels.GetDefinitionSearchNote(results.Count)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func BuildDefinitionResult(result: DefinitionResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["name"] = result.Name
        payload["kind"] = result.Kind
        payload["file"] = result.File
        payload["line"] = result.Line
        payload["column"] = result.Column
        payload["length"] = result.Length
        return payload
    }

    static func BuildDefinitionResults(results: IReadOnlyList<DefinitionResult>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for result in results {
            payload.Add(BuildDefinitionResult(result))
        }

        return payload
    }

    static func CallGraphToJson(result: CallGraphResult): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "callGraph"
        envelope["ok"] = true

        if result.Function != null {
            envelope["function"] = result.Function ?? ""
        }

        envelope["callers"] = BuildCallSites(result.Callers)
        envelope["callees"] = BuildCallSites(result.Callees)
        envelope["truncated"] = result.Truncated
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func BuildCallSites(sites: List<CallSiteResult>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for site in sites {
            payload.Add(BuildCallSite(site))
        }

        return payload
    }

    static func BuildCallSite(site: CallSiteResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["name"] = site.Name

        if site.File != null {
            payload["file"] = OutputFormatterNormalizationKernels.NormalizePath(site.File) ?? ""
        }

        payload["line"] = site.Line
        payload["column"] = site.Column
        return payload
    }

    static func ImplementorsToJson(result: ImplementorsResult): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "implementors"
        envelope["ok"] = true
        envelope["interface"] = result.Interface
        envelope["results"] = BuildImplementorResults(result.Results)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func ErrorToJson(command: string, message: string, projectRoot: string?, errorCode: string?, details: object?): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = command
        envelope["ok"] = false

        normalizedProjectRoot := OutputFormatterNormalizationKernels.NormalizePath(projectRoot)
        if normalizedProjectRoot != null {
            envelope["projectRoot"] = normalizedProjectRoot ?? ""
        }

        errorPayload := new Dictionary<string, object>()
        if errorCode != null {
            errorPayload["code"] = errorCode ?? ""
        }

        errorPayload["message"] = message
        if details != null {
            errorPayload["details"] = details
        }

        envelope["error"] = errorPayload
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func BuildImplementorResults(results: List<ImplementorResult>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for result in results {
            payload.Add(BuildImplementorResult(result))
        }

        return payload
    }

    static func BuildImplementorResult(result: ImplementorResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["typeName"] = result.TypeName
        payload["kind"] = result.Kind

        if result.File != null {
            payload["file"] = OutputFormatterNormalizationKernels.NormalizePath(result.File) ?? ""
        }

        payload["line"] = result.Line
        payload["column"] = result.Column
        return payload
    }

    static func HoverToJson(result: HoverResult, fileName: string, line: int, col: int): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "hover"
        envelope["ok"] = true

        normalizedFile := OutputFormatterNormalizationKernels.NormalizePath(fileName)
        if normalizedFile != null {
            envelope["file"] = normalizedFile ?? ""
        }

        envelope["position"] = BuildPosition(line, col)
        envelope["result"] = BuildHoverResult(result)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func BuildPosition(line: int, col: int): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["line"] = line
        payload["column"] = col
        return payload
    }

    static func BuildHoverResult(result: HoverResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["signature"] = result.Signature

        if result.Documentation != null {
            payload["documentation"] = result.Documentation ?? ""
        }

        if result.DefinedIn != null {
            payload["definedIn"] = OutputFormatterNormalizationKernels.NormalizePath(result.DefinedIn) ?? ""
        }

        payload["kind"] = result.Kind
        return payload
    }

    static func TypeToJson(result: TypeResult, fileName: string, line: int, col: int): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "type"
        envelope["ok"] = true

        normalizedFile := OutputFormatterNormalizationKernels.NormalizePath(fileName)
        if normalizedFile != null {
            envelope["file"] = normalizedFile ?? ""
        }

        envelope["position"] = BuildPosition(line, col)
        envelope["result"] = BuildTypeResult(result)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func PerfToJson(fileName: string, line: int, col: int, projectRoot: string?, facts: IReadOnlyList<object>): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "perf"
        envelope["ok"] = true

        normalizedProjectRoot := OutputFormatterNormalizationKernels.NormalizePath(projectRoot)
        if normalizedProjectRoot != null {
            envelope["projectRoot"] = normalizedProjectRoot ?? ""
        }

        normalizedFile := OutputFormatterNormalizationKernels.NormalizePath(fileName)
        if normalizedFile != null {
            envelope["file"] = normalizedFile ?? ""
        }

        envelope["position"] = BuildPosition(line, col)
        envelope["facts"] = BuildPerfFacts(facts)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func BuildPerfFacts(facts: IReadOnlyList<object>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for fact in facts {
            payload.Add(BuildPerfFact(fact))
        }

        return payload
    }

    static func BuildPerfFact(fact: object): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        source := ReadObjectStringProperty(fact, "source")
        if source != null {
            payload["source"] = source ?? ""
        }

        if source == "systems" {
            AddObjectProperty(payload, "code", fact, "Code")
            AddObjectProperty(payload, "severity", fact, "Severity")
            AddObjectProperty(payload, "effect", fact, "Effect")
            AddObjectProperty(payload, "message", fact, "Message")
            AddObjectProperty(payload, "function", fact, "Function")
            AddObjectProperty(payload, "policy", fact, "Policy")
            AddObjectProperty(payload, "suggestion", fact, "Suggestion")
            return payload
        }

        if source == "systemsFunction" {
            AddObjectProperty(payload, "name", fact, "Name")
            AddObjectProperty(payload, "isHot", fact, "IsHot")
            AddObjectProperty(payload, "isBoundary", fact, "IsBoundary")
            AddObjectProperty(payload, "allocNone", fact, "AllocNone")
            AddObjectProperty(payload, "summarySource", fact, "SummarySource")
            AddSystemsEffectFactsObject(payload, fact)
            AddObjectProperty(payload, "calls", fact, "Calls")
            return payload
        }

        AddObjectProperty(payload, "file", fact, "file")
        AddObjectProperty(payload, "line", fact, "line")
        AddObjectProperty(payload, "column", fact, "column")
        AddObjectProperty(payload, "allocation", fact, "allocation")
        AddObjectProperty(payload, "capture", fact, "capture")
        AddObjectProperty(payload, "dispatch", fact, "dispatch")
        AddObjectProperty(payload, "escape", fact, "escape")
        AddObjectProperty(payload, "valueLayout", fact, "valueLayout")
        AddObjectProperty(payload, "aotSafety", fact, "aotSafety")
        return payload
    }

    static func AddSystemsEffectFactsObject(payload: Dictionary<string, object>, fact: object) {
        effects := ReadObjectProperty(fact, "Effects")
        if effects == null {
            return
        }

        effectPayload := new Dictionary<string, object>()
        AddObjectProperty(effectPayload, "allocates", effects, "Allocates")
        AddObjectProperty(effectPayload, "boxes", effects, "Boxes")
        AddObjectProperty(effectPayload, "constructsDelegate", effects, "ConstructsDelegate")
        AddObjectProperty(effectPayload, "capturesClosure", effects, "CapturesClosure")
        AddObjectProperty(effectPayload, "usesRuntimeDispatch", effects, "UsesRuntimeDispatch")
        AddObjectProperty(effectPayload, "usesReflection", effects, "UsesReflection")
        AddObjectProperty(effectPayload, "usesDynamicCode", effects, "UsesDynamicCode")
        AddObjectProperty(effectPayload, "throws", effects, "Throws")
        AddObjectProperty(effectPayload, "hasImplicitTrapObligation", effects, "HasImplicitTrapObligation")
        AddObjectProperty(effectPayload, "usesUnknownExternalCall", effects, "UsesUnknownExternalCall")
        AddObjectProperty(effectPayload, "usesResource", effects, "UsesResource")
        AddObjectProperty(effectPayload, "usesPool", effects, "UsesPool")
        AddObjectProperty(effectPayload, "usesConcurrencyPrimitive", effects, "UsesConcurrencyPrimitive")
        AddObjectProperty(effectPayload, "requiresWarmup", effects, "RequiresWarmup")
        AddObjectProperty(effectPayload, "aotSafe", effects, "AotSafe")
        payload["effects"] = effectPayload
    }

    static func AddObjectProperty(payload: Dictionary<string, object>, outputName: string, value: object, propertyName: string) {
        rawValue := ReadObjectProperty(value, propertyName)
        if rawValue != null {
            payload[outputName] = rawValue
        }
    }

    static func ReadObjectStringProperty(value: object, propertyName: string): string? {
        rawValue := ReadObjectProperty(value, propertyName)
        if rawValue == null {
            return null
        }

        return rawValue as string
    }

    static func ReadObjectProperty(value: object, propertyName: string): object? {
        property := value.GetType().GetProperty(propertyName)
        if property != null {
            return property.GetValue(value)
        }

        return null
    }

    static func ReferencesToJson(symbolName: string, symbolKind: string, definedAt: LocationResult?, results: List<ReferenceResult>): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "references"
        envelope["ok"] = true
        envelope["symbol"] = BuildReferenceSymbol(symbolName, symbolKind, definedAt)
        envelope["count"] = results.Count
        envelope["results"] = BuildReferenceResults(results)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func BuildReferenceSymbol(symbolName: string, symbolKind: string, definedAt: LocationResult?): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["name"] = symbolName
        payload["kind"] = symbolKind

        definition := BuildLocationResult(definedAt)
        if definition != null {
            payload["definedAt"] = definition
        }

        return payload
    }

    static func BuildReferenceResults(results: List<ReferenceResult>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for result in results {
            payload.Add(BuildReferenceResult(result))
        }

        return payload
    }

    static func BuildReferenceResult(result: ReferenceResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["file"] = result.File
        payload["line"] = result.Line
        payload["column"] = result.Column
        payload["length"] = result.Length

        if result.Context != null {
            payload["context"] = result.Context ?? ""
        }

        payload["isDefinition"] = result.IsDefinition
        return payload
    }

    static func OutlineToJson(result: OutlineResult): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "outline"
        envelope["ok"] = true

        normalizedFile := OutputFormatterNormalizationKernels.NormalizePath(result.File)
        if normalizedFile != null {
            envelope["file"] = normalizedFile ?? ""
        }

        envelope["imports"] = result.Imports
        envelope["outline"] = BuildOutlineEntries(result.Outline)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func SymbolsToJson(results: List<SymbolResult>, projectRoot: string?): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "symbols"
        envelope["ok"] = true

        normalizedProjectRoot := OutputFormatterNormalizationKernels.NormalizePath(projectRoot)
        if normalizedProjectRoot != null {
            envelope["projectRoot"] = normalizedProjectRoot ?? ""
        }

        envelope["results"] = BuildSymbolResults(results)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func DiagnosticsToJson(results: List<DiagnosticResult>, projectRoot: string?): string {
        summary := OutputFormatterDiagnosticKernels.SummarizeDiagnosticSeverities(results)
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "diagnostics"
        envelope["ok"] = summary.Errors == 0

        normalizedProjectRoot := OutputFormatterNormalizationKernels.NormalizePath(projectRoot)
        if normalizedProjectRoot != null {
            envelope["projectRoot"] = normalizedProjectRoot ?? ""
        }

        envelope["results"] = BuildDiagnosticResults(results)
        envelope["summary"] = BuildDiagnosticSummary(summary)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func DiagnosticClustersToJson(results: List<DiagnosticResult>, projectRoot: string?): string {
        summary := OutputFormatterDiagnosticKernels.SummarizeDiagnosticSeverities(results)
        clusters := OutputFormatterDiagnosticClusterBuilder.BuildDiagnosticClusters(results)
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "diagnostics.clusters"
        envelope["ok"] = summary.Errors == 0

        normalizedProjectRoot := OutputFormatterNormalizationKernels.NormalizePath(projectRoot)
        if normalizedProjectRoot != null {
            envelope["projectRoot"] = normalizedProjectRoot ?? ""
        }

        envelope["clusters"] = BuildDiagnosticClusters(clusters)
        envelope["summary"] = BuildDiagnosticSummary(summary)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func CheckToJson(results: List<DiagnosticResult>, projectRoot: string?, checkedFiles: int): string {
        summary := OutputFormatterDiagnosticKernels.SummarizeDiagnosticSeverities(results)
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "check"

        normalizedProjectRoot := OutputFormatterNormalizationKernels.NormalizePath(projectRoot)
        if normalizedProjectRoot != null {
            envelope["projectRoot"] = normalizedProjectRoot ?? ""
        }

        envelope["checkedFiles"] = checkedFiles
        envelope["ok"] = summary.Errors == 0
        envelope["results"] = BuildDiagnosticResults(results)
        envelope["summary"] = BuildDiagnosticSummary(summary)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func LintToJson(results: List<DiagnosticResult>, projectRoot: string?, lintedFiles: int): string {
        summary := OutputFormatterDiagnosticKernels.SummarizeDiagnosticSeverities(results)
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "lint"

        normalizedProjectRoot := OutputFormatterNormalizationKernels.NormalizePath(projectRoot)
        if normalizedProjectRoot != null {
            envelope["projectRoot"] = normalizedProjectRoot ?? ""
        }

        envelope["lintedFiles"] = lintedFiles
        envelope["ok"] = summary.Errors == 0
        envelope["results"] = BuildDiagnosticResults(results)
        envelope["summary"] = BuildDiagnosticSummary(summary)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func BuildPerfReportToJson(projectRoot: string?, ok: bool, allocationSites: IReadOnlyList<PerfReportSite>, delegateSites: IReadOnlyList<PerfReportSite>, boxingSites: IReadOnlyList<PerfReportSite>, dispatchSites: IReadOnlyList<PerfReportSite>, closureCaptures: IReadOnlyList<PerfReportSite>, poolSites: IReadOnlyList<PerfReportSite>, resourceSites: IReadOnlyList<PerfReportSite>, boundaryLeakSites: IReadOnlyList<PerfReportSite>, hotReadinessSites: IReadOnlyList<PerfReportSite>, implicitTrapSites: IReadOnlyList<PerfReportSite>, trustedSites: IReadOnlyList<PerfReportTrustedSite>): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "build"
        envelope["ok"] = ok

        normalizedProjectRoot := OutputFormatterNormalizationKernels.NormalizePath(projectRoot)
        if normalizedProjectRoot != null {
            envelope["projectRoot"] = normalizedProjectRoot ?? ""
        }

        perfReport := new Dictionary<string, object>()
        perfReport["allocationSites"] = BuildPerfReportSites(allocationSites)
        perfReport["delegateSites"] = BuildPerfReportSites(delegateSites)
        perfReport["boxingSites"] = BuildPerfReportSites(boxingSites)
        perfReport["dispatchSites"] = BuildPerfReportSites(dispatchSites)
        perfReport["closureCaptures"] = BuildPerfReportSites(closureCaptures)
        perfReport["poolSites"] = BuildPerfReportSites(poolSites)
        perfReport["resourceSites"] = BuildPerfReportSites(resourceSites)
        perfReport["boundaryLeakSites"] = BuildPerfReportSites(boundaryLeakSites)
        perfReport["hotReadinessSites"] = BuildPerfReportSites(hotReadinessSites)
        perfReport["implicitTrapSites"] = BuildPerfReportSites(implicitTrapSites)
        perfReport["trustedSites"] = BuildPerfReportTrustedSites(trustedSites)
        envelope["perfReport"] = perfReport

        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func CheckSystemsReportToJson(diagnostics: List<DiagnosticResult>, projectRoot: string?, checkedFiles: int, report: SystemsReport): string {
        summary := OutputFormatterDiagnosticKernels.SummarizeDiagnosticSeverities(diagnostics)
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "check.systemsReport"

        normalizedProjectRoot := OutputFormatterNormalizationKernels.NormalizePath(projectRoot)
        if normalizedProjectRoot != null {
            envelope["projectRoot"] = normalizedProjectRoot ?? ""
        }

        envelope["checkedFiles"] = checkedFiles
        envelope["ok"] = summary.Errors == 0
        envelope["diagnostics"] = BuildDiagnosticResults(diagnostics)
        envelope["summary"] = BuildDiagnosticSummary(summary)
        envelope["systemsReport"] = BuildSystemsReport(OutputFormatterNormalizationKernels.NormalizeSystemsReport(report))
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func CompletionsToJson(result: CompletionResult, fileName: string, line: int, col: int): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "completions"
        envelope["ok"] = true

        normalizedFile := OutputFormatterNormalizationKernels.NormalizePath(fileName)
        if normalizedFile != null {
            envelope["file"] = normalizedFile ?? ""
        }

        envelope["position"] = BuildPosition(line, col)
        envelope["context"] = CompletionContextToJsonText(result.Context)

        receiver := BuildCompletionReceiver(result)
        if receiver != null {
            envelope["receiver"] = receiver
        } else {
            envelope["receiver"] = new Dictionary<string, object>()
        }

        envelope["completions"] = BuildCompletionGroups(result.Completions)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func InspectToJson(result: InspectResult, fileName: string, line: int, col: int): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "inspect"
        envelope["ok"] = true

        normalizedFile := OutputFormatterNormalizationKernels.NormalizePath(fileName)
        if normalizedFile != null {
            envelope["file"] = normalizedFile ?? ""
        }

        envelope["position"] = BuildPosition(line, col)
        envelope["result"] = BuildInspectResult(result)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func InspectSummaryToJson(result: InspectResult, fileName: string, line: int, col: int): string {
        summary := InspectSummaryBuilder.Build(result)
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "inspect"
        envelope["ok"] = true

        normalizedFile := OutputFormatterNormalizationKernels.NormalizePath(fileName)
        if normalizedFile != null {
            envelope["file"] = normalizedFile ?? ""
        }

        envelope["position"] = BuildPosition(line, col)
        envelope["summary"] = BuildInspectSummaryResult(summary)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func DocToJson(result: DocResult, query: string): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "doc"
        envelope["ok"] = true
        envelope["query"] = query
        envelope["result"] = BuildDocResult(result)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func BuildDiagnosticResults(results: List<DiagnosticResult>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for result in results {
            payload.Add(BuildDiagnosticResult(result))
        }

        return payload
    }

    static func BuildDiagnosticResult(result: DiagnosticResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["code"] = result.Code
        payload["severity"] = result.Severity
        payload["message"] = result.Message
        payload["file"] = result.File
        payload["line"] = result.Line
        payload["column"] = result.Column
        payload["length"] = result.Length

        if result.SourceSnippet != null {
            payload["sourceSnippet"] = result.SourceSnippet ?? ""
        }

        if result.Explanation != null {
            payload["explanation"] = result.Explanation ?? ""
        }

        if result.Suggestion != null {
            payload["suggestion"] = result.Suggestion ?? ""
        }

        if result.Hint != null {
            payload["hint"] = result.Hint ?? ""
        }

        if result.ExpectedType != null {
            payload["expectedType"] = result.ExpectedType ?? ""
        }

        if result.ActualType != null {
            payload["actualType"] = result.ActualType ?? ""
        }

        if result.DocsUrl != null {
            payload["docsUrl"] = result.DocsUrl ?? ""
        }

        return payload
    }

    static func BuildDiagnosticSummary(summary: DiagnosticSummary): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["errors"] = summary.Errors
        payload["warnings"] = summary.Warnings
        payload["info"] = summary.Info
        return payload
    }

    static func BuildDiagnosticClusters(clusters: List<DiagnosticCluster>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for cluster in clusters {
            payload.Add(BuildDiagnosticCluster(cluster))
        }

        return payload
    }

    static func BuildDiagnosticCluster(cluster: DiagnosticCluster): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["id"] = cluster.Id
        payload["category"] = cluster.Category
        payload["recipe"] = cluster.Recipe
        payload["risk"] = cluster.Risk
        payload["count"] = cluster.Count
        payload["severity"] = cluster.Severity
        payload["files"] = cluster.Files
        payload["relatedDiagnostics"] = BuildDiagnosticClusterRelatedDiagnostics(cluster.RelatedDiagnostics)
        payload["nextCommand"] = cluster.NextCommand
        payload["rootLocation"] = BuildDiagnosticClusterLocation(cluster.RootLocation)
        payload["messagePattern"] = cluster.MessagePattern
        payload["sourceConstruct"] = cluster.SourceConstruct
        payload["suggestedNextActions"] = cluster.SuggestedNextActions
        payload["examples"] = BuildDiagnosticClusterExamples(cluster.Examples)
        return payload
    }

    static func BuildDiagnosticClusterLocation(location: DiagnosticClusterLocation): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["file"] = location.File
        payload["line"] = location.Line
        payload["column"] = location.Column
        return payload
    }

    static func BuildDiagnosticClusterRelatedDiagnostics(results: DiagnosticClusterRelatedDiagnostic[]): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for result in results {
            payload.Add(BuildDiagnosticClusterRelatedDiagnostic(result))
        }

        return payload
    }

    static func BuildDiagnosticClusterRelatedDiagnostic(result: DiagnosticClusterRelatedDiagnostic): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["code"] = result.Code
        payload["severity"] = result.Severity
        payload["file"] = result.File
        payload["line"] = result.Line
        payload["column"] = result.Column
        payload["message"] = result.Message
        return payload
    }

    static func BuildDiagnosticClusterExamples(results: DiagnosticClusterExample[]): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for result in results {
            payload.Add(BuildDiagnosticClusterExample(result))
        }

        return payload
    }

    static func BuildDiagnosticClusterExample(result: DiagnosticClusterExample): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["file"] = result.File
        payload["line"] = result.Line
        payload["column"] = result.Column
        payload["message"] = result.Message

        if result.SourceSnippet != null {
            payload["sourceSnippet"] = result.SourceSnippet ?? ""
        }

        if result.Suggestion != null {
            payload["suggestion"] = result.Suggestion ?? ""
        }

        return payload
    }

    static func BuildPerfReportSites(sites: IReadOnlyList<PerfReportSite>): List<Dictionary<string, object>> {
        normalizedSites := OutputFormatterNormalizationKernels.NormalizePerfReportSites(sites)
        return BuildPerfReportSiteJsonArray(normalizedSites)
    }

    static func BuildPerfReportSiteJsonArray(sites: PerfReportSiteJson[]): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for site in sites {
            payload.Add(BuildPerfReportSite(site))
        }

        return payload
    }

    static func BuildPerfReportSite(site: PerfReportSiteJson): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["code"] = site.Code
        payload["effect"] = site.Effect
        payload["file"] = site.File
        payload["line"] = site.Line
        payload["column"] = site.Column
        payload["message"] = site.Message

        if site.Function != null {
            payload["function"] = site.Function ?? ""
        }

        if site.Suggestion != null {
            payload["suggestion"] = site.Suggestion ?? ""
        }

        return payload
    }

    static func BuildPerfReportTrustedSites(sites: IReadOnlyList<PerfReportTrustedSite>): List<Dictionary<string, object>> {
        normalizedSites := OutputFormatterNormalizationKernels.NormalizePerfReportTrustedSites(sites)
        return BuildPerfReportTrustedSiteJsonArray(normalizedSites)
    }

    static func BuildPerfReportTrustedSiteJsonArray(sites: PerfReportTrustedSiteJson[]): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for site in sites {
            payload.Add(BuildPerfReportTrustedSite(site))
        }

        return payload
    }

    static func BuildPerfReportTrustedSite(site: PerfReportTrustedSiteJson): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["function"] = site.Function
        payload["file"] = site.File
        payload["line"] = site.Line
        payload["column"] = site.Column

        if site.Owner != null {
            payload["owner"] = site.Owner ?? ""
        }

        if site.Review != null {
            payload["review"] = site.Review ?? ""
        }

        if site.Expires != null {
            payload["expires"] = site.Expires ?? ""
        }

        payload["hasUnsafe"] = site.HasUnsafe
        payload["bodyStatementCount"] = site.BodyStatementCount
        return payload
    }

    static func BuildSystemsReport(report: SystemsReportJsonPayload): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["schemaVersion"] = report.SchemaVersion
        payload["profile"] = report.Profile
        payload["mode"] = report.Mode
        payload["aotTarget"] = report.AotTarget
        payload["aot"] = BuildSystemsAotReport(report.Aot)
        payload["warmup"] = report.Warmup
        payload["functions"] = BuildSystemsFunctionSummaries(report.Functions)
        payload["findings"] = BuildSystemsFindings(report.Findings)
        payload["trustedSites"] = BuildTrustedResults(report.TrustedSites)
        payload["summary"] = BuildSystemsReportSummary(report.Summary)
        return payload
    }

    static func BuildSystemsAotReport(report: SystemsAotReportJson): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["target"] = report.Target
        payload["analysis"] = report.Analysis
        payload["nativeImageEmitted"] = report.NativeImageEmitted
        payload["trimSafe"] = report.TrimSafe
        return payload
    }

    static func BuildSystemsFunctionSummaries(functions: SystemsFunctionSummaryJson[]): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for function in functions {
            payload.Add(BuildSystemsFunctionSummary(function))
        }

        return payload
    }

    static func BuildSystemsFunctionSummary(function: SystemsFunctionSummaryJson): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["name"] = function.Name
        payload["file"] = function.File
        payload["line"] = function.Line
        payload["column"] = function.Column
        payload["isHot"] = function.IsHot
        payload["isBoundary"] = function.IsBoundary
        payload["allocNone"] = function.AllocNone
        payload["summarySource"] = function.SummarySource
        payload["effects"] = BuildSystemsEffectFacts(function.Effects)
        payload["calls"] = function.Calls
        return payload
    }

    static func BuildSystemsEffectFacts(effects: SystemsEffectFactsJson): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["allocates"] = effects.Allocates
        payload["boxes"] = effects.Boxes
        payload["constructsDelegate"] = effects.ConstructsDelegate
        payload["capturesClosure"] = effects.CapturesClosure
        payload["usesRuntimeDispatch"] = effects.UsesRuntimeDispatch
        payload["usesReflection"] = effects.UsesReflection
        payload["usesDynamicCode"] = effects.UsesDynamicCode
        payload["throws"] = effects.Throws
        payload["hasImplicitTrapObligation"] = effects.HasImplicitTrapObligation
        payload["usesUnknownExternalCall"] = effects.UsesUnknownExternalCall
        payload["usesResource"] = effects.UsesResource
        payload["usesPool"] = effects.UsesPool
        payload["usesConcurrencyPrimitive"] = effects.UsesConcurrencyPrimitive
        payload["requiresWarmup"] = effects.RequiresWarmup
        payload["aotSafe"] = effects.AotSafe
        return payload
    }

    static func BuildSystemsFindings(findings: SystemsFindingJson[]): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for finding in findings {
            payload.Add(BuildSystemsFinding(finding))
        }

        return payload
    }

    static func BuildSystemsFinding(finding: SystemsFindingJson): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["code"] = finding.Code
        payload["severity"] = finding.Severity
        payload["effect"] = finding.Effect
        payload["message"] = finding.Message
        payload["file"] = finding.File
        payload["line"] = finding.Line
        payload["column"] = finding.Column
        payload["length"] = finding.Length

        if finding.Function != null {
            payload["function"] = finding.Function ?? ""
        }

        if finding.Policy != null {
            payload["policy"] = finding.Policy ?? ""
        }

        if finding.SummarySource != null {
            payload["summarySource"] = finding.SummarySource ?? ""
        }

        if finding.Suggestion != null {
            payload["suggestion"] = finding.Suggestion ?? ""
        }

        payload["callPath"] = finding.CallPath
        return payload
    }

    static func BuildSystemsReportSummary(summary: SystemsReportSummaryJson): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["functions"] = summary.Functions
        payload["hotFunctions"] = summary.HotFunctions
        payload["boundaryFunctions"] = summary.BoundaryFunctions
        payload["findings"] = summary.Findings
        payload["errors"] = summary.Errors
        payload["warnings"] = summary.Warnings
        payload["trustedSites"] = summary.TrustedSites
        return payload
    }

    static func BuildCompletionReceiver(result: CompletionResult): Dictionary<string, object>? {
        if result.Receiver == null {
            return null
        }

        payload := new Dictionary<string, object>()
        payload["name"] = result.Receiver ?? ""

        if result.ReceiverType != null {
            payload["type"] = result.ReceiverType ?? ""
        }

        return payload
    }

    static func BuildCompletionGroups(completions: Dictionary<string, List<CompletionItem>>): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        for entry in completions {
            payload[entry.Key] = BuildCompletionItems(entry.Value)
        }

        return payload
    }

    static func BuildCompletionItems(items: List<CompletionItem>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for item in items {
            payload.Add(BuildCompletionItem(item))
        }

        return payload
    }

    static func BuildCompletionItem(item: CompletionItem): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["name"] = item.Name
        payload["kind"] = item.Kind

        if item.Type != null {
            payload["type"] = item.Type ?? ""
        }

        if item.Parameters != null {
            payload["parameters"] = item.Parameters ?? ""
        }

        if item.Documentation != null {
            payload["documentation"] = item.Documentation ?? ""
        }

        payload["isStatic"] = item.IsStatic
        return payload
    }

    static func CompletionContextToJsonText(context: CompletionContext): string {
        if context == CompletionContext.MemberAccess {
            return "memberaccess"
        }

        if context == CompletionContext.Identifier {
            return "identifier"
        }

        if context == CompletionContext.Namespace {
            return "namespace"
        }

        return "unknown"
    }

    static func BuildInspectResult(result: InspectResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()

        symbol := BuildInspectSymbolResult(result.Symbol)
        if symbol != null {
            payload["symbol"] = symbol
        }

        typeResult := BuildOptionalTypeResult(result.Type)
        if typeResult != null {
            payload["type"] = typeResult
        }

        definition := BuildOptionalDefinitionResult(result.Definition)
        if definition != null {
            payload["definition"] = definition
        }

        payload["references"] = BuildInspectReferencesResult(result.References)
        payload["completions"] = BuildCompletionResult(result.Completions)
        return payload
    }

    static func BuildInspectSymbolResult(result: InspectSymbolResult?): Dictionary<string, object>? {
        if result == null {
            return null
        }

        symbol := (InspectSymbolResult)result
        payload := new Dictionary<string, object>()
        payload["name"] = symbol.Name
        payload["kind"] = symbol.Kind

        definition := BuildLocationResult(symbol.Definition)
        if definition != null {
            payload["definition"] = definition
        }

        return payload
    }

    static func BuildOptionalTypeResult(result: TypeResult?): Dictionary<string, object>? {
        if result == null {
            return null
        }

        return BuildTypeResult((TypeResult)result)
    }

    static func BuildOptionalDefinitionResult(result: DefinitionResult?): Dictionary<string, object>? {
        if result == null {
            return null
        }

        return BuildDefinitionResult((DefinitionResult)result)
    }

    static func BuildInspectReferencesResult(result: InspectReferencesResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["count"] = result.Count
        payload["definitionCount"] = result.DefinitionCount
        payload["results"] = BuildReferenceArray(result.Results)
        return payload
    }

    static func BuildReferenceArray(results: ReferenceResult[]): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for result in results {
            payload.Add(BuildReferenceResult(result))
        }

        return payload
    }

    static func BuildCompletionResult(result: CompletionResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["context"] = CompletionContextToJsonText(result.Context)

        if result.Receiver != null {
            payload["receiver"] = result.Receiver ?? ""
        }

        if result.ReceiverType != null {
            payload["receiverType"] = result.ReceiverType ?? ""
        }

        payload["completions"] = BuildCompletionGroups(result.Completions)
        return payload
    }

    static func BuildInspectSummaryResult(result: InspectSummaryResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()

        symbol := BuildInspectSummarySymbolResult(result.Symbol)
        if symbol != null {
            payload["symbol"] = symbol
        }

        typeResult := BuildInspectSummaryTypeResult(result.Type)
        if typeResult != null {
            payload["type"] = typeResult
        }

        definition := BuildLocationResult(result.Definition)
        if definition != null {
            payload["definition"] = definition
        }

        payload["references"] = BuildInspectSummaryReferencesResult(result.References)
        payload["completions"] = BuildInspectSummaryCompletionsResult(result.Completions)
        return payload
    }

    static func BuildInspectSummarySymbolResult(result: InspectSummarySymbolResult?): Dictionary<string, object>? {
        if result == null {
            return null
        }

        symbol := (InspectSummarySymbolResult)result
        payload := new Dictionary<string, object>()
        payload["name"] = symbol.Name
        payload["kind"] = symbol.Kind
        return payload
    }

    static func BuildInspectSummaryTypeResult(result: InspectSummaryTypeResult?): Dictionary<string, object>? {
        if result == null {
            return null
        }

        typeResult := (InspectSummaryTypeResult)result
        payload := new Dictionary<string, object>()
        payload["name"] = typeResult.Name
        payload["resolvedType"] = typeResult.ResolvedType
        payload["kind"] = typeResult.Kind

        if typeResult.Nullability != null {
            payload["nullability"] = typeResult.Nullability ?? ""
        }

        return payload
    }

    static func BuildInspectSummaryReferencesResult(result: InspectSummaryReferencesResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["count"] = result.Count
        payload["definitionCount"] = result.DefinitionCount
        payload["files"] = result.Files
        payload["sample"] = BuildInspectReferenceSummaryArray(result.Sample)
        return payload
    }

    static func BuildInspectReferenceSummaryArray(results: InspectReferenceSummaryResult[]): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for result in results {
            payload.Add(BuildInspectReferenceSummaryResult(result))
        }

        return payload
    }

    static func BuildInspectReferenceSummaryResult(result: InspectReferenceSummaryResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["file"] = result.File
        payload["line"] = result.Line
        payload["column"] = result.Column
        payload["isDefinition"] = result.IsDefinition
        return payload
    }

    static func BuildInspectSummaryCompletionsResult(result: InspectSummaryCompletionsResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["context"] = result.Context

        if result.Receiver != null {
            payload["receiver"] = result.Receiver ?? ""
        }

        if result.ReceiverType != null {
            payload["receiverType"] = result.ReceiverType ?? ""
        }

        payload["totalCount"] = result.TotalCount
        payload["groupCounts"] = result.GroupCounts
        payload["groups"] = result.Groups
        return payload
    }

    static func BuildDocResult(result: DocResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["name"] = result.Name
        payload["fullName"] = result.FullName
        payload["kind"] = result.Kind

        if result.Summary != null {
            payload["summary"] = result.Summary ?? ""
        }

        if result.Namespace != null {
            payload["namespace"] = result.Namespace ?? ""
        }

        members := BuildDocMemberResults(result.Members)
        if members != null {
            payload["members"] = members
        }

        parameters := BuildDocParameterResults(result.Parameters)
        if parameters != null {
            payload["parameters"] = parameters
        }

        if result.ReturnType != null {
            payload["returnType"] = result.ReturnType ?? ""
        }

        if result.ReturnDoc != null {
            payload["returnDoc"] = result.ReturnDoc ?? ""
        }

        if result.BaseTypes != null {
            payload["baseTypes"] = result.BaseTypes ?? new string[](0)
        }

        return payload
    }

    static func BuildDocMemberResults(results: DocMemberResult[]?): List<Dictionary<string, object>>? {
        if results == null {
            return null
        }

        payload := new List<Dictionary<string, object>>()
        items := results ?? new DocMemberResult[](0)
        for result in items {
            payload.Add(BuildDocMemberResult(result))
        }

        return payload
    }

    static func BuildDocMemberResult(result: DocMemberResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["name"] = result.Name
        payload["kind"] = result.Kind

        if result.Type != null {
            payload["type"] = result.Type ?? ""
        }

        if result.Summary != null {
            payload["summary"] = result.Summary ?? ""
        }

        if result.Parameters != null {
            payload["parameters"] = result.Parameters ?? ""
        }

        return payload
    }

    static func BuildDocParameterResults(results: DocParameterResult[]?): List<Dictionary<string, object>>? {
        if results == null {
            return null
        }

        payload := new List<Dictionary<string, object>>()
        items := results ?? new DocParameterResult[](0)
        for result in items {
            payload.Add(BuildDocParameterResult(result))
        }

        return payload
    }

    static func BuildDocParameterResult(result: DocParameterResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["name"] = result.Name
        payload["type"] = result.Type

        if result.Summary != null {
            payload["summary"] = result.Summary ?? ""
        }

        return payload
    }

    static func BuildSymbolResults(results: List<SymbolResult>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for result in results {
            payload.Add(BuildSymbolResult(result))
        }

        return payload
    }

    static func BuildSymbolArray(results: SymbolResult[]): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for result in results {
            payload.Add(BuildSymbolResult(result))
        }

        return payload
    }

    static func BuildOptionalSymbolArray(results: SymbolResult[]?): List<Dictionary<string, object>>? {
        if results == null {
            return null
        }

        return BuildSymbolArray(results)
    }

    static func BuildSymbolResult(result: SymbolResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["name"] = result.Name
        payload["kind"] = SymbolKindToJsonText(result.Kind)
        payload["file"] = result.File
        payload["line"] = result.Line
        payload["column"] = result.Column

        if result.TypeName != null {
            payload["typeName"] = result.TypeName ?? ""
        }

        if result.Modifiers != null {
            payload["modifiers"] = result.Modifiers
        }

        members := BuildOptionalSymbolArray(result.Members)
        if members != null {
            payload["members"] = members
        }

        parameters := BuildOptionalParameterResults(result.Parameters)
        if parameters != null {
            payload["parameters"] = parameters
        }

        return payload
    }

    static func BuildOptionalParameterResults(parameters: ParameterResult[]?): List<Dictionary<string, object>>? {
        if parameters == null {
            return null
        }

        payload := new List<Dictionary<string, object>>()
        for parameter in parameters {
            payload.Add(BuildParameterResult(parameter))
        }

        return payload
    }

    static func BuildParameterResult(parameter: ParameterResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["name"] = parameter.Name
        payload["type"] = parameter.Type
        payload["hasDefault"] = parameter.HasDefault

        if parameter.DefaultValue != null {
            payload["defaultValue"] = parameter.DefaultValue ?? ""
        }

        return payload
    }

    static func BuildOutlineEntries(entries: OutlineEntry[]): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        for entry in entries {
            payload.Add(BuildOutlineEntry(entry))
        }

        return payload
    }

    static func BuildOptionalOutlineEntries(entries: OutlineEntry[]?): List<Dictionary<string, object>>? {
        if entries == null {
            return null
        }

        return BuildOutlineEntries(entries)
    }

    static func BuildOutlineEntry(entry: OutlineEntry): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["name"] = entry.Name
        payload["kind"] = SymbolKindToJsonText(entry.Kind)
        payload["line"] = entry.Line
        payload["endLine"] = entry.EndLine

        if entry.ReturnType != null {
            payload["returnType"] = entry.ReturnType ?? ""
        }

        if entry.TypeName != null {
            payload["typeName"] = entry.TypeName ?? ""
        }

        children := BuildOptionalOutlineEntries(entry.Children)
        if children != null {
            payload["children"] = children
        }

        return payload
    }

    static func SymbolKindToJsonText(kind: SymbolKind): string {
        if kind == SymbolKind.Function {
            return "function"
        }

        if kind == SymbolKind.Class {
            return "class"
        }

        if kind == SymbolKind.Struct {
            return "struct"
        }

        if kind == SymbolKind.Record {
            return "record"
        }

        if kind == SymbolKind.Interface {
            return "interface"
        }

        if kind == SymbolKind.Enum {
            return "enum"
        }

        if kind == SymbolKind.Union {
            return "union"
        }

        if kind == SymbolKind.Property {
            return "property"
        }

        if kind == SymbolKind.Field {
            return "field"
        }

        if kind == SymbolKind.Method {
            return "method"
        }

        if kind == SymbolKind.Variable {
            return "variable"
        }

        if kind == SymbolKind.Parameter {
            return "parameter"
        }

        if kind == SymbolKind.Constructor {
            return "constructor"
        }

        if kind == SymbolKind.EnumMember {
            return "enumMember"
        }

        if kind == SymbolKind.TypeAlias {
            return "typeAlias"
        }

        if kind == SymbolKind.Test {
            return "test"
        }

        return "unknown"
    }

    static func BuildTypeResult(result: TypeResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["name"] = result.Name
        payload["resolvedType"] = result.ResolvedType
        payload["kind"] = result.Kind

        definition := BuildLocationResult(result.Definition)
        if definition != null {
            payload["definition"] = definition
        }

        if result.Nullability != null {
            payload["nullability"] = result.Nullability ?? ""
        }

        return payload
    }

    static func BuildLocationResult(location: LocationResult?): Dictionary<string, object>? {
        if location == null {
            return null
        }

        payload := new Dictionary<string, object>()
        payload["file"] = location.File
        payload["line"] = location.Line
        payload["column"] = location.Column
        return payload
    }

    static func BuildTrustedResults(sites: SystemsTrustedSiteJson[]): List<Dictionary<string, object>> {
        results := new List<Dictionary<string, object>>()
        for site in sites {
            results.Add(BuildTrustedSite(site))
        }

        return results
    }

    static func BuildTrustedSite(site: SystemsTrustedSiteJson): Dictionary<string, object> {
        result := new Dictionary<string, object>()
        result["function"] = site.Function
        result["file"] = site.File
        result["line"] = site.Line
        result["column"] = site.Column

        if site.Reason != null {
            result["reason"] = site.Reason ?? ""
        }

        if site.Owner != null {
            result["owner"] = site.Owner ?? ""
        }

        if site.Review != null {
            result["review"] = site.Review ?? ""
        }

        if site.Expires != null {
            result["expires"] = site.Expires ?? ""
        }

        result["hasUnsafe"] = site.HasUnsafe
        result["bodyStatementCount"] = site.BodyStatementCount
        return result
    }
}
