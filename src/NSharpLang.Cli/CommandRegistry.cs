using System;
using System.Collections.Generic;
using System.Linq;

namespace NSharpLang.Cli;

public sealed record CliCommandSpec(string Name, string Description, string? AliasOf = null)
{
    public bool IsAlias => AliasOf is not null;
}

public static class CommandRegistry
{
    public static readonly IReadOnlyList<CliCommandSpec> TopLevelCommands = new[]
    {
        new CliCommandSpec("build", "Compile a project or single .nl file"),
        new CliCommandSpec("run", "Build and run a project or single file"),
        new CliCommandSpec("new", "Create a new N# project"),
        new CliCommandSpec("init", "Initialize N# in the current directory"),
        new CliCommandSpec("test", "Run .tests.nl test suites"),
        new CliCommandSpec("format", "Format .nl source files"),
        new CliCommandSpec("lint", "Run static analysis rules"),
        new CliCommandSpec("bench", "Run benchmarks"),
        new CliCommandSpec("clean", "Remove build artifacts"),
        new CliCommandSpec("watch", "Re-run commands on file changes"),
        new CliCommandSpec("doc", "Generate HTML API documentation"),
        new CliCommandSpec("completion", "Generate shell completion scripts"),
        new CliCommandSpec("check", "Fast type-check"),
        new CliCommandSpec("fix", "Auto-apply compiler suggestions"),
        new CliCommandSpec("query", "Code intelligence for LLMs and terminals"),
        new CliCommandSpec("daemon", "Background analysis daemon"),
        new CliCommandSpec("add", "Add a NuGet dependency to project.yml"),
        new CliCommandSpec("tidy", "Identify and remove unused dependencies"),
        new CliCommandSpec("remove", "Remove a dependency from project.yml"),
        new CliCommandSpec("update", "Update dependencies"),
        new CliCommandSpec("publish", "Publish project for deployment"),
        new CliCommandSpec("export", "Export N# sources without changing the IL toolchain"),
        new CliCommandSpec("tree", "Show dependency tree"),
        new CliCommandSpec("audit", "Check dependencies for known vulnerabilities"),
        new CliCommandSpec("env", "Show environment and toolchain info"),
        new CliCommandSpec("doctor", "Verify N# CLI, SDK/templates, LSP, and VS Code tooling"),
        new CliCommandSpec("restore", "Generate MSBuild compatibility config from project.yml"),
        new CliCommandSpec("pack", "Create a NuGet package from project.yml metadata"),
        new CliCommandSpec("help", "Show help")
    };

    public static readonly IReadOnlyList<CliCommandSpec> QueryCommands = new[]
    {
        new CliCommandSpec("batch", "Execute multiple query requests from one JSON file"),
        new CliCommandSpec("symbols", "List all symbols in a file or project"),
        new CliCommandSpec("outline", "Structural outline of a file"),
        new CliCommandSpec("diagnostics", "Errors and warnings with rich context"),
        new CliCommandSpec("type", "Get type info at a position"),
        new CliCommandSpec("inspect", "One-shot symbol/type/refs/completions bundle"),
        new CliCommandSpec("definition", "Find where a symbol is defined"),
        new CliCommandSpec("def", "Alias for definition", AliasOf: "definition"),
        new CliCommandSpec("references", "Find all references to a symbol"),
        new CliCommandSpec("refs", "Alias for references", AliasOf: "references"),
        new CliCommandSpec("completions", "Get completions at a position"),
        new CliCommandSpec("doc", "Look up .NET API documentation"),
        new CliCommandSpec("hover", "Signature + docs at a position"),
        new CliCommandSpec("call-graph", "Callers and callees of a function"),
        new CliCommandSpec("implementors", "Concrete types implementing an interface"),
        new CliCommandSpec("perf", "Explain allocation/dispatch/capture/ABI facts at a position"),
        new CliCommandSpec("help", "Show query help")
    };

    public static string JoinCommandNames(IEnumerable<CliCommandSpec> commands)
        => string.Join(" ", commands.Select(command => command.Name));
}
