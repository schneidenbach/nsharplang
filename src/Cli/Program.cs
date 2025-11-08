using System;
using System.IO;
using System.Linq;
using NewCLILang.Compiler;

namespace NewCLILang.Cli;

class Program
{
    static int Main(string[] args)
    {
        if (args.Length == 0)
        {
            ShowHelp();
            return 0;
        }

        var command = args[0].ToLower();

        return command switch
        {
            "build" => BuildCommand(args.Skip(1).ToArray()),
            "run" => RunCommand(args.Skip(1).ToArray()),
            "transpile" => TranspileCommand(args.Skip(1).ToArray()),
            "new" => NewCommand(args.Skip(1).ToArray()),
            "help" or "--help" or "-h" => ShowHelp(),
            _ => Error($"Unknown command: {command}")
        };
    }

    static int BuildCommand(string[] args)
    {
        // Support both single-file and multi-file builds
        if (args.Length == 0)
        {
            // No args - build all .nl files in current directory (multi-file mode)
            return BuildMultiFile(Directory.GetCurrentDirectory());
        }

        var sourceFile = args[0];
        if (!File.Exists(sourceFile))
        {
            return Error($"File not found: {sourceFile}");
        }

        // Single file build
        try
        {
            Console.WriteLine($"Building {sourceFile}...");

            var source = File.ReadAllText(sourceFile);
            var csharpCode = CompileToCSharp(source, sourceFile);

            // Write C# output
            var csharpFile = Path.ChangeExtension(sourceFile, ".g.cs");
            File.WriteAllText(csharpFile, csharpCode);

            Console.WriteLine($"Generated C# code: {csharpFile}");
            Console.WriteLine("Build successful!");

            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Build failed: {ex.Message}");
        }
    }

    static int BuildMultiFile(string projectRoot)
    {
        try
        {
            Console.WriteLine($"Building project in {projectRoot}...");

            // Load project config
            var config = ProjectFileParser.ParseFromDirectory(projectRoot);

            // Compile all files
            var compiler = new MultiFileCompiler(projectRoot, config);
            var result = compiler.Compile();

            // Report errors and warnings
            foreach (var error in result.Errors)
            {
                var severity = error.Severity == ErrorSeverity.Error ? "error" : "warning";
                var location = $"{error.Line}:{error.Column}";
                Console.Error.WriteLine($"{location}: {severity}: {error.Message}");
            }

            if (!result.Success)
            {
                return Error($"Build failed with {result.Errors.Count(e => e.Severity == ErrorSeverity.Error)} error(s)");
            }

            // Write C# output files
            var outputDir = Path.Combine(projectRoot, "obj", "generated");
            Directory.CreateDirectory(outputDir);

            foreach (var kvp in result.TranspiledFiles)
            {
                var sourceFile = kvp.Key;
                var csharpCode = kvp.Value;
                var relativePath = Path.GetRelativePath(projectRoot, sourceFile);
                var csharpFile = Path.Combine(outputDir, Path.ChangeExtension(relativePath, ".g.cs"));

                // Create subdirectories if needed
                var csharpDir = Path.GetDirectoryName(csharpFile);
                if (csharpDir != null)
                {
                    Directory.CreateDirectory(csharpDir);
                }

                File.WriteAllText(csharpFile, csharpCode);
                Console.WriteLine($"Generated: {Path.GetRelativePath(projectRoot, csharpFile)}");
            }

            Console.WriteLine($"Build successful! ({result.TranspiledFiles.Count} files)");
            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Build failed: {ex.Message}");
        }
    }

    static int TranspileCommand(string[] args)
    {
        if (args.Length == 0)
        {
            return Error("Usage: nlc transpile <file.nl>");
        }

        var sourceFile = args[0];
        if (!File.Exists(sourceFile))
        {
            return Error($"File not found: {sourceFile}");
        }

        try
        {
            var source = File.ReadAllText(sourceFile);
            var csharpCode = CompileToCSharp(source, sourceFile);

            Console.WriteLine(csharpCode);

            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Transpilation failed: {ex.Message}");
        }
    }

