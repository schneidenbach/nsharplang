namespace NSharpLang.Cli.Commands

public class InitOptionSummary {
    NameOption: string?
    TypeOption: string?
    Force: bool
    ShowHelp: bool

    constructor(nameOption: string?, typeOption: string?, force: bool, showHelp: bool) {
        NameOption = nameOption
        TypeOption = typeOption
        Force = force
        ShowHelp = showHelp
    }
}

public class InitCommandKernels {
    public static func GetOptionSummary(args: string[]): InitOptionSummary {
        nameOption: string? = null
        typeOption: string? = null
        force := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            valueIndex := i + 1
            hasValue := valueIndex < args.Length

            if arg == "--name" {
                if nameOption == null && hasValue {
                    nameOption = args[valueIndex]
                }
            } else if arg == "--type" {
                if typeOption == null && hasValue {
                    typeOption = args[valueIndex]
                }
            } else if arg == "--force" {
                force = true
            } else if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            i = i + 1
        }

        return new InitOptionSummary(nameOption, typeOption, force, showHelp)
    }

    public static func GetHelpText(): string {
        return "N# Init\n"
            + "\n"
            + "Usage: nlc init [options]\n"
            + "\n"
            + "Initialize N# in the current directory. Like 'cargo init' — works in an\n"
            + "existing directory instead of creating a new one.\n"
            + "\n"
            + "Options:\n"
            + "  --name <name>   Project name (default: current directory name)\n"
            + "  --type <type>   Output type: exe or library (default: exe)\n"
            + "  --force         Overwrite existing project.yml\n"
            + "  --help, -h      Show this help text\n"
            + "\n"
            + "Examples:\n"
            + "  nlc init\n"
            + "  nlc init --name MyLib --type library\n"
            + "  nlc init --force\n"
            + "\n"
            + "Exit codes:\n"
            + "  0  Project initialized successfully\n"
            + "  1  Initialization failed"
    }

    public static func GetInvalidTypeMessage(projectType: string): string {
        return "Invalid type '" + projectType + "'. Expected 'exe' or 'library'."
    }

    public static func GetProjectFileExistsMessage(): string {
        return "project.yml already exists. Use --force to overwrite."
    }

    public static func GetCreatedFileMessage(sourceFile: string): string {
        return "Created: " + sourceFile
    }

    public static func GetSuccessMessage(): string {
        return "N# project initialized. Run 'nlc build' to compile."
    }

    public static func GetFailedMessage(message: string): string {
        return "Init failed: " + message
    }

    public static func GetProjectYamlText(projectName: string, projectType: string): string {
        entryLine := "entry: Program.nl\n"
        outputType := "exe"
        if projectType == "library" {
            entryLine = ""
            outputType = "library"
        }

        return "name: " + projectName + "\n"
            + "version: 1.0.0\n"
            + entryLine
            + "backend: il\n"
            + "outputType: " + outputType + "\n"
            + "targetFramework: net10.0\n"
            + "\n"
            + "# Test framework: xunit (default) or nunit\n"
            + "# testFramework: xunit\n"
            + "\n"
            + "# Add your dependencies here\n"
            + "# dependencies:\n"
            + "#   - nuget: Newtonsoft.Json\n"
            + "#     version: 13.0.3\n"
            + "\n"
            + "language:\n"
            + "  profile: default\n"
            + "  asyncDefaultType: ValueTask\n"
            + "\n"
            + "# package:\n"
            + "#   author: Your Name\n"
            + "#   description: A short description\n"
            + "#   license: MIT\n"
    }

    public static func GetCsprojText(): string {
        return "<Project Sdk=\"NSharpLang.Sdk\" />\n"
    }

    public static func GetProgramSourceText(): string {
        return "func main() {\n"
            + "    print \"Hello, N#!\"\n"
            + "}"
    }
}
