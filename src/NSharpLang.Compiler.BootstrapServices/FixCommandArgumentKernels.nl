namespace NSharpLang.Cli.Commands

public class FixArgumentSummary {
    ProjectOption: string?
    FileOption: string?
    PositionalProject: string?
    DryRun: bool
    UseText: bool
    IncludeReviewNeeded: bool
    ShowHelp: bool

    constructor(
        projectOption: string?,
        fileOption: string?,
        positionalProject: string?,
        dryRun: bool,
        useText: bool,
        includeReviewNeeded: bool,
        showHelp: bool) {
        ProjectOption = projectOption
        FileOption = fileOption
        PositionalProject = positionalProject
        DryRun = dryRun
        UseText = useText
        IncludeReviewNeeded = includeReviewNeeded
        ShowHelp = showHelp
    }
}

public class FixCommandArgumentKernels {
    public static func GetArgumentSummary(args: string[]): FixArgumentSummary {
        projectOption: string? = null
        fileOption: string? = null
        positionalProject: string? = null
        dryRun := false
        useText := false
        includeReviewNeeded := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            kind := GetArgumentKind(arg)

            if i == 0 && arg == "help" {
                showHelp = true
            }

            if kind == 1 {
                if projectOption == null && i + 1 < args.Length {
                    projectOption = args[i + 1]
                }
            } else if kind == 2 {
                if fileOption == null && i + 1 < args.Length {
                    fileOption = args[i + 1]
                }
            } else if kind == 3 {
                dryRun = true
            } else if kind == 4 {
                useText = true
            } else if kind == 5 {
                includeReviewNeeded = true
            } else if kind == 6 {
                showHelp = true
            }

            i = i + 1
        }

        i = 0
        while i < args.Length {
            arg := args[i]
            kind := GetArgumentKind(arg)
            if kind == 1 || kind == 2 {
                if i + 1 < args.Length {
                    i = i + 2
                } else {
                    i = i + 1
                }

                continue
            }

            if arg.Length == 0 || arg[0] != '-' {
                positionalProject = arg
                break
            }

            i = i + 1
        }

        return new FixArgumentSummary(
            projectOption,
            fileOption,
            positionalProject,
            dryRun,
            useText,
            includeReviewNeeded,
            showHelp)
    }

    public static func GetEffectiveOutputMode(useText: bool): int {
        if useText {
            return 2
        }

        return 1
    }

    static func GetArgumentKind(arg: string): int {
        if arg == "--project" {
            return 1
        }

        if arg == "--file" {
            return 2
        }

        if arg == "--dry-run" {
            return 3
        }

        if arg == "--text" {
            return 4
        }

        if arg == "--include-review-needed" {
            return 5
        }

        if arg == "--help" || arg == "-h" {
            return 6
        }

        return 0
    }
}