    static int RunCommand(string[] args)
    {
        // Support both single-file and multi-file runs
        if (args.Length == 0)
        {
            // No args - run multi-file project in current directory
            return RunMultiFile(Directory.GetCurrentDirectory());
        }

        var sourceFile = args[0];
        if (!File.Exists(sourceFile))
        {
            return Error($"File not found: {sourceFile}");
        }

        // Single file run
        try
        {
            Console.WriteLine($"Running {sourceFile}...");

            var source = File.ReadAllText(sourceFile);
            var csharpCode = CompileToCSharp(source, sourceFile);

            // Write C# to temp file
            var tempDir = Path.Combine(Path.GetTempPath(), "nlc-build");
            Directory.CreateDirectory(tempDir);

            var csharpFile = Path.Combine(tempDir, "Program.cs");
            File.WriteAllText(csharpFile, csharpCode);

            // Look for project.yml in the directory containing the source file
            var sourceDir = Path.GetDirectoryName(Path.GetFullPath(sourceFile)) ?? Directory.GetCurrentDirectory();
            var projectConfig = ProjectFileParser.ParseFromDirectory(sourceDir);

            // Create .csproj (with dependencies if project.yml exists)
            var projectFile = Path.Combine(tempDir, "TempProject.csproj");
            File.WriteAllText(projectFile, GenerateCsProj(projectConfig));

            // Build and run
            var buildResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = $"build \"{projectFile}\" -v q",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            });

            buildResult?.WaitForExit();

            if (buildResult?.ExitCode != 0)
            {
                var error = buildResult?.StandardError.ReadToEnd() ?? "";
                var output = buildResult?.StandardOutput.ReadToEnd() ?? "";
                return Error($"Build failed:\n{error}{output}");
            }

            Console.WriteLine();

