namespace NSharpLang.DaemonExec.Tests

// A RETAINED SESSION ANSWERS AS A FRESH PROCESS DOES, WHATEVER IT LOADED BEFORE.
//
// The workspace server keeps its analyzer between commands, and the analyzer's assembly list only
// grows: a `Microsoft.NETCore.App` assembly a previous command loaded for `import System.Numerics`
// is still loaded after the import is deleted. Such an assembly answers only through its own
// namespace (`FrameworkOnDemandLoads`), so a bare `BigInteger` with the import gone must be the same
// "not found" through the server as in a new process -- not a type the session happens to remember.
func FrameworkHistoryQualified(): string {
    return "namespace DaemonExecProbe\n\nfunc Seed(): System.Numerics.BigInteger {\n    return System.Numerics.BigInteger.One\n}\n"
}

func FrameworkHistoryImported(): string {
    return "namespace DaemonExecProbe\n\nimport System.Numerics\n\nfunc main() {\n    total: BigInteger = Seed()\n    print total.ToString()\n}\n"
}

func FrameworkHistoryImportRemoved(): string {
    return "namespace DaemonExecProbe\n\nfunc main() {\n    total: BigInteger = Seed()\n    print total.ToString()\n}\n"
}

test "a removed framework import is reported the same through a warm server as in a new process" {
    workspace := NewWorkspace()
    try {
        WriteSource(workspace, "Seed.nl", FrameworkHistoryQualified())
        WriteSource(workspace, "Program.nl", FrameworkHistoryImported())
        StartServer(workspace)
        _ = AssertParity(workspace, ["check", "--json"], null)

        WriteSource(workspace, "Program.nl", FrameworkHistoryImportRemoved())
        trace := AssertParity(workspace, ["check", "--json"], null)
        assert RoutedThroughServer(trace), trace
        fresh := NlcWith(["check", "--json"], workspace, InProcess(), null)
        assert fresh.ExitCode != 0, fresh.Stdout
        assert fresh.Stdout.Contains("BigInteger"), fresh.Stdout
    } finally {
        DeleteWorkspace(workspace)
    }
}
