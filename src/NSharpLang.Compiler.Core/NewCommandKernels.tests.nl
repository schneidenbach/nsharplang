namespace NSharpLang.Cli

import NSharpLang.Compiler

// THE `nlc new` ARGUMENT, TEMPLATE-RESOLUTION, MESSAGE AND FILE-TEXT KERNELS.
//
// These blocks replace ONE `[Fact]` deleted from `tests/CliCommandTests.cs`:
// `NewCommandKernels_SummarizesArguments`, which at 163 declaration lines and 72 `Assert.` rows was
// the largest single body left in that file. It is pure — every argument is a literal and every
// answer is a value — so the whole of it is here, with no console capture and no split.
//
// FIVE CONTROLS THE DELETED BODY DID NOT HAVE ARE ADDED, AND EACH IS NAMED WHERE IT SITS:
// `--template` beating `--type`, `--template` taking its FIRST occurrence, the bare word `help`
// being positional after index 0, the four `ShouldShow*` predicates read directly, and the
// `GetEffectiveProjectName` / `GetEffectiveRequestedTemplate` pair that is the actual policy behind
// `nlc new systems-cli PacketTool`.

// ── the argument summary ──────────────────────────────────────────────────────
test "the new argument summary reads the template option, the systems flag and the help flag" {
    summary := NewCommandKernels.GetArgumentSummary(["--template", "library", "--systems", "PacketCore", "-h"])

    assert summary.FirstPositional == "PacketCore"
    assert summary.SecondPositional == null
    assert summary.TemplateOption == "library"
    assert summary.Systems
    assert summary.ShowHelp
}

test "two bare words are the positional template and the positional project name" {
    summary := NewCommandKernels.GetArgumentSummary(["systems-cli", "PacketTool"])

    assert summary.FirstPositional == "systems-cli"
    assert summary.SecondPositional == "PacketTool"
    assert summary.TemplateOption == null
    assert !summary.Systems
    assert !summary.ShowHelp
}

test "--type is an alias for --template" {
    summary := NewCommandKernels.GetArgumentSummary(["--type", "webapi", "MyApi"])

    assert summary.TemplateOption == "webapi"
    assert summary.FirstPositional == "MyApi"
    assert summary.SecondPositional == null
}

test "--template WINS over --type when both are given" {
    // A CONTROL THE DELETED BODY DID NOT HAVE. It asked for each alias separately, so a parser that
    // let the LAST one win, or that ignored `--template` entirely, would have passed it. The
    // production rule reads both and then overwrites the `--type` answer with `--template`.
    summary := NewCommandKernels.GetArgumentSummary(["--type", "webapi", "--template", "library", "MyThing"])

    assert summary.TemplateOption == "library"
    assert summary.FirstPositional == "MyThing"
}

test "--template takes its FIRST occurrence, not its last" {
    // A CONTROL THE DELETED BODY DID NOT HAVE. Repeating the option is accepted and the first value
    // stands; neither value's position is a positional argument.
    summary := NewCommandKernels.GetArgumentSummary(["--template", "library", "--template", "webapi", "MyThing"])

    assert summary.TemplateOption == "library"
    assert summary.FirstPositional == "MyThing"
    assert summary.SecondPositional == null
}

test "the bare word help asks for help only at index 0, and is a positional anywhere else" {
    // A CONTROL THE DELETED BODY DID NOT HAVE. It asserted only that `["help"]` shows help. The
    // production rule is `i == 0 && arg == "help"`, so a project literally named `help` created as
    // `nlc new MyApp help` does NOT trigger the help screen — and `help` is still counted as a
    // positional in BOTH placements, which is why `["help"]` also reports it as the first one.
    atStart := NewCommandKernels.GetArgumentSummary(["help"])
    assert atStart.ShowHelp
    assert atStart.FirstPositional == "help"

    later := NewCommandKernels.GetArgumentSummary(["MyApp", "help"])
    assert !later.ShowHelp
    assert later.FirstPositional == "MyApp"
    assert later.SecondPositional == "help"
}

test "a value-less flag is never mistaken for a positional" {
    // `--systems` is in the value-less set, so the word after it stays the FIRST positional rather
    // than sliding into second place.
    summary := NewCommandKernels.GetArgumentSummary(["--systems", "PacketCore"])

    assert summary.Systems
    assert summary.FirstPositional == "PacketCore"
    assert summary.SecondPositional == null
}

