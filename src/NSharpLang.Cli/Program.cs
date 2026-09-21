using System.Reflection;

namespace NSharpLang.Cli;

// THE ENTRY POINT, AND NOTHING ELSE.
//
// Dispatch, every command and the watch loop are N#: `CliPipeline.Execute` in
// `NSharpLang.TestHost`. What cannot move is the version read. `nlc --version` and the help header
// must report THIS assembly's `AssemblyInformationalVersion` — the gate greps that string for build
// provenance — and `typeof(Program).Assembly` is the only spelling that names `Cli.dll` from inside
// `Cli.dll`. So the version is read here and handed to the pipeline as a value.
partial class Program
{
    static int Main(string[] args)
        => InternalErrorBoundary.Execute(() => CliPipeline.Execute(args, GetVersion()));

    internal static string GetVersion()
    {
        return typeof(Program).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()
            ?.InformationalVersion
            ?? typeof(Program).Assembly.GetName().Version?.ToString()
            ?? "unknown";
    }
}
