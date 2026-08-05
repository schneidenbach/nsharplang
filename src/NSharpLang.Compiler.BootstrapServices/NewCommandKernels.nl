namespace NSharpLang.Cli

import System
import System.IO

class NewArgumentSummary {
    FirstPositional: string?
    SecondPositional: string?
    TemplateOption: string?
    Systems: bool
    ShowHelp: bool

    constructor(firstPositional: string?, secondPositional: string?, templateOption: string?, systems: bool, showHelp: bool) {
        FirstPositional = firstPositional
        SecondPositional = secondPositional
        TemplateOption = templateOption
        Systems = systems
        ShowHelp = showHelp
    }
}

enum NewProjectTemplateKind {
    Unknown = 0,
    Console = 1,
    Library = 2,
    Test = 3,
    WebApi = 4,
    SystemsCli = 5,
    SystemsLib = 6
}

enum NewTemplateSourceFileKind {
    Program = 1,
    Calculator = 2,
    CalculatorTests = 3,
    WebApiController = 4,
    SystemsTests = 5,
    PacketCore = 6,
    PacketCoreTests = 7
}

class NewCommandKernels {
    static func GetArgumentSummary(args: string[]): NewArgumentSummary {
        firstPositional: string? = null
        secondPositional: string? = null
        templateOption: string? = null
        typeOption: string? = null
        systems := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            if arg == "--systems" {
                systems = true
            }

            if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            if arg == "--template" {
                if templateOption == null && i + 1 < args.Length {
                    templateOption = args[i + 1]
                }
            } else if arg == "--type" {
                if typeOption == null && i + 1 < args.Length {
                    typeOption = args[i + 1]
                }
            }

            i = i + 1
        }

        selectedTemplate := typeOption
        if templateOption != null {
            selectedTemplate = templateOption
        }

        positionalCount := 0
        i = 0
        while i < args.Length {
            arg := args[i]
            if arg == "--template" || arg == "--type" {
                if i + 1 < args.Length {
                    i = i + 2
                } else {
                    i = i + 1
                }

                continue
            }

            if IsValueLessFlag(arg) {
                i = i + 1
                continue
            }

            if arg.Length == 0 || arg[0] != '-' {
                if positionalCount == 0 {
                    firstPositional = arg
                } else if positionalCount == 1 {
                    secondPositional = arg
                }

                positionalCount = positionalCount + 1
            }

            i = i + 1
        }