// ── the template-kind normaliser ──────────────────────────────────────────────

test "the template normaliser trims, ignores case, and accepts every documented alias" {
    assert NewCommandKernels.NormalizeTemplateKind(" LIB ") == NewProjectTemplateKind.Library
    assert NewCommandKernels.NormalizeTemplateKind("library") == NewProjectTemplateKind.Library
    assert NewCommandKernels.NormalizeTemplateKind("web-api") == NewProjectTemplateKind.WebApi
    assert NewCommandKernels.NormalizeTemplateKind("webapi") == NewProjectTemplateKind.WebApi
    assert NewCommandKernels.NormalizeTemplateKind("web") == NewProjectTemplateKind.WebApi
    assert NewCommandKernels.NormalizeTemplateKind("systems") == NewProjectTemplateKind.SystemsCli
    assert NewCommandKernels.NormalizeTemplateKind("systems-console") == NewProjectTemplateKind.SystemsCli
    assert NewCommandKernels.NormalizeTemplateKind("systems-library") == NewProjectTemplateKind.SystemsLib
    assert NewCommandKernels.NormalizeTemplateKind("console") == NewProjectTemplateKind.Console
    assert NewCommandKernels.NormalizeTemplateKind("exe") == NewProjectTemplateKind.Console
    assert NewCommandKernels.NormalizeTemplateKind("app") == NewProjectTemplateKind.Console
    assert NewCommandKernels.NormalizeTemplateKind("tests") == NewProjectTemplateKind.Test
    assert NewCommandKernels.NormalizeTemplateKind("unknown") == NewProjectTemplateKind.Unknown
    assert NewCommandKernels.NormalizeTemplateKind("") == NewProjectTemplateKind.Unknown
}

test "--systems upgrades console and library only, and leaves every other template alone" {
    assert NewCommandKernels.ResolveTemplateKind("console", true) == NewProjectTemplateKind.SystemsCli
    assert NewCommandKernels.ResolveTemplateKind("library", true) == NewProjectTemplateKind.SystemsLib
    // test and webapi are NOT upgraded — the flag is silently inert on them
    assert NewCommandKernels.ResolveTemplateKind("test", true) == NewProjectTemplateKind.Test
    assert NewCommandKernels.ResolveTemplateKind("webapi", true) == NewProjectTemplateKind.WebApi
    assert NewCommandKernels.ResolveTemplateKind("web-api", false) == NewProjectTemplateKind.WebApi
    assert NewCommandKernels.ResolveTemplateKind("console", false) == NewProjectTemplateKind.Console
}

test "the positional template is only honoured when a SECOND positional supplies the name" {
    // A CONTROL THE DELETED BODY DID NOT HAVE, AND IT IS THE POLICY BEHIND `nlc new systems-cli X`.
    // With two positionals and a recognised first one, the SECOND is the project name and the
    // FIRST is the template. With one positional, the word is the name even when it happens to
    // spell a template.
    assert NewCommandKernels.GetEffectiveProjectName("systems-cli", "PacketTool") == "PacketTool"
    assert NewCommandKernels.GetEffectiveRequestedTemplate(null, "systems-cli", "PacketTool") == "systems-cli"

    // one positional: a project genuinely named `library`
    assert NewCommandKernels.GetEffectiveProjectName("library", null) == "library"
    assert NewCommandKernels.GetEffectiveRequestedTemplate(null, "library", null) == null

    // two positionals whose first is NOT a template: the first is the name
    assert NewCommandKernels.GetEffectiveProjectName("MyApp", "extra") == "MyApp"
    assert NewCommandKernels.GetEffectiveRequestedTemplate("webapi", "MyApp", "extra") == "webapi"
}

// ── the per-template source-file set ──────────────────────────────────────────

