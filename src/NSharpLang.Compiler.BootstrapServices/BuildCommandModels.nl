namespace NSharpLang.Cli

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
