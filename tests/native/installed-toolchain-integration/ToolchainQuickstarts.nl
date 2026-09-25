namespace NSharpLang.InstalledToolchainIntegration.Tests

import System
import System.Collections.Generic
import System.IO
import System.Text.RegularExpressions

// ─── THE QUICKSTARTS IN `templates/README.md`, READ AS A CONTRACT ──────────────────────────────
//
// `TemplateQuickstartDocs_ReplaySuccessfully` was the largest of the deleted rows and the only one
// whose INPUT is a shipped document: each `<!-- quickstart:<name> -->` block in `templates/README.md`
// is a `bash` fence, and the row replays every command in it inside the container. A documented first
// command that no longer works is a defect a user meets before anything else, which is why the
// document is parsed rather than paraphrased.
//
// THE PARSE AND THE REWRITES ARE SEPARATED FROM THE REPLAY ON PURPOSE. Reading the document, pinning
// the six names, rewriting `MyApp` into a unique directory, tracking `cd` across commands and wrapping
// the web-API `nlc run` in a poll-and-kill script are all HOST-SIDE decisions that need no daemon. A
// machine with no Docker still holds every one of them to a row (`ToolchainCommandContracts.tests.nl`),
// and only the replay itself is gated.
class TemplateQuickstart {
    Name: string
    Commands: List<string>

    constructor(name: string, commands: List<string>) {
        Name = name
        Commands = commands
    }
}

func TemplateQuickstartDocsPath(): string {
    return Path.Combine(Path.Combine(ToolchainRepositoryRoot(), "templates"), "README.md")
}

// The deleted `ReadTemplateQuickstarts` regex, unchanged, including `RegexOptions.Singleline` so a
// fence body spans lines: an HTML comment naming the quickstart, then the ```bash fence that follows
// it. Blank lines and `#` comment lines are dropped, everything else is a command in source order.
func ReadTemplateQuickstarts(markdown: string): List<TemplateQuickstart> {
    quickstarts := new List<TemplateQuickstart>()
    matches := Regex.Matches(
        markdown,
        "<!--\\s*quickstart:(?<name>[a-z0-9-]+)\\s*-->\\s*```bash\\s*(?<commands>.*?)\\s*```",
        RegexOptions.Singleline
    )

    matchIndex := 0
    while matchIndex < matches.Count {
        // The group values are hoisted into locals rather than passed inline: a group-indexer chain
        // in the ARGUMENT of an otherwise-modeled static call declines at emit (NL103,
        // `emit.call.static-member-unmodeled`), and a local is the documented way past it. Nothing
        // about the claim changes.
        name: string = matches[matchIndex].Groups["name"].Value
        body: string = matches[matchIndex].Groups["commands"].Value
        lines := body.Split('\n')
        commands := new List<string>()
        lineIndex := 0
        while lineIndex < lines.Length {
            line := lines[lineIndex].Trim()
            if line.Length > 0 && !line.StartsWith("#") {
                commands.Add(line)
            }

            lineIndex = lineIndex + 1
        }

        quickstarts.Add(new TemplateQuickstart(name, commands))
        matchIndex = matchIndex + 1
    }

    return quickstarts
}

func ReadTemplateQuickstartsFromDocs(): List<TemplateQuickstart> {
    return ReadTemplateQuickstarts(File.ReadAllText(TemplateQuickstartDocsPath()))
}

func TemplateQuickstartNamesSorted(quickstarts: List<TemplateQuickstart>): List<string> {
    names := new List<string>()
    index := 0
    while index < quickstarts.Count {
        names.Add(quickstarts[index].Name)
        index = index + 1
    }

    names.Sort(StringComparer.Ordinal)
    return names
}

// EVERY PLACE THE DOCUMENT NAMES A DIRECTORY, POINTED AT A UNIQUE ONE. `-o MyApp` and the `cd` that
// follows it both become the scratch directory, and the bare project names the other commands use
// (`MyApp`, `MyLib`, `MyTests`, `MyApi`) become its leaf. A replay that used the documented name
// would collide with the previous quickstart inside one shared container.
func RewriteProjectName(commands: List<string>, projectDirectory: string): List<string> {
    projectName := Path.GetFileName(projectDirectory) ?? ""
    rewritten := new List<string>()
    index := 0
    while index < commands.Count {
        command := Regex.Replace(commands[index], "\\s-o\\s+\\S+", " -o " + projectDirectory)
        command = Regex.Replace(command, "^cd\\s+\\S+$", "cd " + projectDirectory)
        command = command.Replace(" MyApp", " " + projectName)
        command = command.Replace(" MyLib", " " + projectName)
        command = command.Replace(" MyTests", " " + projectName)
        command = command.Replace(" MyApi", " " + projectName)
        rewritten.Add(command)
        index = index + 1
    }

    return rewritten
}

// Each command runs in its own `bash -c`, so a `cd` in the document does not survive to the next one.
// The working directory is therefore tracked HERE and prefixed onto the next command, which is what
// makes `cd MyApp` followed by `nlc build` mean what the document says it means.
func ApplyCd(workingDirectory: string, command: string): string {
    if !command.StartsWith("cd ") {
        return workingDirectory
    }

    destination := command.Substring(3).Trim()
    if destination.StartsWith("/") {
        return destination
    }

    return workingDirectory.TrimEnd('/') + "/" + destination
}

// THE ONE COMMAND THAT NEVER RETURNS. The web-API quickstart's last line starts a Kestrel server, so
// replaying it verbatim would hang the row until the ceiling. It is wrapped in a script that starts
// the server in the background, polls `/api/weather` for twenty seconds, and then:
//
//   * a response ⇒ kill the server, print the body, exit 0 — the row passes ONLY if the running app
//     actually served the documented route;
//   * the server died ⇒ print its log and exit 1;
//   * twenty seconds with neither ⇒ print the log, kill it, exit 1.
//
// So "it started" is never mistaken for "it works", and no branch leaves the server behind.
func ReplayCommand(command: string): string {
    if !command.StartsWith("ASPNETCORE_URLS=") || !command.EndsWith(" nlc run") {
        return command
    }

    escaped := command.Replace("'", "'\\''")
    return "bash -c 'set -e; " + escaped + " > /tmp/nsharp-webapi-quickstart.log 2>&1 & pid=$!; " + "for i in $(seq 1 40); do " + "if curl -fsS http://127.0.0.1:5050/api/weather >/tmp/nsharp-webapi-quickstart-response.txt 2>/dev/null; then " + "kill $pid; wait $pid 2>/dev/null || true; cat /tmp/nsharp-webapi-quickstart-response.txt; exit 0; " + "fi; " + "if ! kill -0 $pid 2>/dev/null; then cat /tmp/nsharp-webapi-quickstart.log; exit 1; fi; " + "sleep 0.5; " + "done; " + "cat /tmp/nsharp-webapi-quickstart.log; kill $pid 2>/dev/null || true; exit 1'"
}