test "each template names exactly the source files it creates" {
    webApi := NewCommandKernels.GetTemplateSourceFileKinds("webapi")
    assert webApi.Length == 2
    assert webApi[0] == NewTemplateSourceFileKind.Program
    assert webApi[1] == NewTemplateSourceFileKind.WebApiController

    systemsLib := NewCommandKernels.GetTemplateSourceFileKinds("systems-lib")
    assert systemsLib.Length == 2
    assert systemsLib[0] == NewTemplateSourceFileKind.PacketCore
    assert systemsLib[1] == NewTemplateSourceFileKind.PacketCoreTests

    // the four the deleted body never asked for
    consoleKinds := NewCommandKernels.GetTemplateSourceFileKinds("console")
    assert consoleKinds.Length == 1
    assert consoleKinds[0] == NewTemplateSourceFileKind.Program

    libraryKinds := NewCommandKernels.GetTemplateSourceFileKinds("library")
    assert libraryKinds.Length == 1
    assert libraryKinds[0] == NewTemplateSourceFileKind.Calculator

    testKinds := NewCommandKernels.GetTemplateSourceFileKinds("test")
    assert testKinds.Length == 2
    assert testKinds[0] == NewTemplateSourceFileKind.Calculator
    assert testKinds[1] == NewTemplateSourceFileKind.CalculatorTests

    systemsCliKinds := NewCommandKernels.GetTemplateSourceFileKinds("systems-cli")
    assert systemsCliKinds.Length == 2
    assert systemsCliKinds[0] == NewTemplateSourceFileKind.Program
    assert systemsCliKinds[1] == NewTemplateSourceFileKind.SystemsTests

    assert NewCommandKernels.GetTemplateSourceFileKinds("unknown").Length == 0
}

test "each source-file kind has exactly one on-disk name, and the controller nests in a folder" {
    assert NewCommandKernels.GetTemplateSourceFileName(NewTemplateSourceFileKind.Program) == "Program.nl"
    assert NewCommandKernels.GetTemplateSourceFileName(NewTemplateSourceFileKind.Calculator) == "Calculator.nl"
    assert NewCommandKernels.GetTemplateSourceFileName(NewTemplateSourceFileKind.CalculatorTests) == "Calculator.tests.nl"
    assert NewCommandKernels.GetTemplateSourceFileName(NewTemplateSourceFileKind.WebApiController) == "Controllers/WeatherController.nl"
    assert NewCommandKernels.GetTemplateSourceFileName(NewTemplateSourceFileKind.SystemsTests) == "Systems.tests.nl"
    assert NewCommandKernels.GetTemplateSourceFileName(NewTemplateSourceFileKind.PacketCore) == "PacketCore.nl"
    assert NewCommandKernels.GetTemplateSourceFileName(NewTemplateSourceFileKind.PacketCoreTests) == "PacketCore.tests.nl"
}

test "the next-steps block is chosen per template, and every command line is exactly these" {
    // The deleted body read two of the four intros. All four are here, with the three predicates
    // that decide WHICH command lines are printed beside them — none of which it read at all.
    assert NewCommandKernels.GetNextStepsIntroMessage("systems-lib") == "To check systems policy and inspect performance facts:"
    assert NewCommandKernels.GetNextStepsIntroMessage("systems-cli") == "To check systems policy and inspect performance facts:"
    assert NewCommandKernels.GetNextStepsIntroMessage("library") == "To build your project:"
    assert NewCommandKernels.GetNextStepsIntroMessage("test") == "To build and test your project:"
    assert NewCommandKernels.GetNextStepsIntroMessage("console") == "To build and run your project:"

    assert NewCommandKernels.ShouldShowSystemsCommands("systems-cli")
    assert NewCommandKernels.ShouldShowSystemsCommands("systems-lib")
    assert !NewCommandKernels.ShouldShowSystemsCommands("console")
    assert NewCommandKernels.ShouldShowTestCommand("test")
    assert !NewCommandKernels.ShouldShowTestCommand("library")
    // `nlc run` is offered for EVERY template except a library — including a test project
    assert NewCommandKernels.ShouldShowRunCommand("console")
    assert NewCommandKernels.ShouldShowRunCommand("test")
    assert !NewCommandKernels.ShouldShowRunCommand("library")

    assert NewCommandKernels.GetCdCommandMessage("MyApp") == "  cd MyApp"
    assert NewCommandKernels.GetSystemsReportCommandMessage() == "  nlc check --systems-report"
    assert NewCommandKernels.GetSystemsBuildCommandMessage() == "  nlc build --perf-report"
    assert NewCommandKernels.GetBuildCommandMessage() == "  nlc build"
    assert NewCommandKernels.GetTestCommandMessage() == "  nlc test"
    assert NewCommandKernels.GetRunCommandMessage() == "  nlc run"
}

