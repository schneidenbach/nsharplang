namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import System.Text.Json

public class OutputFormatterJsonKernels {
    static func CreateWriteIndentedOptions(): JsonSerializerOptions {
        return new JsonSerializerOptions { WriteIndented: true }
    }

    public static func TrustedToJson(report: SystemsReport, projectRoot: string?): string {
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

    public static func DefinitionToJson(result: DefinitionResult): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "definition"
        envelope["ok"] = true
        envelope["result"] = BuildDefinitionResult(result)
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

    public static func CallGraphToJson(result: CallGraphResult): string {
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
        foreach site in sites {
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

    public static func ImplementorsToJson(result: ImplementorsResult): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "implementors"
        envelope["ok"] = true
        envelope["interface"] = result.Interface
        envelope["results"] = BuildImplementorResults(result.Results)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    static func BuildImplementorResults(results: List<ImplementorResult>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        foreach result in results {
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

    public static func HoverToJson(result: HoverResult, fileName: string, line: int, col: int): string {
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

    public static func TypeToJson(result: TypeResult, fileName: string, line: int, col: int): string {
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

    public static func ReferencesToJson(symbolName: string, symbolKind: string, definedAt: LocationResult?, results: List<ReferenceResult>): string {
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
        foreach result in results {
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

    public static func OutlineToJson(result: OutlineResult): string {
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

    public static func SymbolsToJson(results: List<SymbolResult>, projectRoot: string?): string {
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

    static func BuildSymbolResults(results: List<SymbolResult>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        foreach result in results {
            payload.Add(BuildSymbolResult(result))
        }

        return payload
    }

    static func BuildSymbolArray(results: SymbolResult[]): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        foreach result in results {
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
        foreach parameter in parameters {
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
        foreach entry in entries {
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
        foreach site in sites {
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
