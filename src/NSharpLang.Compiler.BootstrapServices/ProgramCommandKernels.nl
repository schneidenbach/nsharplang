namespace NSharpLang.Cli

public class ProgramCommandKernels {
    public static func GetCommandKind(args: string[]): int {
        if args.Length == 0 {
            return 29
        }

        command := args[0]
        if CommandEquals(command, "build") {
            return 1
        }

        if CommandEquals(command, "run") {
            return 2
        }

        if CommandEquals(command, "publish") {
            return 3
        }

        if CommandEquals(command, "new") {
            return 4
        }

        if CommandEquals(command, "test") {
            return 5
        }

        if CommandEquals(command, "format") {
            return 6
        }

        if CommandEquals(command, "lint") {
            return 7
        }

        if CommandEquals(command, "restore") {
            return 8
        }

        if CommandEquals(command, "clean") {
            return 9
        }

        if CommandEquals(command, "watch") {
            return 10
        }

        if CommandEquals(command, "doc") {
            return 11
        }

        if CommandEquals(command, "completion") {
            return 12
        }

        if CommandEquals(command, "check") {
            return 13
        }

        if CommandEquals(command, "fix") {
            return 14
        }

        if CommandEquals(command, "query") {
            return 15
        }

        if CommandEquals(command, "daemon") {
            return 16
        }

        if CommandEquals(command, "add") {
            return 17
        }

        if CommandEquals(command, "tidy") {
            return 18
        }

        if CommandEquals(command, "remove") {
            return 19
        }

        if CommandEquals(command, "update") {
            return 20
        }

        if CommandEquals(command, "init") {
            return 21
        }

        if CommandEquals(command, "env") {
            return 22
        }

        if CommandEquals(command, "doctor") {
            return 23
        }

        if CommandEquals(command, "tree") {
            return 24
        }

        if CommandEquals(command, "audit") {
            return 25
        }

        if CommandEquals(command, "pack") {
            return 26
        }

        if CommandEquals(command, "help")
            || CommandEquals(command, "--help")
            || CommandEquals(command, "-h") {
            return 29
        }

        if CommandEquals(command, "--version") || command == "-V" {
            return 30
        }

        return 0
    }

    public static func GetVersionText(version: string): string {
        return "nlc " + version
    }

    public static func GetHelpText(version: string): string {
        return "N# Compiler (nlc) " + version + "\n"
            + "\n"
            + "Usage: nlc <command> [options]\n"
            + "\n"
            + "Build & Run:\n"
            + "  build [file]         Compile a project or single .nl file (--release, --verbose)\n"
            + "  run [file]           Build and run a project or single file\n"
            + "  restore              Generate MSBuild compatibility config from project.yml\n"
            + "  publish              Publish project for deployment\n"
            + "  pack                 Create a NuGet package from project.yml metadata\n"
            + "  clean                Remove build artifacts\n"
            + "\n"
            + "Analysis & Fix:\n"
            + "  check                Fast type-check (JSON by default)\n"
            + "  fix                  Auto-apply compiler suggestions\n"
            + "  query <cmd>          Code intelligence for LLMs and terminals\n"
            + "  daemon <cmd>         Background analysis daemon\n"
            + "Code Quality:\n"
            + "  format [files...]    Format .nl source files\n"
            + "  lint [files...]      Run static analysis rules\n"
            + "  test                 Run .tests.nl test suites (--filter, --verbose)\n"
            + "\n"
            + "Dependencies:\n"
            + "  add <package>        Add a NuGet dependency to project.yml\n"
            + "  tidy                 Identify and remove unused dependencies\n"
            + "  remove <package>     Remove a dependency from project.yml\n"
            + "  update [package]     Update dependencies to latest versions\n"
            + "  tree                 Show dependency tree\n"
            + "  audit                Check for known vulnerabilities\n"
            + "\n"
            + "Project:\n"
            + "  new <name>           Create a new N# project\n"
            + "  init                 Initialize N# in the current directory\n"
            + "  watch <cmd>          Re-run check/build/test/lint/format on file changes\n"
            + "  doc                  Generate HTML API documentation\n"
            + "  env                  Show environment and toolchain info\n"
            + "  doctor               Verify N# CLI, SDK/templates, LSP, and VS Code tooling\n"
            + "  completion <shell>   Generate shell completion scripts\n"
            + "Options:\n"
            + "  --version, -V        Show nlc version\n"
            + "  --text               Human-readable output for check/fix/query/lint\n"
            + "  --json               Structured JSON output (default for check/fix/query/lint)\n"
            + "  --help, -h           Show this help message\n"
            + "\n"
            + "Common Workflows:\n"
            + "  nlc new MyApp && cd MyApp    Create and enter a new project\n"
            + "  nlc build                    Compile the project\n"
            + "  nlc run                      Build and run\n"
            + "  nlc test                     Run tests\n"
            + "  nlc add Serilog@3.1.0        Add a dependency\n"
            + "  nlc check                    Fast feedback loop\n"
            + "  nlc doctor                   Verify the installed toolchain\n"
            + "  nlc fix && nlc check         Auto-fix then verify\n"
            + "  nlc build --release          Release configuration/output layout\n"
            + "  nlc format --check           CI formatting gate\n"
            + "  nlc test --filter AddPerson  Run specific tests\n"
            + "  nlc watch check              Re-check on every save\n"
            + "  nlc publish -c Release       Publish for deployment\n"
            + "\n"
            + "Run 'nlc <command> --help' for command-specific options."
    }

    public static func GetUnknownCommandMessage(command: string): string {
        return "Unknown command: " + command + ". Run 'nlc help' to see available commands."
    }

    public static func GetErrorLine(message: string): string {
        return "Error: " + message
    }

    public static func FormatElapsedMilliseconds(elapsedMilliseconds: long): string {
        if elapsedMilliseconds >= 60000 {
            minutes := elapsedMilliseconds / 60000
            seconds := (elapsedMilliseconds / 1000) - minutes * 60
            secondsText := seconds.ToString()
            if seconds < 10 {
                secondsText = "0" + secondsText
            }

            return minutes.ToString() + "m " + secondsText + "s"
        }

        tenths := (elapsedMilliseconds + 50) / 100
        whole := tenths / 10
        fraction := tenths - whole * 10
        return whole.ToString() + "." + fraction.ToString() + "s"
    }

    static func CommandEquals(command: string, expected: string): bool {
        return String.Compare(command, expected, StringComparison.OrdinalIgnoreCase) == 0
    }
}
