namespace NSharpLang.Cli

import System.Collections.Generic
import System.Text

public class CommandRegistry {
    public static TopLevelCommands: IReadOnlyList<CliCommandSpec> => BuildTopLevelCommands()
    public static QueryCommands: IReadOnlyList<CliCommandSpec> => BuildQueryCommands()

    public static func JoinCommandNames(commands: IEnumerable<CliCommandSpec>): string {
        builder := new StringBuilder()
        first := true

        foreach command in commands {
            if first {
                first = false
            } else {
                builder.Append(" ")
            }

            builder.Append(command.Name)
        }

        return builder.ToString()
    }

    static func BuildTopLevelCommands(): CliCommandSpec[] {
        commands := new CliCommandSpec[](27)
        commands[0] = new CliCommandSpec("build", "Compile a project or single .nl file")
        commands[1] = new CliCommandSpec("run", "Build and run a project or single file")
        commands[2] = new CliCommandSpec("new", "Create a new N# project")
        commands[3] = new CliCommandSpec("init", "Initialize N# in the current directory")
        commands[4] = new CliCommandSpec("test", "Run .tests.nl test suites")
        commands[5] = new CliCommandSpec("format", "Format .nl source files")
        commands[6] = new CliCommandSpec("lint", "Run static analysis rules")
        commands[7] = new CliCommandSpec("clean", "Remove build artifacts")
        commands[8] = new CliCommandSpec("watch", "Re-run commands on file changes")
        commands[9] = new CliCommandSpec("doc", "Generate HTML API documentation")
        commands[10] = new CliCommandSpec("completion", "Generate shell completion scripts")
        commands[11] = new CliCommandSpec("check", "Fast type-check")
        commands[12] = new CliCommandSpec("fix", "Auto-apply compiler suggestions")
        commands[13] = new CliCommandSpec("query", "Code intelligence for LLMs and terminals")
        commands[14] = new CliCommandSpec("daemon", "Background analysis daemon")
        commands[15] = new CliCommandSpec("add", "Add a NuGet dependency to project.yml")
        commands[16] = new CliCommandSpec("tidy", "Identify and remove unused dependencies")
        commands[17] = new CliCommandSpec("remove", "Remove a dependency from project.yml")
        commands[18] = new CliCommandSpec("update", "Update dependencies")
        commands[19] = new CliCommandSpec("publish", "Publish project for deployment")
        commands[20] = new CliCommandSpec("tree", "Show dependency tree")
        commands[21] = new CliCommandSpec("audit", "Check dependencies for known vulnerabilities")
        commands[22] = new CliCommandSpec("env", "Show environment and toolchain info")
        commands[23] = new CliCommandSpec("doctor", "Verify N# CLI, SDK/templates, LSP, and VS Code tooling")
        commands[24] = new CliCommandSpec("restore", "Generate MSBuild compatibility config from project.yml")
        commands[25] = new CliCommandSpec("pack", "Create a NuGet package from project.yml metadata")
        commands[26] = new CliCommandSpec("help", "Show help")
        return commands
    }

    static func BuildQueryCommands(): CliCommandSpec[] {
        commands := new CliCommandSpec[](19)
        commands[0] = new CliCommandSpec("batch", "Execute multiple query requests from one JSON file")
        commands[1] = new CliCommandSpec("symbols", "List all symbols in a file or project")
        commands[2] = new CliCommandSpec("outline", "Structural outline of a file")
        commands[3] = new CliCommandSpec("ast", "Full parsed AST as stable JSON (whole project or --file)")
        commands[4] = new CliCommandSpec("diagnostics", "Errors and warnings with rich context")
        commands[5] = new CliCommandSpec("type", "Get type info at a position")
        commands[6] = new CliCommandSpec("inspect", "One-shot symbol/type/refs/completions bundle")
        commands[7] = new CliCommandSpec("definition", "Find where a symbol is defined")
        commands[8] = new CliCommandSpec("def", "Alias for definition", "definition")
        commands[9] = new CliCommandSpec("references", "Find all references to a symbol")
        commands[10] = new CliCommandSpec("refs", "Alias for references", "references")
        commands[11] = new CliCommandSpec("completions", "Get completions at a position")
        commands[12] = new CliCommandSpec("doc", "Look up .NET API documentation")
        commands[13] = new CliCommandSpec("hover", "Signature + docs at a position")
        commands[14] = new CliCommandSpec("call-graph", "Callers and callees of a function")
        commands[15] = new CliCommandSpec("implementors", "Concrete types implementing an interface")
        commands[16] = new CliCommandSpec("perf", "Explain allocation/dispatch/capture/ABI facts at a position")
        commands[17] = new CliCommandSpec("trusted", "List governed Systems N# trusted wrappers")
        commands[18] = new CliCommandSpec("help", "Show query help")
        return commands
    }
}
