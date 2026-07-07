namespace NSharpLang.Cli

import NSharpLang.Compiler.CodeIntelligence

public class QueryErrorPositionDetails {
    lineValue: int
    columnValue: int

    Line: int => lineValue
    Column: int => columnValue

    constructor(line: int, column: int) {
        lineValue = line
        columnValue = column
    }
}

public class QueryErrorLocationDetails {
    fileValue: string?
    positionValue: QueryErrorPositionDetails

    File: string? => fileValue
    Position: QueryErrorPositionDetails => positionValue

    constructor(filePath: string?, position: QueryErrorPositionDetails) {
        fileValue = filePath
        positionValue = position
    }
}

public class QueryErrorRequestsDetails {
    requestsValue: string?

    Requests: string? => requestsValue

    constructor(requestsPath: string?) {
        requestsValue = requestsPath
    }
}

public class QueryErrorSymbolDetails {
    nameValue: string
    kindValue: string
    definedAtValue: LocationResult

    Name: string => nameValue
    Kind: string => kindValue
    DefinedAt: LocationResult => definedAtValue

    constructor(name: string, kind: string, definedAt: LocationResult) {
        nameValue = name
        kindValue = kind
        definedAtValue = definedAt
    }
}

public class QueryErrorSemanticReferencesDetails {
    fileValue: string?
    positionValue: QueryErrorPositionDetails
    symbolValue: QueryErrorSymbolDetails

    File: string? => fileValue
    Position: QueryErrorPositionDetails => positionValue
    Symbol: QueryErrorSymbolDetails => symbolValue

    constructor(filePath: string?, position: QueryErrorPositionDetails, symbol: QueryErrorSymbolDetails) {
        fileValue = filePath
        positionValue = position
        symbolValue = symbol
    }
}

public class QueryErrorDetailKernels {
    public static func Position(filePath: string?, line: int, column: int): QueryErrorLocationDetails {
        return new QueryErrorLocationDetails(
            OutputFormatterNormalizationKernels.NormalizePath(filePath),
            new QueryErrorPositionDetails(line, column))
    }

    public static func Requests(requestsPath: string?): QueryErrorRequestsDetails {
        return new QueryErrorRequestsDetails(OutputFormatterNormalizationKernels.NormalizePath(requestsPath))
    }

    public static func SemanticReferencesUnavailable(
        filePath: string?,
        line: int,
        column: int,
        symbolName: string,
        symbolKind: string,
        definedAt: LocationResult): QueryErrorSemanticReferencesDetails {
        return new QueryErrorSemanticReferencesDetails(
            OutputFormatterNormalizationKernels.NormalizePath(filePath),
            new QueryErrorPositionDetails(line, column),
            new QueryErrorSymbolDetails(symbolName, symbolKind, definedAt))
    }
}
