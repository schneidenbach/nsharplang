namespace SystemsProofs.GeneratedRegexBoundary

import System
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
    match := RouteParser.RouteRegex().Match(line)
    if !match.Success {
        return Err("invalid route")
    }

    return Ok(Route { Method: match.Groups[1].Value, Path: match.Groups[2].Value })
}

func Main() {
    print ParseRoute("GET /health")
}