// ── the user-facing sentences ─────────────────────────────────────────────────

test "the new help text names the command, both usage forms and the failure exit code" {
    helpText := NewCommandKernels.GetHelpText()

    assert helpText.StartsWith("N# New Project")
    assert helpText.Contains("Usage: nlc new <project-name>")
    assert helpText.Contains("nlc new systems-cli <project-name>")
    assert helpText.Contains("Project creation failed")
}

test "the new command's sentences are exactly these" {
    assert NewCommandKernels.GetUsageMessage() == "Usage: nlc new <project-name> [--template <template>]"
    assert NewCommandKernels.GetInvalidTemplateMessage() == "Invalid template. Expected one of: console, library, test, webapi, systems-cli, systems-lib."
    assert NewCommandKernels.GetDirectoryExistsMessage("/tmp/MyApp") == "Directory already exists: /tmp/MyApp. Use a different name or remove the existing directory."
    assert NewCommandKernels.GetCreatingProjectMessage("systems-cli", "PacketTool") == "Creating new systems-cli project: PacketTool"
    assert NewCommandKernels.GetCreatedFileMessage("MyApp", "project.yml") == "Created: MyApp/project.yml"
    assert NewCommandKernels.GetProjectShapeMessage() == "Project shape: csproj-free source tree; nlc builds directly from project.yml."
    assert NewCommandKernels.GetFailedMessage("denied") == "Failed to create project: denied"
}

// ── the generated project.yml ─────────────────────────────────────────────────

test "the console project.yml is the shared project-file template, verbatim" {
    consoleYaml := NewCommandKernels.GetProjectYamlText("MyApp", "console")

    assert consoleYaml == ProjectFileParser.GenerateTemplate("MyApp")
    // and the delegation is pinned by CONTENT too, so an agreeing pair of wrong answers is caught
    assert consoleYaml.StartsWith("name: MyApp\n")
    assert consoleYaml.Contains("entry: Program.nl\n")
    assert consoleYaml.Contains("outputType: exe\n")
    assert consoleYaml.Contains("  profile: default\n")
}

test "an unrecognised template falls back to the console project.yml rather than failing" {
    // The kernel's final `return` is a fallback, not an error path: `nlc new X --template nonsense`
    // reaches the invalid-template MESSAGE elsewhere, but this kernel still answers.
    assert NewCommandKernels.GetProjectYamlText("MyApp", "nonsense") == NewCommandKernels.GetProjectYamlText("MyApp", "console")
}

test "the library project.yml is a library with no entry point" {
    libraryYaml := NewCommandKernels.GetProjectYamlText("MyLib", "library")

    assert libraryYaml.Contains("name: MyLib\n")
    assert libraryYaml.Contains("outputType: library\n")
    assert libraryYaml.Contains("language:\n  asyncDefaultType: ValueTask\n")
    assert !libraryYaml.Contains("entry: Program.nl")
    // the test template shares this text exactly
    assert NewCommandKernels.GetProjectYamlText("MyLib", "test") == libraryYaml
}

test "the webapi project.yml carries the Web SDK and its three dependencies" {
    webApiYaml := NewCommandKernels.GetProjectYamlText("MyApi", "webapi")

    assert webApiYaml.Contains("sdk: Microsoft.NET.Sdk.Web\n")
    assert webApiYaml.Contains("  - framework: Microsoft.AspNetCore.App\n")
    assert webApiYaml.Contains("  - nuget: Swashbuckle.AspNetCore\n    version: 7.2.0\n")
    assert webApiYaml.Contains("  - nuget: Microsoft.AspNetCore.OpenApi\n    version: 9.0.0\n")
}

test "the systems-cli project.yml is an exe under the strict systems profile" {
    systemsCliYaml := NewCommandKernels.GetProjectYamlText("PacketTool", "systems-cli")

    assert systemsCliYaml.Contains("entry: Program.nl\n")
    assert systemsCliYaml.Contains("outputType: exe\n")
    assert systemsCliYaml.Contains("  profile: systems\n")
    assert systemsCliYaml.Contains("    warmup:\n      - Warmup\n")
    // the four systems settings the deleted body never read
    assert systemsCliYaml.Contains("    mode: strict\n")
    assert systemsCliYaml.Contains("    unknownExternalCalls: warn\n")
    assert systemsCliYaml.Contains("    aotTarget: nativeaot\n")
    assert systemsCliYaml.Contains("    stackBudgetBytes: 4096\n")
}

