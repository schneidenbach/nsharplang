# Task 053: Lint CLI Command

**Effort:** Small (3-4 hours)
**Depends:** Task 052
**Ships:** `nsharp lint` command

## Goal

Add lint command to CLI.

## Deliverable

Command that runs linter and shows diagnostics.

## Implementation

Add to `src/Cli/Program.cs`:

```csharp
if (args[0] == "lint")
{
    var files = GetSourceFiles(args);
    var totalDiagnostics = 0;

    foreach (var file in files)
    {
        var source = File.ReadAllText(file);
        var ast = Parse(source);
        var diagnostics = new Linter().Lint(ast);

        if (diagnostics.Count > 0)
        {
            Console.WriteLine($"\n{file}:");
            foreach (var diag in diagnostics)
            {
                PrintDiagnostic(diag);
            }
            totalDiagnostics += diagnostics.Count;
        }
    }

    Console.WriteLine($"\nFound {totalDiagnostics} issues");
    return totalDiagnostics > 0 ? 1 : 0;
}

void PrintDiagnostic(Diagnostic diag)
{
    var color = diag.Severity switch
    {
        DiagnosticSeverity.Error => ConsoleColor.Red,
        DiagnosticSeverity.Warning => ConsoleColor.Yellow,
        _ => ConsoleColor.Gray
    };

    Console.ForegroundColor = color;
    Console.Write($"  {diag.Severity.ToString().ToLower()}");
    Console.ResetColor();
    Console.WriteLine($"[{diag.Code}]: {diag.Message}");
    Console.WriteLine($"    --> {diag.Location}");
}
```

## Usage

```bash
# Lint single file
nsharp lint Program.nl

# Lint directory
nsharp lint

# CI mode (exit code 1 if issues)
nsharp lint || exit 1
```

## Done When

- [ ] `nsharp lint` works
- [ ] Shows all diagnostics
- [ ] Colored output
- [ ] Exit code reflects issues
