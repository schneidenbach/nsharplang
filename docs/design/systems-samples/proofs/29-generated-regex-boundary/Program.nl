namespace SystemsProofs.GeneratedRegexBoundary

import System.Text.RegularExpressions

record Route {
    Method: string
    Path: string
}

partial class RouteParser {
    [GeneratedRegex("^(GET|POST) ([A-Za-z0-9/_-]+)$")]
    static partial func RouteRegex(): Regex
}

[boundary]
func ParseRoute(line: string): Result<Route, string> {
    routeMatch := RouteParser.RouteRegex().Match(line)
    if !routeMatch.Success {
        return Err("invalid route")
    }

    return Ok(new Route { Method: routeMatch.Groups[1].Value, Path: routeMatch.Groups[2].Value })
}

[boundary]
func Main(): int {
    route := ParseRoute("GET /health")
    if !route.IsOk {
        return 1
    }

    ok := route.OkValueUnchecked
    if ok.Method != "GET" {
        return 2
    }
    if ok.Path != "/health" {
        return 3
    }

    invalid := ParseRoute("DELETE /health")
    if invalid.IsOk {
        return 4
    }

    return 0
}
