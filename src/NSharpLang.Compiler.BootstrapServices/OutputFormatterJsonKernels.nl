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
