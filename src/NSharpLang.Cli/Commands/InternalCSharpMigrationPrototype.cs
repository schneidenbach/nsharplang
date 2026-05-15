using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Cli;

namespace NSharpLang.Cli.Commands;

internal static class InternalCSharpMigrationPrototype
{
    internal static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
        {
            return ShowHelp();
        }

        var inputFile = GetOptionValue(args, "--file");
        var inputDir = GetOptionValue(args, "--dir");
        var output = GetOptionValue(args, "--output") ?? GetOptionValue(args, "-o");
        var useStdin = args.Contains("--stdin");
        var dryRun = args.Contains("--dry-run");

        var inputModes = new[] { !string.IsNullOrWhiteSpace(inputFile), !string.IsNullOrWhiteSpace(inputDir), useStdin }.Count(mode => mode);
        if (inputModes != 1)
        {
            return Error("Specify exactly one input mode: --file <path>, --dir <path>, or --stdin.");
        }

        try
        {
            if (useStdin)
            {
                return ConvertStdin(dryRun);
            }

            if (!string.IsNullOrWhiteSpace(inputFile))
            {
                return ConvertFile(inputFile, output, dryRun);
            }

            return ConvertDirectory(inputDir!, output, dryRun);
        }
        catch (Exception ex)
        {
            return Error($"Convert failed: {ex.Message}");
        }
    }

    private static int ConvertStdin(bool dryRun)
    {
        var source = Console.In.ReadToEnd();
        var result = new CSharpToNSharpConverter().Convert(source, "stdin.cs");
        EmitDiagnostics(result.Diagnostics);
        if (!result.Success)
        {
            return 1;
        }

        Console.Write(result.Output);
        return result.Diagnostics.Count > 0 && dryRun ? 1 : 0;
    }

    private static int ConvertFile(string inputFile, string? output, bool dryRun)
    {
        if (!File.Exists(inputFile))
        {
            return Error($"File not found: {inputFile}");
        }

        if (!inputFile.EndsWith(".cs", StringComparison.OrdinalIgnoreCase))
        {
            return Error($"Expected a .cs file, got: {inputFile}");
        }

        var source = File.ReadAllText(inputFile);
        var result = new CSharpToNSharpConverter().Convert(source, inputFile);
        EmitDiagnostics(result.Diagnostics);
        if (!result.Success)
        {
            return 1;
        }

        var outputFile = ResolveOutputFile(inputFile, output);
        if (dryRun || string.IsNullOrWhiteSpace(output))
        {
            Console.Write(result.Output);
            return result.Diagnostics.Count > 0 ? 1 : 0;
        }

        if (string.Equals(Path.GetFullPath(outputFile), Path.GetFullPath(inputFile), StringComparison.OrdinalIgnoreCase))
        {
            return Error("Refusing to overwrite the source .cs file. Choose a different output path.");
        }

        Directory.CreateDirectory(Path.GetDirectoryName(outputFile) ?? Directory.GetCurrentDirectory());
        File.WriteAllText(outputFile, result.Output);
        Console.WriteLine($"Converted {inputFile} to {outputFile}");
        return result.Diagnostics.Count > 0 ? 1 : 0;
    }

    private static int ConvertDirectory(string inputDir, string? output, bool dryRun)
    {
        if (!Directory.Exists(inputDir))
        {
            return Error($"Directory not found: {inputDir}");
        }

        var files = Directory.GetFiles(inputDir, "*.cs", SearchOption.AllDirectories)
            .Where(file => !IsGeneratedPath(file))
            .OrderBy(file => file, StringComparer.OrdinalIgnoreCase)
            .ToArray();
        if (files.Length == 0)
        {
            return Error($"No .cs files found under {inputDir}.");
        }

        if (string.IsNullOrWhiteSpace(output) && !dryRun)
        {
            return Error("--dir requires --output <directory> unless --dry-run is set.");
        }

        var converter = new CSharpToNSharpConverter();
        var hadDiagnostics = false;
        foreach (var file in files)
        {
            var result = converter.Convert(File.ReadAllText(file), file);
            EmitDiagnostics(result.Diagnostics);
            hadDiagnostics |= result.Diagnostics.Count > 0;
            if (!result.Success)
            {
                continue;
            }

            var relative = Path.GetRelativePath(Path.GetFullPath(inputDir), Path.GetFullPath(file));
            var outputFile = Path.Combine(Path.GetFullPath(output ?? inputDir), Path.ChangeExtension(relative, ".nl"));
            if (dryRun)
            {
                Console.WriteLine($"--- {Path.ChangeExtension(relative, ".nl")} ---");
                Console.Write(result.Output);
                continue;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(outputFile) ?? Directory.GetCurrentDirectory());
            File.WriteAllText(outputFile, result.Output);
        }

        if (!dryRun)
        {
            Console.WriteLine($"Converted {files.Length} file(s) to {Path.GetFullPath(output!)}");
        }

        return hadDiagnostics ? 1 : 0;
    }

    private static string ResolveOutputFile(string inputFile, string? output)
    {
        if (string.IsNullOrWhiteSpace(output))
        {
            return Path.ChangeExtension(inputFile, ".nl");
        }

        return Directory.Exists(output)
            ? Path.Combine(output, Path.GetFileName(Path.ChangeExtension(inputFile, ".nl")))
            : output;
    }

    private static bool IsGeneratedPath(string file)
    {
        var parts = Path.GetFullPath(file).Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return parts.Any(part => part is "bin" or "obj");
    }

    private static string? GetOptionValue(string[] args, string option)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i] == option)
            {
                return args[i + 1];
            }
        }

        return null;
    }

    private static void EmitDiagnostics(IReadOnlyList<string> diagnostics)
    {
        foreach (var diagnostic in diagnostics)
        {
            Console.Error.WriteLine(diagnostic);
        }
    }

    private static int ShowHelp()
    {
        Console.WriteLine(@"N# Internal C# Migration Prototype

Usage:
  internal-csharp-migration-prototype --file <file.cs> [--output file.nl]
  internal-csharp-migration-prototype --dir <src-dir> --output <out-dir>
  internal-csharp-migration-prototype --stdin

Internal prototype only: produces scratch C# syntax-to-N# output using Roslyn.
It is not a public CLI command and is not the migration contract. Review-ready
migrations must use the AI-authored .nl + nlc check/idiom/fix/format/test loop.

Options:
  --file <path>       Convert one C# file
  --dir <path>        Convert all .cs files under a directory, excluding bin/obj
  --stdin             Read C# source from stdin and write N# to stdout
  --output <path>     Output file or directory (-o shorthand)
  --dry-run           Print converted output without writing files
  --help, -h          Show this help text

Exit codes:
  0  Conversion completed with no manual-review diagnostics
  1  Conversion failed or emitted manual-review diagnostics");

        return 0;
    }

    private static int Error(string message)
    {
        Console.Error.WriteLine($"Error: {message}");
        return 1;
    }
}
