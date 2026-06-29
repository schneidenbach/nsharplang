namespace NSharpLang.Compiler.Performance

import System
import System.Collections.Generic
import NSharpLang.Compiler

public record SystemsReport(
    SchemaVersion: int,
    Profile: string,
    Mode: string,
    AotTarget: string,
    Warmup: IReadOnlyList<string>,
    Functions: IReadOnlyList<SystemsFunctionSummary>,
    Findings: IReadOnlyList<SystemsFinding>,
    TrustedSites: IReadOnlyList<SystemsTrustedSite>,
    Aot: SystemsAotReport,
    Summary: SystemsReportSummary) {

    public static func Empty(config: ProjectConfig?): SystemsReport {
        profile := "default"
        mode := "strict"
        aotTarget := "nativeaot"
        warmup := new string[](0)

        if config != null {
            profile = config.Language.Profile
            mode = config.Language.Systems.Mode
            aotTarget = config.Language.Systems.AotTarget
            warmup = config.Language.Systems.Warmup.ToArray()
        }

        return new SystemsReport(
            1,
            profile,
            mode,
            aotTarget,
            warmup,
            new SystemsFunctionSummary[](0),
            new SystemsFinding[](0),
            new SystemsTrustedSite[](0),
            new SystemsAotReport(
                aotTarget,
                "pass",
                false,
                true),
            new SystemsReportSummary(0, 0, 0, 0, 0, 0, 0))
    }
}

public record SystemsFunctionSummary(
    Name: string,
    File: string,
    Line: int,
    Column: int,
    IsHot: bool,
    IsBoundary: bool,
    AllocNone: bool,
    SummarySource: string,
    Effects: SystemsEffectFacts,
    Calls: IReadOnlyList<string>) {
}

public record SystemsFinding(
    Code: string,
    Severity: string,
    Effect: string,
    Message: string,
    File: string,
    Line: int,
    Column: int,
    Length: int,
    Function: string?,
    Policy: string?,
    SummarySource: string?,
    Suggestion: string?,
    CallPath: IReadOnlyList<string>) {
}

public record SystemsTrustedSite(
    Function: string,
    File: string,
    Line: int,
    Column: int,
    Reason: string?,
    Owner: string?,
    Review: string?,
    Expires: string?,
    HasUnsafe: bool,
    BodyStatementCount: int) {
}
