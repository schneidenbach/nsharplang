using System;

namespace NSharpLang.Cli;

internal enum ProgramCommandKind
{
    Unknown = 0,
    Build = 1,
    Run = 2,
    Publish = 3,
    New = 4,
    Test = 5,
    Format = 6,
    Lint = 7,
    Restore = 8,
    Clean = 9,
    Watch = 10,
    Doc = 11,
    Completion = 12,
    Check = 13,
    Fix = 14,
    Query = 15,
    Daemon = 16,
    Add = 17,
    Tidy = 18,
    Remove = 19,
    Update = 20,
    Init = 21,
    Env = 22,
    Doctor = 23,
    Tree = 24,
    Audit = 25,
    Pack = 26,
    Export = 27,
    Help = 29,
    Version = 30,
    Transpile = 31
}

internal static class ProgramCommandKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static bool TryGetCommandKind(string[] args, out ProgramCommandKind commandKind)
    {
        commandKind = ProgramCommandKind.Unknown;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            var value = bindings.CommandKind(args);
            if (!Enum.IsDefined(typeof(ProgramCommandKind), value))
                return false;

            commandKind = (ProgramCommandKind)value;
            return true;
        }
        catch
        {
            commandKind = ProgramCommandKind.Unknown;
            return false;
        }
    }

    internal static string GetVersionText(string version)
    {
        if (TryGetMessage(bindings => bindings.ProgramVersionText(version), out var message))
            return message;

        return GetVersionTextWithCSharp(version);
    }

    internal static string GetHelpText(string version)
    {
        if (TryGetMessage(bindings => bindings.ProgramHelpText(version), out var message))
            return message;

        return GetHelpTextWithCSharp(version);
    }

    internal static string GetTranspileRemovedMessage()
    {
        if (TryGetMessage(bindings => bindings.ProgramTranspileRemovedMessage(), out var message))
            return message;

        return GetTranspileRemovedMessageWithCSharp();
    }

    internal static string GetUnknownCommandMessage(string command)
    {
        if (TryGetMessage(bindings => bindings.ProgramUnknownCommandMessage(command), out var message))
            return message;

        return GetUnknownCommandMessageWithCSharp(command);
    }

    private static bool TryGetMessage(Func<Bindings, string> getMessage, out string message)
    {
        message = string.Empty;

        var bindings = s_bindings.Value;
        if (bindings == null)
            return false;

        try
        {
            message = getMessage(bindings);
            return !string.IsNullOrEmpty(message);
        }
        catch
        {
            message = string.Empty;
            return false;
        }
    }

    // Stage 6 C#-surface-shrink: fallback/oracle only; product top-level text routes through CliProgram* kernels.
    private static string GetVersionTextWithCSharp(string version)
        => $"nlc {version}";

    private static string GetHelpTextWithCSharp(string version)
        => $"N# Compiler (nlc) {version}\n"
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
           + "  export <target>      Export N# sources without changing the IL toolchain\n"
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
           + "  nlc export csharp --project . -o ./myapp-csharp\n"
           + "                               Export C# for inspection\n"
           + "  nlc format --check           CI formatting gate\n"
           + "  nlc test --filter AddPerson  Run specific tests\n"
           + "  nlc watch check              Re-check on every save\n"
           + "  nlc publish -c Release       Publish for deployment\n"
           + "\n"
           + "Run 'nlc <command> --help' for command-specific options.";

    private static string GetTranspileRemovedMessageWithCSharp()
        => "The 'transpile' command has been removed. Use 'nlc export csharp' instead.";

    private static string GetUnknownCommandMessageWithCSharp(string command)
        => $"Unknown command: {command}. Run 'nlc help' to see available commands.";

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<CliProgramCommandKind>(
                programType,
                "CliProgramCommandKind"),
            DogfoodKernelLoader.CreateDelegate<CliProgramVersionText>(
                programType,
                "CliProgramVersionText"),
            DogfoodKernelLoader.CreateDelegate<CliProgramHelpText>(
                programType,
                "CliProgramHelpText"),
            DogfoodKernelLoader.CreateDelegate<CliProgramTranspileRemovedMessage>(
                programType,
                "CliProgramTranspileRemovedMessage"),
            DogfoodKernelLoader.CreateDelegate<CliProgramUnknownCommandMessage>(
                programType,
                "CliProgramUnknownCommandMessage")));

    private delegate int CliProgramCommandKind(string[] args);
    private delegate string CliProgramVersionText(string version);
    private delegate string CliProgramHelpText(string version);
    private delegate string CliProgramTranspileRemovedMessage();
    private delegate string CliProgramUnknownCommandMessage(string command);

    private sealed record Bindings(
        CliProgramCommandKind CommandKind,
        CliProgramVersionText ProgramVersionText,
        CliProgramHelpText ProgramHelpText,
        CliProgramTranspileRemovedMessage ProgramTranspileRemovedMessage,
        CliProgramUnknownCommandMessage ProgramUnknownCommandMessage);
}
