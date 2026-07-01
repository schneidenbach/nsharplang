namespace NSharpLang.Cli.Commands

public class EnvOptionSummary {
    Json: bool
    ShowHelp: bool

    constructor(json: bool, showHelp: bool) {
        Json = json
        ShowHelp = showHelp
    }
}

public class EnvCommandKernels {
    public static func GetOptionSummary(args: string[]): EnvOptionSummary {
        json := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            if arg == "--json" {
                json = true
            } else if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            i = i + 1
        }

        return new EnvOptionSummary(json, showHelp)
    }

    public static func GetOutputMode(json: bool): int {
        if json {
            return 1
        }

        return 2
    }

    public static func GetHelpText(): string {
        return "N# Environment Info\n"
            + "\n"
            + "Usage: nlc env [options]\n"
            + "\n"
            + "Show toolchain and environment information.\n"
            + "\n"
            + "Options:\n"
            + "  --json          Output as JSON envelope\n"
            + "  --help, -h      Show this help text\n"
            + "\n"
            + "Examples:\n"
            + "  nlc env\n"
            + "  nlc env --json\n"
            + "\n"
            + "Exit codes:\n"
            + "  0  Always succeeds"
    }

    public static func GetTextLine(kind: int, value: string): string {
        if kind == 1 {
            return "nlc version:    " + value
        }

        if kind == 2 {
            return "dotnet version: " + value
        }

        if kind == 3 {
            return "runtime:        " + value
        }

        if kind == 4 {
            return "os:             " + value
        }

        if kind == 5 {
            return "arch:           " + value
        }

        if kind == 6 {
            return "nuget cache:    " + value
        }

        if kind == 7 {
            return "nsharp bin:     " + value
        }

        if kind == 8 {
            return "nsharp packages: " + value
        }

        if kind == 9 {
            return "project:        " + value
        }

        if kind == 10 {
            return "target:         " + value
        }

        if kind == 11 {
            return "output type:    " + value
        }

        if kind == 12 {
            return "sdk:            " + value
        }

        return ""
    }
}