test "the systems-lib project.yml is the same profile as a LIBRARY with no entry point" {
    systemsLibYaml := NewCommandKernels.GetProjectYamlText("PacketCore", "systems-lib")

    assert systemsLibYaml.Contains("outputType: library\n")
    assert systemsLibYaml.Contains("  profile: systems\n")
    assert !systemsLibYaml.Contains("entry: Program.nl")
    assert systemsLibYaml.Contains("    stackBudgetBytes: 4096\n")
}

// ── the generated global.json and NuGet.config ────────────────────────────────

test "the generated global.json pins the SDK feature band and the MSBuild SDK version" {
    assert NewCommandKernels.GetGlobalJsonText() == "{\n" + "  \"sdk\": {\n" + "    \"version\": \"10.0.100\",\n" + "    \"rollForward\": \"latestFeature\"\n" + "  },\n" + "  \"msbuild-sdks\": {\n" + "    \"NSharpLang.Sdk\": \"0.1.0\"\n" + "  }\n" + "}\n"
}

test "the generated NuGet.config clears inherited sources and adds nuget.org plus the local feed" {
    defaultNuGetConfig := NewCommandKernels.GetNuGetConfigText("%HOME%/.nsharp/packages")

    assert defaultNuGetConfig == "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" + "<configuration>\n" + "  <packageSources>\n" + "    <clear />\n" + "    <add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" />\n" + "    <add key=\"nsharp-local\" value=\"%HOME%/.nsharp/packages\" />\n" + "  </packageSources>\n" + "</configuration>\n"
}

test "the feed path is XML-attribute escaped, all five characters" {
    escaped := NewCommandKernels.GetNuGetConfigText("/tmp/a&b<c>d\"e'f/packages")

    assert escaped.Contains("/tmp/a&amp;b&lt;c&gt;d&quot;e&apos;f/packages")
    // a path with nothing to escape passes through untouched
    assert NewCommandKernels.XmlAttributeEscape("/plain/path") == "/plain/path"
    assert NewCommandKernels.XmlAttributeEscape("&") == "&amp;"
}

// ── the generated source files ────────────────────────────────────────────────

test "the console Program.nl is exactly the three-line hello world" {
    assert NewCommandKernels.GetTemplateSourceText("console", NewTemplateSourceFileKind.Program) == "func main() {\n    print \"Hello, N#!\"\n}\n"
}

test "the library Calculator.nl declares both operations as static functions" {
    calculatorSource := NewCommandKernels.GetTemplateSourceText("library", NewTemplateSourceFileKind.Calculator)

    assert calculatorSource.Contains("class Calculator {\n")
    assert calculatorSource.Contains("static func Add(a: int, b: int): int")
    assert calculatorSource.Contains("static func Subtract(a: int, b: int): int")
}

test "the generated Calculator.tests.nl uses the native test and assert syntax" {
    calculatorTestsSource := NewCommandKernels.GetTemplateSourceText("test", NewTemplateSourceFileKind.CalculatorTests)

    assert calculatorTestsSource.Contains("test \"adds two numbers\" {\n")
    assert calculatorTestsSource.Contains("assert result == 3\n")
}

test "the webapi template writes a minimal host and an attribute-routed controller" {
    webApiProgramSource := NewCommandKernels.GetTemplateSourceText("webapi", NewTemplateSourceFileKind.Program)
    assert webApiProgramSource.Contains("WebApplication.CreateBuilder(args)")

    controllerSource := NewCommandKernels.GetTemplateSourceText("webapi", NewTemplateSourceFileKind.WebApiController)
    assert controllerSource.Contains("[Route(\"api/weather\")]\n")
    assert controllerSource.Contains("CreateWeatherRequest")
}

test "the systems-cli Program.nl carries an allow() with a reason and a void main" {
    systemsCliSource := NewCommandKernels.GetTemplateSourceText("systems-cli", NewTemplateSourceFileKind.Program)

    assert systemsCliSource.Contains("allow(alloc, reason: \"CLI startup allocates outside the hot parser\")")
    assert systemsCliSource.Contains("func main(): void")
    assert systemsCliSource.Contains("[hot]\n")
    assert systemsCliSource.Contains("[boundary]\n")
}

