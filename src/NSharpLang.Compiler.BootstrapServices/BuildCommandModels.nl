namespace NSharpLang.Cli

import System.Collections.Generic
import NSharpLang.Compiler.CodeIntelligence

public class BuildOptionSummary {
    OutputDir: string?
    BackendOption: string?
    ProjectOption: string?
    Release: bool
    Verbose: bool
    Timings: bool
    PerfReport: bool
    Aot: bool
    ShowHelp: bool

    constructor(
        outputDir: string?,
        backendOption: string?,
        projectOption: string?,
        release: bool,
        verbose: bool,
        timings: bool,
        perfReport: bool,
        aot: bool,
        showHelp: bool) {
        OutputDir = outputDir
        BackendOption = backendOption
        ProjectOption = projectOption
        Release = release
        Verbose = verbose
        Timings = timings
        PerfReport = perfReport
        Aot = aot
        ShowHelp = showHelp
    }
}

public class BuildCommandResult {
    exitCodeValue: int
    perfFactsValue: BuildPerfReportFacts

    ExitCode: int {
        get { return exitCodeValue }
    }

    PerfFacts: BuildPerfReportFacts {
        get { return perfFactsValue }
    }

    constructor(exitCode: int, perfFacts: BuildPerfReportFacts) {
        exitCodeValue = exitCode
        perfFactsValue = perfFacts
    }

    public static func Failure(exitCode: int = 1, perfFacts: BuildPerfReportFacts? = null): BuildCommandResult {
        facts := perfFacts
        if facts == null {
            facts = BuildPerfReportFacts.Empty
        }

        return new BuildCommandResult(exitCode, facts)
    }
}

public class BuildPerfReportFacts {
    allocationSitesValue: IReadOnlyList<PerfReportSite>
    delegateSitesValue: IReadOnlyList<PerfReportSite>
    boxingSitesValue: IReadOnlyList<PerfReportSite>
    dispatchSitesValue: IReadOnlyList<PerfReportSite>
    closureCapturesValue: IReadOnlyList<PerfReportSite>
    poolSitesValue: IReadOnlyList<PerfReportSite>
    resourceSitesValue: IReadOnlyList<PerfReportSite>
    boundaryLeakSitesValue: IReadOnlyList<PerfReportSite>
    hotReadinessSitesValue: IReadOnlyList<PerfReportSite>
    implicitTrapSitesValue: IReadOnlyList<PerfReportSite>
    trustedSitesValue: IReadOnlyList<PerfReportTrustedSite>

    AllocationSites: IReadOnlyList<PerfReportSite> {
        get { return allocationSitesValue }
    }

    DelegateSites: IReadOnlyList<PerfReportSite> {
        get { return delegateSitesValue }
    }

    BoxingSites: IReadOnlyList<PerfReportSite> {
        get { return boxingSitesValue }
    }

    DispatchSites: IReadOnlyList<PerfReportSite> {
        get { return dispatchSitesValue }
    }

    ClosureCaptures: IReadOnlyList<PerfReportSite> {
        get { return closureCapturesValue }
    }

    PoolSites: IReadOnlyList<PerfReportSite> {
        get { return poolSitesValue }
    }

    ResourceSites: IReadOnlyList<PerfReportSite> {
        get { return resourceSitesValue }
    }

    BoundaryLeakSites: IReadOnlyList<PerfReportSite> {
        get { return boundaryLeakSitesValue }
    }

    HotReadinessSites: IReadOnlyList<PerfReportSite> {
        get { return hotReadinessSitesValue }
    }

    ImplicitTrapSites: IReadOnlyList<PerfReportSite> {
        get { return implicitTrapSitesValue }
    }

    TrustedSites: IReadOnlyList<PerfReportTrustedSite> {
        get { return trustedSitesValue }
    }

    public static Empty: BuildPerfReportFacts => new BuildPerfReportFacts(
        new PerfReportSite[](0),
        new PerfReportSite[](0),
        new PerfReportSite[](0),
        new PerfReportSite[](0),
        new PerfReportSite[](0),
        new PerfReportSite[](0),
        new PerfReportSite[](0),
        new PerfReportSite[](0),
        new PerfReportSite[](0),
        new PerfReportSite[](0),
        new PerfReportTrustedSite[](0))

    constructor(
        allocationSites: IReadOnlyList<PerfReportSite>,
        delegateSites: IReadOnlyList<PerfReportSite>,
        boxingSites: IReadOnlyList<PerfReportSite>,
        dispatchSites: IReadOnlyList<PerfReportSite>,
        closureCaptures: IReadOnlyList<PerfReportSite>,
        poolSites: IReadOnlyList<PerfReportSite>,
        resourceSites: IReadOnlyList<PerfReportSite>,
        boundaryLeakSites: IReadOnlyList<PerfReportSite>,
        hotReadinessSites: IReadOnlyList<PerfReportSite>,
        implicitTrapSites: IReadOnlyList<PerfReportSite>,
        trustedSites: IReadOnlyList<PerfReportTrustedSite>) {
        allocationSitesValue = allocationSites
        delegateSitesValue = delegateSites
        boxingSitesValue = boxingSites
        dispatchSitesValue = dispatchSites
        closureCapturesValue = closureCaptures
        poolSitesValue = poolSites
        resourceSitesValue = resourceSites
        boundaryLeakSitesValue = boundaryLeakSites
        hotReadinessSitesValue = hotReadinessSites
        implicitTrapSitesValue = implicitTrapSites
        trustedSitesValue = trustedSites
    }
}
