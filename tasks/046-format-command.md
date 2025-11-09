# Task 046: Format CLI Command

**Effort:** Small (3-4 hours)
**Depends:** Task 045
**Ships:** `nsharp format` command

## Goal

Add format command to nsharp CLI.

## Deliverable

CLI command that formats files in-place.

## Implementation

Add to `src/Cli/Program.cs`:

```csharp
if (args[0] == "format")
{
    var files = args.Skip(1).ToArray();

    if (files.Length == 0)
    {
        files = Directory.GetFiles(".", "*.nl", SearchOption.AllDirectories)
            .Where(f => !f.EndsWith(".tests.nl"))
            .ToArray();
    }

    foreach (var file in files)
    {
        Console.WriteLine($"Formatting {file}...");

        var source = File.ReadAllText(file);
        var ast = Parse(source);
        var formatted = new Formatter().Format(ast);

        File.WriteAllText(file, formatted);
    }

    Console.WriteLine($"Formatted {files.Length} files");
    return 0;
}
```

## Usage

```bash
# Format single file
nsharp format Program.nl

# Format all files in directory
nsharp format

# Format specific files
nsharp format src/*.nl
```

## Done When

- [ ] `nsharp format` works
- [ ] Formats single file
- [ ] Formats multiple files
- [ ] Formats directory recursively
