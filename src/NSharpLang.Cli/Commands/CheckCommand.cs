using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.Cli.Commands;

public static class CheckCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var useText = args.Contains("--text");
        var projectDir = GetProjectDir(args);

        if (!Directory.Exists(projectDir))
        {
            return EmitError(useText, $"Directory not found: {projectDir}", projectDir);
        }

        // Generate build config so that check-then-build workflows work
        // (nlc check -> dotnet build should succeed without a separate nlc restore)
        // Only attempt if project.yml exists — single-file examples and non-project dirs skip this
        var projectYmlPath = Path.Combine(projectDir, "project.yml");
        if (File.Exists(projectYmlPath))
        {
            RestoreCommand.Restore(projectDir, quiet: true);
        }

        var sw = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            var projectConfig = ProjectFileParser.ParseFromDirectory(projectDir);
            var backend = ResolveCompilationBackend(args, projectConfig);
            var service = new CodeIntelligenceService();
            var snapshot = service.LoadProject(projectDir);
            var diagnostics = service.GetDiagnostics(snapshot);
            diagnostics.AddRange(GetLintDiagnostics(projectDir, snapshot.SourceFiles));
            diagnostics = DeduplicateAndSort(diagnostics);

            // If analysis found no errors AND this is a proper project (has project.yml),
            // verify the generated C# also compiles. This closes the gap where `nlc check`
            // passes but `dotnet build` fails on generated C# (transpiler errors or C#
            // compiler errors). Non-project directories (standalone .nl files) skip this
            // because they aren't meant to be compiled as a single project.
            if (!diagnostics.Any(d => d.Severity == "error")
                && snapshot.SourceFiles.Count > 0
                && File.Exists(projectYmlPath))
            {
                var verificationDiagnostics = VerifyBackendOutput(projectDir, backend);
                if (verificationDiagnostics.Count > 0)
                {
                    diagnostics.AddRange(verificationDiagnostics);
                    diagnostics = DeduplicateAndSort(diagnostics);
                }
            }

            if (useText)
            {
                var errors = diagnostics.Count(d => d.Severity == "error");
                var warnings = diagnostics.Count(d => d.Severity == "warning");
                if (errors == 0 && warnings == 0)
                {
                    var fileCount = snapshot.SourceFiles.Count;
                    Console.Error.WriteLine($"  Checked {fileCount} file{(fileCount == 1 ? "" : "s")} — no errors. [{FormatElapsed(sw.Elapsed)}]");
                }
                else
                {
                    Console.Error.Write(OutputFormatter.DiagnosticsToText(diagnostics));
                    Console.Error.WriteLine($"  Checked in {FormatElapsed(sw.Elapsed)}");
                }
            }
            else
            {
                Console.Write(OutputFormatter.CheckToJson(diagnostics, snapshot.ProjectRoot, snapshot.SourceFiles.Count));
            }

            return diagnostics.Any(d => d.Severity == "error") ? 1 : 0;
        }
        catch (Exception ex)
        {
            if (useText)
                Console.Error.WriteLine($"  Check failed in {FormatElapsed(sw.Elapsed)}");
            return EmitError(useText, $"Check failed: {ex.Message}", projectDir);
        }
    }

    /// <summary>
    /// Verifies that the transpiler output compiles as valid C#.
    /// Runs the full N# compilation pipeline (parse → analyze → transpile)
    /// then invokes <c>dotnet build</c> on the generated C# files.
    /// </summary>
    private static List<DiagnosticResult> VerifyBackendOutput(string projectDir, CompilationBackend backend)
    {
        return backend switch
        {
            CompilationBackend.Transpile => VerifyTranspilerOutput(projectDir),
            CompilationBackend.Il => VerifyIlOutput(projectDir),
            _ => throw new InvalidOperationException($"Unsupported compilation backend: {backend}")
        };
    }

    private static List<DiagnosticResult> VerifyTranspilerOutput(string projectDir)
    {
        var results = new List<DiagnosticResult>();

        var config = ProjectFileParser.ParseFromDirectory(projectDir);
        var compiler = new MultiFileCompiler(projectDir, config);
        var compileResult = compiler.Compile();

        // Report transpiler errors (errors that surface during code generation
        // but not during analysis — this is the gap the users reported)
        if (!compileResult.Success)
        {
            foreach (var error in compileResult.Errors.Where(e => e.Severity == ErrorSeverity.Error))
            {
                var relativeFile = error.FileName != null
                    ? NormalizePath(Path.GetRelativePath(projectDir, error.FileName))
                    : "unknown";
                results.Add(new DiagnosticResult(
                    error.DiagnosticId,
                    "error",
                    error.Message,
                    relativeFile,
                    error.Line,
                    error.Column,
                    error.Length,
                    error.SourceSnippet,
                    error.HumanExplanation,
                    error.Suggestion ?? FormatSuggestions(error.Suggestions),
                    error.ContextualHint,
                    error.ExpectedType,
                    error.ActualType,
                    error.DocsUrl));
            }
            return results;
        }

        // No transpiler errors — verify the generated C# compiles with dotnet build
        if (compileResult.TranspiledFiles.Count == 0)
            return results;

        var tempDir = Path.Combine(Path.GetTempPath(), $"nlc-check-verify-{Guid.NewGuid():N}");
        try
        {
            Directory.CreateDirectory(tempDir);

            // Write generated C# files to temp directory
            foreach (var (sourceFile, csharpCode) in compileResult.TranspiledFiles)
            {
                var relativePath = Path.GetRelativePath(projectDir, sourceFile);
                var csharpFile = Path.Combine(tempDir, Path.ChangeExtension(relativePath, ".cs"));
                var dir = Path.GetDirectoryName(csharpFile);
                if (dir != null) Directory.CreateDirectory(dir);
                File.WriteAllText(csharpFile, csharpCode);
            }

            // Generate a verification .csproj matching the project config
            var projectFile = Path.Combine(tempDir, "VerifyCheck.csproj");
            File.WriteAllText(projectFile, GenerateVerificationCsProj(config, projectDir));

            // Run dotnet build to verify the C# compiles
            var buildResult = DotnetRunner.Run(
                $"build \"{projectFile}\" -v q --nologo",
                timeout: TimeSpan.FromSeconds(30));

            if (buildResult.ExitCode != 0)
            {
                var buildOutput = buildResult.Stderr + buildResult.Stdout;
                results.AddRange(ParseCSharpBuildErrors(buildOutput, projectDir, tempDir));
            }
        }
        finally
        {
            try { Directory.Delete(tempDir, true); } catch { /* best effort */ }
        }

        return results;
    }

    private static List<DiagnosticResult> VerifyIlOutput(string projectDir)
    {
        var results = new List<DiagnosticResult>();
        var config = ProjectFileParser.ParseFromDirectory(projectDir) ?? ProjectFileParser.CreateDefault();
        var tempDir = Path.Combine(Path.GetTempPath(), $"nlc-check-il-{Guid.NewGuid():N}");

        try
        {
            Directory.CreateDirectory(tempDir);
            var outputPath = Path.Combine(tempDir, $"{config.EffectiveName}.dll");
            var compiler = new MultiFileCompiler(projectDir, config);
            var compileResult = compiler.Compile(CompilationBackend.Il, config.EffectiveName, outputPath);

            if (!compileResult.Success)
            {
                foreach (var error in compileResult.Errors.Where(e => e.Severity == ErrorSeverity.Error))
                {
                    var relativeFile = error.FileName != null
                        ? NormalizePath(Path.GetRelativePath(projectDir, error.FileName))
                        : "unknown";
                    results.Add(new DiagnosticResult(
                        error.DiagnosticId,
                        "error",
                        error.Message,
                        relativeFile,
                        error.Line,
                        error.Column,
                        error.Length,
                        error.SourceSnippet,
                        error.HumanExplanation,
                        error.Suggestion ?? FormatSuggestions(error.Suggestions),
                        error.ContextualHint,
                        error.ExpectedType,
                        error.ActualType,
                        error.DocsUrl));
                }
            }
        }
        finally
        {
            try { Directory.Delete(tempDir, true); } catch { /* best effort */ }
        }

        return results;
    }

    /// <summary>
    /// Generates a minimal .csproj for verifying generated C# compiles.
    /// Mirrors the project's SDK, target framework, and dependencies.
    /// </summary>
    private static string GenerateVerificationCsProj(ProjectConfig? config, string projectDir)
    {
        config ??= ProjectFileParser.CreateDefault();

        var sb = new System.Text.StringBuilder();
        sb.AppendLine($@"<Project Sdk=""{config.Sdk}"">");
        sb.AppendLine("  <PropertyGroup>");
        sb.AppendLine($"    <OutputType>{(config.OutputType == "exe" ? "Exe" : "Library")}</OutputType>");
        sb.AppendLine($"    <TargetFramework>{config.TargetFramework}</TargetFramework>");
        sb.AppendLine("    <LangVersion>latest</LangVersion>");
        sb.AppendLine("    <Nullable>enable</Nullable>");
        sb.AppendLine("  </PropertyGroup>");

        if (config.Dependencies.Count > 0)
        {
            sb.AppendLine();
            sb.AppendLine("  <ItemGroup>");
            foreach (var reference in config.Dependencies)
            {
                switch (reference.Type)
                {
                    case ReferenceType.NuGet:
                        sb.AppendLine($"    <PackageReference Include=\"{reference.Nuget}\" Version=\"{reference.Version ?? "*"}\" />");
                        break;
                    case ReferenceType.Dll:
                        // Resolve relative paths against the project directory, not cwd
                        var dllPath = Path.GetFullPath(reference.Dll!, projectDir);
                        sb.AppendLine($"    <Reference Include=\"{Path.GetFileNameWithoutExtension(reference.Dll)}\">");
                        sb.AppendLine($"      <HintPath>{dllPath}</HintPath>");
                        sb.AppendLine("    </Reference>");
                        break;
                    case ReferenceType.Project:
                        var projPath = Path.GetFullPath(reference.Project!, projectDir);
                        sb.AppendLine($"    <ProjectReference Include=\"{projPath}\" />");
                        break;
                    case ReferenceType.Framework:
                        sb.AppendLine($"    <FrameworkReference Include=\"{reference.Framework}\" />");
                        break;
                }
            }
            sb.AppendLine("  </ItemGroup>");
        }

        sb.AppendLine("</Project>");
        return sb.ToString();
    }

    /// <summary>
    /// Parses C# build errors from dotnet build output and maps them back to N# source files.
    /// Handles multiple error formats:
    ///   /path/to/File.cs(line,col): error CS1234: message  (Roslyn)
    ///   /path/to/File.cs(line,col): error NETSDK1234: ...  (SDK)
    ///   MSBUILD : error MSB1234: message                   (MSBuild, no file)
    /// </summary>
    private static List<DiagnosticResult> ParseCSharpBuildErrors(
        string buildOutput, string projectDir, string tempDir)
    {
        var results = new List<DiagnosticResult>();
        // Match errors with file location (CS, NETSDK, MSB, NU prefixes)
        var errorPattern = new Regex(
            @"^(.+?)\((\d+),(\d+)\):\s+error\s+([A-Z]+\d+):\s+(.+)$",
            RegexOptions.Multiline);

        var matches = errorPattern.Matches(buildOutput);

        if (matches.Count > 0)
        {
            foreach (Match match in matches)
            {
                var csFile = match.Groups[1].Value.Trim();
                var line = int.Parse(match.Groups[2].Value);
                var col = int.Parse(match.Groups[3].Value);
                var code = match.Groups[4].Value;
                var message = match.Groups[5].Value.Trim();

                // Map the .cs file back to the .nl source file
                var nlFile = MapCsFileToNlFile(csFile, projectDir, tempDir) ?? "unknown";

                results.Add(new DiagnosticResult(
                    code,
                    "error",
                    $"Generated C# failed to compile: {message}",
                    nlFile,
                    line,
                    col,
                    1,
                    null,
                    "The N# analyzer did not catch this error, but the generated C# code does not compile. " +
                    "This indicates a gap in the N# type checker. Please report this as a bug.",
                    null,
                    null,
                    null,
                    null,
                    null));
            }
        }
        else
        {
            // Could not parse individual errors — report the raw build failure
            var errorLines = buildOutput.Split('\n')
                .Where(l => l.Contains("error", StringComparison.OrdinalIgnoreCase))
                .Take(5)
                .ToList();

            var detail = errorLines.Count > 0
                ? string.Join("\n", errorLines)
                : buildOutput.Trim();

            if (!string.IsNullOrWhiteSpace(detail))
            {
                results.Add(new DiagnosticResult(
                    "NL999",
                    "error",
                    $"Generated C# failed to compile: {detail}",
                    "unknown",
                    0,
                    0,
                    0,
                    null,
                    "The N# analyzer did not catch this error, but the generated C# code does not compile. " +
                    "This indicates a gap in the N# type checker. Please report this as a bug.",
                    null,
                    null,
                    null,
                    null,
                    null));
            }
        }

        return results;
    }

    /// <summary>
    /// Maps a generated .cs file path back to its original .nl source file.
    /// </summary>
    private static string? MapCsFileToNlFile(string csFile, string projectDir, string tempDir)
    {
        try
        {
            var relativeCsPath = Path.GetRelativePath(tempDir, csFile);
            var nlRelativePath = Path.ChangeExtension(relativeCsPath, ".nl");
            return NormalizePath(nlRelativePath);
        }
        catch
        {
            return null;
        }
    }

    private static string? FormatSuggestions(IReadOnlyList<string>? suggestions)
    {
        if (suggestions == null || suggestions.Count == 0) return null;
        return string.Join("; ", suggestions);
    }

    private static List<DiagnosticResult> DeduplicateAndSort(List<DiagnosticResult> diagnostics)
    {
        return diagnostics
            .GroupBy(d => (d.Code, d.File, d.Line, d.Column, d.Message))
            .Select(group => group.First())
            .OrderBy(d => d.File)
            .ThenBy(d => d.Line)
            .ThenBy(d => d.Column)
            .ToList();
    }

    private static List<DiagnosticResult> GetLintDiagnostics(string projectDir, IReadOnlyList<string> sourceFiles)
    {
        var results = new List<DiagnosticResult>();

        foreach (var filePath in sourceFiles)
        {
            string source;
            try
            {
                source = File.ReadAllText(filePath);
            }
            catch
            {
                continue;
            }

            var lexer = new Lexer(source, filePath);
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens, filePath, source);
            var parseResult = parser.ParseCompilationUnit();
            if (parseResult.CompilationUnit == null)
                continue;

            var fileDir = Path.GetDirectoryName(filePath) ?? projectDir;
            var linter = new Linter(LinterConfig.FromEditorConfig(fileDir));
            var diagnostics = linter.Lint(parseResult.CompilationUnit, filePath, source);

            foreach (var diagnostic in diagnostics)
            {
                results.Add(new DiagnosticResult(
                    diagnostic.Code,
                    diagnostic.Severity switch
                    {
                        DiagnosticSeverity.Error => "error",
                        DiagnosticSeverity.Warning => "warning",
                        _ => "info"
                    },
                    diagnostic.Message,
                    NormalizePath(Path.GetRelativePath(projectDir, filePath)),
                    diagnostic.Location.Line,
                    diagnostic.Location.Column,
                    1,
                    ExtractSourceLine(source, diagnostic.Location.Line),
                    null,
                    diagnostic.Suggestion,
                    null,
                    null,
                    null,
                    null));
            }
        }

        return results;
    }

    public static int ShowHelp()
    {
        Console.WriteLine(@"N# Type Check

Usage: nlc check [options] [project-dir]

Verifies your N# project compiles without errors. Runs semantic analysis,
linting, and verification of the selected compilation backend.

Options:
  --backend <mode>  Compilation backend: transpile (default) or il
  --json        Output as JSON (default)
  --text        Output as human-readable diagnostics
  --project     Project root directory (default: current directory)
  --help, -h    Show this help text

Examples:
  nlc check
  nlc check --backend il
  nlc check --text
  nlc check --project examples/16-task-cli

Exit codes:
  0  No errors found
  1  One or more errors detected");

        return 0;
    }

    private static string GetProjectDir(string[] args)
    {
        var projectOption = GetOption(args, "--project");
        if (!string.IsNullOrWhiteSpace(projectOption))
            return Path.GetFullPath(projectOption);

        var positional = GetFirstPositionalArg(args, Array.Empty<string>());
        return Path.GetFullPath(positional ?? Directory.GetCurrentDirectory());
    }

    private static CompilationBackend ResolveCompilationBackend(string[] args, ProjectConfig? config)
    {
        var backendOption = GetOption(args, "--backend");
        return !string.IsNullOrWhiteSpace(backendOption)
            ? CompilationBackendExtensions.Parse(backendOption)
            : config?.EffectiveBackend ?? CompilationBackend.Transpile;
    }

    private static string? GetOption(string[] args, string flag)
    {
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == flag)
                return args[i + 1];
        }

        return null;
    }

    private static string? GetFirstPositionalArg(string[] args, string[] optionsWithValues)
    {
        for (int i = 0; i < args.Length; i++)
        {
            if (optionsWithValues.Contains(args[i], StringComparer.Ordinal))
            {
                i++;
                continue;
            }

            if (!args[i].StartsWith("-", StringComparison.Ordinal))
                return args[i];
        }

        return null;
    }

    private static int EmitError(bool useText, string message, string? projectRoot = null)
    {
        if (useText)
        {
            Console.Error.WriteLine(message);
        }
        else
        {
            Console.Write(OutputFormatter.ErrorToJson("check", message, projectRoot));
        }

        return 1;
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');

    private static string FormatElapsed(TimeSpan elapsed)
    {
        if (elapsed.TotalMinutes >= 1)
            return $"{(int)elapsed.TotalMinutes}m {elapsed.Seconds:D2}s";
        return $"{elapsed.TotalSeconds:F1}s";
    }

    private static string? ExtractSourceLine(string source, int line)
    {
        var lines = source.Split('\n');
        return line > 0 && line <= lines.Length ? lines[line - 1] : null;
    }
}