        return new NewArgumentSummary(firstPositional, secondPositional, selectedTemplate, systems, showHelp)
    }

    static func NormalizeTemplateKind(value: string): NewProjectTemplateKind {
        normalized := value.Trim()

        if String.Compare(normalized, "console", StringComparison.OrdinalIgnoreCase) == 0 || String.Compare(normalized, "exe", StringComparison.OrdinalIgnoreCase) == 0 || String.Compare(normalized, "app", StringComparison.OrdinalIgnoreCase) == 0 {
            return NewProjectTemplateKind.Console
        }

        if String.Compare(normalized, "library", StringComparison.OrdinalIgnoreCase) == 0 || String.Compare(normalized, "lib", StringComparison.OrdinalIgnoreCase) == 0 {
            return NewProjectTemplateKind.Library
        }

        if String.Compare(normalized, "test", StringComparison.OrdinalIgnoreCase) == 0 || String.Compare(normalized, "tests", StringComparison.OrdinalIgnoreCase) == 0 {
            return NewProjectTemplateKind.Test
        }

        if String.Compare(normalized, "webapi", StringComparison.OrdinalIgnoreCase) == 0 || String.Compare(normalized, "web-api", StringComparison.OrdinalIgnoreCase) == 0 || String.Compare(normalized, "web", StringComparison.OrdinalIgnoreCase) == 0 {
            return NewProjectTemplateKind.WebApi
        }

        if String.Compare(normalized, "systems-cli", StringComparison.OrdinalIgnoreCase) == 0 || String.Compare(normalized, "systems-console", StringComparison.OrdinalIgnoreCase) == 0 || String.Compare(normalized, "systems", StringComparison.OrdinalIgnoreCase) == 0 {
            return NewProjectTemplateKind.SystemsCli
        }

        if String.Compare(normalized, "systems-lib", StringComparison.OrdinalIgnoreCase) == 0 || String.Compare(normalized, "systems-library", StringComparison.OrdinalIgnoreCase) == 0 {
            return NewProjectTemplateKind.SystemsLib
        }

        return NewProjectTemplateKind.Unknown
    }

    static func ResolveTemplateKind(value: string, systems: bool): NewProjectTemplateKind {
        templateKind := NormalizeTemplateKind(value)
        if systems && templateKind == NewProjectTemplateKind.Console {
            return NewProjectTemplateKind.SystemsCli
        }

        if systems && templateKind == NewProjectTemplateKind.Library {
            return NewProjectTemplateKind.SystemsLib
        }

        return templateKind
    }

    static func GetEffectiveProjectName(firstPositional: string?, secondPositional: string?): string? {
        if secondPositional != null && GetProjectTemplateName(NormalizeTemplateKind(firstPositional ?? "")) != null {
            return secondPositional
        }

        return firstPositional
    }

    static func GetEffectiveRequestedTemplate(templateOption: string?, firstPositional: string?, secondPositional: string?): string? {
        if secondPositional != null {
            positionalTemplate := GetProjectTemplateName(NormalizeTemplateKind(firstPositional ?? ""))
            if positionalTemplate != null {
                return positionalTemplate
            }
        }

        return templateOption
    }

    static func GetProjectDirectory(currentDirectory: string, projectName: string): string {
        return Path.Combine(currentDirectory, projectName)
    }

    static func GetProjectYamlPath(projectDir: string): string {
        return Path.Combine(projectDir, "project.yml")
    }

    static func GetGlobalJsonPath(projectDir: string): string {
        return Path.Combine(projectDir, "global.json")
    }

    static func GetNuGetConfigPath(projectDir: string): string {
        return Path.Combine(projectDir, "NuGet.config")
    }

    static func GetTemplateSourceFilePath(projectDir: string, sourceFileKind: NewTemplateSourceFileKind): string {
        return Path.Combine(projectDir, GetTemplateSourceFileName(sourceFileKind))
    }

    static func GetTemplateSourceFileDirectory(projectDir: string, sourceFileKind: NewTemplateSourceFileKind): string? {
        return Path.GetDirectoryName(GetTemplateSourceFilePath(projectDir, sourceFileKind))
    }

    static func ShouldShowSystemsCommands(template: string): bool {
        return template == "systems-cli" || template == "systems-lib"
    }

    static func ShouldShowTestCommand(template: string): bool {
        return template == "test"
    }

    static func ShouldShowRunCommand(template: string): bool {
        return template != "library"
    }

    static func GetTemplateSourceFileKinds(template: string): NewTemplateSourceFileKind[] {
        templateKind := NormalizeTemplateKind(template)

        if templateKind == NewProjectTemplateKind.Console {
            result := new NewTemplateSourceFileKind[](1)
            result[0] = NewTemplateSourceFileKind.Program
            return result
        }

        if templateKind == NewProjectTemplateKind.Library {
            result := new NewTemplateSourceFileKind[](1)
            result[0] = NewTemplateSourceFileKind.Calculator
            return result
        }

        if templateKind == NewProjectTemplateKind.Test {
            result := new NewTemplateSourceFileKind[](2)
            result[0] = NewTemplateSourceFileKind.Calculator
            result[1] = NewTemplateSourceFileKind.CalculatorTests
            return result
        }

        if templateKind == NewProjectTemplateKind.WebApi {
            result := new NewTemplateSourceFileKind[](2)
            result[0] = NewTemplateSourceFileKind.Program
            result[1] = NewTemplateSourceFileKind.WebApiController
            return result
        }

        if templateKind == NewProjectTemplateKind.SystemsCli {
            result := new NewTemplateSourceFileKind[](2)
            result[0] = NewTemplateSourceFileKind.Program
            result[1] = NewTemplateSourceFileKind.SystemsTests
            return result
        }

        if templateKind == NewProjectTemplateKind.SystemsLib {
            result := new NewTemplateSourceFileKind[](2)
            result[0] = NewTemplateSourceFileKind.PacketCore
            result[1] = NewTemplateSourceFileKind.PacketCoreTests
            return result
        }

        return new NewTemplateSourceFileKind[](0)
    }

    static func GetProjectTemplateName(templateKind: NewProjectTemplateKind): string? {
        if templateKind == NewProjectTemplateKind.Console {
            return "console"
        }

        if templateKind == NewProjectTemplateKind.Library {
            return "library"
        }

        if templateKind == NewProjectTemplateKind.Test {
            return "test"
        }

        if templateKind == NewProjectTemplateKind.WebApi {
            return "webapi"
        }

        if templateKind == NewProjectTemplateKind.SystemsCli {
            return "systems-cli"
        }

        if templateKind == NewProjectTemplateKind.SystemsLib {
            return "systems-lib"
        }

        return null
    }

    static func GetTemplateSourceFileName(sourceFileKind: NewTemplateSourceFileKind): string {
        if sourceFileKind == NewTemplateSourceFileKind.Program {
            return "Program.nl"
        }

        if sourceFileKind == NewTemplateSourceFileKind.Calculator {
            return "Calculator.nl"
        }

        if sourceFileKind == NewTemplateSourceFileKind.CalculatorTests {
            return "Calculator.tests.nl"
        }

        if sourceFileKind == NewTemplateSourceFileKind.WebApiController {
            return "Controllers/WeatherController.nl"
        }

        if sourceFileKind == NewTemplateSourceFileKind.SystemsTests {
            return "Systems.tests.nl"
        }

        if sourceFileKind == NewTemplateSourceFileKind.PacketCore {
            return "PacketCore.nl"
        }

        if sourceFileKind == NewTemplateSourceFileKind.PacketCoreTests {
            return "PacketCore.tests.nl"
        }

        throw new InvalidOperationException("N# new text kernel returned empty output.")
    }

    static func GetHelpText(): string {
        return "N# New Project\n" + "\n" + "Usage: nlc new <project-name> [--template <template>] [--systems]\n" + "       nlc new systems-cli <project-name>\n" + "       nlc new systems-lib <project-name>\n" + "\n" + "Create a new csproj-free N# project. Fresh projects are project.yml-first:\n" + "`nlc build`, `nlc run`, and `nlc test` build directly from project.yml.\n" + "Do not hand-author project build settings in .csproj.\n" + "\n" + "Options:\n" + "  --template <template>  Project template: console, library, test, webapi, systems-cli, systems-lib (default: console)\n" + "  --type <template>      Alias for --template\n" + "  --systems              Enable the systems profile for console/library templates\n" + "  --help, -h             Show this help text\n" + "\n" + "Examples:\n" + "  nlc new MyApp\n" + "  nlc new MyLib --template library\n" + "  nlc new MyApi --template webapi\n" + "  nlc new systems-cli PacketTool\n" + "  nlc new PacketCore --template library --systems\n" + "  nlc new lib PacketCore --systems\n" + "  cd MyApp && nlc build\n" + "\n" + "Exit codes:\n" + "  0  Project created successfully\n" + "  1  Project creation failed"
    }

    static func GetUsageMessage(): string {
        return "Usage: nlc new <project-name> [--template <template>]"
    }

    static func GetInvalidTemplateMessage(): string {
        return "Invalid template. Expected one of: console, library, test, webapi, systems-cli, systems-lib."
    }

    static func GetDirectoryExistsMessage(projectDir: string): string {
        return "Directory already exists: " + projectDir + ". Use a different name or remove the existing directory."
    }

    static func GetCreatingProjectMessage(template: string, projectName: string): string {
        return "Creating new " + template + " project: " + projectName
    }

    static func GetCreatedFileMessage(projectName: string, sourceFile: string): string {
        return "Created: " + projectName + "/" + sourceFile
    }

    static func GetProjectShapeMessage(): string {
        return "Project shape: csproj-free source tree; nlc builds directly from project.yml."
    }

    static func GetNextStepsIntroMessage(template: string): string {
        if template == "systems-cli" || template == "systems-lib" {
            return "To check systems policy and inspect performance facts:"
        }

        if template == "test" {
            return "To build and test your project:"
        }

        if template == "library" {
            return "To build your project:"
        }

        return "To build and run your project:"
    }

    static func GetCdCommandMessage(projectName: string): string {
        return "  cd " + projectName
    }

    static func GetSystemsReportCommandMessage(): string {
        return "  nlc check --systems-report"
    }

    static func GetSystemsBuildCommandMessage(): string {
        return "  nlc build --perf-report"
    }

    static func GetBuildCommandMessage(): string {
        return "  nlc build"
    }

    static func GetTestCommandMessage(): string {
        return "  nlc test"
    }

    static func GetRunCommandMessage(): string {
        return "  nlc run"
    }

    static func GetFailedMessage(message: string): string {
        return "Failed to create project: " + message
    }

    static func GetProjectYamlText(projectName: string, template: string): string {
        if template == "library" || template == "test" {
            return "name: " + projectName + "\n" + "version: 1.0.0\n" + "backend: il\n" + "outputType: library\n" + "targetFramework: net10.0\n" + "\n" + "# Test framework: xunit (default) or nunit\n" + "# testFramework: xunit\n" + "\n" + "language:\n" + "  asyncDefaultType: ValueTask\n"
        }

        if template == "webapi" {
            return "name: " + projectName + "\n" + "version: 1.0.0\n" + "entry: Program.nl\n" + "backend: il\n" + "outputType: exe\n" + "targetFramework: net10.0\n" + "sdk: Microsoft.NET.Sdk.Web\n" + "\n" + "dependencies:\n" + "  - framework: Microsoft.AspNetCore.App\n" + "  - nuget: Swashbuckle.AspNetCore\n" + "    version: 7.2.0\n" + "  - nuget: Microsoft.AspNetCore.OpenApi\n" + "    version: 9.0.0\n" + "\n" + "language:\n" + "  asyncDefaultType: ValueTask\n"
        }

        if template == "systems-cli" {
            return "name: " + projectName + "\n" + "version: 1.0.0\n" + "entry: Program.nl\n" + "backend: il\n" + "outputType: exe\n" + "targetFramework: net10.0\n" + "\n" + "language:\n" + "  profile: systems\n" + "  asyncDefaultType: ValueTask\n" + "  systems:\n" + "    mode: strict\n" + "    unknownExternalCalls: warn\n" + "    aotTarget: nativeaot\n" + "    stackBudgetBytes: 4096\n" + "    warmup:\n" + "      - Warmup\n"
        }

        if template == "systems-lib" {
            return "name: " + projectName + "\n" + "version: 1.0.0\n" + "backend: il\n" + "outputType: library\n" + "targetFramework: net10.0\n" + "\n" + "language:\n" + "  profile: systems\n" + "  asyncDefaultType: ValueTask\n" + "  systems:\n" + "    mode: strict\n" + "    unknownExternalCalls: warn\n" + "    aotTarget: nativeaot\n" + "    stackBudgetBytes: 4096\n" + "    warmup:\n" + "      - Warmup\n"
        }

        return "name: " + projectName + "\n" + "version: 1.0.0\n" + "entry: Program.nl\n" + "backend: il\n" + "outputType: exe\n" + "targetFramework: net10.0\n" + "\n" + "# Test framework: xunit (default) or nunit\n" + "# testFramework: xunit\n" + "\n" + "# Add your dependencies here\n" + "# dependencies:\n" + "#   - nuget: Newtonsoft.Json\n" + "#     version: 13.0.3\n" + "\n" + "language:\n" + "  profile: default\n" + "  asyncDefaultType: ValueTask\n" + "\n" + "# package:\n" + "#   author: Your Name\n" + "#   description: A short description\n" + "#   license: MIT\n"
    }

    static func GetGlobalJsonText(): string {
        return "{\n" + "  \"sdk\": {\n" + "    \"version\": \"10.0.100\",\n" + "    \"rollForward\": \"latestFeature\"\n" + "  },\n" + "  \"msbuild-sdks\": {\n" + "    \"NSharpLang.Sdk\": \"0.1.0\"\n" + "  }\n" + "}\n"
    }

    static func GetNuGetConfigText(feedValue: string): string {
        return "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" + "<configuration>\n" + "  <packageSources>\n" + "    <clear />\n" + "    <add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" />\n" + "    <add key=\"nsharp-local\" value=\"" + XmlAttributeEscape(feedValue) + "\" />\n" + "  </packageSources>\n" + "</configuration>\n"
    }

    static func GetTemplateSourceText(template: string, sourceFileKind: NewTemplateSourceFileKind): string {
        text := GetTemplateSourceTextOrEmpty(template, sourceFileKind)
        if text.Length == 0 {
            throw new InvalidOperationException("N# new text kernel returned empty output.")
        }

        return text
    }

    static func GetTemplateSourceTextOrEmpty(template: string, sourceFileKind: NewTemplateSourceFileKind): string {
        if sourceFileKind == NewTemplateSourceFileKind.Program {
            if template == "webapi" {
                return "import Microsoft.AspNetCore.Builder\n" + "import Microsoft.Extensions.DependencyInjection\n" + "\n" + "func main(args: string[]) {\n" + "    builder := WebApplication.CreateBuilder(args)\n" + "\n" + "    builder.Services.AddControllers()\n" + "    builder.Services.AddEndpointsApiExplorer()\n" + "    builder.Services.AddSwaggerGen()\n" + "\n" + "    app := builder.Build()\n" + "\n" + "    app.UseSwagger()\n" + "    app.UseSwaggerUI()\n" + "    app.UseHttpsRedirection()\n" + "    app.UseAuthorization()\n" + "    app.MapControllers()\n" + "\n" + "    app.Run()\n" + "}\n"
            }

            if template == "systems-cli" {
                return "namespace SystemsTemplate\n" + "\n" + "import System\n" + "import System.Buffers.Binary\n" + "\n" + "enum ParseError {\n" + "    Short\n" + "}\n" + "\n" + "[hot]\n" + "func ParseLength(buf: ReadOnlySpan<byte>): Result<uint, ParseError> {\n" + "    if buf.Length < 4 {\n" + "        return Err(ParseError.Short)\n" + "    }\n" + "\n" + "    return Ok(BinaryPrimitives.ReadUInt32LittleEndian(buf.Slice(0, 4)))\n" + "}\n" + "\n" + "[boundary]\n" + "func Run(): Result<int, ParseError> {\n" + "    allow(alloc, reason: \"CLI startup allocates outside the hot parser\") {\n" + "        print \"Systems N# template\"\n" + "    }\n" + "    return Ok(0)\n" + "}\n" + "\n" + "func Warmup(): void {\n" + "}\n" + "\n" + "func main(): void {\n" + "    _ := Run()\n" + "}\n"
            }

            return "func main() {\n" + "    print \"Hello, N#!\"\n" + "}\n"
        }

        if sourceFileKind == NewTemplateSourceFileKind.Calculator {
            return "class Calculator {\n" + "    static func Add(a: int, b: int): int {\n" + "        return a + b\n" + "    }\n" + "\n" + "    static func Subtract(a: int, b: int): int {\n" + "        return a - b\n" + "    }\n" + "}\n"
        }

        if sourceFileKind == NewTemplateSourceFileKind.CalculatorTests {
            return "test \"adds two numbers\" {\n" + "    result := Calculator.Add(2, 3)\n" + "    assert result == 5\n" + "}\n" + "\n" + "test \"subtracts two numbers\" {\n" + "    result := Calculator.Subtract(7, 4)\n" + "    assert result == 3\n" + "}\n"
        }

        if sourceFileKind == NewTemplateSourceFileKind.WebApiController {
            return "import Microsoft.AspNetCore.Mvc\n" + "\n" + "[ApiController]\n" + "[Route(\"api/weather\")]\n" + "class WeatherController: ControllerBase {\n" + "    [HttpGet]\n" + "    func Get(): IActionResult {\n" + "        data := [\"Sunny\", \"Cloudy\", \"Rainy\"]\n" + "        return Ok(data)\n" + "    }\n" + "\n" + "    [HttpGet(\"{id}\")]\n" + "    func GetById([FromRoute] id: int): IActionResult {\n" + "        return Ok(id)\n" + "    }\n" + "\n" + "    [HttpPost]\n" + "    func Create([FromBody] request: CreateWeatherRequest): IActionResult {\n" + "        return Ok(request)\n" + "    }\n" + "}\n" + "\n" + "class CreateWeatherRequest {\n" + "    Summary: string\n" + "    TemperatureC: int\n" + "}\n"
        }

        if sourceFileKind == NewTemplateSourceFileKind.SystemsTests || sourceFileKind == NewTemplateSourceFileKind.PacketCoreTests {
            return "test \"systems smoke\" {\n" + "    assert true\n" + "}\n"
        }

        if sourceFileKind == NewTemplateSourceFileKind.PacketCore {
            return "namespace SystemsTemplate\n" + "\n" + "import System\n" + "import System.Buffers.Binary\n" + "\n" + "enum ParseError {\n" + "    Short\n" + "}\n" + "\n" + "[hot]\n" + "public func ParseLength(buf: ReadOnlySpan<byte>): Result<uint, ParseError> {\n" + "    if buf.Length < 4 {\n" + "        return Err(ParseError.Short)\n" + "    }\n" + "\n" + "    return Ok(BinaryPrimitives.ReadUInt32LittleEndian(buf.Slice(0, 4)))\n" + "}\n" + "\n" + "[boundary]\n" + "public func AdaptPacket(bytes: byte[]): Result<uint, ParseError> {\n" + "    return ParseLength(bytes.AsSpan())\n" + "}\n" + "\n" + "public func Warmup(): void {\n" + "}\n"
        }

        return ""
    }

    static func XmlAttributeEscape(value: string): string {
        result := ""
        index := 0
        while index < value.Length {
            ch := value[index]
            if ch == '&' {
                result = result + "&amp;"
            } else if ch == '<' {
                result = result + "&lt;"
            } else if ch == '>' {
                result = result + "&gt;"
            } else if ch == '"' {
                result = result + "&quot;"
            } else if ch == '\'' {
                result = result + "&apos;"
            } else {
                result = result + value.Substring(index, 1)
            }

            index = index + 1
        }

        return result
    }

    static func IsValueLessFlag(arg: string): bool {
        return arg == "--check" || arg == "--verify-no-changes" || arg == "--diff" || arg == "--stdin" || arg == "--verbose" || arg == "--systems"
    }
}
