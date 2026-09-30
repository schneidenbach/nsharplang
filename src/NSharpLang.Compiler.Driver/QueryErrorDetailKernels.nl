namespace NSharpLang.Cli

import System.Collections.Generic
import NSharpLang.Compiler.CodeIntelligence

class QueryErrorDetailKernels {
    static func Position(filePath: string?, line: int, column: int): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        normalizedFile := OutputFormatterNormalizationKernels.NormalizePath(filePath)
        if normalizedFile != null {
            payload["file"] = normalizedFile ?? ""
        }

        payload["position"] = BuildPosition(line, column)
        return payload
    }

    static func Requests(requestsPath: string?): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        normalizedRequests := OutputFormatterNormalizationKernels.NormalizePath(requestsPath)
        if normalizedRequests != null {
            payload["requests"] = normalizedRequests ?? ""
        }

        return payload
    }

    static func SemanticReferencesUnavailable(filePath: string?, line: int, column: int, symbolName: string, symbolKind: string, definedAt: LocationResult): Dictionary<string, object> {
        payload := Position(filePath, line, column)

        symbol := new Dictionary<string, object>()
        symbol["name"] = symbolName
        symbol["kind"] = symbolKind
        symbol["definedAt"] = BuildLocation(definedAt)
        payload["symbol"] = symbol
        return payload
    }

    static func BuildPosition(line: int, column: int): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["line"] = line
        payload["column"] = column
        return payload
    }

    static func BuildLocation(location: LocationResult): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        normalizedFile := OutputFormatterNormalizationKernels.NormalizePath(location.File)
        if normalizedFile != null {
            payload["file"] = normalizedFile ?? ""
        }

        payload["line"] = location.Line
        payload["column"] = location.Column
        return payload
    }
}
