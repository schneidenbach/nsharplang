# Task 041: MSBuild Compile Task

**Effort:** Medium (8-10 hours)
**Depends:** None
**Ships:** `dotnet build` compiles .nl files

## Goal

Create MSBuild task that compiles .nl files to .cs files during build.

## Deliverable

MSBuild task that integrates N# compiler into dotnet build pipeline.

## Implementation

Create `src/NSharpLang.Build.Tasks/NSharpCompile.cs`:

```csharp
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

public class NSharpCompile : Task
{
    [Required]
    public ITaskItem[] Sources { get; set; }

    public ITaskItem[] References { get; set; }

    [Required]
    public string OutputPath { get; set; }

    public override bool Execute()
    {
        Log.LogMessage($"Compiling {Sources.Length} N# files...");

        try
        {
            var compiler = new MultiFileCompiler(
                Sources.Select(s => s.ItemSpec).ToList(),
                OutputPath,
                new ProjectConfig()
            );

            var result = compiler.Compile();

            if (!result.Success)
            {
                foreach (var err in result.Errors)
                    Log.LogError(err.Message);
                return false;
            }

            return true;
        }
        catch (Exception ex)
        {
            Log.LogErrorFromException(ex);
            return false;
        }
    }
}
```

## Testing

```bash
# Create test project
dotnet new classlib -o TestBuild
cd TestBuild

# Add task assembly reference
# Build with MSBuild
dotnet build

# Verify .nl files compiled to .cs
```

## Done When

- [ ] NSharpCompile task exists
- [ ] Task compiles .nl to .cs files
- [ ] Build errors propagate correctly
- [ ] References resolved properly