test "the systems-lib PacketCore.nl exports a Result-returning boundary and has NO main" {
    packetCoreSource := NewCommandKernels.GetTemplateSourceText("systems-lib", NewTemplateSourceFileKind.PacketCore)

    assert packetCoreSource.Contains("public func AdaptPacket(bytes: byte[]): Result<uint, ParseError>")
    assert !packetCoreSource.Contains("func main")
    assert packetCoreSource.Contains("public func Warmup(): void")
}

test "both systems test files are the same two-line smoke test" {
    packetCoreTestsSource := NewCommandKernels.GetTemplateSourceText("systems-lib", NewTemplateSourceFileKind.PacketCoreTests)

    assert packetCoreTestsSource == "test \"systems smoke\" {\n    assert true\n}\n"
    assert NewCommandKernels.GetTemplateSourceText("systems-cli", NewTemplateSourceFileKind.SystemsTests) == packetCoreTestsSource
}

test "the source-file text depends on the TEMPLATE only for Program.nl" {
    // MEASURED, NOT ASSUMED, AND IT OVERTURNED THE OBVIOUS READING. Only the `Program` arm branches
    // on the template; every other kind answers the same text for every template. So asking the
    // console template for a WebApi controller returns the CONTROLLER — the pair is not rejected.
    controllerFromConsole := NewCommandKernels.GetTemplateSourceText("console", NewTemplateSourceFileKind.WebApiController)
    assert controllerFromConsole == NewCommandKernels.GetTemplateSourceText("webapi", NewTemplateSourceFileKind.WebApiController)

    calculatorFromSystems := NewCommandKernels.GetTemplateSourceText("systems-cli", NewTemplateSourceFileKind.Calculator)
    assert calculatorFromSystems == NewCommandKernels.GetTemplateSourceText("library", NewTemplateSourceFileKind.Calculator)

    // and Program.nl really is the one that differs, three ways
    consoleProgram := NewCommandKernels.GetTemplateSourceText("console", NewTemplateSourceFileKind.Program)
    webApiProgram := NewCommandKernels.GetTemplateSourceText("webapi", NewTemplateSourceFileKind.Program)
    systemsProgram := NewCommandKernels.GetTemplateSourceText("systems-cli", NewTemplateSourceFileKind.Program)
    assert consoleProgram != webApiProgram
    assert consoleProgram != systemsProgram
    assert webApiProgram != systemsProgram
    // an unknown template falls back to the console program, it does not answer empty
    assert NewCommandKernels.GetTemplateSourceText("nonsense", NewTemplateSourceFileKind.Program) == consoleProgram
}

test "every one of the seven declared source kinds answers non-empty, for every template" {
    // THIS IS WHY THE `N# new text kernel returned empty output.` GUARD IS STRUCTURALLY
    // UNREACHABLE THROUGH THE ENUM. `GetTemplateSourceText` throws when `…OrEmpty` answers "", and
    // `…OrEmpty`'s final `return ""` is reachable only for an enum value outside the seven
    // declared members. The deleted body never asked, and the finding is recorded rather than
    // fixed. Each kind is asked under a template that does NOT create it, which is the strongest
    // form of the claim.
    assert NewCommandKernels.GetTemplateSourceTextOrEmpty("library", NewTemplateSourceFileKind.Program).Length > 0
    assert NewCommandKernels.GetTemplateSourceTextOrEmpty("console", NewTemplateSourceFileKind.Calculator).Length > 0
    assert NewCommandKernels.GetTemplateSourceTextOrEmpty("console", NewTemplateSourceFileKind.CalculatorTests).Length > 0
    assert NewCommandKernels.GetTemplateSourceTextOrEmpty("console", NewTemplateSourceFileKind.WebApiController).Length > 0
    assert NewCommandKernels.GetTemplateSourceTextOrEmpty("console", NewTemplateSourceFileKind.SystemsTests).Length > 0
    assert NewCommandKernels.GetTemplateSourceTextOrEmpty("console", NewTemplateSourceFileKind.PacketCore).Length > 0
    assert NewCommandKernels.GetTemplateSourceTextOrEmpty("console", NewTemplateSourceFileKind.PacketCoreTests).Length > 0
}