            var runResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = $"run --project \"{projectFile}\" --no-build",
                UseShellExecute = false
            });

            runResult?.WaitForExit();

            return runResult?.ExitCode ?? 0;
        }
        catch (Exception ex)
        {
            return Error($"Run failed: {ex.Message}");
        }
    }

    static int RunMultiFile(string projectRoot)
    {
        try
        {
            Console.WriteLine($"Running project in {projectRoot}...");

            // Load project config
            var projectConfig = ProjectFileParser.ParseFromDirectory(projectRoot);

            // Compile all files
            var compiler = new MultiFileCompiler(projectRoot, projectConfig);
            var result = compiler.Compile();

            // Report errors and warnings
            foreach (var error in result.Errors)
            {
                var severity = error.Severity == ErrorSeverity.Error ? "error" : "warning";
                var location = $"{error.Line}:{error.Column}";
                Console.Error.WriteLine($"{location}: {severity}: {error.Message}");
            }

            if (!result.Success)
            {
                return Error($"Compilation failed with {result.Errors.Count(e => e.Severity == ErrorSeverity.Error)} error(s)");
            }

            // Write C# to temp directory
            var tempDir = Path.Combine(Path.GetTempPath(), "nlc-build");
            Directory.CreateDirectory(tempDir);

            foreach (var kvp in result.TranspiledFiles)
            {
                var sourceFile = kvp.Key;
                var csharpCode = kvp.Value;
                var relativePath = Path.GetRelativePath(projectRoot, sourceFile);
                var csharpFile = Path.Combine(tempDir, Path.ChangeExtension(relativePath, ".cs"));

                // Create subdirectories if needed
                var csharpDir = Path.GetDirectoryName(csharpFile);
                if (csharpDir != null)
                {
                    Directory.CreateDirectory(csharpDir);
                }

                File.WriteAllText(csharpFile, csharpCode);
            }

            // Create .csproj
            var projectFile = Path.Combine(tempDir, "TempProject.csproj");
            File.WriteAllText(projectFile, GenerateCsProj(projectConfig));

            // Build and run
            var buildResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = $"build \"{projectFile}\" -v q",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            });

            buildResult?.WaitForExit();

            if (buildResult?.ExitCode != 0)
            {
                var error = buildResult?.StandardError.ReadToEnd() ?? "";
                var output = buildResult?.StandardOutput.ReadToEnd() ?? "";
                return Error($"Build failed:\n{error}{output}");
            }

            Console.WriteLine();

            var runResult = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = "dotnet",
                Arguments = $"run --project \"{projectFile}\" --no-build",
                UseShellExecute = false
            });

            runResult?.WaitForExit();

            return runResult?.ExitCode ?? 0;
        }
        catch (Exception ex)
        {
            return Error($"Run failed: {ex.Message}");
        }
    }

    static string GenerateCsProj(ProjectConfig? config)
    {
        config ??= ProjectFileParser.CreateDefault();

        var dependencies = string.Join("\n    ",
            config.Dependencies.Select(kvp =>
                $@"<PackageReference Include=""{kvp.Key}"" Version=""{kvp.Value}"" />"));

        return $@"<Project Sdk=""Microsoft.NET.Sdk"">
  <PropertyGroup>
    <OutputType>{(config.OutputType == "exe" ? "Exe" : "Library")}</OutputType>
    <TargetFramework>{config.TargetFramework}</TargetFramework>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    {dependencies}
  </ItemGroup>
</Project>";
    }

    static string CompileToCSharp(string source, string fileName)
    {
        // Lexical analysis
        var lexer = new Lexer(source, fileName);
        var tokens = lexer.Tokenize();

        // Parsing
        var parser = new Parser(tokens, fileName);
        var compilationUnit = parser.ParseCompilationUnit();

        // Semantic analysis
        var analyzer = new Analyzer();
        var projectRoot = Path.GetDirectoryName(Path.GetFullPath(fileName)) ?? Directory.GetCurrentDirectory();
        var analysisResult = analyzer.Analyze(compilationUnit, fileName, projectRoot);

        // Report errors and warnings
        foreach (var error in analysisResult.Errors)
        {
            var severity = error.Severity == ErrorSeverity.Error ? "error" : "warning";
            var location = $"{fileName}:{error.Line}:{error.Column}";
            Console.Error.WriteLine($"{location}: {severity}: {error.Message}");
        }

        // Stop if there are errors
        if (analysisResult.HasErrors)
        {
            throw new Exception($"Compilation failed with {analysisResult.Errors.Count(e => e.Severity == ErrorSeverity.Error)} error(s)");
        }

        // Transpilation
        var transpiler = new Transpiler(compilationUnit);
        return transpiler.Transpile();
    }

    static int NewCommand(string[] args)
    {
        if (args.Length == 0)
        {
            return Error("Usage: nlc new <project-name>");
        }

        var projectName = args[0];
        var projectDir = Path.Combine(Directory.GetCurrentDirectory(), projectName);

        if (Directory.Exists(projectDir))
        {
            return Error($"Directory already exists: {projectDir}");
        }

        try
        {
            Console.WriteLine($"Creating new project: {projectName}");

            // Create project directory
            Directory.CreateDirectory(projectDir);

            // Create project.yml
            var projectYml = Path.Combine(projectDir, "project.yml");
            File.WriteAllText(projectYml, ProjectFileParser.GenerateTemplate(projectName));

            // Create Program.nl
            var programNl = Path.Combine(projectDir, "Program.nl");
            File.WriteAllText(programNl, $@"namespace {projectName}

func Main() {{
    print ""Hello, World from N#!""
    print $""Project: {projectName}""
}}
");

            Console.WriteLine($"Created: {projectName}/project.yml");
            Console.WriteLine($"Created: {projectName}/Program.nl");
            Console.WriteLine();
            Console.WriteLine($"To build and run your project:");
            Console.WriteLine($"  cd {projectName}");
            Console.WriteLine($"  nlc run Program.nl");
            Console.WriteLine();

            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Failed to create project: {ex.Message}");
        }
    }

    static int ShowHelp()
    {
        Console.WriteLine("NewCLILang Compiler (nlc)");
        Console.WriteLine();
        Console.WriteLine("Usage: nlc <command> [options]");
        Console.WriteLine();
        Console.WriteLine("Commands:");
        Console.WriteLine("  build <file.nl>      - Compile single .nl file to C#");
        Console.WriteLine("  build                - Compile all .nl files in project (multi-file)");
        Console.WriteLine("  transpile <file.nl>  - Transpile .nl file to C# and print to stdout");
        Console.WriteLine("  run <file.nl>        - Compile and run single .nl file");
        Console.WriteLine("  run                  - Compile and run all .nl files in project");
        Console.WriteLine("  new <project-name>   - Create a new N# project with project.yml");
        Console.WriteLine("  help                 - Show this help message");
        Console.WriteLine();

        return 0;
    }

    static int Error(string message)
    {
        Console.Error.WriteLine($"Error: {message}");
        return 1;
    }
}
