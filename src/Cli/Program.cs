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
            "help" or "--help" or "-h" => ShowHelp(),
            _ => Error($"Unknown command: {command}")
        };
    }

    static int BuildCommand(string[] args)
    {
        if (args.Length == 0)
        {
            return Error("Usage: nlc build <file.nl>");
        }

        var sourceFile = args[0];
        if (!File.Exists(sourceFile))
        {
            return Error($"File not found: {sourceFile}");
        }

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
        if (args.Length == 0)
        {
            return Error("Usage: nlc run <file.nl>");
        }

        var sourceFile = args[0];
        if (!File.Exists(sourceFile))
        {
            return Error($"File not found: {sourceFile}");
        }

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

            // Create a minimal .csproj
            var projectFile = Path.Combine(tempDir, "TempProject.csproj");
            File.WriteAllText(projectFile, @"<Project Sdk=""Microsoft.NET.Sdk"">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>");

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

    static int ShowHelp()
    {
        Console.WriteLine("NewCLILang Compiler (nlc)");
        Console.WriteLine();
        Console.WriteLine("Usage: nlc <command> [options]");
        Console.WriteLine();
        Console.WriteLine("Commands:");
        Console.WriteLine("  build <file.nl>      - Compile .nl file to C#");
        Console.WriteLine("  transpile <file.nl>  - Transpile .nl file to C# and print to stdout");
        Console.WriteLine("  run <file.nl>        - Compile and run .nl file");
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
